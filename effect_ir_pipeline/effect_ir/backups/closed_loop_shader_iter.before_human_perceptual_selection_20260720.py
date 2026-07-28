from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import subprocess
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
from .shader_builder import build_initial_edit_plan_from_ir, build_shader_from_edit_plan, extract_feedback_edit_plan
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
    ],
    "appearance": [
        "brightness",
        "contrast",
        "saturation",
        "rgb_shift",
        "blur",
        "sharpen",
        "vignette",
    ],
    "temporal_curves": [
        "linear",
        "ease_in",
        "ease_out",
        "ease_in_out",
        "bell",
        "early_progressive",
        "late_progressive",
        "two_phase",
    ],
}

GEOMETRY_EDIT_PRIMITIVES = set(PRIMITIVE_EDIT_VOCABULARY["geometry"]) - {"identity"}


def extract_json_object(text: str) -> dict[str, Any]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{.*\}", text, flags=re.S)
    if not match:
        raise ValueError(f"No JSON object found in response: {text[:300]}")
    return json.loads(match.group(0))


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


def read_effect_sources(effect_name: str, repo_root: Path) -> str:
    code_dir = repo_root / "code" / effect_name
    chunks: list[str] = []
    filter_path = code_dir / "filter.json"
    if filter_path.exists():
        chunks.append(f"-- FILE: filter.json\n{filter_path.read_text(encoding='utf-8', errors='replace')}")
    for path in sorted(code_dir.rglob("*.lua")):
        chunks.append(f"-- FILE: {path.relative_to(code_dir)}\n{path.read_text(encoding='utf-8', errors='replace')}")
    return "\n\n".join(chunks)[:30000]


def extract_glsl_blocks(shader_text: str) -> tuple[str, str]:
    blocks = re.findall(r"```glsl\s*(.*?)```", shader_text, flags=re.S | re.I)
    if len(blocks) < 2:
        blocks = re.findall(r"```\s*(.*?)```", shader_text, flags=re.S | re.I)
    if len(blocks) < 2:
        raise ValueError("Expected at least two GLSL code blocks in shader response")
    return blocks[0].strip() + "\n", blocks[1].strip() + "\n"


def shader_needs_repair(shader_text: str) -> tuple[bool, str]:
    valid, reason = validate_shader_text(shader_text)
    return (not valid), reason


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
    uniforms = re.findall(r"\buniform\s+\w+\s+(\w+)\s*;", fragment)
    extra_uniforms = sorted({name for name in uniforms if name not in allowed_uniforms})
    if extra_uniforms:
        return False, f"Fragment shader uses unsupported extra uniforms: {extra_uniforms}"
    return True, ""


def lint_shader_safety(shader_text: str) -> tuple[bool, str]:
    """Reject GLSL patterns that often render as black/NaN on Shader Lab/mobile GL."""
    try:
        _vertex, fragment = extract_glsl_blocks(shader_text)
    except Exception as exc:
        return False, str(exc)
    compact = re.sub(r"\s+", " ", fragment)
    lower = compact.lower()
    issues: list[str] = []
    if re.search(r"sin\s*\([^;]{0,120}\)\s*\*\s*(?:43758|4375|10000|1e)", lower):
        issues.append("uses large-constant sin hash; replace with small-range stable hash/noise")
    if re.search(r"dot\s*\([^;]{0,120}uTime", fragment, flags=re.I) or re.search(r"sin\s*\([^;]{0,80}uTime\s*\*", fragment, flags=re.I):
        if "mod(uTime" not in fragment and "mod( uTime" not in fragment:
            issues.append("uses uTime in periodic/hash math without first bounding it with mod(uTime, ...)")
    if re.search(r"floor\s*\([^;]{0,80}uTime", fragment, flags=re.I):
        issues.append("uses floor(uTime...) directly; derive a bounded time variable first")
    if re.search(r"gl_FragColor\s*=\s*vec4\s*\(\s*(?:0\.0|0|vec3\s*\(\s*0)", fragment):
        issues.append("directly outputs black color")
    if "discard" in lower:
        issues.append("uses discard, which can produce black holes in rendered video")
    if re.search(r"color\.a\s*=\s*0(?:\.0)?\s*;", lower) or re.search(r"gl_FragColor\s*=\s*vec4\s*\([^;]*,\s*0(?:\.0)?\s*\)", fragment):
        issues.append("sets alpha to zero")
    risky_divisions = re.findall(r"/\s*([A-Za-z_]\w*)", fragment)
    if any(name.lower() in {"denom", "denominator", "length", "dist", "distance"} for name in risky_divisions):
        if "max(" not in fragment and "epsilon" not in lower:
            issues.append("contains high-risk division without obvious epsilon/max guard")
    if re.search(r"\bpow\s*\(", lower) or re.search(r"\bsqrt\s*\(", lower) or re.search(r"\blog\s*\(", lower):
        if "max(" not in fragment:
            issues.append("uses pow/sqrt/log without obvious non-negative guard")
    if "texture2D(inputImageTexture, uv)" not in fragment:
        issues.append("does not keep a direct source texture sample as stable fallback")
    if issues:
        return False, "; ".join(issues)
    return True, ""


def repair_shader_safety(shader_text: str, *, model: str, temperature: float, safety_reason: str) -> str:
    prompt = (
        "Rewrite the shader into a numerically stable Shader Lab GLSL version. Output exactly two ```glsl code blocks: Vertex, Fragment.\n"
        "The visual goal is unchanged, but fix these safety issues:\n"
        f"{safety_reason}\n\n"
        "Hard requirements:\n"
        "- Fragment uniforms only: sampler2D inputImageTexture, float uProgress, float uTime.\n"
        "- Start fragment with: vec2 uv = textureCoord; float p = clamp(uProgress,0.0,1.0); float t = mod(uTime, 10.0);\n"
        "- Always sample source = texture2D(inputImageTexture, uv) and make it the stable base for final color.\n"
        "- Do not use large-constant sin hash like sin(...)*43758. Use bounded simple periodic functions or small deterministic row/tile patterns.\n"
        "- Do not output black, do not discard, do not set alpha to zero, do not fade source out over progress.\n"
        "- Clamp UV before texture2D and clamp final rgb; set final alpha to 1.0.\n\n"
        f"Original shader:\n{shader_text}\n"
    )
    return call_llm_text(
        prompt,
        model=model,
        temperature=temperature,
        max_tokens=3600,
        timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
    )


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


