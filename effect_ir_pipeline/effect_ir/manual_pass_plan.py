"""Turn a human pass implementation reference into a visually grounded contract."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .expert_pass_plan import _json_object, validate_expert_brief
from .model_client import generate_messages


MANUAL_PLAN_COMPILER_PROMPT = """You are beginning stage two of a multi-pass shader implementation workflow.

PASS_IMPLEMENTATION_REFERENCE was written in stage one. It fixes the pass count, order, resource flow, and responsibility of each pass. SOURCE_IMAGE is the clean input. TARGET_VIDEO_SAMPLES are chronological frames of the desired final effect and are the visual ground truth. Both visual inputs are upright in normal human-view orientation. Preserve that orientation unless the target visibly performs a flip or rotation; the renderer already handles WebGL texture coordinates.

Convert the reference into an executable render-graph contract. Do not add, remove, merge, split, reorder, or reassign passes. Use the referenced techniques as the intended implementation route, but ground all visible behavior in SOURCE_IMAGE → TARGET_VIDEO_SAMPLES: infer concrete timing, thresholds, colors, spatial scale, and acceptance criteria from the target frames so the final rendered video matches them as closely as possible. Do not invent embellishments merely because they sound compatible with the reference. Do not write GLSL yet.

Return JSON only with this shape:
{
  "effect_summary":"short description faithful to the human plan",
  "temporal_story":[{"range":"p=...","visible_change":"visible process"}],
  "parameters":{"uniformName":{"type":"float","keyframes":[[0,0],[1,1]]}},
  "pass_count":2,
  "passes":[{
    "id":"pass_01",
    "name":"descriptive name",
    "role":"the responsibility assigned by the human",
    "pass_goal":"visible intermediate result",
    "output_contract":{"semantics":"what downstream passes can read from this texture","channels":{"rgba":"encoded meaning"},"value_range":"expected range","temporal_behavior":"how the texture changes"},
    "inputs":{"inputImageTexture":"source"},
    "output":"pass_01",
    "scale":1.0,
    "dynamic":false,
    "progress_behavior":"exact temporal behavior",
    "shader_stages":["fragment"],
    "implementation_notes":["implementation guidance"],
    "success_criteria":["visible acceptance facts"],
    "preserve":["properties to retain"],
    "avoid":["wrong shortcuts or artifacts"]
  }]
}

Use only source and earlier pass outputs as inputs. Scale must be 0.05..1.0. shader_stages must be ["fragment"] or ["vertex","fragment"]. uProgress, uTime, current-pass uResolution/uTexelSize, and uSourceResolution are available. The declared pass_count must exactly equal the human-declared count. Structure comes from the reference; final appearance and motion come from the visual evidence.
"""


def compile_manual_pass_plan(
    human_text: str,
    *,
    visual: list[dict[str, Any]],
    model: str,
    attempts: int,
    temperature: float,
    work_dir: Path,
    label: str,
    expected_pass_count: int,
) -> tuple[dict[str, Any], list[str]]:
    """Compile free-form human intent inside stage two; never alter its pass layout."""
    if not human_text.strip():
        raise ValueError("Human pass plan cannot be empty")
    raw_responses: list[str] = []
    error_message = ""
    for attempt in range(1, attempts + 1):
        correction = "" if attempt == 1 else (
            f"\nPrevious contract was invalid: {error_message}. Return a complete corrected JSON object, "
            "without changing the human pass count, order, or responsibilities."
        )
        prompt = (
            MANUAL_PLAN_COMPILER_PROMPT
            + f"\n\nHUMAN-DECLARED PASS COUNT: {expected_pass_count}"
            + "\n\nPASS_IMPLEMENTATION_REFERENCE (verbatim):\n---\n"
            + human_text.strip()
            + "\n---"
            + correction
        )
        raw = generate_messages(
            [{"role": "user", "content": [{"type": "text", "text": prompt}, *visual]}],
            model=model,
            temperature=temperature,
        )
        raw_responses.append(raw)
        (work_dir / f"{label}_plan_compile_{attempt:02d}.txt").write_text(raw, encoding="utf-8")
        try:
            brief = validate_expert_brief(_json_object(raw, "manual plan compiler"))
            if brief["pass_count"] != expected_pass_count:
                raise ValueError(
                    f"Compiler returned {brief['pass_count']} passes; human requested {expected_pass_count}"
                )
            return brief, raw_responses
        except ValueError as exc:
            error_message = str(exc)
    raise ValueError(f"Manual pass plan compilation failed after {attempts} attempts: {error_message}")


def parse_complete_contract(human_text: str) -> dict[str, Any] | None:
    """Accept a user-authored full contract without a model compilation call."""
    try:
        payload = json.loads(human_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return validate_expert_brief(payload)
