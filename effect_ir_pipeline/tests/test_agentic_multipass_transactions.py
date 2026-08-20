from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from effect_ir_pipeline.effect_ir import agentic_multipass_translation as agent
from effect_ir_pipeline.effect_ir.agentic_multipass_translation import (
    _apply_graph_patch,
    _auto_plan_passes,
    _compact_working_memory,
    _final_review_context,
    _load_shader_packages,
    _execute_repair_transaction,
    _dirty_passes_for_graph_patch,
    _inspect_contract_sheet,
    _normalize_repair,
    _resource_sheets_for_pass,
    _observe_dense_timeline,
    _synthesize_dense_timeline,
    _verify_repair,
)
from effect_ir_pipeline.effect_ir.direct_shader_baseline import build_timeline_contact_sheet_data_urls
from effect_ir_pipeline.effect_ir.expert_pass_plan import validate_expert_brief


def _brief() -> dict:
    return validate_expert_brief({
        "effect_summary": "mask drives a final composite",
        "temporal_story": [{"range": "p=0..1", "visible_change": "mask grows continuously"}],
        "parameters": {"amount": {"type": "float", "keyframes": [[0, 0], [1, 1]]}},
        "passes": [
            {
                "name": "Mask", "role": "produce mask", "pass_goal": "white growing mask",
                "inputs": {"inputImageTexture": "source"}, "output": "mask", "scale": 0.5,
                "dynamic": True, "progress_behavior": "grows", "shader_stages": ["fragment"],
                "implementation_notes": ["luminance mask"], "success_criteria": ["mask grows"],
                "preserve": ["upright orientation"], "avoid": ["color noise"],
            },
            {
                "name": "Composite", "role": "apply mask", "pass_goal": "final color composite",
                "inputs": {"inputImageTexture": "source", "maskTexture": "mask"}, "output": "final", "scale": 1.0,
                "dynamic": False, "progress_behavior": "follows mask", "shader_stages": ["fragment"],
                "implementation_notes": ["masked mix"], "success_criteria": ["mask controls composite"],
                "preserve": ["source detail"], "avoid": ["black frame"],
            },
        ],
    })


