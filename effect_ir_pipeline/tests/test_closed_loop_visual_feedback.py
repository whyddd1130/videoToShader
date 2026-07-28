from __future__ import annotations

import base64
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.closed_loop_shader_iter import (
    _apply_feedback_guardrails,
    _build_comparison_contact_sheet_data_url,
    _normalize_feedback_score,
    _visual_feedback_validation_error,
    reconcile_atomic_change_state,
    extract_glsl_blocks,
    infer_library_target_effect_name,
    validate_rendered_video,
    validate_shader_text,
    build_llm_visual_feedback_content,
)
from effect_ir_pipeline.effect_ir.shader_builder import merge_edit_plan_delta, normalize_edit_plan


def _write_video(path: Path, frames: list[np.ndarray], *, fps: float = 12.0) -> None:
    height, width = frames[0].shape[:2]
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), fps, (width, height))
    if not writer.isOpened():
        raise RuntimeError("OpenCV could not open MJPG VideoWriter")
    try:
        for frame_rgb in frames:
            writer.write(cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2BGR))
    finally:
        writer.release()


def _frames(amount: int = 0) -> list[np.ndarray]:
    base = np.zeros((32, 32, 3), dtype=np.uint8)
    base[:, :16] = (120, 128, 8)
    base[:, 16:] = (40, 160, 30)
    frames = []
    for index in range(6):
        frame = base.copy()
        frame[:, :, 2] = np.clip(frame[:, :, 2].astype(np.int16) + index * 10 + amount, 0, 255).astype(np.uint8)
        frames.append(frame)
    return frames


