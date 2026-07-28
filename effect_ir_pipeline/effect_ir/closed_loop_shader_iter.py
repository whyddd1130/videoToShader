from __future__ import annotations

import argparse
import base64
import json
import os
import re
import time
from pathlib import Path
from typing import Any
from urllib import error, parse, request

import cv2
import numpy as np

from .compare_video_ir import apply_observation_guardrails_to_ir, build_structured_visual_observation_prompt, load_library_structured_rows
from .library_retrieval import build_reference_sources_block, select_top_reference
from .manifest import resolve_repo_path
from .model_client import generate_text
from .schema_ir import build_structured_ir_summary, normalize_structured_ir, parse_structured_ir_response
from .shader_builder import build_initial_edit_plan_from_ir, build_shader_from_edit_plan, extract_feedback_edit_plan, merge_edit_plan_delta
from .visual_observation import build_visual_observation_data, sample_frame_indices_for_video, sample_video_frames

PRIMITIVE_EDIT_VOCABULARY = {
    "geometry": [
        "identity",
        "translate",
        "scale_x",
        "scale_y",
        "rotate",
        "flip_x",
        "flip_y",
        "crop_or_pad",
        "perspective_skew",
        "radial_swirl",
        "wave_warp",
        "band_mask",
        "discrete_region_switch",
        "segmented_x_displacement",
    ],
    "appearance": [
        "brightness",
        "exposure",
        "contrast",
        "saturation",
        "rgb_shift",
        "color_remap",
        "blur",
        "sharpen",
        "vignette",
    ],
    "temporal_curves": [
        "linear",
        "ease_in",
        "ease_out",
        "ease_in_out",
        "early_progressive",
        "late_progressive",
    ],
}

GEOMETRY_EDIT_PRIMITIVES = set(PRIMITIVE_EDIT_VOCABULARY["geometry"]) - {"identity"}


def persist_stage_artifact(work_dir: Path, *, stage: str, iteration: int | None, payload: dict[str, Any]) -> Path:
    """Persist one pipeline-stage contract independently of the final report."""
    stage_dir = work_dir / "stages"
    stage_dir.mkdir(parents=True, exist_ok=True)
    prefix = "target" if iteration is None else f"iter_{iteration:02d}"
    path = stage_dir / f"{prefix}_{stage}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def load_top1_shader_text(reference: dict[str, Any], *, repo_root: Path) -> str:
    """Return the library Top-1 shader as the first rendered candidate."""
    code_dir_value = reference.get("code_dir")
    code_dir = Path(str(code_dir_value)) if code_dir_value else repo_root / "code" / str(reference["effect_name"])
    if not code_dir.is_absolute():
        code_dir = repo_root / code_dir
    glsl_files = sorted(code_dir.rglob("*.glsl"))
    vertex = next((path for path in glsl_files if path.name.lower().endswith((".vert.glsl", ".vert"))), None)
    fragment = next((path for path in glsl_files if path.name.lower().endswith((".frag.glsl", ".frag"))), None)
    if vertex is not None and fragment is not None:
        return f"```glsl\n{vertex.read_text(encoding='utf-8')}\n```\n\n```glsl\n{fragment.read_text(encoding='utf-8')}\n```\n"
    for lua_path in sorted(code_dir.rglob("*.lua")):
        source = lua_path.read_text(encoding="utf-8", errors="replace")
        vs = re.search(r"local\s+vs\s*=\s*\[\[(.*?)\]\]", source, re.DOTALL)
        fs = re.search(r"local\s+fs\s*=\s*\[\[(.*?)\]\]", source, re.DOTALL)
        if vs and fs:
            return f"```glsl\n{vs.group(1).strip()}\n```\n\n```glsl\n{fs.group(1).strip()}\n```\n"
    raise RuntimeError(f"Top-1 reference has no readable vertex/fragment shader: {code_dir}")


def extract_json_object(text: str) -> dict[str, Any]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _end = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    raise ValueError(f"No valid JSON object found in response: {text[:300]}")


def parse_ir(text: str) -> dict[str, Any]:
    try:
        return parse_structured_ir_response(text)
    except Exception:
        return normalize_structured_ir(extract_json_object(text))


def generate_video_ir(
    video_path: Path,
    *,
    input_image: Path | None,
    repo_root: Path,
    sample_id: str,
    model: str,
    temperature: float,
    sample_fps: float,
    image_size: int,
) -> dict[str, Any]:
    resolved = resolve_repo_path(repo_root, str(video_path))
    frame_indices = sample_frame_indices_for_video(resolved, sample_fps=sample_fps)
    sample = {
        "sample_id": sample_id,
        "effect_name": "unknown",
        "input_variant": "provided_image_and_video" if input_image else "video_only_first_frame_fallback",
        "video_path": str(video_path),
    }
    if input_image is not None:
        sample["input_image_path"] = str(input_image)
    observation_data = build_visual_observation_data(
        sample,
        repo_root=repo_root,
        frame_indices=frame_indices,
        image_size=image_size,
    )
    prompt = build_structured_visual_observation_prompt(sample, repo_root=repo_root, frame_indices=frame_indices, image_size=image_size)
    response = generate_text(prompt, model=model, temperature=temperature)
    structured_ir = apply_observation_guardrails_to_ir(parse_ir(response), observation_data)
    return {
        "input_image_path": None if input_image is None else str(input_image),
        "video_path": str(video_path),
        "resolved_video_path": str(resolved),
        "frame_indices": frame_indices,
        "structured_ir": structured_ir,
        "summary": build_structured_ir_summary(structured_ir),
        "raw_response": response,
    }

def extract_glsl_blocks(shader_text: str) -> tuple[str, str]:
    glsl_blocks: list[str] = []
    generic_blocks: list[str] = []
    active: list[str] | None = None
    active_language = ""
    for line in shader_text.splitlines():
        stripped = line.strip()
        if active is None and stripped.startswith("```"):
            active = []
            active_language = stripped[3:].strip().lower()
            continue
        if active is not None and stripped == "```":
            block = "\n".join(active).strip()
            generic_blocks.append(block)
            if active_language == "glsl":
                glsl_blocks.append(block)
            active = None
            active_language = ""
            continue
        if active is not None:
            active.append(line)
    blocks = glsl_blocks if len(glsl_blocks) >= 2 else generic_blocks
    if len(blocks) < 2:
        raise ValueError("Expected at least two GLSL code blocks in shader response")
    return blocks[0].strip() + "\n", blocks[1].strip() + "\n"


def validate_shader_text(shader_text: str) -> tuple[bool, str]:
    try:
        vertex, fragment = extract_glsl_blocks(shader_text)
    except Exception as exc:
        return False, str(exc)
    checks = [
        ("vertex", vertex),
        ("fragment", fragment),
    ]
    for label, source in checks:
        if "void main" not in source:
            return False, f"{label} shader is incomplete: missing void main"
        if source.count("{") != source.count("}"):
            return False, f"{label} shader has unbalanced braces"
        if len(source.strip()) < 80:
            return False, f"{label} shader is too short to be complete"
    if "attribute vec2 position" not in vertex:
        return False, "Vertex shader must declare attribute vec2 position"
    if "varying vec2 textureCoord" not in vertex or "varying vec2 textureCoord" not in fragment:
        return False, "Both shaders must declare varying vec2 textureCoord"
    if "gl_Position" not in vertex:
        return False, "Vertex shader must assign gl_Position"
    if "textureCoord" not in vertex or "position * 0.5 + 0.5" not in vertex:
        return False, "Vertex shader must map position to textureCoord = position * 0.5 + 0.5"
    required_fragment_tokens = [
        "uniform sampler2D inputImageTexture",
        "uniform float uProgress",
        "uniform float uTime",
        "texture2D",
        "gl_FragColor",
    ]
    for token in required_fragment_tokens:
        if token not in fragment:
            return False, f"Fragment shader is incomplete: missing {token}"
    allowed_uniforms = {"inputImageTexture", "uProgress", "uTime"}
    uniforms: set[str] = set()
    for line in fragment.splitlines():
        statement = line.split("//", 1)[0].strip().rstrip(";")
        parts = statement.split()
        if len(parts) >= 3 and parts[0] == "uniform":
            uniforms.add(parts[2].split("[", 1)[0])
    extra_uniforms = sorted(uniforms - allowed_uniforms)
    if extra_uniforms:
        return False, f"Fragment shader uses unsupported extra uniforms: {extra_uniforms}"
    return True, ""


def ensure_shader_precision_preamble(shader_text: str) -> str:
    vertex, fragment = extract_glsl_blocks(shader_text)
    preamble = (
        "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
        "precision highp float;\n"
        "#else\n"
        "precision mediump float;\n"
        "#endif\n\n"
    )
    if "precision highp float" not in vertex and "precision mediump float" not in vertex:
        vertex = preamble + vertex
    if "precision highp float" not in fragment and "precision mediump float" not in fragment:
        fragment = preamble + fragment
    return f"```glsl\n{vertex.strip()}\n```\n\n```glsl\n{fragment.strip()}\n```"




def write_shader_files(shader_text: str, out_dir: Path, iteration: int) -> tuple[Path, Path]:
    vertex, fragment = extract_glsl_blocks(shader_text)
    out_dir.mkdir(parents=True, exist_ok=True)
    vertex_path = out_dir / f"iter_{iteration:02d}.vert.glsl"
    fragment_path = out_dir / f"iter_{iteration:02d}.frag.glsl"
    vertex_path.write_text(vertex, encoding="utf-8")
    fragment_path.write_text(fragment, encoding="utf-8")
    return vertex_path, fragment_path