class AgentTransactionContractTest(unittest.TestCase):
    def test_dense_timeline_sampler_uses_real_point_two_second_intervals(self) -> None:
        import cv2
        import numpy as np
        with tempfile.TemporaryDirectory() as temporary:
            video = Path(temporary) / "timeline.mp4"
            writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"mp4v"), 10.0, (32, 32))
            for index in range(11):
                writer.write(np.full((32, 32, 3), index * 10, dtype=np.uint8))
            writer.release()
            sheets, samples = build_timeline_contact_sheet_data_urls(
                video, interval_seconds=0.2, image_size=32, frames_per_sheet=3,
            )
            self.assertEqual([item["frame_index"] for item in samples], [0, 2, 4, 6, 8, 10])
            self.assertEqual([item["time_seconds"] for item in samples], [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
            self.assertEqual(len(sheets), 2)

    def test_dense_timeline_observer_cannot_leak_pass_or_shader_prior(self) -> None:
        import cv2
        import numpy as np
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            video = root / "timeline.mp4"
            writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"mp4v"), 10.0, (32, 32))
            for index in range(5):
                writer.write(np.full((32, 32, 3), index * 20, dtype=np.uint8))
            writer.release()
            captured: dict = {}
            response = {
                "duration_seconds": 0.4, "sample_interval_seconds": 0.2,
                "global_process": "brightness rises",
                "timeline": [
                    {"start_seconds": 0.0, "end_seconds": 0.2, "visible_change": "brighter"},
                    {"start_seconds": 0.2, "end_seconds": 0.4, "visible_change": "brighter again"},
                ],
            }
            def generate(messages, **kwargs):
                captured["prompt"] = messages[0]["content"][0]["text"]
                return json.dumps(response)
            with patch.object(agent, "generate_messages", side_effect=generate):
                observation, samples = _observe_dense_timeline(
                    source_part={"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,"}},
                    video=video, interval_seconds=0.2, maximum_frames=10,
                    model="model", temperature=0, work_dir=root, job_id="dense",
                )
            self.assertEqual(observation["sample_count"], 3)
            self.assertEqual(len(samples), 3)
            self.assertIn("Do not infer, mention, or recommend pass count", captured["prompt"])
            self.assertNotIn("PASS RESPONSIBILITIES", captured["prompt"])

    def test_dense_timeline_synthesis_is_detailed_text_only_middle_stage(self) -> None:
        observation = {
            "duration_seconds": 0.4,
            "sample_interval_seconds": 0.2,
            "global_process": "a ripple begins at the right edge",
            "timeline": [
                {"start_seconds": 0.0, "end_seconds": 0.2, "visible_change": "right edge begins bending leftward"},
                {"start_seconds": 0.2, "end_seconds": 0.4, "visible_change": "the bend crosses the center and the right side recovers"},
            ],
        }
        synthesized = {
            "overall_process": "The clean image first bends at the right edge, the bend travels left across the center, and the right side recovers behind it.",
            "initial_state": "clean image",
            "phases": [
                {
                    "start_seconds": 0.0, "end_seconds": 0.2, "phase_name": "onset",
                    "continuous_change": "A bend grows at the right edge and begins moving left.",
                },
                {
                    "start_seconds": 0.2, "end_seconds": 0.4, "phase_name": "propagation and recovery",
                    "continuous_change": "The bend crosses the center while the right side returns to its source position.",
                },
            ],
            "event_relationships": ["recovery follows the traveling bend"],
            "final_state": "right side recovered while the bend has crossed the center",
        }
        captured: dict = {}

        def generate(messages, **kwargs):
            captured["content"] = messages[0]["content"]
            return json.dumps(synthesized)

        with tempfile.TemporaryDirectory() as temporary, patch.object(agent, "generate_messages", side_effect=generate):
            result = _synthesize_dense_timeline(
                observation=observation, model="model", temperature=0,
                work_dir=Path(temporary), job_id="dense_middle",
            )
        self.assertEqual(result["source_interval_count"], 2)
        self.assertEqual(len(captured["content"]), 1)
        prompt = captured["content"][0]["text"]
        self.assertIn("continuous account", prompt)
        self.assertIn("right edge begins bending", prompt)
        self.assertNotIn("TARGET TIMELINE SHEET", prompt)
        self.assertIn("Do not mention pass count", prompt)

    def test_validator_adds_semantic_texture_contract(self) -> None:
        brief = _brief()
        self.assertEqual(brief["passes"][0]["output_contract"]["semantics"], "white growing mask")
        self.assertTrue(brief["passes"][0]["output_contract"]["channels"])

    def test_validator_accepts_more_than_five_passes(self) -> None:
        brief = _brief()
        for index in range(3, 8):
            item = copy.deepcopy(brief["passes"][-1])
            item["id"] = f"pass_{index:02d}"
            item["name"] = f"Stage {index}"
            item["inputs"] = {"inputImageTexture": brief["passes"][-1]["output"]}
            item["output"] = f"stage_{index}"
            brief["passes"].append(item)
        validated = validate_expert_brief(brief)
        self.assertEqual(validated["pass_count"], 7)

    def test_effect_description_is_auxiliary_and_visual_evidence_wins(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            captured: dict = {}

            def generate(messages, **kwargs):
                captured["messages"] = messages
                return json.dumps(_brief())

            with patch.object(agent, "generate_messages", side_effect=generate):
                brief, _ = _auto_plan_passes(
                    visual=[], effect_description="A clear lens enters and bends the moving background.",
                    model="model", attempts=1, temperature=0, work_dir=Path(temporary), job_id="effect_mode",
                )

            prompt = captured["messages"][0]["content"][0]["text"]
            self.assertIn("AUXILIARY EFFECT DESCRIPTION", prompt)
            self.assertIn("Ignore unsupported or conflicting claims", prompt)
            self.assertIn("must yield to visual evidence", prompt)
            self.assertIn("Infer every omitted field yourself", prompt)
            self.assertEqual(brief["pass_count"], 2)

    def test_planner_combines_independent_optional_constraints(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            captured: dict = {}

            def generate(messages, **kwargs):
                captured["prompt"] = messages[0]["content"][0]["text"]
                return json.dumps(_brief())

            with patch.object(agent, "generate_messages", side_effect=generate):
                brief, _ = _auto_plan_passes(
                    visual=[], effect_description="A growing liquid lens.",
                    pass_count_constraint=2,
                    pass_responsibilities="One pass must create a mask; another must composite it.",
                    model="model", attempts=1, temperature=0,
                    work_dir=Path(temporary), job_id="combined_constraints",
                )

            self.assertEqual(brief["pass_count"], 2)
            self.assertIn("PASS COUNT: exactly 2", captured["prompt"])
            self.assertIn("PASS RESPONSIBILITIES", captured["prompt"])
            self.assertIn("AUXILIARY EFFECT DESCRIPTION", captured["prompt"])

    def test_visual_only_observation_precedes_auxiliary_description(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            captured: dict = {}

            def generate(messages, **kwargs):
                captured["prompt"] = messages[0]["content"][0]["text"]
                return json.dumps(_brief())

            visual_observation = {
                "observed_effect": "a band enters from the left",
                "temporal_story": [{"range": "early", "visible_change": "band moves right"}],
            }
            with patch.object(agent, "generate_messages", side_effect=generate):
                _auto_plan_passes(
                    visual=[], visual_observation=visual_observation,
                    effect_description="A centered static circle.", model="model", attempts=1,
                    temperature=0, work_dir=Path(temporary), job_id="visual_first",
                )

            self.assertLess(captured["prompt"].index("VISUAL_ONLY_OBSERVATION"), captured["prompt"].index("AUXILIARY EFFECT DESCRIPTION"))
            self.assertIn("a band enters from the left", captured["prompt"])

    def test_pass_count_can_be_the_only_constraint(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(agent, "generate_messages", return_value=json.dumps(_brief())):
                brief, _ = _auto_plan_passes(
                    visual=[], pass_count_constraint=2, model="model", attempts=1,
                    temperature=0, work_dir=Path(temporary), job_id="count_only",
                )
            self.assertEqual(brief["pass_count"], 2)

    def test_autonomous_planner_uses_editable_responsibility_boundaries(self) -> None:
        prompt = agent.AUTO_PASS_PLANNER_PROMPT
        self.assertIn("causal responsibility and editability", prompt)
        self.assertIn("distinct sampling domain", prompt)
        self.assertIn("source-derived branch", prompt)
        self.assertIn("later visual review", prompt)
        self.assertIn("Never create identity, placeholder", prompt)
        self.assertNotIn("Prefer one pass whenever", prompt)
        self.assertNotIn("Use more than one pass only", prompt)

    def test_validator_rejects_descriptive_non_executable_parameters(self) -> None:
        brief = _brief()
        brief["parameters"] = {"lensRadius": {"type": "curve", "description": "grows over time"}}
        with self.assertRaisesRegex(ValueError, "unsupported type"):
            validate_expert_brief(brief)

    def test_validator_normalizes_compact_p_keyframes(self) -> None:
        brief = _brief()
        brief["parameters"] = {
            "amount": {"type": "float", "keyframes": [{"p": 0.0, "value": 0.0}, {"p": 1.0, "value": 1.0}]}
        }
        validated = validate_expert_brief(brief)
        self.assertEqual(validated["parameters"]["amount"]["keyframes"][1]["progress"], 1.0)
        self.assertNotIn("p", validated["parameters"]["amount"]["keyframes"][1])

    def test_validator_accepts_analytic_pass_without_sampler_inputs(self) -> None:
        brief = _brief()
        brief["passes"][0]["inputs"] = {}
        validated = validate_expert_brief(brief)
        self.assertEqual(validated["passes"][0]["inputs"], {})

    def test_multi_pass_repair_requires_observable_acceptance(self) -> None:
        repair = _normalize_repair({
            "decision": "revise", "scope": "multi_pass", "responsible_passes": [2, 1, 2],
            "instruction": "change producer and consumer together", "required_visible_change": "mask expands continuously",
            "acceptance_criteria": ["middle frame is between first and last"], "preserve": ["orientation"], "graph_patch": {},
        }, 2)
        self.assertEqual(repair["responsible_passes"], [1, 2])
        self.assertEqual(repair["scope"], "multi_pass")

    def test_graph_patch_is_allowlisted_and_revalidated(self) -> None:
        brief = _brief()
        repair = _normalize_repair({
            "decision": "revise", "scope": "graph", "responsible_passes": [1, 2],
            "instruction": "raise mask resolution", "required_visible_change": "edges become smoother",
            "acceptance_criteria": ["no blocky mask edge"], "preserve": [],
            "graph_patch": {"parameters": {"amount": {"type": "float", "keyframes": [[0, 0.2], [1, 0.8]]}}, "pass_updates": [{"pass": 1, "scale": 1.0}]},
        }, 2)
        patched = _apply_graph_patch(brief, repair)
        self.assertEqual(patched["passes"][0]["scale"], 1.0)
        self.assertEqual(patched["passes"][0]["role"], "produce mask")
        self.assertEqual(patched["parameters"]["amount"]["keyframes"][-1][1], 0.8)

    def test_graph_patch_invalidates_transitive_consumers(self) -> None:
        brief = _brief()
        repair = {
            "graph_patch": {"pass_updates": [{"pass": 1, "scale": 1.0}]},
        }
        self.assertEqual(_dirty_passes_for_graph_patch(brief, repair), [1, 2])

    def test_declared_inputs_are_mapped_to_named_producer_sheets(self) -> None:
        brief = _brief()
        sheets = [Path("mask.jpg")]
        self.assertEqual(_resource_sheets_for_pass(brief, 2, sheets), {"mask": sheets[0]})

    def test_working_memory_excludes_full_history(self) -> None:
        brief = _brief()
        brief["human_constraints"] = {"pass_count": 2, "effect_description": "untrusted prose"}
        brief["visual_only_observation"] = {"observed_effect": "visible wave"}
        memory = json.loads(_compact_working_memory(brief, [f"fact {index}" for index in range(12)], {"required_visible_change": "grow"}))
        self.assertEqual(len(memory["accepted_facts"]), 8)
        self.assertNotIn("model_responses", memory)
        self.assertNotIn("effect_description", memory["human_constraints"])
        self.assertEqual(memory["target"]["visual_only_observation"]["observed_effect"], "visible wave")
        self.assertEqual(memory["current_obligation"]["required_visible_change"], "grow")

    def test_final_review_context_excludes_dense_observation_and_shader_source(self) -> None:
        brief = _brief()
        brief["visual_only_observation"] = {"timeline": [{"visible_change": "very long"}] * 30}
        brief["passes"][0]["implementation_notes"] = ["internal algorithm details"]
        final_context = json.dumps(_final_review_context(brief), ensure_ascii=False)
        self.assertNotIn("visual_only_observation", final_context)
        self.assertNotIn("implementation_notes", final_context)
        self.assertNotIn("gl_FragColor", final_context)

    def test_main_loop_uses_local_contract_probe_without_intermediate_model_review(self) -> None:
        source = Path(agent.__file__).read_text(encoding="utf-8")
        self.assertNotIn("def _observe_pass(", source)
        self.assertNotIn("--pass-revisions", source)
        self.assertIn("generation_with_local_contract_probe", source)
        self.assertIn("--contract-revisions", source)

    def test_resume_loads_longest_complete_shader_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "pass_01.frag.glsl").write_text("fragment one", encoding="utf-8")
            (root / "pass_01.vert.glsl").write_text("vertex one", encoding="utf-8")
            (root / "pass_02.frag.glsl").write_text("fragment two", encoding="utf-8")
            (root / "pass_04.frag.glsl").write_text("must not skip gap", encoding="utf-8")
            packages = _load_shader_packages(root, 5)
            self.assertEqual(len(packages), 2)
            self.assertEqual(packages[0]["vertex"], "vertex one")
            self.assertEqual(packages[1]["fragment"], "fragment two")

    def test_transaction_commits_only_after_verifier_fulfills(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "input.png"; image.write_bytes(b"image")
            before = root / "before.mp4"; before.write_bytes(b"before")
            rendered = root / "rendered.mp4"; rendered.write_bytes(b"rendered")
            package = {"vertex": "", "fragment": "old"}
            repair = _normalize_repair({
                "decision": "revise", "scope": "single_pass", "responsible_passes": [1],
                "instruction": "grow the mask", "required_visible_change": "mask becomes larger",
                "acceptance_criteria": ["after is larger than before"], "preserve": [], "graph_patch": {},
            }, 2)
            with patch.object(agent, "_generate_pass", return_value={"vertex": "", "fragment": "new"}), \
                 patch.object(agent, "_studio_task", return_value=rendered), \
                 patch.object(agent, "_render_prefixes", side_effect=AssertionError("verification must not re-render pass prefixes")), \
                 patch.object(agent, "_verify_repair", return_value={"outcome": "fulfilled", "requirement_check": "larger", "regressions": [], "next_instruction": "", "accepted_facts": ["mask size correct"]}):
                brief, packages, candidate, _, transaction = _execute_repair_transaction(
                    repair=repair, brief=_brief(), packages=[package, package], target_video=before, before_video=before, input_image=image,
                    repo=root, studio=root, studio_url="http://example", job_dir=root / "graph", job_id="job", out=root,
                    visual=[], model="model", temperature=0, code_attempts=1, transaction_attempts=1,
                    label="repair", accepted_facts=[],
                )
            self.assertTrue(transaction["committed"])
            self.assertEqual(packages[0]["fragment"], "new")
            self.assertEqual(candidate.read_bytes(), b"rendered")
            self.assertEqual(brief["pass_count"], 2)

    def test_graph_repair_rewrites_patched_pass_and_transitive_consumer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "input.png"; image.write_bytes(b"image")
            before = root / "before.mp4"; before.write_bytes(b"before")
            rendered = root / "rendered.mp4"; rendered.write_bytes(b"rendered")
            prefix = root / "prefix.jpg"; prefix.write_bytes(b"prefix")
            packages = [{"vertex": "", "fragment": "old1"}, {"vertex": "", "fragment": "old2"}]
            repair = _normalize_repair({
                "decision": "revise", "scope": "graph", "responsible_passes": [1, 2],
                "instruction": "change mask resolution and keep its consumer compatible",
                "required_visible_change": "mask edge becomes smoother",
                "acceptance_criteria": ["smooth edge"], "preserve": [],
                "graph_patch": {"pass_updates": [{"pass": 1, "scale": 1.0}]},
            }, 2)
            rewritten: list[int] = []

            def generate(**kwargs):
                rewritten.append(kwargs["index"])
                return {"vertex": "", "fragment": f"new{kwargs['index']}"}

            def render(*args, **kwargs):
                return prefix if len(args) > 6 and args[6] is not None else rendered

            with patch.object(agent, "_generate_pass", side_effect=generate), \
                 patch.object(agent, "_studio_task", side_effect=render), \
                 patch.object(agent, "_verify_repair", return_value={"outcome": "fulfilled", "requirement_check": "done", "regressions": [], "next_instruction": "", "accepted_facts": []}):
                _, result_packages, _, _, transaction = _execute_repair_transaction(
                    repair=repair, brief=_brief(), packages=packages, target_video=before,
                    before_video=before, input_image=image, repo=root, studio=root,
                    studio_url="http://example", job_dir=root / "graph", job_id="job", out=root,
                    visual=[], model="model", temperature=0, code_attempts=1,
                    transaction_attempts=1, label="graph_repair", accepted_facts=[],
                )
            self.assertEqual(rewritten, [1, 2])
            self.assertEqual(result_packages[1]["fragment"], "new2")
            self.assertEqual(transaction["attempts"][0]["dependency_invalidated_passes"], [1, 2])

    def test_transaction_rolls_back_a_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "input.png"; image.write_bytes(b"image")
            before = root / "before.mp4"; before.write_bytes(b"before")
            rendered = root / "rendered.mp4"; rendered.write_bytes(b"rendered")
            packages = [{"vertex": "", "fragment": "old"}, {"vertex": "", "fragment": "old2"}]
            repair = _normalize_repair({
                "decision": "revise", "scope": "single_pass", "responsible_passes": [1],
                "instruction": "change", "required_visible_change": "visible change",
                "acceptance_criteria": ["change is present"], "preserve": ["color"], "graph_patch": {},
            }, 2)
            with patch.object(agent, "_generate_pass", return_value={"vertex": "", "fragment": "bad"}), \
                 patch.object(agent, "_studio_task", return_value=rendered), \
                 patch.object(agent, "_verify_repair", return_value={"outcome": "regressed", "requirement_check": "color broke", "regressions": ["color"], "next_instruction": "", "accepted_facts": []}):
                _, result_packages, result_video, _, transaction = _execute_repair_transaction(
                    repair=repair, brief=_brief(), packages=packages, target_video=before, before_video=before, input_image=image,
                    repo=root, studio=root, studio_url="http://example", job_dir=root / "graph", job_id="job", out=root,
                    visual=[], model="model", temperature=0, code_attempts=1, transaction_attempts=1,
                    label="repair", accepted_facts=[],
                )
            self.assertFalse(transaction["committed"])
            self.assertEqual(result_packages, packages)
            self.assertEqual(result_video, before)

    def test_human_mode_keeps_unfulfilled_candidate_separate_from_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "input.png"; image.write_bytes(b"image")
            before = root / "before.mp4"; before.write_bytes(b"before")
            rendered = root / "rendered.mp4"; rendered.write_bytes(b"candidate")
            packages = [{"vertex": "", "fragment": "old"}, {"vertex": "", "fragment": "old2"}]
            repair = _normalize_repair({
                "decision": "revise", "scope": "single_pass", "responsible_passes": [1],
                "instruction": "change", "required_visible_change": "visible change",
                "acceptance_criteria": ["change is present"], "preserve": [], "graph_patch": {},
            }, 2)
            with patch.object(agent, "_generate_pass", return_value={"vertex": "", "fragment": "candidate_shader"}), \
                 patch.object(agent, "_studio_task", return_value=rendered), \
                 patch.object(agent, "_verify_repair", return_value={"outcome": "partial", "requirement_check": "incomplete", "regressions": [], "next_instruction": "more", "accepted_facts": []}):
                _, result_packages, result_video, _, transaction = _execute_repair_transaction(
                    repair=repair, brief=_brief(), packages=packages, target_video=before, before_video=before, input_image=image,
                    repo=root, studio=root, studio_url="http://example", job_dir=root / "graph", job_id="job", out=root,
                    visual=[], model="model", temperature=0, code_attempts=1, transaction_attempts=1,
                    label="repair", accepted_facts=[], stage_unfulfilled=True,
                )
            self.assertFalse(transaction["committed"])
            self.assertTrue(transaction["staged_for_human_review"])
            self.assertTrue(transaction["preview_only"])
            self.assertEqual(result_packages, packages)
            self.assertEqual(result_video, before)
            self.assertEqual(Path(transaction["staged_video"]).read_bytes(), b"candidate")

    def test_contract_probe_flags_black_and_unexpected_static_output(self) -> None:
        import cv2
        import numpy as np
        with tempfile.TemporaryDirectory() as temporary:
            sheet = Path(temporary) / "prefix.jpg"
            self.assertTrue(cv2.imwrite(str(sheet), np.zeros((64, 192, 3), dtype=np.uint8)))
            result = _inspect_contract_sheet(sheet, _brief()["passes"][0])
            self.assertFalse(result["usable"])
            self.assertTrue(result["fatal"])
            self.assertFalse(result["dynamic_detected"])

    def test_fast_verifier_uses_seven_frames_without_intermediate_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            before = root / "before.mp4"; before.write_bytes(b"before")
            after = root / "after.mp4"; after.write_bytes(b"after")
            calls: list[tuple[Path, int]] = []
            captured: dict = {}

            def contact_sheet(video: Path, *, frame_count: int, work_dir: Path):
                calls.append((video, frame_count))
                return f"data:image/jpeg;base64,{video.stem}", []

            def json_call(**kwargs):
                captured["content"] = kwargs["content"]
                result = {
                    "outcome": "partial", "requirement_check": "motion improved",
                    "regressions": ["one", "two", "three"], "next_instruction": "increase motion",
                    "accepted_facts": ["a", "b", "c", "d"],
                }
                return kwargs["validator"](result)

            with patch.object(agent, "build_target_contact_sheet_data_url", side_effect=contact_sheet), \
                 patch.object(agent, "_validated_json_call", side_effect=json_call):
                result = _verify_repair(
                    repair={"required_visible_change": "move"}, target_video=before, before_video=before, after_video=after,
                    visual=[], model="model", temperature=0, work_dir=root,
                )

            self.assertEqual(calls, [(before, 7), (before, 7), (after, 7)])
            text_parts = "\n".join(part.get("text", "") for part in captured["content"])
            self.assertNotIn("INTERMEDIATE_PASS", text_parts)
            self.assertEqual(result["regressions"], ["one", "two"])
            self.assertEqual(result["accepted_facts"], ["a", "b", "c"])


if __name__ == "__main__":
    unittest.main()