def repair_shader_text(shader_text: str, *, model: str, temperature: float) -> str:
    prompt = (
        "Rewrite the following shader response into exactly two complete ```glsl code blocks and no other code blocks.\n"
        "First block: Vertex Shader. Second block: Fragment Shader.\n"
        "The shader must be directly usable in shader-lab.\n"
        "Do not use any Fragment Shader uniforms except: sampler2D inputImageTexture, float uProgress, float uTime.\n"
        "Do not use uTexelSize, resolution, hue, lightness, saturation, or any external texture/uniform.\n"
        "Do not assume uProgress=0 must equal the source image; the target video's first frame may already contain the effect.\n"
        "Keep the effect temporally controllable and visible across uProgress.\n\n"
        f"Original response:\n{shader_text}\n"
    )
    return call_llm_text(
        prompt,
        model=model,
        temperature=temperature,
        max_tokens=2600,
        timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
    )


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


def save_first_frame(video_path: Path, *, repo_root: Path, output_path: Path) -> Path:
    from PIL import Image
    import cv2

    resolved = resolve_repo_path(repo_root, str(video_path))
    first_frame_bgr = sample_video_frames(resolved, [0])[0]
    first_frame_rgb = cv2.cvtColor(first_frame_bgr, cv2.COLOR_BGR2RGB)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(first_frame_rgb).save(output_path)
    return output_path


def prepare_input_image(input_image: Path | None, *, video_path: Path, repo_root: Path, work_dir: Path) -> Path:
    if input_image is not None:
        resolved = resolve_repo_path(repo_root, str(input_image))
        if not resolved.exists():
            raise FileNotFoundError(f"Input image does not exist: {resolved}")
        return resolved
    return save_first_frame(video_path, repo_root=repo_root, output_path=work_dir / "target_first_frame.png")


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


def call_llm_text(prompt: str, *, model: str, temperature: float, max_tokens: int, timeout: float) -> str:
    return call_llm_content(
        prompt,
        model=model,
        temperature=temperature,
        max_tokens=max_tokens,
        timeout=timeout,
    )


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
        image_size=image_size,
    )
    response = call_llm_content(
        content,
        model=model,
        temperature=temperature,
        max_tokens=int(os.environ.get("EFFECT_IR_VISUAL_FEEDBACK_MAX_TOKENS", "6000")),
        timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
    )
    try:
        parsed: dict[str, Any] | None = extract_json_object(response)
    except Exception:
        parsed = None
    if parsed is not None:
        parsed = _apply_feedback_guardrails(parsed, target_ir=target_ir)
        parsed = _normalize_feedback_score(parsed)
    return {
        "model": model,
        "raw_response": response,
        "parsed": parsed,
    }


def _normalize_feedback_score(parsed: dict[str, Any]) -> dict[str, Any]:
    parsed = dict(parsed)
    score = parsed.get("match_score")
    if not isinstance(score, dict):
        parsed["match_score"] = {
            "overall": None,
            "reason": "model did not return structured match_score",
        }
        return parsed
    normalized: dict[str, Any] = {}
    value = score.get("overall")
    if value is None:
        normalized["overall"] = None
    else:
        try:
            normalized["overall"] = max(0.0, min(100.0, float(value)))
        except (TypeError, ValueError):
            normalized["overall"] = None
    normalized["reason"] = str(normalized.get("reason", "")).strip()
    if not normalized["reason"]:
        normalized["reason"] = str(score.get("reason", "")).strip()
    parsed["match_score"] = normalized
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


def _feedback_text(parsed: dict[str, Any] | None) -> str:
    if not isinstance(parsed, dict):
        return ""
    chunks: list[str] = []
    for key in [
        "temporal_process_observation",
        "key_transition_observation",
        "motion_signature",
        "progress_evidence_summary",
        "frame_by_frame_observation",
        "target_video_observation",
        "candidate_video_observation",
        "most_important_gap",
        "visual_difference_summary",
        "candidate_errors",
        "next_change_in_plain_words",
        "optimization_plan",
        "operation_family",
        "guardrail_note",
    ]:
        value = parsed.get(key)
        if value is not None:
            chunks.append(json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else str(value))
    score = parsed.get("match_score")
    if isinstance(score, dict):
        chunks.append(str(score.get("reason", "")))
    plan = parsed.get("primitive_edit_plan")
    if isinstance(plan, dict):
        chunks.append(json.dumps(plan.get("rejected_primitives", []), ensure_ascii=False))
        chunks.append(json.dumps(plan.get("implementation_notes", []), ensure_ascii=False))
    return "\n".join(chunks).lower()


def detect_reference_reselection_signal(feedback: dict[str, Any] | None) -> dict[str, Any]:
    parsed = feedback.get("parsed") if isinstance(feedback, dict) else None
    text = _feedback_text(parsed)
    rejected_primitives: list[str] = []
    overall_score: float | None = None
    change_family_requested = False
    if isinstance(parsed, dict):
        score = parsed.get("match_score")
        if isinstance(score, dict):
            try:
                overall_score = None if score.get("overall") is None else float(score.get("overall"))
            except (TypeError, ValueError):
                overall_score = None
        change_family_requested = (
            bool(parsed.get("change_family_allowed"))
            or str(parsed.get("operation_family", "")).strip().lower() == "change_family"
        )
        plan = parsed.get("primitive_edit_plan")
        if isinstance(plan, dict):
            for item in plan.get("rejected_primitives", []) or []:
                if isinstance(item, dict):
                    rejected_primitives.append(str(item.get("name", "")).strip().lower())
    wrong_terms = [
        "geometry family wrong",
        "change family",
        "wrong family",
        "wrong primitive",
        "completely wrong",
        "opposite",
        "几何家族",
        "几何形态完全错误",
        "几何原语错误",
        "方向错误",
        "形态完全错误",
        "完全错误",
        "完全相反",
        "严重不匹配",
        "大幅重构",
        "换特效家族",
        "第一眼不像",
        "不是同一种效果",
        "核心效果缺失",
        "主效果缺失",
        "完全不像",
    ]
    low_score = overall_score is not None and overall_score <= 35.0
    family_wrong = any(term in text for term in wrong_terms)
    has_rejected_primitives = bool(rejected_primitives)
    severe_failure = (
        low_score
        or change_family_requested
        or (family_wrong and has_rejected_primitives)
    )
    return {
        "triggered": severe_failure,
        "low_score": low_score,
        "family_wrong": family_wrong,
        "change_family_requested": change_family_requested,
        "has_rejected_primitives": has_rejected_primitives,
        "overall_score": overall_score,
        "rejected_primitives": rejected_primitives,
    }


