"""Stage one of the expert-to-agent multi-pass translation workflow.

The expert sees only chronological samples from the target video.  It describes
an implementation-oriented pass decomposition, but deliberately writes no GLSL.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .direct_shader_baseline import build_target_contact_sheet_data_url
from .model_client import generate_messages


EXPERT_VIDEO_PROMPT = """You are an experienced real-time graphics engineer studying a reference effect video. TARGET_VIDEO_SAMPLES is chronological from p=0 to p=1. You do not see the clean source image in this stage.

Describe how you would decompose the visible effect into an executable WebGL multi-pass shader graph. Infer the smallest useful number of passes from the video; do not default to three. Each pass must have one clear responsibility that produces a meaningful intermediate texture. Do not add identity, placeholder, or redundant passes.

Separate:
- spatial resampling or geometry,
- blur, support, masks, edges, or intermediate textures,
- color/compositing/finishing,
- animation timing and reset points,
- host-controlled parameters, FBO scale, and resource connections.

Return JSON only. Do not write GLSL or markdown. Use this exact top-level shape:
{
  "effect_summary":"short description",
  "temporal_story":[{"range":"p=...","visible_change":"what visibly happens"}],
  "parameters":{"uniformName":{"type":"float","keyframes":[[0,0],[1,1]]}},
  "pass_count":2,
  "passes":[{
    "id":"pass_01",
    "name":"descriptive name",
    "role":"single responsibility",
    "pass_goal":"what its intermediate texture should visibly contain",
    "output_contract":{"semantics":"what the output texture represents","channels":{"rgba":"encoded meaning"},"value_range":"expected range","temporal_behavior":"how this texture changes over progress"},
    "inputs":{"inputImageTexture":"source"},
    "output":"pass_01",
    "scale":1.0,
    "dynamic":false,
    "progress_behavior":"static or exact temporal behavior",
    "shader_stages":["fragment"],
    "implementation_notes":["techniques an experienced shader author would try"],
    "success_criteria":["visible facts that prove this pass works"],
    "preserve":["properties this pass must retain"],
    "avoid":["likely wrong shortcuts or artifacts"]
  }]
}