def validate_rendered_video(video_path: Path, *, min_mean: float = 1.0, min_std: float = 0.5) -> tuple[bool, str]:
    if not video_path.exists() or video_path.stat().st_size == 0:
        return False, f"rendered video is missing or empty: {video_path}"
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False, f"rendered video cannot be opened: {video_path}"
    try:
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if frame_count <= 0:
            return False, "rendered video has no readable frames"
        sample_positions = sorted({0, frame_count // 4, frame_count // 2, (frame_count * 3) // 4, frame_count - 1})
        means: list[float] = []
        stds: list[float] = []
        readable = 0
        for pos in sample_positions:
            cap.set(cv2.CAP_PROP_POS_FRAMES, pos)
            ok, frame = cap.read()
            if not ok:
                continue
            readable += 1
            means.append(float(np.mean(frame)))
            stds.append(float(np.std(frame)))
        if readable == 0:
            return False, "rendered video has no readable sampled frames"
        mean_value = float(np.mean(means))
        std_value = float(np.mean(stds))
        if mean_value < min_mean and std_value < min_std:
            return False, f"rendered video appears black or blank: mean={mean_value:.3f}, std={std_value:.3f}"
    finally:
        cap.release()
    return True, ""


def validate_initial_black_frame_contract(target_video: Path, candidate_video: Path) -> tuple[bool, str]:
    """Verify a target-required black opening without using it as a ranking score."""
    stats: list[tuple[float, float]] = []
    for path in [target_video, candidate_video]:
        cap = cv2.VideoCapture(str(path))
        if not cap.isOpened():
            return False, f"cannot open video for initial black-frame validation: {path}"
        try:
            ok, frame = cap.read()
        finally:
            cap.release()
        if not ok:
            return False, f"cannot read first frame for initial black-frame validation: {path}"
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        stats.append((float(np.mean(gray)), float(np.mean(gray <= 16))))
    (target_mean, target_dark), (candidate_mean, candidate_dark) = stats
    target_is_black = target_mean <= 16.0 and target_dark >= 0.90
    if not target_is_black:
        return True, ""
    if candidate_mean > 24.0 or candidate_dark < 0.85:
        return False, (
            "target starts from black but candidate first frame does not: "
            f"target_mean={target_mean:.2f}, target_dark={target_dark:.3f}, "
            f"candidate_mean={candidate_mean:.2f}, candidate_dark={candidate_dark:.3f}"
        )
    return True, ""


def video_starts_black(video_path: Path) -> bool:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False
    try:
        ok, frame = cap.read()
    finally:
        cap.release()
    if not ok:
        return False
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return float(np.mean(gray)) <= 16.0 and float(np.mean(gray <= 16)) >= 0.90


def infer_library_target_effect_name(video_path: Path, *, repo_root: Path) -> str | None:
    """Infer self effect name for library-video ablation tests.

    Expected library target naming: test_videos/lib/EffectName__inputVariant.mp4.
    """
    resolved = resolve_repo_path(repo_root, str(video_path))
    try:
        relative = resolved.relative_to(repo_root)
    except ValueError:
        relative = resolved
    parts = relative.parts
    if len(parts) < 3 or parts[0] != "test_videos" or parts[1] != "lib":
        return None
    stem = resolved.stem
    if "__" not in stem:
        return None
    effect_name = stem.split("__", 1)[0].strip()
    return effect_name or None




def _extract_text_from_llm_body(body: dict[str, Any]) -> str:
    choices = body.get("choices")
    if isinstance(choices, list) and choices:
        message = choices[0].get("message") if isinstance(choices[0], dict) else None
        if isinstance(message, dict) and message.get("content") is not None:
            text = _content_to_text(message.get("content"))
            if text.strip():
                return text
            raise RuntimeError(
                "LLM response contained empty message content; "
                f"finish_reason={choices[0].get('finish_reason')}; usage={body.get('usage')}"
            )
    if body.get("content") is not None:
        text = _content_to_text(body.get("content"))
        if text.strip():
            return text
        raise RuntimeError(f"LLM response contained empty top-level content; keys={sorted(body.keys())}")
    message = body.get("message")
    if isinstance(message, dict) and message.get("content") is not None:
        text = _content_to_text(message.get("content"))
        if text.strip():
            return text
        raise RuntimeError(f"LLM response contained empty message content; keys={sorted(body.keys())}")
    if body.get("output_text") is not None:
        return str(body.get("output_text"))
    raise RuntimeError(f"Cannot extract text from LLM response keys={sorted(body.keys())}")


def _content_to_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks: list[str] = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text" and item.get("text") is not None:
                    chunks.append(str(item.get("text")))
                elif item.get("content") is not None:
                    chunks.append(_content_to_text(item.get("content")))
            elif item is not None:
                chunks.append(str(item))
        text = "\n".join(chunks)
        if text.strip():
            return text
        raise RuntimeError("LLM response contained no text content")
    return str(content)


def _chat_content_blocks(content: str | list[dict[str, Any]]) -> str | list[dict[str, Any]]:
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return content


def _maybe_add_generation_limits(payload: dict[str, Any], *, max_tokens: int, temperature: float | None) -> None:
    # Some newer chat-completions endpoints reject legacy max_tokens and non-default
    # temperature values. Keep the payload close to Wanqing's documented format.
    if max_tokens:
        payload["max_completion_tokens"] = max_tokens
    if temperature not in (None, 0, 0.0, 1, 1.0):
        payload["temperature"] = temperature


def call_code_llm_text(prompt: str, *, model: str, temperature: float, max_tokens: int, timeout: float) -> str:
    endpoint = (
        os.environ.get("EFFECT_IR_CODE_LLM_ENDPOINT")
        or os.environ.get("EFFECT_IR_LLM_ENDPOINT")
        or "http://wanqing.internal/api/gateway/v1/endpoints/chat/completions"
    )
    api_key = os.environ.get("EFFECT_IR_CODE_LLM_API_KEY") or os.environ.get("WQ_API_KEY", "EMPTY")
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": _chat_content_blocks(prompt)}],
    }
    _maybe_add_generation_limits(payload, max_tokens=max_tokens, temperature=temperature)
    req = request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    retries = max(1, int(os.environ.get("EFFECT_IR_CODE_LLM_RETRIES", os.environ.get("EFFECT_IR_LLM_RETRIES", "3"))))
    base_sleep = float(os.environ.get("EFFECT_IR_CODE_LLM_RETRY_SLEEP", os.environ.get("EFFECT_IR_LLM_RETRY_SLEEP", "2")))
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with request.urlopen(req, timeout=timeout) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            return _extract_text_from_llm_body(body)
        except (error.HTTPError, error.URLError, TimeoutError, ConnectionError, OSError, RuntimeError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(base_sleep * attempt)
    assert last_error is not None
    raise RuntimeError(f"Code LLM request failed after {retries} attempts: {last_error}") from last_error


def call_llm_content(content: str | list[dict[str, Any]], *, model: str, temperature: float, max_tokens: int, timeout: float) -> str:
    endpoint = os.environ.get("EFFECT_IR_LLM_ENDPOINT", "http://wanqing.internal/api/gateway/v1/endpoints/chat/completions")
    api_key = os.environ.get("EFFECT_IR_LLM_API_KEY") or os.environ.get("WQ_API_KEY", "EMPTY")
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": _chat_content_blocks(content)}],
    }
    _maybe_add_generation_limits(payload, max_tokens=max_tokens, temperature=temperature)
    req = request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    retries = max(1, int(os.environ.get("EFFECT_IR_LLM_RETRIES", "3")))
    base_sleep = float(os.environ.get("EFFECT_IR_LLM_RETRY_SLEEP", "2"))
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with request.urlopen(req, timeout=timeout) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            return _extract_text_from_llm_body(body)
        except (error.HTTPError, error.URLError, TimeoutError, ConnectionError, OSError, RuntimeError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(base_sleep * attempt)
    assert last_error is not None
    raise RuntimeError(f"LLM request failed after {retries} attempts: {last_error}") from last_error


def generate_llm_visual_feedback(
    *,
    target_video: Path,
    candidate_video: Path,
    repo_root: Path,
    target_ir: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    current_shader: str | None,
    previous_candidate_video: Path | None = None,
    previous_required_changes: list[dict[str, str]] | None = None,
    model: str,
    temperature: float,
    image_size: int,
) -> dict[str, Any]:
    content = build_llm_visual_feedback_content(
        target_video=resolve_repo_path(repo_root, str(target_video)),
        candidate_video=resolve_repo_path(repo_root, str(candidate_video)),
        target_ir=target_ir,
        candidate_ir=candidate_ir,
        current_shader=current_shader,
        previous_candidate_video=(
            resolve_repo_path(repo_root, str(previous_candidate_video))
            if previous_candidate_video is not None
            else None
        ),
        previous_required_changes=previous_required_changes,
        image_size=image_size,
    )
    review_attempts = max(1, int(os.environ.get("EFFECT_IR_VISUAL_REVIEW_ATTEMPTS", "3")))
    failed_attempts: list[dict[str, Any]] = []
    for attempt in range(1, review_attempts + 1):
        response = call_llm_content(
            content,
            model=model,
            temperature=temperature,
            # Input context is compacted above, but reasoning-capable models still
            # need enough output budget to finish reasoning and emit the JSON.
            max_tokens=int(os.environ.get("EFFECT_IR_VISUAL_FEEDBACK_MAX_TOKENS", "6000")),
            timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
        )
        try:
            parsed = extract_json_object(response)
            parsed = _apply_feedback_guardrails(parsed, target_ir=target_ir)
            parsed = _normalize_feedback_score(parsed)
            error_message = _visual_feedback_validation_error(
                parsed,
                expected_required_changes=previous_required_changes,
            )
        except Exception as exc:
            parsed = None
            error_message = f"invalid JSON review: {exc}"
        if not error_message:
            return {
                "model": model,
                "raw_response": response,
                "parsed": parsed,
                "review_attempt": attempt,
                "failed_review_attempts": failed_attempts,
            }
        failed_attempts.append(
            {
                "attempt": attempt,
                "reason": error_message,
                "response_preview": response[:500],
            }
        )
    reasons = "; ".join(item["reason"] for item in failed_attempts)
    raise RuntimeError(f"Visual review did not return a complete score/edit plan after {review_attempts} attempts: {reasons}")


def _visual_feedback_validation_error(
    parsed: dict[str, Any],
    *,
    expected_required_changes: list[dict[str, str]] | None = None,
) -> str:
    score = parsed.get("match_score")
    if not isinstance(score, dict) or score.get("overall") is None:
        return "missing numeric match_score.overall"
    try:
        float(score["overall"])
    except (TypeError, ValueError):
        return "match_score.overall is not numeric"
    if not str(score.get("reason", "")).strip():
        return "missing match_score.reason"
    if not isinstance(parsed.get("optimization_priority"), dict):
        return "missing optimization_priority"
    if not isinstance(parsed.get("primitive_edit_plan"), dict):
        return "missing primitive_edit_plan"
    if not str(parsed.get("most_important_gap", "")).strip():
        return "missing most_important_gap"
    expected_required_changes = expected_required_changes or []
    if expected_required_changes:
        check = parsed.get("required_change_check")
        if not isinstance(check, dict):
            return "missing required_change_check"
        checked_items = check.get("items")
        if not isinstance(checked_items, list):
            return "missing required_change_check.items"
        by_id = {
            str(item.get("id", "")).strip(): item
            for item in checked_items
            if isinstance(item, dict) and str(item.get("id", "")).strip()
        }
        for expected in expected_required_changes:
            item_id = str(expected.get("id", "")).strip()
            item = by_id.get(item_id)
            if not isinstance(item, dict):
                return f"missing required_change_check item: {item_id}"
            status = str(item.get("status", "")).strip().lower()
            if status not in {"implemented", "partial", "not_implemented", "regressed"}:
                return f"invalid required_change_check status: {item_id}"
            if not str(item.get("evidence", "")).strip():
                return f"missing required_change_check evidence: {item_id}"
    return ""


def _normalize_required_changes(value: Any) -> list[dict[str, str]]:
    """Normalize atomic, independently verifiable changes without parsing prose."""
    if not isinstance(value, list):
        return []
    normalized: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, item in enumerate(value, 1):
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("id", "")).strip() or f"change_{index}"
        change = str(item.get("change", "")).strip()
        if not change or item_id in seen:
            continue
        seen.add(item_id)
        normalized.append({"id": item_id, "change": change})
    return normalized[:4]


def _normalize_frozen_constraints(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return list(dict.fromkeys(str(item).strip() for item in value if str(item).strip()))[:8]


def _normalize_feedback_score(parsed: dict[str, Any]) -> dict[str, Any]:
    parsed = dict(parsed)
    score = parsed.get("match_score")
    if not isinstance(score, dict):
        score = {
            "overall": parsed.get("overall_score"),
            "reason": parsed.get("score_reason", ""),
        }
    normalized: dict[str, Any] = {}
    value = score.get("overall")
    if value is None:
        normalized["overall"] = None
    else:
        try:
            normalized["overall"] = max(0.0, min(100.0, float(value)))
        except (TypeError, ValueError):
            normalized["overall"] = None
    normalized["reason"] = str(score.get("reason", "")).strip()
    parsed["match_score"] = normalized
    # This is an optimization controller, not a final-ranking score.  It
    # prevents an easy colour match from consuming the next iteration while
    # the perceptually dominant spatial process is still missing.
    priority = parsed.get("optimization_priority")
    if not isinstance(priority, dict):
        priority = {}
    allowed_dimensions = {"geometry_motion", "temporal_process", "effect_region", "appearance"}
    blocking = [str(item).strip().lower() for item in priority.get("blocking_dimensions", []) if str(item).strip().lower() in allowed_dimensions]
    parsed["optimization_priority"] = {
        "blocking_dimensions": list(dict.fromkeys(blocking)),
        "primary_focus": str(priority.get("primary_focus", "appearance")).strip().lower(),
        "appearance_edits_allowed": bool(priority.get("appearance_edits_allowed", not blocking)),
        "required_changes": _normalize_required_changes(priority.get("required_changes")),
        "frozen_constraints": _normalize_frozen_constraints(priority.get("frozen_constraints")),
        "reason": str(priority.get("reason", "")).strip(),
    }
    compositing_mode = str(parsed.get("compositing_mode", "")).strip().lower()
    parsed["compositing_mode"] = (
        compositing_mode
        if compositing_mode in {"replace_source", "preserve_source", "local_overlay"}
        else "replace_source"
    )
    raw_background = parsed.get("background_policy")
    raw_background = raw_background if isinstance(raw_background, dict) else {}
    feedback_text = json.dumps(parsed, ensure_ascii=False).lower()
    black_start = any(term in feedback_text for term in ["black start", "initial black", "p=0 black", "黑场起步", "黑场开始", "起始为全黑", "p=0 完全黑", "p=0为黑场"])
    black_outside = any(term in feedback_text for term in ["outside black", "black outside", "范围外为黑", "区域外为黑", "遮罩外输出黑", "平面外区域保持黑"])
    initial_canvas = str(raw_background.get("initial_canvas", "black" if black_start else "transformed_effect")).strip().lower()
    outside_fill = str(raw_background.get("outside_effect_region", "black" if black_outside or black_start else "clamp_to_edge")).strip().lower()
    source_visibility = str(raw_background.get("source_visibility", "transformed_region_only" if black_outside or black_start else "full_canvas")).strip().lower()
    parsed["background_policy"] = {
        "initial_canvas": initial_canvas if initial_canvas in {"black", "source", "transformed_effect"} else "transformed_effect",
        "outside_effect_region": outside_fill if outside_fill in {"black", "source", "clamp_to_edge"} else "clamp_to_edge",
        "source_visibility": source_visibility if source_visibility in {"full_canvas", "transformed_region_only"} else "full_canvas",
    }
    if parsed["background_policy"]["initial_canvas"] == "black" or parsed["background_policy"]["outside_effect_region"] == "black":
        parsed["compositing_mode"] = "replace_source"
    return parsed


def extract_feedback_overall_score(feedback: dict[str, Any] | None) -> float | None:
    if not feedback:
        return None
    parsed = feedback.get("parsed")
    if not isinstance(parsed, dict):
        return None
    score = parsed.get("match_score")
    if not isinstance(score, dict):
        return None
    overall = score.get("overall")
    if overall is None:
        return None
    try:
        return float(overall)
    except (TypeError, ValueError):
        return None


def extract_optimization_priority(feedback: dict[str, Any] | None) -> dict[str, Any]:
    """Return the mandatory focus for the next shader-editing iteration."""
    parsed = feedback.get("parsed") if isinstance(feedback, dict) else None
    priority = parsed.get("optimization_priority") if isinstance(parsed, dict) else None
    if not isinstance(priority, dict):
        return {
            "blocking_dimensions": [],
            "primary_focus": "appearance",
            "appearance_edits_allowed": True,
            "required_changes": [],
            "frozen_constraints": [],
            "reason": "审查未返回下一轮优先级，按普通 edit plan 执行",
        }
    return {
        "blocking_dimensions": list(priority.get("blocking_dimensions", [])),
        "primary_focus": str(priority.get("primary_focus", "appearance")),
        "appearance_edits_allowed": bool(priority.get("appearance_edits_allowed", True)),
        "required_changes": _normalize_required_changes(priority.get("required_changes")),
        "frozen_constraints": _normalize_frozen_constraints(priority.get("frozen_constraints")),
        "reason": str(priority.get("reason", "")),
    }


def reconcile_atomic_change_state(
    parsed_feedback: dict[str, Any],
    *,
    previous_required_changes: list[dict[str, str]],
    previous_frozen_constraints: list[str],
) -> dict[str, Any]:
    """Carry only unfinished atomic changes forward and freeze completed ones."""
    priority = parsed_feedback.get("optimization_priority")
    priority = dict(priority) if isinstance(priority, dict) else {}
    proposed = _normalize_required_changes(priority.get("required_changes"))
    proposed_by_id = {item["id"]: item for item in proposed}
    frozen = _normalize_frozen_constraints(
        previous_frozen_constraints + _normalize_frozen_constraints(priority.get("frozen_constraints"))
    )

    check = parsed_feedback.get("required_change_check")
    checked_items = check.get("items", []) if isinstance(check, dict) else []
    checked_by_id = {
        str(item.get("id", "")).strip(): item
        for item in checked_items
        if isinstance(item, dict) and str(item.get("id", "")).strip()
    }
    unresolved: list[dict[str, str]] = []
    completed_ids: set[str] = set()
    for required in previous_required_changes:
        item_id = required["id"]
        checked = checked_by_id.get(item_id, {})
        status = str(checked.get("status", "")).strip().lower()
        if status == "implemented":
            completed_ids.add(item_id)
            frozen.append(f"保持已完成变化 [{item_id}]：{required['change']}")
        elif status == "partial":
            remaining = str(checked.get("remaining_change", "")).strip() or required["change"]
            unresolved.append({"id": item_id, "change": remaining})

    merged: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in unresolved + proposed:
        if item["id"] in completed_ids or item["id"] in seen:
            continue
        seen.add(item["id"])
        merged.append(item)
    priority["required_changes"] = merged[:4]
    priority["frozen_constraints"] = _normalize_frozen_constraints(frozen)
    parsed_feedback["optimization_priority"] = priority
    return parsed_feedback


def _compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2)


def _compact_ir_context(value: dict[str, Any] | None) -> dict[str, Any] | None:
    """Keep only IR fields that can affect the next shader decision."""
    if not isinstance(value, dict):
        return None
    keys = (
        "summary", "region_scope", "geometry_ops", "appearance_ops",
        "temporal_pattern", "motion_hint", "color_hint", "edge_hint",
        "shape_hint", "geometry_pattern", "transform_primitives",
        "operation_family", "complexity", "render_contract",
    )
    return {key: value[key] for key in keys if key in value and value[key] not in (None, "", [], {})}


def _compact_feedback_context(value: dict[str, Any] | None) -> dict[str, Any] | None:
    """Drop raw responses and duplicated evidence before feedback is reused."""
    parsed = value.get("parsed") if isinstance(value, dict) and "parsed" in value else value
    if not isinstance(parsed, dict):
        return None
    keys = (
        "temporal_process_observation", "candidate_process_observation",
        "key_transition_observation", "motion_signature", "most_important_gap",
        "match_score", "compositing_mode", "background_policy",
        "optimization_priority", "next_change_in_plain_words",
        "optimization_plan", "operation_family", "change_family_allowed",
        "parameter_hints", "confidence",
    )
    return {key: parsed[key] for key in keys if key in parsed and parsed[key] not in (None, "", [], {})}


def _shader_structure_summary(shader: str | None) -> dict[str, Any] | None:
    """Tell the reviewer which operations exist without sending GLSL source."""
    if not shader:
        return None
    token_text = shader
    for separator in "();,+-*/=[]{}\n\t":
        token_text = token_text.replace(separator, " ")
    active_amounts = sorted(
        {token[7:] for token in token_text.split() if token.startswith("amount_") and len(token) > 7}
    )[:16]
    compact = "".join(shader.split())
    return {
        "active_amounts": active_amounts,
        "has_progress": "uProgress" in shader,
        "has_time": "uTime" in shader,
        "uses_source_mix": "mix(originalColor" in compact or "mix(source" in compact,
    }


def _format_list(value: Any) -> str:
    if isinstance(value, list):
        if not value:
            return "- 无"
        return "\n".join(f"- {json.dumps(item, ensure_ascii=False) if isinstance(item, (dict, list)) else item}" for item in value)
    if value in (None, ""):
        return "- 无"
    return f"- {value}"


def write_iteration_review_markdown(
    *,
    path: Path,
    iteration: int,
    rendered_video: Path,
    vertex_shader: Path,
    fragment_shader: Path,
    shader_source_markdown: Path | None,
    selected_references: list[dict[str, Any]],
    shader_edit_plan_used: dict[str, Any] | None,
    feedback_used_for_prompt: dict[str, Any] | None,
    feedback_after_render: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    shader_builder_record: dict[str, Any] | None,
) -> None:
    parsed = feedback_after_render.get("parsed") if isinstance(feedback_after_render, dict) else None
    parsed = parsed if isinstance(parsed, dict) else {}
    match_score = parsed.get("match_score") if isinstance(parsed.get("match_score"), dict) else {}
    if match_score.get("overall") is None:
        raise ValueError("Refusing to write iteration report without a valid overall score")
    optimization_priority = extract_optimization_priority(feedback_after_render)
    required_change_check = parsed.get("required_change_check")
    required_change_check = required_change_check if isinstance(required_change_check, dict) else {}
    next_plan = parsed.get("primitive_edit_plan")
    score_text = str(match_score.get("overall"))
    lines = [
        f"# Iteration {iteration:02d} Review",
        "",
        "## 结果文件",
        "",
        f"- rendered_video: `{rendered_video}`",
        f"- vertex_shader: `{vertex_shader}`",
        f"- fragment_shader: `{fragment_shader}`",
    ]
    if shader_source_markdown is not None:
        lines.append(f"- shader_source_markdown: `{shader_source_markdown}`")
    lines.extend(
        [
            "",
            "## 分数",
            "",
            f"- overall_score: `{score_text}`",
            f"- reason: {match_score.get('reason') or '无'}",
            f"- 下一轮阻塞项: {', '.join(optimization_priority['blocking_dimensions']) or '无'}",
            f"- 下一轮主修改方向: {optimization_priority['primary_focus'] or '无'}",
            f"- 外观微调是否可作为主修改: {'是' if optimization_priority['appearance_edits_allowed'] else '否'}",
            "- 下一轮原子必改项:",
            _format_list(optimization_priority["required_changes"]),
            "- 已完成且不得回退:",
            _format_list(optimization_priority["frozen_constraints"]),
            "",
            "## 上一轮必改项验收",
            "",
            _format_list(required_change_check.get("items")),
            f"- 合成模式: `{parsed.get('compositing_mode', 'replace_source')}`",
            f"- 背景策略: `{json.dumps(parsed.get('background_policy', {}), ensure_ascii=False)}`",
            "",
            "## 本轮审查意见",
            "",
            f"- target_video_observation: {parsed.get('target_video_observation') or '无'}",
            f"- candidate_video_observation: {parsed.get('candidate_video_observation') or '无'}",
            f"- most_important_gap: {parsed.get('most_important_gap') or '无'}",
            f"- temporal_process_observation: {parsed.get('temporal_process_observation') or '无'}",
            f"- key_transition_observation: {parsed.get('key_transition_observation') or '无'}",
            f"- motion_signature: {parsed.get('motion_signature') or '无'}",
            f"- visual_difference_summary: {parsed.get('visual_difference_summary') or '无'}",
            "",
            "### 进度证据摘要",
            "",
            _format_list(parsed.get("progress_evidence_summary")),
            "",
            "### 可见证据",
            "",
            _format_list(parsed.get("evidence")),
            "",
            "### 候选画面问题",
            "",
            _format_list(parsed.get("candidate_errors")),
            "",
            "## 下一轮修改方向",
            "",
            "### 画面语言",
            "",
            _format_list(parsed.get("next_change_in_plain_words")),
            "",
            "### Shader 修改方向",
            "",
            _format_list(parsed.get("optimization_plan")),
            "",
            "### 下一轮 edit plan",
            "",
            "```json",
            _compact_json(next_plan or {}),
            "```",
            "",
            "## 本轮生成时使用的 edit plan",
            "",
            "```json",
            _compact_json(shader_edit_plan_used or {}),
            "```",
            "",
            "## 上一轮关键上下文",
            "",
            "```json",
            _compact_json(_compact_feedback_context(feedback_used_for_prompt)),
            "```",
            "",
            "## 候选视频 IR 摘要",
            "",
            "```json",
            _compact_json(_compact_ir_context(candidate_ir) or {}),
            "```",
            "",
            "## Shader builder 摘要",
            "",
            "```json",
            _compact_json({
                "backend": (shader_builder_record or {}).get("backend"),
                "builder_notes": (shader_builder_record or {}).get("builder_notes", []),
                "previous_failure": (shader_builder_record or {}).get("previous_failure"),
            }),
            "```",
            "",
            "## 当前参考摘要",
            "",
            "```json",
            _compact_json([
                {
                    "effect_name": item.get("effect_name"),
                    "display_name": item.get("display_name"),
                    "similarity": item.get("similarity"),
                }
                for item in selected_references[:3]
                if isinstance(item, dict)
            ]),
            "```",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def build_llm_visual_feedback_content(
    *,
    target_video: Path,
    candidate_video: Path,
    target_ir: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    current_shader: str | None,
    previous_candidate_video: Path | None = None,
    previous_required_changes: list[dict[str, str]] | None = None,
    image_size: int,
) -> list[dict[str, Any]]:
    # Five evenly spaced samples preserve onset, middle process and final state
    # while keeping multimodal review latency manageable.
    progress_values = [0.0, 0.25, 0.5, 0.75, 1.0]
    contact_sheet_url = _build_comparison_contact_sheet_data_url(
        target_video,
        candidate_video,
        progress_values=progress_values,
        image_size=image_size,
    )
    change_sheet_url = None
    previous_required_changes = previous_required_changes or []
    if previous_candidate_video is not None and previous_required_changes:
        change_sheet_url = _build_comparison_contact_sheet_data_url(
            previous_candidate_video,
            candidate_video,
            # This sheet is only an acceptance check for the previous atomic
            # requirement, so endpoints plus midpoint are sufficient.
            progress_values=[0.0, 0.5, 1.0],
            image_size=image_size,
            first_label="before",
            second_label="after",
        )
    primitive_schema = {
        "selected_primitives": [
            {
                "name": "one primitive from primitive_vocabulary",
                "role": "primary / secondary / correction",
                "params": {
                    "from": "number/bool/list if known, otherwise null",
                    "to": "number/bool/list if known, otherwise null",
                    "center": [0.5, 0.5],
                    "axis": "x/y/radial/none",
                    "strength": "weak/medium/strong",
                },
                "temporal": "one curve from primitive_vocabulary.temporal_curves",
                "evidence": "plain visual evidence from the target/candidate frames, not jargon",
                "confidence": 0.0,
            }
        ],
        "rejected_primitives": [
            {
                "name": "primitive name",
                "reason": "why evidence does not support it",
            }
        ],
        "implementation_notes": [
            "short GLSL-level notes tied to the visible change, not long terminology"
        ],
        "temporal_controller": {
            "mode": "continuous_monotonic / cyclic / impulse / freeform",
            "driver": "shared for continuous_monotonic, otherwise model_defined",
            "shared_progress_curve": "linear / ease_in / ease_out / ease_in_out / early_progressive",
            "onset": "early / middle / late / immediate",
            "trend": "plain description of the complete visible process",
            "evidence": "video evidence for this temporal form"
        },
    }
    required_change_instruction = (
        "第二张 contact sheet 的三列是 BEFORE/AFTER/DIFF，用它验收上一轮必改项。\n"
        f"上一轮原子必改项：{json.dumps(previous_required_changes, ensure_ascii=False)}\n"
        "required_change_check.items 必须逐项保留相同 id，并只依据修改前后视频中可见的动态变化判断："
        "implemented=已清楚落实；partial=方向正确但不足；not_implemented=基本未发生；"
        "regressed=向相反方向变化。不要根据 Shader 源码猜测。\n"
        if change_sheet_url is not None
        else "本轮没有上一轮必改项，required_change_check.items 输出空数组。\n"
    )
    text = (
        "你是视频特效过程审查员。看 contact sheet：每行同一进度，三列为 TARGET/CANDIDATE/DIFF。\n"
        f"{required_change_instruction}"
        "目标不是复刻某一帧截图，而是还原从 p=0 到 p=1 的变化规律。少用术语，以画面为准。\n"
        "请把各进度帧当作时间采样来总结运动/出现/增强/消失的过程，不要描述横线、块、遮挡在脸上或画面中的精确位置；位置只允许概括为全局/局部、上中下、横向/纵向。\n"
        "重点描述：变化何时开始、强度如何随进度变化、元素是连续移动还是跳变、边缘硬/软；并判断目标是完整替换原图采样，还是应保留原图作为全局/局部底图。\n"
        "最多写 2 个关键过程差异、3 条修改建议。建议必须说这个动态过程要怎么改，避免让 shader 拟合单帧形象。\n"
        "不要使用固定峰值、阶段、after 或 handoff 模板。连续增强/减弱过程使用 temporal_controller.mode=continuous_monotonic，并让全部相关操作共享同一个连续进度；周期、瞬时或其他非单调过程只描述完整可见规律，由代码模型直接实现。\n"
        "primitive_edit_plan 可只写本轮增量；未提及的上一轮操作会保留。若要删除旧操作，必须把它放入 rejected_primitives。\n"
        "若目标是局部硬边碎片/条带跳切，必须组合选择 band_mask、discrete_region_switch、segmented_x_displacement；不要把它笼统写成 pixelation。\n"
        "评分只给整体人类观感 overall+reason，不打分项：0-20 完全不像；21-40 第一眼不像；41-60 同类但关键错；61-80 接近；81-100 很像。\n"
        "这是为下一轮服务的审查，不是最终选 best。若目标的空间形变、翻转、位移、运动节奏或局部作用区域尚未复现，把对应维度列入 blocking_dimensions；此时不要用任何次级外观变化替代缺失的核心过程。\n"
        "required_changes 必须拆成 1 到 4 个可独立验收的原子变化：方向、轴向、强度、启动时机等不得合并在同一项。已经正确的变化不要再次写入 required_changes，而应写入 frozen_constraints，明确下一轮保持不回退。\n"
        "只有空间/时序/区域的核心过程已经成立，才允许把 appearance 作为下一轮主修改。若目标本来没有空间变化或局部区域，不要把它列为阻塞项。reason 必须解释为何本轮应优先处理 primary_focus，以及其他空间、时序、区域、颜色、亮度、模糊或纹理变化为何应暂缓或可作为次要修改。\n"
        "第一眼不是同一种效果 overall≤40；主效果缺失 overall≤30。只输出 JSON，且第一项必须是 match_score（overall 必须是 0-100 数字，绝不能省略）：\n"
        "{\n"
        "  \"match_score\": {\"overall\": 0, \"reason\": \"像人类评审一样说明为什么这个整体分数合理\"},\n"
        "  \"temporal_process_observation\": \"目标从 p=0 到 p=1 的整体变化过程，强调动态规律而非单帧位置\",\n"
        "  \"candidate_process_observation\": \"候选从 p=0 到 p=1 的整体变化过程\",\n"
        "  \"key_transition_observation\": \"关键帧之间发生了什么，例如开始、持续变化、消退或跳变\",\n"
        "  \"motion_signature\": \"用短语概括目标动态：例如稳定底图+细水平跳切/逐渐粗块化/连续波动/瞬时闪烁\",\n"
        "  \"progress_evidence_summary\": [\"最多 4 条进度证据，只写变化趋势，不写精确位置\"],\n"
        "  \"target_video_observation\": \"目标视频整体动态观感\",\n"
        "  \"candidate_video_observation\": \"候选视频整体动态观感\",\n"
        "  \"most_important_gap\": \"最重要的过程差距，不要写成某一帧的局部截图差异\",\n"
        "  \"visual_difference_summary\": \"一句话中文总结，不超过 60 字\",\n"
        "  \"evidence\": [\"最多 3 条可见证据\"],\n"
        "  \"candidate_errors\": [\"最多 2 条候选画面问题\"],\n"
        "  \"required_change_check\": {\"items\": [{\"id\": \"与上一轮完全相同\", \"change\": \"原子变化\", \"status\": \"implemented / partial / not_implemented / regressed\", \"evidence\": \"可见证据\", \"visible_delta\": \"实际变化\", \"remaining_change\": \"partial 时只写尚未完成的部分\"}]},\n"
        "  \"compositing_mode\": \"replace_source / preserve_source / local_overlay；空间重映射、全屏模糊、像素化和全屏色差通常为 replace_source；只有画面证据显示原图应继续可见时才用 preserve_source，局部效果用 local_overlay\",\n"
        "  \"background_policy\": {\"initial_canvas\": \"black / source / transformed_effect\", \"outside_effect_region\": \"black / source / clamp_to_edge\", \"source_visibility\": \"full_canvas / transformed_region_only\"},\n"
        "  \"optimization_priority\": {\"blocking_dimensions\": [\"geometry_motion / temporal_process / effect_region / appearance\"], \"primary_focus\": \"geometry_motion / temporal_process / effect_region / appearance\", \"appearance_edits_allowed\": false, \"required_changes\": [{\"id\": \"稳定简短标识\", \"change\": \"单一、可独立验收的动态变化\"}], \"frozen_constraints\": [\"已经正确、下一轮不得回退的可见变化\"], \"reason\": \"解释优先级\"},\n"
        "  \"next_change_in_plain_words\": [\"最多 3 条，直接说动态过程要怎么改\"],\n"
        "  \"optimization_plan\": [\"最多 3 条 shader 修改方向，必须来自过程差异\"],\n"
        "  \"primitive_edit_plan\": <见 primitive_edit_plan_schema>,\n"
        "  \"operation_family\": \"keep_current_family / tune_color_curve / tune_temporal_curve / small_geometry_adjustment / change_family\",\n"
        "  \"change_family_allowed\": false,\n"
        "  \"parameter_hints\": {\"brightness\": \"...\", \"color\": \"...\", \"blur\": \"...\", \"temporal\": \"...\", \"mask\": \"...\"},\n"
        "  \"confidence\": 0.0\n"
        "}\n\n"
        f"primitive_vocabulary:{json.dumps(PRIMITIVE_EDIT_VOCABULARY, ensure_ascii=False)}\n"
        f"primitive_edit_plan_schema:{json.dumps(primitive_schema, ensure_ascii=False)}\n"
        f"target_ir_summary:{json.dumps(_compact_ir_context(target_ir), ensure_ascii=False)}\n"
        f"candidate_ir_summary:{json.dumps(_compact_ir_context(candidate_ir), ensure_ascii=False) if candidate_ir else 'null'}\n"
        f"current_shader_structure:{json.dumps(_shader_structure_summary(current_shader), ensure_ascii=False)}\n"
    )
    content = [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": contact_sheet_url}},
    ]
    if change_sheet_url is not None:
        content.append({"type": "image_url", "image_url": {"url": change_sheet_url}})
    return content


def _apply_feedback_guardrails(parsed: dict[str, Any], *, target_ir: dict[str, Any]) -> dict[str, Any]:
    geometry_ops = {str(item).lower() for item in target_ir.get("geometry_ops", [])}
    geometry_pattern = str(target_ir.get("geometry_pattern", "")).lower()
    shape_hint = str(target_ir.get("shape_hint", "")).lower()
    geometry_none = (
        not geometry_ops
        or geometry_ops == {"none"}
        or "none" in geometry_ops
    ) and geometry_pattern in {"", "none"} and shape_hint in {"", "none"}
    if not geometry_none:
        return _normalize_primitive_edit_plan(parsed)

    family = str(parsed.get("operation_family", ""))
    change_allowed = bool(parsed.get("change_family_allowed"))
    if change_allowed or family in {"small_geometry_adjustment", "change_family"}:
        parsed = dict(parsed)
        parsed["change_family_allowed"] = False
        parsed["operation_family"] = "tune_color_curve"
        parsed["guardrail_note"] = (
            "target_ir indicates no geometry change, so geometry/ring/mask family changes are disabled; "
            "optimize color, brightness, saturation, blur strength, and temporal curves first."
        )
        plan = parsed.get("optimization_plan", [])
        if isinstance(plan, list):
            parsed["optimization_plan"] = [
                "Keep the current full-frame appearance/color-adjustment family.",
                "Tune RGB/HSL curves over uProgress to match target mean_rgb and brightness trajectories.",
                "Use only mild blur/glow if needed; do not add radial rings, wave distortion, or mask logic.",
                *[
                    item
                    for item in plan
                    if not any(term in str(item).lower() for term in ["radial", "ring", "wave", "distortion", "mask", "光环", "波纹", "形变", "蒙版"])
                ],
            ][:6]
    return _normalize_primitive_edit_plan(parsed, allow_geometry=False)


def _normalize_primitive_edit_plan(parsed: dict[str, Any], *, allow_geometry: bool = True) -> dict[str, Any]:
    parsed = dict(parsed)
    plan = parsed.get("primitive_edit_plan")
    if not isinstance(plan, dict):
        parsed["primitive_edit_plan"] = {
            "selected_primitives": [],
            "rejected_primitives": [],
            "implementation_notes": ["No structured primitive_edit_plan was returned; use optimization_plan conservatively."],
        }
        return parsed

    selected = plan.get("selected_primitives", [])
    rejected = plan.get("rejected_primitives", [])
    notes = plan.get("implementation_notes", [])
    if not isinstance(selected, list):
        selected = []
    if not isinstance(rejected, list):
        rejected = []
    if not isinstance(notes, list):
        notes = [str(notes)]

    allowed_names = set(PRIMITIVE_EDIT_VOCABULARY["geometry"]) | set(PRIMITIVE_EDIT_VOCABULARY["appearance"])
    normalized_selected = []
    normalized_rejected = list(rejected)
    for item in selected[:3]:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name", "")).strip()
        if name not in allowed_names:
            normalized_rejected.append({"name": name or "unknown", "reason": "not in primitive_vocabulary"})
            continue
        if not allow_geometry and name in GEOMETRY_EDIT_PRIMITIVES:
            normalized_rejected.append({"name": name, "reason": "target evidence does not support geometry edits"})
            continue
        normalized = dict(item)
        normalized["name"] = name
        if normalized.get("temporal") not in PRIMITIVE_EDIT_VOCABULARY["temporal_curves"]:
            normalized["temporal"] = "linear"
        try:
            normalized["confidence"] = max(0.0, min(1.0, float(normalized.get("confidence", 0.0))))
        except (TypeError, ValueError):
            normalized["confidence"] = 0.0
        normalized_selected.append(normalized)

    raw_controller = plan.get("temporal_controller")
    raw_controller = raw_controller if isinstance(raw_controller, dict) else {}
    allowed_modes = {"continuous_monotonic", "cyclic", "impulse", "freeform"}
    mode = str(raw_controller.get("mode", "continuous_monotonic")).strip().lower()
    if mode not in allowed_modes:
        mode = "freeform"
    allowed_curves = {"linear", "ease_in", "ease_out", "ease_in_out", "early_progressive"}
    shared_curve = str(raw_controller.get("shared_progress_curve", "ease_in_out")).strip().lower()
    if shared_curve not in allowed_curves:
        shared_curve = "ease_in_out"
    temporal_controller = {
        "mode": mode,
        "driver": "shared" if mode == "continuous_monotonic" else "model_defined",
        "shared_progress_curve": shared_curve,
        "onset": str(raw_controller.get("onset", "unspecified")),
        "trend": str(raw_controller.get("trend", "")),
        "evidence": str(raw_controller.get("evidence", "")),
    }
    if mode == "continuous_monotonic":
        for primitive in normalized_selected:
            params = primitive.get("params") if isinstance(primitive.get("params"), dict) else {}
            primitive["params"] = {
                key: value
                for key, value in params.items()
                if key not in {"weight_keyframes", "value_keyframes", "keyframes", "curve_points", "after"}
            }
            primitive["temporal"] = shared_curve

    parsed["primitive_edit_plan"] = {
        "selected_primitives": normalized_selected,
        "rejected_primitives": normalized_rejected,
        "implementation_notes": notes,
        "temporal_controller": temporal_controller,
    }
    return parsed


def _build_comparison_contact_sheet_data_url(
    target_video: Path,
    candidate_video: Path,
    *,
    progress_values: list[float],
    image_size: int,
    first_label: str = "target",
    second_label: str = "candidate",
) -> str:
    target_frames = _sample_video_frames_at_progress(target_video, progress_values=progress_values, image_size=image_size)
    candidate_frames = _sample_video_frames_at_progress(candidate_video, progress_values=progress_values, image_size=image_size)
    cell_h = image_size
    label_h = 28
    cols = 3
    rows = len(progress_values)
    sheet = np.full((rows * (cell_h + label_h), cols * image_size, 3), 255, dtype=np.uint8)
    for row, (progress, target_frame, candidate_frame) in enumerate(zip(progress_values, target_frames, candidate_frames)):
        diff = cv2.absdiff(target_frame, candidate_frame)
        diff = np.clip(diff.astype(np.float32) * 3.0, 0.0, 255.0).astype(np.uint8)
        frames = [target_frame, candidate_frame, diff]
        labels = [f"{first_label} p={progress:.2f}", second_label, "diff x3"]
        y0 = row * (cell_h + label_h)
        for col, (frame, label) in enumerate(zip(frames, labels)):
            x0 = col * image_size
            sheet[y0 + label_h : y0 + label_h + cell_h, x0 : x0 + image_size] = frame
            cv2.putText(
                sheet,
                label,
                (x0 + 6, y0 + 19),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 0, 0),
                1,
                cv2.LINE_AA,
            )
    ok, encoded = cv2.imencode(".jpg", cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR), [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise RuntimeError("Cannot encode visual feedback contact sheet")
    payload = base64.b64encode(encoded.tobytes()).decode("ascii")
    return f"data:image/jpeg;base64,{payload}"


def _sample_video_frames_at_progress(video_path: Path, *, progress_values: list[float], image_size: int) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if frame_count <= 0:
        cap.release()
        raise RuntimeError(f"Video has no readable frames: {video_path}")
    frames: list[np.ndarray] = []
    try:
        for progress in progress_values:
            frame_index = min(frame_count - 1, max(0, int(round(progress * (frame_count - 1)))))
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame_bgr = cap.read()
            if not ok:
                raise RuntimeError(f"Cannot read frame {frame_index} from {video_path}")
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            frame_rgb = cv2.resize(frame_rgb, (image_size, image_size), interpolation=cv2.INTER_AREA)
            frames.append(frame_rgb)
    finally:
        cap.release()
    return frames


def _multipart_form_data(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = f"----closed-loop-shader-{int(time.time() * 1000)}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode("utf-8"))
        chunks.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        chunks.append(value.encode("utf-8"))
        chunks.append(b"\r\n")
    for name, path in files.items():
        filename = path.name
        content_type = "image/png" if path.suffix.lower() == ".png" else "application/octet-stream"
        chunks.append(f"--{boundary}\r\n".encode("utf-8"))
        chunks.append(
            f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n".encode("utf-8")
        )
        chunks.append(path.read_bytes())
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(chunks), boundary


def _open_json(req: request.Request, *, timeout: float) -> dict[str, Any]:
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {details}") from exc


def run_shader_lab_render(
    *,
    base_url: str,
    token: str,
    vertex_shader: Path,
    fragment_shader: Path,
    input_image: Path,
    output_video: Path,
    timeout: float,
    poll_interval: float,
) -> dict[str, Any]:
    output_video.parent.mkdir(parents=True, exist_ok=True)
    opener = request.build_opener(request.HTTPCookieProcessor())
    login_url = parse.urljoin(base_url.rstrip("/") + "/", f"login?token={parse.quote(token)}")
    opener.open(login_url, timeout=timeout).read()

    body, boundary = _multipart_form_data(
        fields={
            "vs": vertex_shader.read_text(encoding="utf-8"),
            "fs": fragment_shader.read_text(encoding="utf-8"),
        },
        files={"image": input_image},
    )
    submit_url = parse.urljoin(base_url.rstrip("/") + "/", "api/shader-lab/jobs")
    submit_req = request.Request(
        submit_url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    job = _open_json(opener.open(submit_req, timeout=timeout), timeout=timeout) if False else None
    try:
        with opener.open(submit_req, timeout=timeout) as resp:
            job = json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Shader Lab submit failed HTTP {exc.code}: {details}") from exc
    job_id = job["job_id"]

    deadline = time.time() + timeout
    transient_status_errors = 0
    while time.time() < deadline:
        status_url = parse.urljoin(base_url.rstrip("/") + "/", f"api/shader-lab/jobs/{parse.quote(job_id)}")
        try:
            with opener.open(status_url, timeout=timeout) as resp:
                job = json.loads(resp.read().decode("utf-8"))
            transient_status_errors = 0
        except (error.HTTPError, error.URLError, ConnectionResetError, TimeoutError, OSError) as exc:
            transient_status_errors += 1
            if transient_status_errors > 5:
                raise RuntimeError(f"Shader Lab status polling failed for job_id={job_id}: {exc}") from exc
            time.sleep(poll_interval * transient_status_errors)
            continue
        if job.get("state") == "done":
            break
        if job.get("state") == "failed":
            raise RuntimeError(f"Shader Lab render failed: {job}")
        time.sleep(poll_interval)
    else:
        raise TimeoutError(f"Shader Lab render timed out for job_id={job_id}")

    video_path = job.get("video_path")
    if not video_path:
        raise RuntimeError(f"Shader Lab job finished without video_path: {job}")
    file_url = parse.urljoin(base_url.rstrip("/") + "/", f"files/{video_path}")
    with opener.open(file_url, timeout=timeout) as resp:
        output_video.write_bytes(resp.read())
    if not output_video.exists() or output_video.stat().st_size == 0:
        raise FileNotFoundError(f"Shader Lab video download failed: {output_video}")
    job["downloaded_video"] = str(output_video)
    return job


def _feedback_for_result(feedback: dict[str, Any] | None) -> dict[str, Any] | None:
    """Persist structured feedback only; raw model text is never loop state."""
    if not isinstance(feedback, dict):
        return None
    return {
        "model": feedback.get("model"),
        "parsed": feedback.get("parsed"),
        "review_attempt": feedback.get("review_attempt"),
        "failed_review_attempts": feedback.get("failed_review_attempts", []),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Five-round video-to-shader closed loop.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True, help="Original image paired with the target video.")
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--library-structured", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--work-dir", type=Path, default=Path("effect_ir_pipeline/reports/closed_loop_run"))
    parser.add_argument("--request-model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--code-model", default=os.environ.get("EFFECT_IR_CODE_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--sample-fps", type=float, default=2.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--max-iters", type=int, default=5)
    parser.add_argument("--max-generation-attempts", type=int, default=5)
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", "http://172.22.112.93:8788"))
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", "Zaz_tjklcxhqjfo6Sy7HsA"))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    parser.add_argument("--exclude-effect-name", action="append", default=[])
    parser.add_argument(
        "--resume-result",
        type=Path,
        help="Continue from the final accepted iteration stored in an earlier closed_loop_result.json.",
    )
    args = parser.parse_args()

    if args.max_iters <= 0 or args.max_generation_attempts <= 0:
        raise ValueError("max-iters and max-generation-attempts must be positive.")

    repo_root = args.repo_root.resolve()
    work_dir = args.work_dir
    work_dir.mkdir(parents=True, exist_ok=True)
    input_image = resolve_repo_path(repo_root, str(args.input_image))
    if not input_image.exists():
        raise FileNotFoundError(f"Input image does not exist: {input_image}")
    target_video = resolve_repo_path(repo_root, str(args.video_path))
    iterations: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    current_shader: str | None = None
    previous_plan: dict[str, Any] | None = None
    previous_feedback: dict[str, Any] | None = None
    candidate_ir: dict[str, Any] | None = None
    latest_video: Path | None = None
    latest_shader_path: Path | None = None
    latest_review_path: Path | None = None
    iteration_offset = 0
    resume_metadata: dict[str, Any] | None = None

    if args.resume_result is not None:
        resume_path = resolve_repo_path(repo_root, str(args.resume_result))
        resume_result = json.loads(resume_path.read_text(encoding="utf-8"))
        prior_iterations = resume_result.get("iterations")
        if not isinstance(prior_iterations, list) or not prior_iterations:
            raise ValueError(f"Resume result has no accepted iterations: {resume_path}")
        last_iteration = prior_iterations[-1]
        if not isinstance(last_iteration, dict):
            raise ValueError(f"Resume result has an invalid final iteration: {resume_path}")
        resumed_target = resolve_repo_path(repo_root, str(resume_result.get("video_path", "")))
        resumed_input = resolve_repo_path(repo_root, str(resume_result.get("input_image_path", "")))
        if resumed_target != target_video or resumed_input != input_image:
            raise ValueError("Resume result target video/input image do not match the current command.")
        target_ir_generation = resume_result.get("target_ir_generation")
        if not isinstance(target_ir_generation, dict) or not isinstance(target_ir_generation.get("structured_ir"), dict):
            raise ValueError("Resume result is missing target_ir_generation.structured_ir")
        target_ir = target_ir_generation["structured_ir"]
        selected_reference = resume_result.get("selected_reference")
        if not isinstance(selected_reference, dict):
            raise ValueError("Resume result is missing selected_reference")
        selected_references = [selected_reference]
        selected_sources = ""
        excluded_names = set(resume_result.get("library_ablation", {}).get("excluded_effect_names", []))
        current_shader_path = resolve_repo_path(repo_root, str(last_iteration.get("shader_source_markdown", "")))
        current_shader = current_shader_path.read_text(encoding="utf-8")
        previous_plan = last_iteration.get("shader_edit_plan_used")
        previous_feedback = last_iteration.get("feedback_after_render")
        candidate_ir = last_iteration.get("candidate_ir")
        latest_video = resolve_repo_path(repo_root, str(last_iteration.get("rendered_video", "")))
        latest_shader_path = current_shader_path
        latest_review_path = resolve_repo_path(repo_root, str(last_iteration.get("review_markdown", "")))
        iteration_offset = int(last_iteration.get("iteration", len(prior_iterations)))
        resume_metadata = {
            "result_path": str(resume_path),
            "seed_iteration": iteration_offset,
            "seed_overall_score": last_iteration.get("overall_score"),
            "seed_rendered_video": str(latest_video),
        }
        print(f"[1] resume from accepted iteration {iteration_offset}", flush=True)
        print(f"[2] reuse selected_top1={selected_reference.get('display_name')}", flush=True)
    else:
        print("[1] analyze target video", flush=True)
        target_ir_generation = generate_video_ir(
            args.video_path,
            input_image=input_image,
            repo_root=repo_root,
            sample_id=args.video_path.stem,
            model=args.request_model,
            temperature=args.temperature,
            sample_fps=args.sample_fps,
            image_size=args.image_size,
        )
        target_ir = target_ir_generation["structured_ir"]
        if video_starts_black(target_video):
            target_ir = {
                **target_ir,
                "render_contract": {
                    "initial_canvas": "black",
                    "outside_effect_region": "black",
                    "source_visibility": "transformed_region_only",
                    "evidence": "target video first frame is predominantly black",
                },
            }
            target_ir_generation["structured_ir"] = target_ir

        print("[2] retrieve one non-excluded reference", flush=True)
        explicit_exclusions = {name.strip() for name in args.exclude_effect_name if name.strip()}
        inferred_self = infer_library_target_effect_name(args.video_path, repo_root=repo_root)
        excluded_names = explicit_exclusions | ({inferred_self} if inferred_self else set())
        selection = select_top_reference(
            target_ir,
            load_library_structured_rows(args.library_structured),
            strategy="balanced",
            exclude_effect_names=excluded_names or None,
            exclude_library_ids=excluded_names or None,
        )
        selected_references = selection["selected_references"]
        if not selected_references:
            raise RuntimeError("No reference shader remains after exclusion.")
        selected_reference = selected_references[0]
        selected_sources = build_reference_sources_block(selected_references, repo_root)
        print(f"[2] selected_top1={selected_reference['display_name']}", flush=True)
        persist_stage_artifact(
            work_dir,
            stage="observation",
            iteration=None,
            payload={
                "input_video": str(target_video),
                "input_image": str(input_image),
                "target_ir_generation": target_ir_generation,
                "selected_reference": selected_reference,
                "excluded_effect_names": sorted(excluded_names),
            },
        )

    for local_iteration in range(1, args.max_iters + 1):
        iteration = iteration_offset + local_iteration
        if previous_feedback is None:
            plan = build_initial_edit_plan_from_ir(target_ir)
        else:
            delta = extract_feedback_edit_plan(previous_feedback) or build_initial_edit_plan_from_ir(target_ir)
            plan = merge_edit_plan_delta(previous_plan, delta)

        previous_priority = extract_optimization_priority(previous_feedback)
        previous_required_changes = previous_priority["required_changes"]
        previous_frozen_constraints = previous_priority["frozen_constraints"]
        persist_stage_artifact(
            work_dir,
            stage="plan",
            iteration=iteration,
            payload={
                "target_ir": target_ir,
                "candidate_ir": candidate_ir,
                "input_feedback": _feedback_for_result(previous_feedback),
                "edit_plan": plan,
                "required_changes": previous_required_changes,
                "frozen_constraints": previous_frozen_constraints,
            },
        )

        last_failure = ""
        retry_shader = current_shader
        active_feedback = previous_feedback
        for attempt in range(1, args.max_generation_attempts + 1):
            if iteration == 1 and current_shader is None:
                print(f"[3.{iteration}] use selected_top1 shader directly", flush=True)
                shader_text = ensure_shader_precision_preamble(load_top1_shader_text(selected_reference, repo_root=repo_root))
                shader_record = {"backend": "direct_top1", "selected_reference": selected_reference, "normalized_edit_plan": plan}
            else:
                print(f"[3.{iteration}] build shader backend=code_model", flush=True)
                build = build_shader_from_edit_plan(
                    edit_plan=plan, target_ir=target_ir, candidate_ir=candidate_ir,
                    llm_visual_feedback=active_feedback, current_shader=retry_shader,
                    selected_sources=selected_sources, selected_references=selected_references,
                    iteration=iteration, backend="code_model", code_model=args.code_model or args.request_model,
                    temperature=args.temperature, previous_failure=last_failure or None,
                    llm_call=lambda prompt, model, temperature, max_tokens, timeout: call_code_llm_text(
                        prompt, model=model or args.request_model, temperature=temperature,
                        max_tokens=max_tokens, timeout=timeout),
                )
                shader_text = ensure_shader_precision_preamble(build.shader_text)
                shader_record = build.to_jsonable()
            shader_record["previous_failure"] = last_failure or None

            valid, reason = validate_shader_text(shader_text)
            # Library shaders may use a different varying name (for example
            # uv0) but are still accepted by Shader Lab; render is the final
            # compatibility check for the direct Top-1 bootstrap only.
            if shader_record.get("backend") == "direct_top1" and not valid:
                valid, reason = True, "validated by renderer"
            if not valid:
                last_failure = f"invalid shader: {reason}"
                retry_shader = shader_text
                failures.append({"iteration": iteration, "attempt": attempt, "stage": "shader_validation", "reason": last_failure})
                continue
            effective_plan = shader_record.get("normalized_edit_plan") if isinstance(shader_record.get("normalized_edit_plan"), dict) else plan

            shader_source_path = work_dir / f"iter_{iteration:02d}_shader_source.md"
            shader_source_path.write_text(shader_text, encoding="utf-8")
            vertex_path, fragment_path = write_shader_files(shader_text, work_dir, iteration)
            rendered_video = work_dir / f"iter_{iteration:02d}_rendered.mp4"
            print(f"[4.{iteration}] render", flush=True)
            try:
                render_job = run_shader_lab_render(
                    base_url=args.shader_lab_url,
                    token=args.shader_lab_token,
                    vertex_shader=vertex_path,
                    fragment_shader=fragment_path,
                    input_image=input_image,
                    output_video=rendered_video,
                    timeout=args.shader_lab_timeout,
                    poll_interval=args.shader_lab_poll_interval,
                )
                valid, reason = validate_rendered_video(rendered_video)
                if not valid:
                    raise RuntimeError(reason)
                policy = effective_plan.get("background_policy") if isinstance(effective_plan, dict) else {}
                if policy.get("initial_canvas") == "black":
                    valid, reason = validate_initial_black_frame_contract(target_video, rendered_video)
                    if not valid:
                        raise RuntimeError(f"initial black-frame contract: {reason}")
            except Exception as exc:
                last_failure = f"render failed: {exc}"
                retry_shader = shader_text
                failures.append({"iteration": iteration, "attempt": attempt, "stage": "render", "reason": last_failure})
                continue

            persist_stage_artifact(
                work_dir,
                stage="execution",
                iteration=iteration,
                payload={
                    "attempt": attempt,
                    "shader_builder": shader_record,
                    "effective_plan": effective_plan,
                    "vertex_shader": str(vertex_path),
                    "fragment_shader": str(fragment_path),
                    "rendered_video": str(rendered_video),
                    "render_job": render_job,
                },
            )

            print(f"[5.{iteration}] review rendered video", flush=True)
            candidate_ir = generate_video_ir(
                rendered_video,
                input_image=input_image,
                repo_root=repo_root,
                sample_id=f"iter_{iteration:02d}_rendered",
                model=args.request_model,
                temperature=args.temperature,
                sample_fps=args.sample_fps,
                image_size=args.image_size,
            )["structured_ir"]
            feedback = generate_llm_visual_feedback(
                target_video=args.video_path,
                candidate_video=rendered_video,
                repo_root=repo_root,
                target_ir=target_ir,
                candidate_ir=candidate_ir,
                current_shader=shader_text,
                previous_candidate_video=latest_video,
                previous_required_changes=previous_required_changes,
                model=args.request_model,
                temperature=args.temperature,
                image_size=args.image_size,
            )
            persist_stage_artifact(
                work_dir,
                stage="acceptance",
                iteration=iteration,
                payload={
                    "candidate_ir": candidate_ir,
                    "visual_feedback": _feedback_for_result(feedback),
                    "rendered_video": str(rendered_video),
                },
            )
            parsed_feedback = feedback.get("parsed") if isinstance(feedback, dict) else None
            required_change_check = (
                parsed_feedback.get("required_change_check")
                if isinstance(parsed_feedback, dict)
                else None
            )
            required_change_check = required_change_check if isinstance(required_change_check, dict) else {}
            checked_items = required_change_check.get("items", [])
            checked_items = checked_items if isinstance(checked_items, list) else []
            failed_checks = [
                item for item in checked_items
                if isinstance(item, dict)
                and str(item.get("status", "")).strip().lower() in {"not_implemented", "regressed"}
            ]
            if previous_required_changes and failed_checks:
                last_failure = (
                    "visual atomic required-change check failed; "
                    f"failed_items={json.dumps(failed_checks, ensure_ascii=False)}; "
                    f"frozen_constraints={json.dumps(previous_frozen_constraints, ensure_ascii=False)}"
                )
                retry_shader = shader_text
                failures.append(
                    {
                        "iteration": iteration,
                        "attempt": attempt,
                        "stage": "required_change_visual_check",
                        "reason": last_failure,
                        "required_change_check": required_change_check,
                    }
                )
                # A rejected candidate is new evidence. Rebuild the same
                # iteration's plan from that evidence instead of blindly
                # retrying the stale plan and stale feedback.
                repair_delta = extract_feedback_edit_plan(feedback)
                if repair_delta:
                    plan = merge_edit_plan_delta(plan, repair_delta)
                    active_feedback = feedback
                    persist_stage_artifact(
                        work_dir,
                        stage="repair_plan",
                        iteration=iteration,
                        payload={
                            "attempt": attempt,
                            "failed_required_changes": failed_checks,
                            "repair_feedback": _feedback_for_result(feedback),
                            "repair_plan": plan,
                        },
                    )
                print(f"[5.{iteration}] required change not accepted; regenerate same iteration", flush=True)
                continue
            if isinstance(parsed_feedback, dict):
                reconcile_atomic_change_state(
                    parsed_feedback,
                    previous_required_changes=previous_required_changes,
                    previous_frozen_constraints=previous_frozen_constraints,
                )
            review_path = work_dir / f"iter_{iteration:02d}_review.md"
            write_iteration_review_markdown(
                path=review_path,
                iteration=iteration,
                rendered_video=rendered_video,
                vertex_shader=vertex_path,
                fragment_shader=fragment_path,
                shader_source_markdown=shader_source_path,
                selected_references=selected_references,
                shader_edit_plan_used=effective_plan,
                feedback_used_for_prompt=previous_feedback,
                feedback_after_render=feedback,
                candidate_ir=candidate_ir,
                shader_builder_record=shader_record,
            )
            score = extract_feedback_overall_score(feedback)
            if score is None:
                raise RuntimeError("Visual review passed validation without a numeric overall score")
            iterations.append({
                "iteration": iteration,
                "attempt": attempt,
                "overall_score": score,
                "match_score": (feedback.get("parsed") or {}).get("match_score"),
                "optimization_priority": extract_optimization_priority(feedback),
                "rendered_video": str(rendered_video),
                "review_markdown": str(review_path),
                "shader_source_markdown": str(shader_source_path),
                "vertex_shader": str(vertex_path),
                "fragment_shader": str(fragment_path),
                "shader_builder": shader_record,
                "shader_edit_plan_used": effective_plan,
                "feedback_used_for_prompt": _feedback_for_result(previous_feedback),
                "feedback_after_render": _feedback_for_result(feedback),
                "candidate_ir": candidate_ir,
                "shader_lab_job": render_job,
            })
            current_shader, previous_plan, previous_feedback = shader_text, effective_plan, feedback
            latest_video, latest_shader_path, latest_review_path = rendered_video, shader_source_path, review_path
            break
        else:
            raise RuntimeError(f"Iteration {iteration} failed after {args.max_generation_attempts} attempts: {last_failure}")

    ranking = sorted(
        (
            {
                "iteration": item["iteration"],
                "overall_score": item["overall_score"],
                "match_score": item["match_score"],
                "optimization_priority": item["optimization_priority"],
                "rendered_video": item["rendered_video"],
                "review_markdown": item["review_markdown"],
                "shader_source_markdown": item["shader_source_markdown"],
            }
            for item in iterations
        ),
        key=lambda item: float(item["overall_score"] if item["overall_score"] is not None else -1),
        reverse=True,
    )
    for rank, item in enumerate(ranking, 1):
        item["rank"] = rank
    result = {
        "video_path": str(args.video_path),
        "input_image_path": str(input_image),
        "shader_builder_backend": "code_model",
        "code_model": args.code_model or args.request_model,
        "selected_reference": selected_reference,
        "resume_from": resume_metadata,
        "library_ablation": {"excluded_effect_names": sorted(excluded_names)},
        "target_ir_generation": target_ir_generation,
        "iterations": iterations,
        "failed_generation_attempts": failures,
        "score_ranking": ranking,
        "best_iteration_by_llm_score": ranking[0] if ranking else None,
        "final_candidate_video": str(latest_video) if latest_video else None,
        "final_shader_markdown": str(latest_review_path) if latest_review_path else None,
        "final_shader_source_markdown": str(latest_shader_path) if latest_shader_path else None,
    }
    result_path = work_dir / "closed_loop_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"result": str(result_path), "best": result["best_iteration_by_llm_score"], "final_candidate_video": result["final_candidate_video"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