def build_feedback_hard_constraints(feedback_history: list[dict[str, Any]]) -> str:
    if not feedback_history:
        return ""
    rejected: set[str] = set()
    notes: list[str] = []
    for item in feedback_history[-2:]:
        signal = item.get("signal", {})
        for primitive in signal.get("rejected_primitives", []) or []:
            if primitive:
                rejected.add(str(primitive))
        if signal.get("family_wrong") or signal.get("change_family_requested") or signal.get("low_score"):
            notes.append("Treat the previous shader family as failed; rebuild from the newly selected references instead of locally editing the old shader.")
    if not rejected and not notes:
        return ""
    return (
        "\n\nfeedback_hard_constraints:\n"
        f"- rejected_primitives: {sorted(rejected)}\n"
        + "".join(f"- {note}\n" for note in sorted(set(notes)))
    )


def _compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2)


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
    next_plan = parsed.get("primitive_edit_plan")
    score_text = "null" if match_score.get("overall") is None else str(match_score.get("overall"))
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
            "## 本轮生成时参考的上一轮审查",
            "",
            "```json",
            _compact_json((feedback_used_for_prompt or {}).get("parsed") if isinstance(feedback_used_for_prompt, dict) else None),
            "```",
            "",
            "## 候选视频 IR",
            "",
            "```json",
            _compact_json(candidate_ir or {}),
            "```",
            "",
            "## Shader builder 记录",
            "",
            "```json",
            _compact_json(shader_builder_record or {}),
            "```",
            "",
            "## 当前审查原始返回",
            "",
            "```json",
            feedback_after_render.get("raw_response", "") if isinstance(feedback_after_render, dict) else "",
            "```",
            "",
            "## 当前选用参考",
            "",
            "```json",
            _compact_json(selected_references),
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
    image_size: int,
) -> list[dict[str, Any]]:
    progress_values = [0.0, 0.25, 0.5, 0.75, 1.0]
    contact_sheet_url = _build_comparison_contact_sheet_data_url(
        target_video,
        candidate_video,
        progress_values=progress_values,
        image_size=image_size,
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
    }
    text = (
        "你是视频特效过程审查员。看 contact sheet：每行同一进度，三列为 TARGET/CANDIDATE/DIFF。\n"
        "目标不是复刻某一帧截图，而是还原从 p=0 到 p=1 的变化规律。少用术语，不复述 IR；若 IR 与画面冲突，以画面为准。\n"
        "请把各进度帧当作时间采样来总结运动/出现/增强/消失的过程，不要描述横线、块、遮挡在脸上或画面中的精确位置；位置只允许概括为全局/局部、上中下、横向/纵向。\n"
        "重点描述：变化何时开始、强度如何随进度变化、元素是连续移动还是跳变、边缘硬/软、画面是否保持原图可见。\n"
        "最多写 2 个关键过程差异、3 条修改建议。建议必须说这个动态过程要怎么改，避免让 shader 拟合单帧形象。\n"
        "评分只给整体人类观感 overall+reason，不打分项：0-20 完全不像；21-40 第一眼不像；41-60 同类但关键错；61-80 接近；81-100 很像。\n"
        "第一眼不是同一种效果 overall≤40；主效果缺失 overall≤30。只输出 JSON：\n"
        "{\n"
        "  \"temporal_process_observation\": \"目标从 p=0 到 p=1 的整体变化过程，强调动态规律而非单帧位置\",\n"
        "  \"candidate_process_observation\": \"候选从 p=0 到 p=1 的整体变化过程\",\n"
        "  \"key_transition_observation\": \"关键帧之间发生了什么，例如开始/增强/峰值/消退/跳变\",\n"
        "  \"motion_signature\": \"用短语概括目标动态：例如稳定底图+细水平跳切/逐渐粗块化/连续波动/瞬时闪烁\",\n"
        "  \"progress_evidence_summary\": [\"最多 4 条进度证据，只写变化趋势，不写精确位置\"],\n"
        "  \"target_video_observation\": \"目标视频整体动态观感\",\n"
        "  \"candidate_video_observation\": \"候选视频整体动态观感\",\n"
        "  \"most_important_gap\": \"最重要的过程差距，不要写成某一帧的局部截图差异\",\n"
        "  \"visual_difference_summary\": \"一句话中文总结，不超过 60 字\",\n"
        "  \"evidence\": [\"最多 3 条可见证据\"],\n"
        "  \"candidate_errors\": [\"最多 2 条候选画面问题\"],\n"
        "  \"match_score\": {\"overall\": 0, \"reason\": \"像人类评审一样说明为什么这个整体分数合理\"},\n"
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
        f"target_ir:{json.dumps(target_ir, ensure_ascii=False)}\n"
        f"candidate_ir:{json.dumps(candidate_ir, ensure_ascii=False) if candidate_ir else 'null'}\n"
        f"current_shader:\n{(current_shader or 'null')[:12000]}\n"
    )
    return [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": contact_sheet_url}},
    ]


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

    parsed["primitive_edit_plan"] = {
        "selected_primitives": normalized_selected,
        "rejected_primitives": normalized_rejected,
        "implementation_notes": notes,
    }
    return parsed