Rules:
- Use the smallest positive number of passes that genuinely implements the effect. There is no fixed upper limit; never add redundant passes.
- A pass can read source and any earlier output, never a future output.
- scale is between 0.05 and 1.0.
- shader_stages is ["fragment"] unless vertex displacement is truly necessary; then use ["vertex","fragment"].
- Use graph parameters only for host-driven shader uniforms. uProgress and uTime are built in and must not appear in parameters.
- Every parameter must be immediately executable, for example {"type":"float","value":0.5} or {"type":"vec2","keyframes":[[0,[0.2,0.5]],[1,[0.8,0.5]]]}. Never return ranges, suggestions, owners, descriptions, curve placeholders, or prose-only parameter objects without value/keyframes.
- Describe the observed video, including turning points and intervals where an operation fades out or yields to another operation.
"""


def _json_object(text: str, label: str) -> dict[str, Any]:
    value_text = text.strip()
    if not value_text.startswith("{"):
        start, end = value_text.find("{"), value_text.rfind("}")
        if start >= 0 and end > start:
            value_text = value_text[start:end + 1]
    try:
        value = json.loads(value_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} returned invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} must return one JSON object")
    return value


def validate_expert_brief(payload: dict[str, Any]) -> dict[str, Any]:
    passes = payload.get("passes")
    if not isinstance(passes, list) or len(passes) < 1:
        raise ValueError("Expert brief must contain at least one pass")
    payload["pass_count"] = len(passes)
    payload.setdefault("parameters", {})
    payload.setdefault("temporal_story", [])
    if not isinstance(payload["parameters"], dict):
        raise ValueError("Expert parameters must be an object")
    allowed_parameter_types = {"float", "int", "vec2", "vec3", "vec4"}
    for name, spec in payload["parameters"].items():
        if name in {"uProgress", "uTime", "progress", "time"}:
            raise ValueError(f"{name} is built in and must not be declared as a graph parameter")
        if isinstance(spec, bool) or not isinstance(spec, (int, float, list, dict)):
            raise ValueError(f"Parameter {name} must be a numeric value, vector, or executable uniform spec")
        if isinstance(spec, dict):
            parameter_type = spec.get("type", "float")
            if parameter_type not in allowed_parameter_types:
                raise ValueError(f"Parameter {name} has unsupported type {parameter_type}")
            keyframes = spec.get("keyframes")
            if "value" not in spec and not isinstance(keyframes, list):
                raise ValueError(f"Parameter {name} must contain value or keyframes, not descriptive metadata only")
            if isinstance(keyframes, list):
                if not keyframes:
                    raise ValueError(f"Parameter {name} keyframes must not be empty")
                for keyframe in keyframes:
                    if isinstance(keyframe, dict):
                        # Model providers commonly use the compact `p` spelling.
                        # Normalize it locally instead of spending another LLM
                        # request on a semantically equivalent JSON rewrite.
                        if "progress" not in keyframe and "p" in keyframe:
                            keyframe["progress"] = keyframe.pop("p")
                        progress, value = keyframe.get("progress"), keyframe.get("value")
                    elif isinstance(keyframe, list) and len(keyframe) == 2:
                        progress, value = keyframe
                    else:
                        raise ValueError(f"Parameter {name} contains an invalid keyframe")
                    if not isinstance(progress, (int, float)) or not 0 <= float(progress) <= 1:
                        raise ValueError(f"Parameter {name} keyframe progress must be within 0..1")
                    if isinstance(value, bool) or not isinstance(value, (int, float, list)):
                        raise ValueError(f"Parameter {name} keyframe value must be numeric or a numeric vector")

    resources = {"source"}
    required = {
        "name", "role", "pass_goal", "inputs", "output", "scale",
        "dynamic", "progress_behavior", "shader_stages",
        "implementation_notes", "success_criteria", "preserve", "avoid",
    }
    for index, item in enumerate(passes, 1):
        if not isinstance(item, dict):
            raise ValueError(f"Pass {index} must be an object")
        item.setdefault("id", f"pass_{index:02d}")
        missing = required.difference(item)
        if missing:
            raise ValueError(f"Pass {index} misses fields: {sorted(missing)}")
        inputs = item["inputs"]
        if not isinstance(inputs, dict):
            raise ValueError(f"Pass {index} inputs must be an object")
        # Analytic support passes (mask, deformation field, noise field, etc.)
        # may intentionally produce a texture from coordinates, time and graph
        # uniforms without sampling an earlier texture.  An empty mapping is a
        # valid explicit declaration, distinct from a missing inputs field.
        if any(str(resource) not in resources for resource in inputs.values()):
            raise ValueError(f"Pass {index} references a future or unknown resource")
        scale = item["scale"]
        if not isinstance(scale, (int, float)) or not 0.05 <= float(scale) <= 1.0:
            raise ValueError(f"Pass {index} scale must be within 0.05..1.0")
        stages = item["shader_stages"]
        if stages not in (["fragment"], ["vertex", "fragment"]):
            raise ValueError(f"Pass {index} shader_stages must be fragment or vertex+fragment")
        for field in ("implementation_notes", "success_criteria", "preserve", "avoid"):
            if not isinstance(item[field], list):
                raise ValueError(f"Pass {index} {field} must be a list")
        contract = item.setdefault("output_contract", {
            "semantics": str(item["pass_goal"]),
            "channels": {"rgba": "color or encoded support data described by semantics"},
            "value_range": "normalized 0..1",
            "temporal_behavior": str(item["progress_behavior"]),
        })
        if not isinstance(contract, dict) or not str(contract.get("semantics", "")).strip():
            raise ValueError(f"Pass {index} output_contract must describe output semantics")
        if not isinstance(contract.get("channels"), dict) or not contract["channels"]:
            raise ValueError(f"Pass {index} output_contract channels must be a non-empty object")
        contract.setdefault("value_range", "normalized 0..1")
        contract.setdefault("temporal_behavior", str(item["progress_behavior"]))
        resources.add(str(item["output"]))
    return payload


def create_expert_brief(
    target_video: Path,
    *,
    model: str,
    frame_count: int,
    work_dir: Path,
    attempts: int = 3,
    temperature: float = 0.0,
) -> tuple[dict[str, Any], str, list[int], str]:
    """Return validated expert brief, raw response, sampled indices and sheet URL."""
    sheet, indices = build_target_contact_sheet_data_url(
        target_video,
        frame_count=frame_count,
        work_dir=work_dir,
    )
    error_message = ""
    raw = ""
    for attempt in range(1, attempts + 1):
        correction = "" if attempt == 1 else f"\nPrevious response was invalid: {error_message}. Return the complete JSON object again."
        raw = generate_messages(
            [{"role": "user", "content": [
                {"type": "text", "text": EXPERT_VIDEO_PROMPT + correction},
                {"type": "image_url", "image_url": {"url": sheet}},
            ]}],
            model=model,
            temperature=temperature,
        )
        (work_dir / f"expert_response_{attempt:02d}.txt").write_text(raw, encoding="utf-8")
        try:
            brief = validate_expert_brief(_json_object(raw, "expert"))
            return brief, raw, indices, sheet
        except ValueError as exc:
            error_message = str(exc)
    raise ValueError(f"Expert failed after {attempts} attempts: {error_message}")