class ClosedLoopVisualFeedbackTest(unittest.TestCase):
    def test_visual_feedback_rejects_missing_overall_score(self) -> None:
        parsed = _normalize_feedback_score(
            {
                "most_important_gap": "missing motion",
                "optimization_priority": {},
                "primitive_edit_plan": {},
            }
        )
        self.assertEqual(
            _visual_feedback_validation_error(parsed),
            "missing numeric match_score.overall",
        )

    def test_visual_feedback_accepts_complete_score_and_plan(self) -> None:
        parsed = _normalize_feedback_score(
            {
                "match_score": {"overall": 46, "reason": "same family but motion differs"},
                "most_important_gap": "missing motion",
                "optimization_priority": {"blocking_dimensions": ["geometry_motion"]},
                "primitive_edit_plan": {"selected_primitives": []},
            }
        )
        self.assertEqual(_visual_feedback_validation_error(parsed), "")
        self.assertEqual(parsed["match_score"]["overall"], 46.0)

    def test_temporal_process_priority_is_preserved(self) -> None:
        parsed = _normalize_feedback_score(
            {
                "match_score": {"overall": 55, "reason": "timing differs"},
                "optimization_priority": {
                    "blocking_dimensions": ["temporal_process"],
                    "primary_focus": "temporal_process",
                },
            }
        )
        self.assertEqual(
            parsed["optimization_priority"]["blocking_dimensions"],
            ["temporal_process"],
        )

    def test_required_change_check_is_mandatory_when_previous_round_has_requirement(self) -> None:
        parsed = _normalize_feedback_score(
            {
                "match_score": {"overall": 45, "reason": "direction is still wrong"},
                "most_important_gap": "vertical direction",
                "optimization_priority": {},
                "primitive_edit_plan": {},
            }
        )
        self.assertEqual(
            _visual_feedback_validation_error(
                parsed,
                expected_required_changes=[{"id": "direction", "change": "reverse vertical motion"}],
            ),
            "missing required_change_check",
        )

    def test_required_change_check_accepts_visible_before_after_evidence(self) -> None:
        parsed = _normalize_feedback_score(
            {
                "match_score": {"overall": 48, "reason": "direction improved"},
                "most_important_gap": "strength remains low",
                "optimization_priority": {},
                "primitive_edit_plan": {},
                "required_change_check": {
                    "items": [{
                        "id": "direction",
                        "change": "reverse vertical motion",
                        "status": "partial",
                        "evidence": "after video moves in the requested direction but too weakly",
                        "visible_delta": "motion direction changed",
                        "remaining_change": "increase the motion strength",
                    }],
                },
            }
        )
        self.assertEqual(
            _visual_feedback_validation_error(
                parsed,
                expected_required_changes=[{"id": "direction", "change": "reverse vertical motion"}],
            ),
            "",
        )

    def test_atomic_change_reconciliation_freezes_completed_and_keeps_only_partial(self) -> None:
        parsed = _normalize_feedback_score({
            "match_score": {"overall": 50, "reason": "direction fixed, timing weak"},
            "optimization_priority": {
                "required_changes": [
                    {"id": "direction", "change": "reverse direction again"},
                    {"id": "downward", "change": "add downward expansion"},
                ],
            },
            "required_change_check": {"items": [
                {"id": "direction", "status": "implemented", "evidence": "direction now matches"},
                {"id": "early", "status": "partial", "evidence": "starts earlier but remains weak", "remaining_change": "increase early strength"},
            ]},
        })
        reconcile_atomic_change_state(
            parsed,
            previous_required_changes=[
                {"id": "direction", "change": "reverse horizontal bend"},
                {"id": "early", "change": "make the first quarter clearly visible"},
            ],
            previous_frozen_constraints=[],
        )
        priority = parsed["optimization_priority"]
        self.assertEqual(
            priority["required_changes"],
            [
                {"id": "early", "change": "increase early strength"},
                {"id": "downward", "change": "add downward expansion"},
            ],
        )
        self.assertIn("reverse horizontal bend", priority["frozen_constraints"][0])

    def test_shader_validation_rejects_incomplete_fragment(self) -> None:
        shader_text = """
```glsl
attribute vec2 position;
varying vec2 textureCoord;
void main() {
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
```
```glsl
precision mediump float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;
void main() {
    vec2 uv = textureCoord;
```
"""
        valid, reason = validate_shader_text(shader_text)

        self.assertFalse(valid)
        self.assertIn("unbalanced braces", reason)

    def test_extract_glsl_blocks_ignores_leading_json_block(self) -> None:
        response = """
```json
{"self_review": "ok"}
```
```glsl
attribute vec2 position;
varying vec2 textureCoord;
void main() {
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
```
```glsl
precision mediump float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;
void main() {
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
```
"""
        vertex, fragment = extract_glsl_blocks(response)

        self.assertIn("attribute vec2 position", vertex)
        self.assertIn("gl_FragColor", fragment)
        self.assertNotIn("self_review", vertex)

    def test_infer_library_target_effect_name_for_ablation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lib_video = root / "test_videos" / "lib" / "Bowknot__model.mp4"
            lib_video.parent.mkdir(parents=True)
            lib_video.touch()
            random_video = root / "test_videos" / "random" / "test4.mp4"
            random_video.parent.mkdir(parents=True)
            random_video.touch()

            self.assertEqual(infer_library_target_effect_name(lib_video, repo_root=root), "Bowknot")
            self.assertIsNone(infer_library_target_effect_name(random_video, repo_root=root))


    def test_rendered_video_validation_rejects_black_video(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            black = Path(tmp) / "black.avi"
            _write_video(black, [np.zeros((32, 32, 3), dtype=np.uint8) for _ in range(6)])

            valid, reason = validate_rendered_video(black)

        self.assertFalse(valid)
        self.assertIn("black or blank", reason)

    def test_contact_sheet_is_single_decodable_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "target.avi"
            candidate = Path(tmp) / "candidate.avi"
            _write_video(target, _frames())
            _write_video(candidate, _frames(amount=20))

            data_url = _build_comparison_contact_sheet_data_url(
                target,
                candidate,
                progress_values=[0.0, 0.5, 1.0],
                image_size=32,
            )

        prefix = "data:image/jpeg;base64,"
        self.assertTrue(data_url.startswith(prefix))
        payload = base64.b64decode(data_url[len(prefix) :])
        decoded = cv2.imdecode(np.frombuffer(payload, dtype=np.uint8), cv2.IMREAD_COLOR)
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded.shape[0], 3 * (32 + 28))
        self.assertEqual(decoded.shape[1], 3 * 32)

    def test_visual_feedback_content_uses_contact_sheet_without_numeric_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "target.avi"
            candidate = Path(tmp) / "candidate.avi"
            _write_video(target, _frames())
            _write_video(candidate, _frames(amount=20))

            content = build_llm_visual_feedback_content(
                target_video=target,
                candidate_video=candidate,
                target_ir={"geometry_ops": ["none"], "geometry_pattern": "none", "shape_hint": "none"},
                candidate_ir={"geometry_ops": ["none"]},
                current_shader="shader",
                image_size=32,
            )

        image_parts = [part for part in content if part["type"] == "image_url"]
        self.assertEqual(len(image_parts), 1)
        self.assertIn("target_ir", content[0]["text"])
        self.assertIn("match_score", content[0]["text"])
        self.assertIn("primitive_edit_plan_schema", content[0]["text"])
        self.assertIn("primitive_vocabulary", content[0]["text"])
        self.assertNotIn("numeric_distance", content[0]["text"])
        self.assertNotIn("trajectory_summary", content[0]["text"])
        self.assertNotIn("target_observation", content[0]["text"])
        self.assertNotIn("candidate_observation", content[0]["text"])
        self.assertNotIn("frame_by_frame_observation", content[0]["text"])
        self.assertIn("temporal_process_observation", content[0]["text"])
        self.assertIn("key_transition_observation", content[0]["text"])
        self.assertIn("motion_signature", content[0]["text"])
        self.assertIn("progress_evidence_summary", content[0]["text"])
        self.assertIn("target_video_observation", content[0]["text"])
        self.assertIn("most_important_gap", content[0]["text"])
        self.assertIn("变化规律", content[0]["text"])
        self.assertIn("不要描述横线、块、遮挡在脸上或画面中的精确位置", content[0]["text"])
        self.assertIn("\"match_score\": {\"overall\": 0, \"reason\"", content[0]["text"])
        self.assertIn("不打分项", content[0]["text"])

    def test_visual_feedback_content_adds_before_after_sheet_for_required_change(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "target.avi"
            before = Path(tmp) / "before.avi"
            after = Path(tmp) / "after.avi"
            _write_video(target, _frames())
            _write_video(before, _frames(amount=10))
            _write_video(after, _frames(amount=20))

            content = build_llm_visual_feedback_content(
                target_video=target,
                candidate_video=after,
                previous_candidate_video=before,
                previous_required_changes=[{"id": "direction", "change": "reverse vertical motion"}],
                target_ir={"geometry_ops": ["warp"]},
                candidate_ir={"geometry_ops": ["warp"]},
                current_shader="shader",
                image_size=32,
            )

        image_parts = [part for part in content if part["type"] == "image_url"]
        self.assertEqual(len(image_parts), 2)
        self.assertIn("BEFORE/AFTER/DIFF", content[0]["text"])
        self.assertIn("reverse vertical motion", content[0]["text"])
        self.assertIn("required_change_check", content[0]["text"])

    def test_visual_feedback_schema_uses_temporal_controller_without_peak_stages(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "target.avi"
            candidate = Path(tmp) / "candidate.avi"
            _write_video(target, _frames())
            _write_video(candidate, _frames(amount=10))
            content = build_llm_visual_feedback_content(
                target_video=target,
                candidate_video=candidate,
                target_ir={"temporal_pattern": "progressive"},
                candidate_ir={"temporal_pattern": "progressive"},
                current_shader="shader",
                image_size=32,
            )
        prompt = content[0]["text"]
        self.assertIn("temporal_controller", prompt)
        self.assertNotIn('"process_stages"', prompt)
        self.assertNotIn('"handoff_constraints"', prompt)
        self.assertNotIn('"weight_curve"', prompt)
        self.assertNotIn('"value_curve"', prompt)

    def test_continuous_temporal_controller_removes_legacy_stage_keyframes(self) -> None:
        plan = {
            "selected_primitives": [{
                "name": "wave_warp",
                "temporal": "late_progressive",
                "params": {
                    "from": 0.0,
                    "to": 1.0,
                    "weight_keyframes": [[0.0, 0.0], [0.5, 1.0]],
                    "value_keyframes": [[0.0, 0.0], [1.0, 1.0]],
                    "after": "hold",
                },
            }],
            "temporal_controller": {
                "mode": "continuous_monotonic",
                "shared_progress_curve": "ease_out",
            },
            "process_stages": [{"id": "legacy"}],
            "handoff_constraints": [{"from": "wave_warp", "to": "scale_x"}],
        }
        normalized = normalize_edit_plan(
            plan,
            target_ir={"temporal_pattern": "progressive", "geometry_ops": ["warp"]},
            llm_visual_feedback={"parsed": {"optimization_priority": {"blocking_dimensions": ["temporal_process"]}}},
        )
        self.assertEqual(normalized["temporal_controller"]["mode"], "continuous_monotonic")
        self.assertNotIn("process_stages", normalized)
        self.assertNotIn("handoff_constraints", normalized)
        primitive = normalized["selected_primitives"][0]
        self.assertEqual(primitive["temporal"], "ease_out")
        self.assertEqual(primitive["params"], {"from": 0.0, "to": 1.0})

    def test_delta_merge_discards_removed_peak_stage_fields(self) -> None:
        merged = merge_edit_plan_delta(
            {"selected_primitives": [], "process_stages": [{"id": "old"}], "handoff_constraints": [{"from": "a", "to": "b"}]},
            {"selected_primitives": [], "implementation_notes": []},
        )
        self.assertNotIn("process_stages", merged)
        self.assertNotIn("handoff_constraints", merged)

    def test_guardrail_blocks_geometry_family_when_target_ir_has_no_geometry(self) -> None:
        parsed = {
            "operation_family": "small_geometry_adjustment",
            "change_family_allowed": True,
            "optimization_plan": [
                "新增 radial ring mask",
                "increase blue channel",
            ],
            "primitive_edit_plan": {
                "selected_primitives": [
                    {"name": "radial_swirl", "temporal": "late_progressive", "confidence": 0.9},
                    {"name": "brightness", "temporal": "linear", "confidence": 0.7},
                ],
                "rejected_primitives": [],
                "implementation_notes": ["test note"],
            },
        }

        guarded = _apply_feedback_guardrails(
            parsed,
            target_ir={"geometry_ops": ["none"], "geometry_pattern": "none", "shape_hint": "none"},
        )

        self.assertFalse(guarded["change_family_allowed"])
        self.assertEqual(guarded["operation_family"], "tune_color_curve")
        self.assertIn("guardrail_note", guarded)
        self.assertTrue(any("RGB/HSL" in item for item in guarded["optimization_plan"]))
        selected_names = [item["name"] for item in guarded["primitive_edit_plan"]["selected_primitives"]]
        rejected_names = [item["name"] for item in guarded["primitive_edit_plan"]["rejected_primitives"]]
        self.assertEqual(selected_names, ["brightness"])
        self.assertIn("radial_swirl", rejected_names)

if __name__ == "__main__":
    unittest.main()