def _build_comparison_contact_sheet_data_url(
    target_video: Path,
    candidate_video: Path,
    *,
    progress_values: list[float],
    image_size: int,
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
        labels = [f"target p={progress:.2f}", "candidate", "diff x3"]
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


def _image_file_data_url(path: Path) -> str:
    mime = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{payload}"


def _build_target_contact_sheet_data_url(
    target_video: Path,
    *,
    progress_values: list[float],
    image_size: int,
) -> str:
    frames = _sample_video_frames_at_progress(target_video, progress_values=progress_values, image_size=image_size)
    label_h = 28
    sheet = np.full((image_size + label_h, len(frames) * image_size, 3), 255, dtype=np.uint8)
    for col, (progress, frame) in enumerate(zip(progress_values, frames)):
        x0 = col * image_size
        sheet[label_h : label_h + image_size, x0 : x0 + image_size] = frame
        cv2.putText(
            sheet,
            f"target p={progress:.2f}",
            (x0 + 6, 19),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )
    ok, encoded = cv2.imencode(".jpg", cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR), [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise RuntimeError("Cannot encode target contact sheet")
    payload = base64.b64encode(encoded.tobytes()).decode("ascii")
    return f"data:image/jpeg;base64,{payload}"


def build_direct_reset_shader_content(
    *,
    input_image: Path,
    target_video: Path,
    target_ir: dict[str, Any],
    reset_reason: dict[str, Any],
    image_size: int,
) -> list[dict[str, Any]]:
    target_sheet = _build_target_contact_sheet_data_url(
        target_video,
        progress_values=[0.0, 0.25, 0.5, 0.75, 1.0],
        image_size=image_size,
    )
    text = (
        "连续严重不匹配，重开初版。不要参考库侧 shader 或旧 candidate。\n"
        "第一张图是原图；第二张图是 target 在 p=0/0.25/0.5/0.75/1 的采样。直接生成 shader 源码，不解释。\n"
        "只输出两个 ```glsl 代码块：Vertex、Fragment。Vertex 用 position→textureCoord；Fragment 只允许 inputImageTexture/uProgress/uTime。"
        "不用外部纹理、resolution、uTexelSize、额外 uniform；不要假设 p=0 是原图。\n"
        f"reset_reason:{json.dumps(reset_reason, ensure_ascii=False)}\n"
        f"target_ir_weak_hint:{json.dumps(target_ir, ensure_ascii=False)}\n"
    )
    return [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": _image_file_data_url(input_image)}},
        {"type": "image_url", "image_url": {"url": target_sheet}},
    ]


def call_code_llm_content(content: str | list[dict[str, Any]], *, model: str, temperature: float, max_tokens: int, timeout: float) -> str:
    endpoint = (
        os.environ.get("EFFECT_IR_CODE_LLM_ENDPOINT")
        or os.environ.get("EFFECT_IR_LLM_ENDPOINT")
        or "http://wanqing.internal/api/gateway/v1/endpoints/chat/completions"
    )
    api_key = os.environ.get("EFFECT_IR_CODE_LLM_API_KEY") or os.environ.get("WQ_API_KEY", "EMPTY")
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
    raise RuntimeError(f"Code LLM content request failed after {retries} attempts: {last_error}") from last_error


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


def build_iteration_prompt(
    *,
    iteration: int,
    selected_effect: str,
    selected_references: list[dict[str, Any]],
    target_ir: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    llm_visual_feedback: dict[str, Any] | None,
    current_shader: str | None,
    selected_sources: str,
) -> str:
    return (
        "迭代修正 shader，使 candidate 更像 target。优先按 llm_visual_feedback 的动态过程差异、motion_signature、most_important_gap 和 primitive_edit_plan 修改；必要时大改。\n"
        "不要拟合某个采样帧中线条/块/遮挡的具体位置；要实现随 uProgress 变化的过程规律。\n"
        "只输出两段 GLSL：Vertex、Fragment。Fragment 只允许 inputImageTexture/uProgress/uTime；不用额外 uniform/外部纹理/resolution/uTexelSize；不要假设 p=0 是原图。\n"
        f"iteration:{iteration}\n"
        f"selected_effect:{selected_effect}\n"
        f"selected_reference:{json.dumps(selected_references[0] if selected_references else None, ensure_ascii=False)}\n"
        f"primitive_vocabulary:{json.dumps(PRIMITIVE_EDIT_VOCABULARY, ensure_ascii=False)}\n"
        f"target_ir:{json.dumps(target_ir, ensure_ascii=False)}\n"
        f"candidate_ir:{json.dumps(candidate_ir, ensure_ascii=False) if candidate_ir else 'null'}\n"
        f"llm_visual_feedback:{json.dumps(llm_visual_feedback, ensure_ascii=False) if llm_visual_feedback else 'null'}\n"
        f"current_shader:\n{current_shader or 'null'}\n\n"
        f"selected_library_sources:\n{selected_sources[:12000]}\n"
    )


def build_initial_shader_prompt(
    *,
    selected_effect: str,
    selected_references: list[dict[str, Any]],
    target_ir: dict[str, Any],
    selected_sources: str,
) -> str:
    return (
        "根据 top1 参考源码和 target_ir 生成初始 shader。只提取相关核心效果，不复制无关逻辑。\n"
        "只输出两段 GLSL：Vertex、Fragment。Fragment 只允许 inputImageTexture/uProgress/uTime；不用额外 uniform/外部纹理/resolution/uTexelSize；不要假设 p=0 是原图。\n"
        f"selected_effect:{selected_effect}\n"
        f"selected_reference:{json.dumps(selected_references[0] if selected_references else None, ensure_ascii=False)}\n"
        f"target_ir:{json.dumps(target_ir, ensure_ascii=False)}\n"
        f"primitive_vocabulary:{json.dumps(PRIMITIVE_EDIT_VOCABULARY, ensure_ascii=False)}\n"
        f"selected_library_sources:\n{selected_sources[:12000]}\n"
    )


def run_render_command(
    command_template: str,
    *,
    vertex_shader: Path,
    fragment_shader: Path,
    input_image: Path,
    output_video: Path,
    iteration: int,
) -> Path:
    output_video.parent.mkdir(parents=True, exist_ok=True)
    values = {
        "vertex_shader": str(vertex_shader),
        "fragment_shader": str(fragment_shader),
        "input_image": str(input_image),
        "output_video": str(output_video),
        "iteration": str(iteration),
    }
    command = command_template.format(**values)
    subprocess.run(command, shell=True, check=True)
    if not output_video.exists():
        raise FileNotFoundError(f"Render command did not create output video: {output_video}")
    return output_video


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


def main() -> None:
    parser = argparse.ArgumentParser(description="Closed-loop shader iteration from a source image and target video.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, help="Source/original image used before the effect. If omitted, the first target-video frame is used for backward compatibility.")
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--library-structured", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--work-dir", type=Path, default=Path("effect_ir_pipeline/reports/closed_loop_run"))
    parser.add_argument("--request-model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--sample-fps", type=float, default=2.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--strategy", default="balanced")
    parser.add_argument("--max-iters", type=int, default=5, help="Fixed number of closed-loop iterations to run.")
    parser.add_argument("--render-command", help="Optional command template. Available placeholders: {vertex_shader}, {fragment_shader}, {input_image}, {output_video}, {iteration}.")
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", "http://172.22.112.93:8788"), help="Shader Lab base URL used when --render-command is not supplied.")
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", "Zaz_tjklcxhqjfo6Sy7HsA"))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    parser.add_argument("--candidate-video", type=Path, help="Optional externally rendered candidate video for resuming comparison. If omitted, the script renders generated shader with --render-command.")
    parser.add_argument("--resume-shader", type=Path, help="Optional current shader markdown with two GLSL code blocks.")
    parser.add_argument("--max-generation-attempts", type=int, default=3, help="Maximum retry attempts for one counted iteration when shader generation or rendering is invalid.")
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument(
        "--shader-builder-backend",
        choices=["programmatic", "code_model", "llm_freeform"],
        default=os.environ.get("EFFECT_IR_SHADER_BUILDER_BACKEND", "programmatic"),
        help=(
            "Shader generation backend. programmatic uses primitive/edit-plan shader builder; "
            "code_model sends the edit plan plus a programmatic draft to a stronger code model; "
            "llm_freeform keeps the older direct full-shader LLM generation path."
        ),
    )
    parser.add_argument(
        "--code-model",
        default=os.environ.get("EFFECT_IR_CODE_LLM_MODEL"),
        help="Model used only when --shader-builder-backend=code_model. Defaults to EFFECT_IR_CODE_LLM_MODEL or request model.",
    )
    parser.add_argument(
        "--max-direct-resets",
        type=int,
        default=int(os.environ.get("EFFECT_IR_MAX_DIRECT_RESETS", "0")),
        help="Disabled by default. If >0, severe mismatch resets can discard the current phase and start a fresh direct video+image generation phase.",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    work_dir = args.work_dir
    work_dir.mkdir(parents=True, exist_ok=True)
    input_image = prepare_input_image(args.input_image, video_path=args.video_path, repo_root=repo_root, work_dir=work_dir)

    print("[1] generate target IR and observation", flush=True)
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
    print("[2] rank library IR and select top1 reference", flush=True)
    library_rows = load_library_structured_rows(args.library_structured)
    self_excluded_effect_name = infer_library_target_effect_name(args.video_path, repo_root=repo_root)
    reference_selection = select_top_reference(
        target_ir,
        library_rows,
        strategy=args.strategy,
        exclude_effect_names={self_excluded_effect_name} if self_excluded_effect_name else None,
        exclude_library_ids={self_excluded_effect_name} if self_excluded_effect_name else None,
    )
    initial_ranking = reference_selection["global_ranking"]
    selected_references = reference_selection["selected_references"]
    if not selected_references:
        raise RuntimeError("No library references selected for initial shader generation.")
    selected_effect = selected_references[0]["display_name"]
    selected_sources = build_reference_sources_block(selected_references, repo_root)
    print(
        f"[2] selected_top1={selected_references[0]['display_name']} "
        f"score={selected_references[0]['retrieval_score']:.4f}",
        flush=True,
    )
    if self_excluded_effect_name:
        print(
            f"[2] library ablation self-exclusion={self_excluded_effect_name}; "
            "selected next available reference instead of self",
            flush=True,
        )

    current_shader = args.resume_shader.read_text(encoding="utf-8") if args.resume_shader else None
    iterations: list[dict[str, Any]] = []
    candidate_ir_generation: dict[str, Any] | None = None
    candidate_ir: dict[str, Any] | None = None
    latest_candidate_video: Path | None = args.candidate_video
    latest_shader_path: Path | None = args.resume_shader
    latest_review_path: Path | None = None
    latest_visual_feedback: dict[str, Any] | None = None
    if args.max_iters <= 0:
        raise ValueError("--max-iters must be a positive integer.")
    if args.max_generation_attempts <= 0:
        raise ValueError("--max-generation-attempts must be a positive integer.")
    failed_generation_attempts: list[dict[str, Any]] = []
    feedback_signal_history: list[dict[str, Any]] = []
    reference_reselection_events: list[dict[str, Any]] = []
    direct_reset_events: list[dict[str, Any]] = []
    excluded_reference_library_ids: set[str] = set()
    excluded_reference_effect_names: set[str] = set()
    active_hard_constraints = ""
    direct_reset_pending: dict[str, Any] | None = None
    direct_reset_count = 0
    phase_index = 0

    if latest_candidate_video is not None:
        print(f"[3] using externally supplied candidate video={latest_candidate_video}", flush=True)
        candidate_ir_generation = generate_video_ir(
            latest_candidate_video,
            input_image=input_image,
            repo_root=repo_root,
            sample_id=f"{selected_effect}__candidate",
            model=args.request_model,
            temperature=args.temperature,
            sample_fps=args.sample_fps,
            image_size=args.image_size,
        )
        candidate_ir = candidate_ir_generation["structured_ir"]
        latest_visual_feedback = generate_llm_visual_feedback(
            target_video=args.video_path,
            candidate_video=latest_candidate_video,
            repo_root=repo_root,
            target_ir=target_ir,
            candidate_ir=candidate_ir,
            current_shader=current_shader,
            model=args.request_model,
            temperature=args.temperature,
            image_size=args.image_size,
        )

    completed_iterations = 0
    while completed_iterations < args.max_iters:
        iteration = completed_iterations + 1
        if (
            args.max_direct_resets > 0
            and len(feedback_signal_history) >= 2
            and all(item.get("signal", {}).get("triggered") for item in feedback_signal_history[-2:])
        ):
            reset_signal = feedback_signal_history[-2:]
            if direct_reset_count < args.max_direct_resets:
                direct_reset_count += 1
                phase_index += 1
                event = {
                    "before_iteration": iteration,
                    "new_phase_index": phase_index,
                    "reason": "Two consecutive feedback rounds reported severe mismatch. Instead of selecting another library top1, start a fresh direct video+image shader generation phase.",
                    "previous_reference": selected_references[0] if selected_references else None,
                    "signals": reset_signal,
                    "discarded_phase_iteration_summary": [
                        {
                            "iteration": item.get("iteration"),
                            "phase_index": item.get("phase_index"),
                            "overall_score": item.get("overall_score"),
                            "match_score": item.get("match_score"),
                        }
                        for item in iterations
                    ],
                }
                direct_reset_events.append(event)
                direct_reset_pending = event
                active_hard_constraints = ""
                current_shader = None
                candidate_ir_generation = None
                candidate_ir = None
                latest_candidate_video = None
                latest_shader_path = None
                latest_review_path = None
                latest_visual_feedback = None
                feedback_signal_history.clear()
                iterations = []
                completed_iterations = 0
                iteration = 1
                print(
                    f"[3.{iteration}] severe mismatch -> direct reset phase {phase_index}; "
                    "generate first shader from source image + target video, no library reselection",
                    flush=True,
                )
            else:
                print(
                    f"[3.{iteration}] severe mismatch detected but max direct resets reached; continue current phase",
                    flush=True,
                )
                feedback_signal_history.clear()

        shader_edit_plan: dict[str, Any] | None
        prompt: str | None = None
        direct_reset_content: list[dict[str, Any]] | None = None
        if candidate_ir_generation is None:
            print(f"[3.{iteration}] build initial shader edit plan from target IR", flush=True)
            llm_visual_feedback = None
            shader_edit_plan = build_initial_edit_plan_from_ir(target_ir)
            if direct_reset_pending is not None:
                direct_reset_content = build_direct_reset_shader_content(
                    input_image=input_image,
                    target_video=resolve_repo_path(repo_root, str(args.video_path)),
                    target_ir=target_ir,
                    reset_reason=direct_reset_pending,
                    image_size=args.image_size,
                )
            if args.shader_builder_backend == "llm_freeform":
                print(f"[3.{iteration}] generate initial shader from top1 reference with legacy freeform LLM", flush=True)
                prompt = build_initial_shader_prompt(
                    selected_effect=selected_effect,
                    selected_references=selected_references,
                    target_ir=target_ir,
                    selected_sources=selected_sources,
                )
                if active_hard_constraints:
                    prompt += active_hard_constraints
        else:
            llm_visual_feedback = latest_visual_feedback
            shader_edit_plan = extract_feedback_edit_plan(llm_visual_feedback) or build_initial_edit_plan_from_ir(target_ir)
            if args.shader_builder_backend == "llm_freeform":
                prompt = build_iteration_prompt(
                    iteration=iteration,
                    selected_effect=selected_effect,
                    selected_references=selected_references,
                    target_ir=target_ir,
                    candidate_ir=candidate_ir,
                    llm_visual_feedback=llm_visual_feedback,
                    current_shader=current_shader,
                    selected_sources=selected_sources,
                )
                if active_hard_constraints:
                    prompt += active_hard_constraints
        last_failure = ""
        for attempt in range(1, args.max_generation_attempts + 1):
            input_candidate_video_for_attempt = latest_candidate_video
            shader_build_record: dict[str, Any] | None = None
            if direct_reset_content is not None:
                print(f"[3.{iteration}] direct reset initial shader from source image + target video", flush=True)
                if last_failure and attempt >= 2:
                    fallback_build = build_shader_from_edit_plan(
                        edit_plan=shader_edit_plan,
                        target_ir=target_ir,
                        candidate_ir=candidate_ir,
                        llm_visual_feedback=llm_visual_feedback,
                        current_shader=current_shader,
                        selected_sources=None,
                        selected_references=[],
                        iteration=iteration,
                        backend="programmatic",
                    )
                    shader_text = fallback_build.shader_text
                    shader_build_record = fallback_build.to_jsonable()
                    shader_build_record["backend"] = "direct_reset_programmatic_fallback_after_failure"
                    shader_build_record["previous_failure"] = last_failure
                elif last_failure:
                    retry_content = list(direct_reset_content)
                    retry_content[0] = {
                        "type": "text",
                        "text": str(retry_content[0].get("text", ""))
                        + "\n\n上一次生成/渲染失败，请重新输出完整可运行的两个 GLSL 代码块。"
                        + f"\nfailure_reason: {last_failure}\n",
                    }
                else:
                    retry_content = direct_reset_content
                if shader_build_record is None:
                    shader_text = call_code_llm_content(
                        retry_content,
                        model=args.code_model or args.request_model,
                        temperature=args.temperature,
                        max_tokens=int(os.environ.get("EFFECT_IR_CODE_LLM_MAX_TOKENS", "3600")),
                        timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
                    )
                    shader_build_record = {
                        "backend": "direct_reset_code_model",
                        "reset_event": direct_reset_pending,
                        "edit_plan": shader_edit_plan,
                        "previous_failure": last_failure or None,
                        "code_model": args.code_model or args.request_model,
                    }
            elif args.shader_builder_backend == "llm_freeform":
                if prompt is None:
                    raise RuntimeError("Legacy llm_freeform backend requires a prompt.")
                attempt_prompt = prompt
                if last_failure:
                    attempt_prompt += (
                        "\n\n上一次生成/渲染失败，失败原因如下。请重新输出完整、可运行的两个 GLSL 代码块；"
                        "不要省略任何函数、main、uniform 或结尾代码。\n"
                        f"failure_reason: {last_failure}\n"
                    )
                shader_text = call_llm_text(
                    attempt_prompt,
                    model=args.request_model,
                    temperature=args.temperature,
                    max_tokens=3200,
                    timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
                )
                shader_build_record = {
                    "backend": "llm_freeform",
                    "edit_plan": shader_edit_plan,
                    "previous_failure": last_failure or None,
                }
            else:
                print(f"[3.{iteration}] build shader from primitive/edit plan backend={args.shader_builder_backend}", flush=True)
                shader_build = build_shader_from_edit_plan(
                    edit_plan=shader_edit_plan,
                    target_ir=target_ir,
                    candidate_ir=candidate_ir,
                    llm_visual_feedback=llm_visual_feedback,
                    current_shader=current_shader,
                    selected_sources=selected_sources,
                    selected_references=selected_references,
                    iteration=iteration,
                    backend=args.shader_builder_backend,
                    code_model=args.code_model,
                    temperature=args.temperature,
                    previous_failure=last_failure or None,
                    llm_call=lambda prompt_text, model, temp, max_tokens, timeout: call_code_llm_text(
                        prompt_text,
                        model=model or args.request_model,
                        temperature=temp,
                        max_tokens=max_tokens,
                        timeout=timeout,
                    ),
                )
                shader_text = shader_build.shader_text
                shader_build_record = shader_build.to_jsonable()
                shader_build_record["previous_failure"] = last_failure or None
            try:
                shader_text = ensure_shader_precision_preamble(shader_text)
            except Exception:
                pass
            valid_shader, shader_reason = validate_shader_text(shader_text)
            if not valid_shader:
                failed_path = work_dir / f"iter_{iteration:02d}_attempt_{attempt:02d}_failed_shader.md"
                failed_path.write_text(shader_text, encoding="utf-8")
                print(f"[4.{iteration}] invalid shader attempt {attempt}: {shader_reason}", flush=True)
                repaired_text = repair_shader_text(shader_text, model=args.request_model, temperature=args.temperature)
                try:
                    repaired_text = ensure_shader_precision_preamble(repaired_text)
                except Exception:
                    pass
                valid_repair, repair_reason = validate_shader_text(repaired_text)
                if not valid_repair:
                    last_failure = f"invalid shader: {shader_reason}; repair failed: {repair_reason}"
                    failed_generation_attempts.append(
                        {
                            "iteration": iteration,
                            "attempt": attempt,
                            "stage": "shader_validation",
                            "reason": last_failure,
                            "failed_shader_markdown": str(failed_path),
                        }
                    )
                    continue
                shader_text = repaired_text
            safe_shader, safety_reason = lint_shader_safety(shader_text)
            if not safe_shader:
                unsafe_path = work_dir / f"iter_{iteration:02d}_attempt_{attempt:02d}_unsafe_shader.md"
                unsafe_path.write_text(shader_text, encoding="utf-8")
                print(f"[4.{iteration}] unsafe shader attempt {attempt}: {safety_reason}", flush=True)
                repaired_text = repair_shader_safety(
                    shader_text,
                    model=args.request_model,
                    temperature=args.temperature,
                    safety_reason=safety_reason,
                )
                try:
                    repaired_text = ensure_shader_precision_preamble(repaired_text)
                except Exception:
                    pass
                valid_repair, repair_reason = validate_shader_text(repaired_text)
                safe_repair, safe_repair_reason = lint_shader_safety(repaired_text) if valid_repair else (False, repair_reason)
                if not valid_repair or not safe_repair:
                    last_failure = (
                        f"unsafe shader: {safety_reason}; "
                        f"safety repair failed: {repair_reason if not valid_repair else safe_repair_reason}"
                    )
                    failed_generation_attempts.append(
                        {
                            "iteration": iteration,
                            "attempt": attempt,
                            "stage": "shader_safety_lint",
                            "reason": last_failure,
                            "unsafe_shader_markdown": str(unsafe_path),
                        }
                    )
                    continue
                shader_text = repaired_text
                if isinstance(shader_build_record, dict):
                    shader_build_record.setdefault("safety_repairs", []).append(
                        {
                            "reason": safety_reason,
                            "unsafe_shader_markdown": str(unsafe_path),
                        }
                    )

            shader_source_path = work_dir / f"iter_{iteration:02d}_shader_source.md"
            shader_source_path.write_text(shader_text, encoding="utf-8")
            vertex_path, fragment_path = write_shader_files(shader_text, work_dir, iteration)

            rendered_video = work_dir / f"iter_{iteration:02d}_rendered.mp4"
            print(f"[4.{iteration}] render candidate video attempt {attempt}", flush=True)
            try:
                if args.render_command:
                    run_render_command(
                        args.render_command,
                        vertex_shader=vertex_path,
                        fragment_shader=fragment_path,
                        input_image=input_image,
                        output_video=rendered_video,
                        iteration=iteration,
                    )
                    render_job = None
                else:
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
            except Exception as exc:
                last_failure = f"render failed: {exc}"
                failed_generation_attempts.append(
                    {
                        "iteration": iteration,
                        "attempt": attempt,
                        "stage": "render",
                        "reason": last_failure,
                        "shader_source_markdown": str(shader_source_path),
                    }
                )
                print(f"[4.{iteration}] render failed attempt {attempt}: {exc}", flush=True)
                continue

            valid_video, video_reason = validate_rendered_video(rendered_video)
            if not valid_video:
                last_failure = f"invalid rendered video: {video_reason}"
                failed_generation_attempts.append(
                    {
                        "iteration": iteration,
                        "attempt": attempt,
                        "stage": "video_validation",
                        "reason": last_failure,
                        "shader_source_markdown": str(shader_source_path),
                        "rendered_video": str(rendered_video),
                    }
                )
                print(f"[4.{iteration}] invalid rendered video attempt {attempt}: {video_reason}", flush=True)
                continue

            current_shader = shader_text
            latest_shader_path = shader_source_path
            latest_candidate_video = rendered_video
            print(f"[4.{iteration}] analyze rendered video for next iteration", flush=True)
            candidate_ir_generation = generate_video_ir(
                rendered_video,
                input_image=input_image,
                repo_root=repo_root,
                sample_id=f"iter_{iteration:02d}_rendered",
                model=args.request_model,
                temperature=args.temperature,
                sample_fps=args.sample_fps,
                image_size=args.image_size,
            )
            candidate_ir = candidate_ir_generation["structured_ir"]
            print(f"[4.{iteration}] score rendered video with visual model", flush=True)
            llm_visual_feedback_after_render = generate_llm_visual_feedback(
                target_video=args.video_path,
                candidate_video=rendered_video,
                repo_root=repo_root,
                target_ir=target_ir,
                candidate_ir=candidate_ir,
                current_shader=current_shader,
                model=args.request_model,
                temperature=args.temperature,
                image_size=args.image_size,
            )
            latest_visual_feedback = llm_visual_feedback_after_render
            if direct_reset_pending is not None:
                direct_reset_pending = None
            feedback_signal = detect_reference_reselection_signal(llm_visual_feedback_after_render)
            review_path = work_dir / f"iter_{iteration:02d}_review.md"
            write_iteration_review_markdown(
                path=review_path,
                iteration=iteration,
                rendered_video=rendered_video,
                vertex_shader=vertex_path,
                fragment_shader=fragment_path,
                shader_source_markdown=shader_source_path,
                selected_references=selected_references,
                shader_edit_plan_used=shader_edit_plan,
                feedback_used_for_prompt=llm_visual_feedback,
                feedback_after_render=llm_visual_feedback_after_render,
                candidate_ir=candidate_ir,
                shader_builder_record=shader_build_record,
            )
            latest_review_path = review_path
            feedback_signal_history.append(
                {
                    "iteration": iteration,
                    "phase_index": phase_index,
                    "signal": feedback_signal,
                    "overall_score": extract_feedback_overall_score(llm_visual_feedback_after_render),
                }
            )
            iterations.append(
                {
                    "iteration": iteration,
                    "phase_index": phase_index,
                    "attempt": attempt,
                    "input_candidate_video": None if input_candidate_video_for_attempt is None else str(input_candidate_video_for_attempt),
                    "review_markdown": str(review_path),
                    "shader_markdown": str(review_path),
                    "shader_source_markdown": str(shader_source_path),
                    "vertex_shader": str(vertex_path),
                    "fragment_shader": str(fragment_path),
                    "shader_builder": shader_build_record,
                    "shader_edit_plan_used": shader_edit_plan,
                    "llm_visual_feedback_used_for_prompt": llm_visual_feedback,
                    "llm_visual_feedback_after_render": llm_visual_feedback_after_render,
                    "match_score": None if llm_visual_feedback_after_render.get("parsed") is None else llm_visual_feedback_after_render["parsed"].get("match_score"),
                    "overall_score": extract_feedback_overall_score(llm_visual_feedback_after_render),
                    "reference_reselection_signal": feedback_signal,
                    "active_references": selected_references,
                    "rendered_video": str(rendered_video),
                    "shader_lab_job": render_job,
                    "candidate_ir": candidate_ir,
                }
            )
            completed_iterations += 1
            break
        else:
            raise RuntimeError(f"Iteration {iteration} failed after {args.max_generation_attempts} generation attempts; last failure: {last_failure}")

    iteration_outputs = [
        {
            "iteration": item["iteration"],
            "overall_score": item.get("overall_score"),
            "match_score": item.get("match_score"),
            "rendered_video": item.get("rendered_video"),
            "review_markdown": item.get("review_markdown"),
            "shader_markdown": item.get("shader_markdown"),
            "shader_source_markdown": item.get("shader_source_markdown"),
            "vertex_shader": item.get("vertex_shader"),
            "fragment_shader": item.get("fragment_shader"),
        }
        for item in iterations
    ]
    score_ranking = sorted(
        [
            {
                "rank": 0,
                "iteration": item["iteration"],
                "overall_score": item.get("overall_score"),
                "match_score": item.get("match_score"),
                "rendered_video": item.get("rendered_video"),
                "review_markdown": item.get("review_markdown"),
                "shader_markdown": item.get("shader_markdown"),
                "shader_source_markdown": item.get("shader_source_markdown"),
            }
            for item in iterations
        ],
        key=lambda item: (-1.0 if item["overall_score"] is None else float(item["overall_score"])),
        reverse=True,
    )
    for rank, item in enumerate(score_ranking, start=1):
        item["rank"] = rank
    best_iteration = score_ranking[0] if score_ranking and score_ranking[0].get("overall_score") is not None else None
    result = {
        "input_image_path": str(input_image),
        "video_path": str(args.video_path),
        "shader_builder_backend": args.shader_builder_backend,
        "code_model": args.code_model,
        "selected_effect": selected_effect,
        "library_ablation": {
            "enabled": self_excluded_effect_name is not None,
            "excluded_self_effect_name": self_excluded_effect_name,
        },
        "selected_reference": selected_references[0],
        "selected_references": selected_references,
        "reference_reselection_events": reference_reselection_events,
        "direct_reset_events": direct_reset_events,
        "latest_candidate_video": None if latest_candidate_video is None else str(latest_candidate_video),
        "target_ir_generation": target_ir_generation,
        "initial_top_results": [
            {
                "library_id": item["library_id"],
                "effect_name": item["effect_name"],
                "display_name": item["display_name"],
                "similarity": item["similarity"],
                "retrieval_score": item["retrieval_score"],
                "library_summary": item["library_summary"],
                "category_info": item.get("category_info"),
            }
            for item in initial_ranking[: args.top_k]
        ],
        "latest_candidate_ir_generation": candidate_ir_generation,
        "iterations": iterations,
        "failed_generation_attempts": failed_generation_attempts,
        "iteration_outputs": iteration_outputs,
        "score_ranking": score_ranking,
        "best_iteration_by_llm_score": best_iteration,
        "final_candidate_video": None if latest_candidate_video is None else str(latest_candidate_video),
        "final_shader_markdown": None if latest_review_path is None else str(latest_review_path),
        "final_shader_source_markdown": None if latest_shader_path is None else str(latest_shader_path),
        "final_shader_source": current_shader,
    }
    result_path = work_dir / "closed_loop_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        json.dumps(
            {
                "result": str(result_path),
                "selected_effect": selected_effect,
                "selected_reference": {
                    "library_id": selected_references[0]["library_id"],
                    "effect_name": selected_references[0]["effect_name"],
                    "similarity": selected_references[0]["similarity"],
                    "retrieval_score": selected_references[0]["retrieval_score"],
                },
                "selected_references": [
                    {
                        "library_id": item["library_id"],
                        "effect_name": item["effect_name"],
                        "similarity": item["similarity"],
                        "retrieval_score": item["retrieval_score"],
                    }
                    for item in selected_references
                ],
                "reference_reselection_events": reference_reselection_events,
                "direct_reset_events": direct_reset_events,
                "iteration_outputs": iteration_outputs,
                "score_ranking": score_ranking,
                "best_iteration_by_llm_score": best_iteration,
                "final_candidate_video": result["final_candidate_video"],
                "final_shader": result["final_shader_markdown"],
            },
            ensure_ascii=False,
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
