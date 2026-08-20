"""Human-authored pass design followed by agentic shader implementation."""
from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import time
import uuid
from pathlib import Path
from typing import Any, Callable

from .direct_shader_baseline import build_target_contact_sheet_data_url, build_timeline_contact_sheet_data_urls
from .expert_pass_plan import validate_expert_brief
from .manual_pass_plan import parse_complete_contract
from .manifest import resolve_repo_path
from .model_client import generate_messages
from .typed_pass_graph_baseline import _archive_round_video, _contact_part, _json, _studio_task, _visual_evidence, _wait_for_web_feedback_event


VISUAL_EVIDENCE_POLICY = """EVIDENCE PRIORITY (highest first): TARGET_VIDEO_SAMPLES, SOURCE_IMAGE, actual rendered candidate/intermediate sheets, then auxiliary human wording. Infer visible content, motion origin, direction, timing, affected region, and appearance from the chronological target frames before considering prose. Auxiliary effect wording is an unverified hint, never visual ground truth. Use only the parts visibly supported by the frames. If wording conflicts with, adds to, or is more specific than the images support, follow the images and discard that wording. Never add an effect, pass, motion, color, or transition solely because auxiliary prose mentions it.
"""


VISUAL_OBSERVER_PROMPT = VISUAL_EVIDENCE_POLICY + """
Observe SOURCE_IMAGE and TARGET_VIDEO_SAMPLES without access to any human effect description. Describe only directly visible evidence. Track the sequence as motion between frames rather than independently describing frame contents. Unknown or ambiguous details must remain uncertain.

Return JSON only:
{"source_content":"stable source elements needed to judge deformation","observed_effect":"short visual-only summary","temporal_story":[{"range":"early|middle|late or p range","visible_change":"what changes between frames"}],"motion_origin":"where the change first becomes visible","motion_path":"how it moves or expands","spatial_regions":["affected regions"],"appearance_changes":["only visible color/light/texture changes"],"uncertain":["facts not safely inferable from sampled frames"]}
"""


DENSE_TIMELINE_OBSERVER_PROMPT = """You are a visual timeline observer, not a shader designer. You receive SOURCE_IMAGE followed by several TARGET TIMELINE SHEETS. Frames are chronological and each tile has its true timestamp. Do not infer, mention, or recommend pass count, render graph, GLSL, uniforms, algorithms, or implementation techniques.

Describe the visible transformation as motion between adjacent samples. For every requested interval, state what newly changes relative to the preceding frame: onset/exit, direction, displacement or scale trend, affected region, boundary behavior, color/light/texture change, and whether the change accelerates, reverses, pauses, or continues. Track persistent objects or patterns across intervals instead of redescribing each frame as a still image. If a fact cannot be seen, mark it uncertain rather than inventing it.

Return JSON only:
{"duration_seconds":0.0,"sample_interval_seconds":0.2,"global_process":"one concise complete account of the evolving effect","timeline":[{"start_seconds":0.0,"end_seconds":0.2,"visible_change":"what changes during this interval relative to its start","affected_regions":["..."],"motion":"direction/path/scale/deformation trend or none","appearance":"color/light/texture trend or none"}],"persistent_properties":["properties maintained throughout"],"recurring_or_reversing_patterns":["cycles, reversals, returns, or repeated phases"],"uncertain":["ambiguities"]}

The timeline array must contain exactly one entry for every adjacent pair listed in REQUIRED_INTERVALS, in the same order and with the exact supplied timestamps.
"""


DENSE_TIMELINE_SYNTHESIS_PROMPT = """You are a temporal-process analyst, not a shader designer. Your only evidence is a chronological observation recorded at approximately 0.2-second intervals. Convert those local interval notes into one precise, continuous account of the complete visible transformation before any render-graph planning occurs.

Do not merely shorten, paraphrase, or classify the effect. Reconcile adjacent intervals into causal phases while retaining exact time ranges and all visually important details: what first changes, where it originates, how it propagates, which regions are affected, motion/deformation direction and shape, intensity and speed trends, appearance changes, recovery or reversal, repeated events, overlap between events, and the final state. Explicitly distinguish simultaneous changes from sequential changes. When an interval contradicts another, preserve the conflict under uncertain_or_conflicting instead of silently choosing one. Do not invent details absent from the interval observations.

Use concrete visible language. Avoid broad phrases such as "the effect intensifies", "dynamic distortion occurs", or "the image changes" unless immediately expanded into what visibly moves or changes, where, in which direction, and during which exact time span. Do not mention pass count, render graph, GLSL, shaders, uniforms, algorithms, implementation techniques, or recommendations.

Return JSON only:
{
  "overall_process":"a detailed end-to-end account naming the initial state, onset, propagation, strongest state, recovery/repetition, and final state",
  "initial_state":"what is visibly true before the first change",
  "phases":[{
    "start_seconds":0.0,
    "end_seconds":0.0,
    "phase_name":"specific visible event",
    "entry_state":"state inherited from the preceding phase",
    "continuous_change":"what evolves throughout this range rather than isolated frame contents",
    "motion_and_geometry":"origin, direction, path, deformation shape, scale/displacement trend and boundary behavior",
    "affected_regions":["specific regions"],
    "appearance_change":"color, brightness, texture, opacity or none",
    "intensity_and_speed":"how strength and rate evolve",
    "exit_state":"what has become true at the end and what remains active"
  }],
  "event_relationships":["overlap, succession, repetition, reversal, recovery, or cause-and-visible-result relationships"],
  "recurring_pattern":{"present":false,"period_seconds":null,"origin":"","propagation":"","variation_between_cycles":""},
  "spatial_summary":{"origins":["..."],"paths":["..."],"affected_then_recovered_regions":["..."]},
  "temporal_landmarks":[{"time_seconds":0.0,"visible_state":"specific state at this landmark","why_it_matters":"onset, peak, reversal, recovery, repeat, or final"}],
  "persistent_properties":["properties that remain stable across the whole video"],
  "final_state":"specific visible state at the end relative to the beginning",
  "uncertain_or_conflicting":["unsupported, ambiguous, or conflicting details"]
}

Cover the entire observed duration without gaps. Phase boundaries must come from the supplied interval timestamps. Prefer enough phases to preserve materially different behavior; do not merge onset, propagation, peak, recovery, and repetition when their visible behavior differs.
"""


DIRECT_SINGLE_PASS_PROMPT = """You are given SOURCE_IMAGE and TARGET_VIDEO_SAMPLES. TARGET_VIDEO_SAMPLES are chronological from p=0 to p=1. Write one complete GLSL ES shader that transforms SOURCE_IMAGE into the target video effect. Infer the complete dynamic process directly from the images; do not use or describe a pass plan, visual observation, IR, edit plan, score, review, or implementation contract.

When the target visibly changes over time, make uProgress drive that visible coordinate or color change through the middle of the video. Reproduce the dominant motion, affected region, timing, and appearance; do not return an unchanged source except where the target is unchanged. Keep useful source detail outside the affected region. Images are upright. Use textureCoord unchanged by default and flip, rotate, or swap axes only when TARGET_VIDEO_SAMPLES visibly do so relative to SOURCE_IMAGE.

Output exactly two fenced ```glsl blocks and nothing else: vertex first, fragment second. The vertex shader must use `attribute vec2 position`, set `textureCoord = position * 0.5 + 0.5`, and assign gl_Position. The fragment shader may use only `inputImageTexture`, `uProgress`, and `uTime`; it must sample inputImageTexture and assign gl_FragColor. Use WebGL 1 only: no #version, layout, texture(), texelFetch, or external textures.
"""


DIRECT_SINGLE_PASS_REWRITE_PROMPT = """Rewrite the CURRENT single-pass shader directly so its rendered video matches TARGET_VIDEO_SAMPLES more closely. Compare the chronological target frames from p=0 to p=1 and make any code change needed to implement the REQUIRED VISIBLE CORRECTION. Preserve behavior that is already useful, but do not preserve an incorrect implementation route. Do not create an edit plan or explain the change.

Output the complete replacement as exactly two fenced ```glsl blocks and nothing else: vertex first, fragment second. Use only inputImageTexture, uProgress, and uTime in the fragment shader; sample inputImageTexture and assign gl_FragColor. Use WebGL 1 only.
"""


PASS_IMPLEMENTER_PROMPT = VISUAL_EVIDENCE_POLICY + """
You are the implementation agent responsible for exactly one pass in a human-designed WebGL render graph. SOURCE_IMAGE is the image that will actually be rendered. TARGET_VIDEO_SAMPLES are chronological frames of the desired final video and are the visual ground truth. Both are upright in normal human-view orientation. PASS_IMPLEMENTATION_REFERENCE fixes the graph structure and explains the intended technique for each pass; it is an implementation reference, not a substitute for observing the target. DECLARED INPUT RESOURCE sheets, when present, show the actual named textures consumed by this pass at p=0, 0.5 and 1. Treat each sheet according to its resource name and contract; do not mistake a mask, displacement/support texture, or source branch for the cumulative final image.

Implement only the assigned pass using the technique assigned in PASS_IMPLEMENTATION_REFERENCE. Follow its input samplers, resource contract, FBO scale, dynamic ownership, and success criteria. Choose the concrete thresholds, strengths, colors, sampling scale, and time curve by comparing SOURCE_IMAGE with TARGET_VIDEO_SAMPLES. The objective is that rendering SOURCE_IMAGE through the complete graph matches the target video's visible content and process as closely as possible. Use textureCoord unchanged by default. Never apply `1.0-textureCoord`, swap axes, or rotate UVs as coordinate-system compensation; do so only when the target visibly performs that transformation relative to the source and this pass explicitly owns it. Do not freely reinterpret the effect, add unobserved details, or copy descriptive wording without implementing its visible consequence. Do not recreate downstream responsibilities. A static pass must not animate. A dynamic pass may use uProgress/uTime and declared graph parameters. The host also injects uResolution (current pass FBO pixels), uOutputResolution (same value), uTexelSize (its reciprocal), and uSourceResolution (clean source pixels). Use these built-ins instead of guessing texture dimensions. Preserve alpha and valid texture coordinates unless the pass explicitly owns those changes.

Return shader source only:
- For fragment-only work, return exactly one fenced glsl block containing the fragment shader.
- If vertex_and_fragment is requested, return exactly two fenced glsl blocks, vertex first and fragment second.
- WebGL 1 only: no #version, layout, texture(), texelFetch, external files or explanation.
- Fragment shader must declare precision highp float, varying vec2 textureCoord, every named sampler, and assign gl_FragColor.
"""


FINAL_AGENT_PROMPT = VISUAL_EVIDENCE_POLICY + """
You are the controller of a multi-pass shader agent. SOURCE_IMAGE is the actual input. TARGET_VIDEO_SAMPLES are the visual ground truth and CANDIDATE_VIDEO_SAMPLES are the current complete render. Every image uses normal upright human-view orientation. PASS_IMPLEMENTATION_REFERENCE is compact working memory, and INTERMEDIATE_PASS_SHEETS expose actual pass outputs. Compare target and candidate directly and propose the smallest repair scope that can really cause the visible correction. Treat a flip as an effect only when visibly present in the target relative to the source.

Return JSON only:
{"decision":"done|revise","scope":"parameter|single_pass|multi_pass|graph","observation":"most important visible comparison","responsible_passes":[1],"instruction":"one executable repair","required_visible_change":"what must visibly differ after rendering","acceptance_criteria":["observable proof"],"preserve":["correct properties that must remain"],"graph_patch":{"parameters":{},"pass_updates":[]}}

Choose done only when no material appearance or motion mismatch remains. Use parameter for existing host uniforms/keyframes, single_pass for a local shader error, multi_pass when producer and consumer must change together, and graph only for resource/FBO/temporal-contract changes. Never change pass count or order. graph_patch may update parameters and existing pass inputs, scale, or progress_behavior only. Do not introduce an unobserved effect.
"""


HUMAN_FEEDBACK_PROMPT = """A human has inspected the current complete render and supplied one high-priority visual correction. SOURCE_IMAGE is the actual input, TARGET_VIDEO_SAMPLES is ground truth, CANDIDATE_VIDEO_SAMPLES is the current result, and INTERMEDIATE_PASS_SHEETS show actual pass outputs. Choose the smallest repair scope that can causally implement the feedback.

Respect the feedback, but use target frames to ground its visible meaning. Use multi_pass when an upstream texture and its consumer must coordinate. Use graph only for existing resource connections, FBO scale, progress behavior, or graph parameters. Never change pass count/order or introduce an absent effect.

Return JSON only:
{"scope":"parameter|single_pass|multi_pass|graph","responsible_passes":[1],"observation":"how the mismatch appears","instruction":"one executable repair","required_visible_change":"what must visibly differ after rendering","acceptance_criteria":["observable proof"],"preserve":["correct properties that must not regress"],"graph_patch":{"parameters":{},"pass_updates":[]}}
"""


REPAIR_VERIFIER_PROMPT = """Quickly verify one multi-pass shader repair. TARGET_VIDEO_SAMPLES are ground truth. BEFORE_VIDEO_SAMPLES show the version before the repair. AFTER_VIDEO_SAMPLES show the proposed result. Check only whether the declared required visible change happened and whether an important preserved property regressed. Judge the sampled motion as a sequence, not isolated frame positions. Be concise.

Return JSON only:
{"outcome":"fulfilled|partial|failed|regressed","requirement_check":"one short sentence","regressions":["at most two important new problems"],"next_instruction":"one short corrected action if needed, otherwise empty","accepted_facts":["at most three proven facts"]}

fulfilled means the requested change is clearly visible and preserved properties did not materially regress. partial means it moved in the right direction but is incomplete. failed means it did not occur. regressed means damage outweighs progress.
"""


AUTO_PASS_PLANNER_PROMPT = VISUAL_EVIDENCE_POLICY + """
You are the stage-one graphics expert. SOURCE_IMAGE is the clean image that will be rendered. TARGET_VIDEO_SAMPLES are chronological frames of the desired video. VISUAL_ONLY_OBSERVATION was produced in a separate call that never saw the auxiliary description; use it as the authoritative text summary of the images. Infer a useful WebGL render graph that can transform SOURCE_IMAGE into that visible process. There is no preferred pass count and no fixed upper limit. Do not default to one, three, or any other number.

Choose pass boundaries by causal responsibility and editability, not by asking whether all math could theoretically fit in one fragment shader. Give a component its own pass when it has an independently meaningful intermediate output and at least one of these is true: it uses a distinct sampling domain or spatial transform; it produces a mask or support texture consumed elsewhere; it forms a source-derived branch that must later be merged; it needs a different FBO scale or sampling footprint; it owns a temporal behavior that should be tuned without rewriting unrelated appearance; or later visual review should be able to revise it without destabilizing already-correct components. A localized lens over a separately processed background, for example, may naturally separate background preparation, refracted content or mask production, and final rim/color/compositing even though one long shader could encode all of them.

Keep one pass when the observed effect is genuinely one coupled operation and splitting would create no reusable, inspectable, or independently adjustable texture. Multiple visible adjectives alone do not justify multiple passes when they are inseparable consequences of the same sampling operation. Never create identity, placeholder, bookkeeping, duplicate, or merely sequential passes whose output has no clear visual/resource contract. Every pass must materially simplify implementation, expose a useful intermediate, or isolate an independently editable responsibility.

Before returning the graph, silently test each proposed boundary: state what texture it produces, who consumes it, and what later correction could be made to this pass without rewriting the others. Merge adjacent passes when those questions have no concrete answer. Conversely, split an overloaded pass when it owns multiple independently observable branches, sampling domains, or temporal responsibilities.

This stage decides only pass count, responsibilities, resource connections, FBO scale, temporal ownership and observable acceptance criteria. Do not write GLSL. A pass may read source and earlier outputs only. The final pass must consume the required branches and produce a display-ready frame. Dynamic behavior may be shared across passes when the target requires coordinated background, mask/lens, and composite motion; declare precisely what each dynamic pass owns instead of forcing all visible time variation into one pass.

Every item in parameters is an executable host uniform, not documentation. uProgress and uTime are built in and must not be declared. Each parameter must contain a concrete value or chronological keyframes, using only float, int, vec2, vec3, or vec4 types. Do not return suggested ranges, owner/description metadata, curve placeholders, or prose-only parameter objects.

Write object-form keyframes with the keys `progress` and `value` (compact `p` is also accepted and normalized locally). `inputs` must always be a JSON object. Use `{}` only for a genuinely analytic support pass that samples no texture; otherwise name every sampler and bind it to `source` or an earlier output.

Return JSON only in the same executable contract shape used by the workflow:
{"effect_summary":"...","temporal_story":[{"range":"p=...","visible_change":"..."}],"parameters":{},"pass_count":2,"passes":[{"id":"pass_01","name":"...","role":"one responsibility","pass_goal":"visible intermediate","output_contract":{"semantics":"...","channels":{"rgba":"..."},"value_range":"0..1","temporal_behavior":"..."},"inputs":{"inputImageTexture":"source"},"output":"pass_01","scale":1.0,"dynamic":false,"progress_behavior":"...","shader_stages":["fragment"],"implementation_notes":["..."],"success_criteria":["..."],"preserve":["..."],"avoid":["..."]}]}
"""


def _auto_plan_passes(
    *,
    visual: list[dict[str, Any]],
    visual_observation: dict[str, Any] | None = None,
    effect_description: str = "",
    pass_count_constraint: int = 0,
    pass_responsibilities: str = "",
    model: str,
    attempts: int,
    temperature: float,
    work_dir: Path,
    job_id: str,
) -> tuple[dict[str, Any], list[str]]:
    responses: list[str] = []
    error_message = ""
    for attempt in range(1, attempts + 1):
        correction = "" if attempt == 1 else f"\nThe prior graph was invalid: {error_message}. Return one complete corrected JSON object."
        supplied: list[str] = []
        if pass_count_constraint:
            supplied.append(
                f"PASS COUNT: exactly {pass_count_constraint}. This is a hard constraint; return exactly this many passes."
            )
        if pass_responsibilities.strip():
            supplied.append(
                "PASS RESPONSIBILITIES:\n---\n"
                + pass_responsibilities.strip()
                + "\n---\nPreserve every responsibility supplied by the human. Infer its missing count, ordering, connections, resources, parameters, and acceptance criteria as needed."
            )
        if effect_description.strip():
            supplied.append(
                "AUXILIARY EFFECT DESCRIPTION (unverified hypothesis):\n---\n"
                + effect_description.strip()
                + "\n---\nUse a claim only when TARGET_VIDEO_SAMPLES or VISUAL_ONLY_OBSERVATION visibly supports it. Ignore unsupported or conflicting claims. This text cannot by itself justify a pass, motion, color, or transition."
            )
        description_context = ""
        if supplied:
            description_context = (
                "\n\nHUMAN-PROVIDED INPUTS:\n"
                + "\n\n".join(supplied)
                + "\nPASS COUNT and PASS RESPONSIBILITIES are hard structural constraints when supplied. AUXILIARY EFFECT DESCRIPTION is not a constraint and must yield to visual evidence. Infer every omitted field yourself."
            )
        observation_context = ""
        if visual_observation:
            observation_context = (
                "\n\nVISUAL_ONLY_OBSERVATION (authoritative, produced without seeing auxiliary wording):\n"
                + json.dumps(visual_observation, ensure_ascii=False)
            )
        raw = generate_messages(
            [{"role": "user", "content": [{"type": "text", "text": AUTO_PASS_PLANNER_PROMPT + observation_context + description_context + correction}, *visual]}],
            model=model,
            temperature=temperature,
        )
        responses.append(raw)
        (work_dir / f"{job_id}_auto_pass_plan_{attempt:02d}.txt").write_text(raw, encoding="utf-8")
        try:
            brief = validate_expert_brief(_json(raw, "automatic pass planner"))
            if pass_count_constraint and brief["pass_count"] != pass_count_constraint:
                raise ValueError(
                    f"Planner returned {brief['pass_count']} passes; the human required {pass_count_constraint}"
                )
            return brief, responses
        except ValueError as exc:
            error_message = str(exc)
    raise ValueError(f"Automatic pass planning failed after {attempts} attempts: {error_message}")


def _observe_visual_evidence(
    *,
    visual: list[dict[str, Any]],
    model: str,
    temperature: float,
    work_dir: Path,
    job_id: str,
) -> dict[str, Any]:
    def validate(payload: dict[str, Any]) -> dict[str, Any]:
        required = {"source_content", "observed_effect", "temporal_story", "motion_origin", "motion_path"}
        missing = required.difference(payload)
        if missing:
            raise ValueError(f"Visual observation misses fields: {sorted(missing)}")
        if not isinstance(payload.get("temporal_story"), list):
            raise ValueError("visual temporal_story must be a list")
        payload.setdefault("spatial_regions", [])
        payload.setdefault("appearance_changes", [])
        payload.setdefault("uncertain", [])
        return payload

    return _validated_json_call(
        content=[{"type": "text", "text": VISUAL_OBSERVER_PROMPT}, *visual],
        model=model,
        temperature=temperature,
        label=f"{job_id}_visual_only_observer",
        validator=validate,
        attempts=2,
        work_dir=work_dir,
    )


def _observe_dense_timeline(
    *,
    source_part: dict[str, Any],
    video: Path,
    interval_seconds: float,
    maximum_frames: int,
    model: str,
    temperature: float,
    work_dir: Path,
    job_id: str,
) -> tuple[dict[str, Any], list[dict[str, float | int]]]:
    sheets, samples = build_timeline_contact_sheet_data_urls(
        video,
        interval_seconds=interval_seconds,
        maximum_frames=maximum_frames,
    )
    intervals = [
        {"start_seconds": left["time_seconds"], "end_seconds": right["time_seconds"]}
        for left, right in zip(samples, samples[1:])
    ]
    content: list[dict[str, Any]] = [
        {"type": "text", "text": DENSE_TIMELINE_OBSERVER_PROMPT + "\nREQUIRED_INTERVALS:\n" + json.dumps(intervals, ensure_ascii=False)},
        {"type": "text", "text": "SOURCE_IMAGE (stable reference, not a video frame):"},
        source_part,
    ]
    for index, sheet in enumerate(sheets, 1):
        content.extend([
            {"type": "text", "text": f"TARGET TIMELINE SHEET {index}/{len(sheets)}:"},
            {"type": "image_url", "image_url": {"url": sheet}},
        ])

    def validate(payload: dict[str, Any]) -> dict[str, Any]:
        timeline = payload.get("timeline")
        if not isinstance(timeline, list) or len(timeline) != len(intervals):
            raise ValueError(f"dense timeline must contain exactly {len(intervals)} intervals")
        for expected, observed in zip(intervals, timeline):
            if not isinstance(observed, dict):
                raise ValueError("each dense timeline interval must be an object")
            try:
                start = float(observed.get("start_seconds"))
                end = float(observed.get("end_seconds"))
            except (TypeError, ValueError) as exc:
                raise ValueError("timeline timestamps must be numeric") from exc
            if abs(start - float(expected["start_seconds"])) > 0.011 or abs(end - float(expected["end_seconds"])) > 0.011:
                raise ValueError("timeline entries must preserve the requested timestamps and order")
            if not str(observed.get("visible_change", "")).strip():
                raise ValueError("every interval needs a visible_change description")
            observed.setdefault("affected_regions", [])
            observed.setdefault("motion", "")
            observed.setdefault("appearance", "")
        payload["duration_seconds"] = samples[-1]["time_seconds"]
        payload["sample_interval_seconds"] = interval_seconds
        payload.setdefault("global_process", "")
        payload.setdefault("persistent_properties", [])
        payload.setdefault("recurring_or_reversing_patterns", [])
        payload.setdefault("uncertain", [])
        payload["sample_count"] = len(samples)
        return payload

    observation = _validated_json_call(
        content=content,
        model=model,
        temperature=temperature,
        label=f"{job_id}_dense_timeline_observer",
        validator=validate,
        attempts=3,
        work_dir=work_dir,
    )
    return observation, samples


def _synthesize_dense_timeline(
    *,
    observation: dict[str, Any],
    model: str,
    temperature: float,
    work_dir: Path,
    job_id: str,
) -> dict[str, Any]:
    """Turn local 0.2-second notes into a detailed process specification.

    This stage deliberately receives no images, human wording, or implementation
    context. Its only job is to preserve and connect the observer's evidence
    before the graph planner reasons about implementation.
    """
    duration = float(observation.get("duration_seconds", 0.0))
    source_timeline = observation.get("timeline", [])

    def validate(payload: dict[str, Any]) -> dict[str, Any]:
        required = {"overall_process", "initial_state", "phases", "event_relationships", "final_state"}
        missing = required.difference(payload)
        if missing:
            raise ValueError(f"dense timeline synthesis misses fields: {sorted(missing)}")
        if not str(payload.get("overall_process", "")).strip():
            raise ValueError("dense timeline synthesis needs a detailed overall_process")
        phases = payload.get("phases")
        if not isinstance(phases, list) or not phases:
            raise ValueError("dense timeline synthesis needs at least one phase")
        previous_end = 0.0
        for index, phase in enumerate(phases):
            if not isinstance(phase, dict):
                raise ValueError("each synthesized phase must be an object")
            try:
                start = float(phase.get("start_seconds"))
                end = float(phase.get("end_seconds"))
            except (TypeError, ValueError) as exc:
                raise ValueError("synthesized phase timestamps must be numeric") from exc
            if start < -0.011 or end <= start or end > duration + 0.011:
                raise ValueError("synthesized phase has an invalid time range")
            if index == 0 and start > 0.011:
                raise ValueError("synthesized phases must begin at zero")
            if index and abs(start - previous_end) > 0.011:
                raise ValueError("synthesized phases must cover the timeline without gaps or overlap")
            if not str(phase.get("continuous_change", "")).strip():
                raise ValueError("every synthesized phase needs a continuous_change")
            phase.setdefault("phase_name", f"phase {index + 1}")
            phase.setdefault("entry_state", "")
            phase.setdefault("motion_and_geometry", "")
            phase.setdefault("affected_regions", [])
            phase.setdefault("appearance_change", "")
            phase.setdefault("intensity_and_speed", "")
            phase.setdefault("exit_state", "")
            previous_end = end
        if abs(previous_end - duration) > 0.011:
            raise ValueError("synthesized phases must reach the final observed timestamp")
        if not isinstance(payload.get("event_relationships"), list):
            raise ValueError("event_relationships must be a list")
        payload.setdefault("recurring_pattern", {"present": False, "period_seconds": None, "origin": "", "propagation": "", "variation_between_cycles": ""})
        payload.setdefault("spatial_summary", {"origins": [], "paths": [], "affected_then_recovered_regions": []})
        payload.setdefault("temporal_landmarks", [])
        payload.setdefault("persistent_properties", [])
        payload.setdefault("uncertain_or_conflicting", [])
        payload["duration_seconds"] = duration
        payload["source_interval_count"] = len(source_timeline)
        return payload

    content = [{
        "type": "text",
        "text": (
            DENSE_TIMELINE_SYNTHESIS_PROMPT
            + "\nOBSERVED_DURATION_SECONDS:\n"
            + json.dumps(duration)
            + "\n\nDENSE_INTERVAL_OBSERVATION (authoritative; preserve its concrete evidence):\n"
            + json.dumps(observation, ensure_ascii=False)
        ),
    }]
    return _validated_json_call(
        content=content,
        model=model,
        temperature=temperature,
        label=f"{job_id}_dense_timeline_synthesis",
        validator=validate,
        attempts=3,
        work_dir=work_dir,
    )


def _brief_reference_text(brief: dict[str, Any]) -> str:
    lines = [f"模型根据原图和目标视频规划了 {brief['pass_count']} 个 Pass："]
    for index, item in enumerate(brief["passes"], 1):
        lines.append(f"Pass {index}（{item['name']}）：{item['role']} 可见目标：{item['pass_goal']}")
    return "\n".join(lines)


DEFAULT_VERTEX_SHADER = """attribute vec2 position;
varying vec2 textureCoord;
void main() {
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}"""


def _fenced_blocks(text: str) -> list[str]:
    parts = text.split("```")
    blocks: list[str] = []
    for index in range(1, len(parts), 2):
        block = parts[index].strip()
        first, separator, rest = block.partition("\n")
        if separator and first.strip().lower() in {"glsl", "vert", "vertex", "frag", "fragment"}:
            block = rest.strip()
        if block:
            blocks.append(block)
    return blocks


def _validate_fragment(source: str) -> None:
    for token in ("precision", "varying vec2 textureCoord", "gl_FragColor"):
        if token not in source:
            raise ValueError(f"Fragment shader misses {token}")
    if "#version" in source:
        raise ValueError("WebGL 1 fragment shader must not contain #version")


def _validate_vertex(source: str) -> None:
    for token in ("gl_Position", "textureCoord"):
        if token not in source:
            raise ValueError(f"Vertex shader misses {token}")
    if "#version" in source:
        raise ValueError("WebGL 1 vertex shader must not contain #version")


def _shader_package(text: str, require_vertex: bool) -> dict[str, str]:
    blocks = _fenced_blocks(text)
    if require_vertex:
        if len(blocks) != 2:
            raise ValueError("Code agent must return vertex and fragment blocks")
        vertex, fragment = blocks
        _validate_vertex(vertex)
    else:
        if len(blocks) != 1:
            raise ValueError("Code agent must return exactly one fragment block")
        vertex, fragment = "", blocks[0]
    _validate_fragment(fragment)
    return {"vertex": vertex, "fragment": fragment}


def _write_graph(
    job_dir: Path,
    job_id: str,
    input_image: Path,
    brief: dict[str, Any],
    packages: list[dict[str, str]],
) -> Path:
    job_dir.mkdir(parents=True, exist_ok=True)
    copied = job_dir / "input.png"
    if not copied.exists():
        shutil.copy2(input_image, copied)
    graph_passes: list[dict[str, Any]] = []
    for index, package in enumerate(packages, 1):
        spec = brief["passes"][index - 1]
        fragment_path = job_dir / f"pass_{index:02d}.frag.glsl"
        fragment_path.write_text(package["fragment"].rstrip() + "\n", encoding="utf-8")
        graph_pass: dict[str, Any] = {
            "id": spec["id"],
            "name": spec["name"],
            "role": spec["role"],
            "inputs": spec["inputs"],
            "output": spec["output"],
            "scale": spec["scale"],
            "dynamic": spec["dynamic"],
            "progress_behavior": spec["progress_behavior"],
            "output_contract": spec["output_contract"],
            "fragment_shader": fragment_path.name,
        }
        if package["vertex"]:
            vertex_path = job_dir / f"pass_{index:02d}.vert.glsl"
            vertex_path.write_text(package["vertex"].rstrip() + "\n", encoding="utf-8")
            graph_pass["vertex_shader"] = vertex_path.name
        graph_passes.append(graph_pass)
    graph = job_dir / "pass_graph.json"
    graph.write_text(json.dumps({
        "id": job_id,
        "effect_summary": brief["effect_summary"],
        "input_image": copied.name,
        "parameters": brief.get("parameters", {}),
        "pass_count": len(graph_passes),
        "passes": graph_passes,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    return graph


def _load_shader_packages(job_dir: Path, pass_count: int) -> list[dict[str, str]]:
    """Load the longest already-written pass prefix for crash-safe resume."""
    packages: list[dict[str, str]] = []
    for index in range(1, pass_count + 1):
        fragment = job_dir / f"pass_{index:02d}.frag.glsl"
        if not fragment.is_file():
            break
        vertex = job_dir / f"pass_{index:02d}.vert.glsl"
        packages.append({
            "vertex": vertex.read_text(encoding="utf-8") if vertex.is_file() else "",
            "fragment": fragment.read_text(encoding="utf-8"),
        })
    return packages


def _write_state(path: Path, state: dict[str, Any], checkpoint: str | None = None, **checkpoint_details: Any) -> None:
    if checkpoint:
        state["checkpoint"] = {"stage": checkpoint, "updated_at": time.time(), **checkpoint_details}
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def _package_text(package: dict[str, str]) -> str:
    vertex = "" if not package["vertex"] else "VERTEX:\n" + package["vertex"] + "\n\n"
    return vertex + "FRAGMENT:\n" + package["fragment"]


def _interface_summary(brief: dict[str, Any], index: int) -> dict[str, Any]:
    return {
        "temporal_story": brief.get("temporal_story", []),
        "parameters": brief.get("parameters", {}),
        "assigned_pass": brief["passes"][index - 1],
        "upstream": [
            {"id": item["id"], "role": item["role"], "output": item["output"], "output_contract": item["output_contract"]}
            for item in brief["passes"][:index - 1]
        ],
        "downstream": [
            {"id": item["id"], "role": item["role"], "inputs": item["inputs"], "expected_input_semantics": item.get("implementation_notes", [])}
            for item in brief["passes"][index:]
        ],
    }


def _compact_working_memory(brief: dict[str, Any], accepted_facts: list[str] | None = None, obligation: dict[str, Any] | None = None) -> str:
    hard_constraints = {
        key: value for key, value in brief.get("human_constraints", {}).items()
        if key != "effect_description"
    }
    memory = {
        "evidence_priority": "target video frames first; auxiliary wording is not retained as visual truth",
        "target": {
            "effect_summary": brief["effect_summary"],
            "temporal_story": brief.get("temporal_story", []),
            "visual_only_observation": brief.get("visual_only_observation", {}),
        },
        "human_constraints": hard_constraints,
        "passes": [
            {
                "index": index,
                "name": item["name"],
                "role": item["role"],
                "inputs": item["inputs"],
                "output": item["output"],
                "output_contract": item["output_contract"],
                "progress_behavior": item["progress_behavior"],
                "success_criteria": item["success_criteria"],
                "avoid": item["avoid"],
            }
            for index, item in enumerate(brief["passes"], 1)
        ],
        "accepted_facts": list(accepted_facts or [])[-8:],
        "current_obligation": obligation or None,
    }
    return json.dumps(memory, ensure_ascii=False)


def _short_text(value: Any, limit: int = 280) -> str:
    text = " ".join(str(value or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _short_list(values: Any, limit: int = 4) -> list[str]:
    if not isinstance(values, list):
        return []
    return [_short_text(value) for value in values if str(value).strip()][:limit]


def _compact_temporal_story(brief: dict[str, Any], limit: int = 8) -> list[Any]:
    story = brief.get("temporal_story", [])
    if not isinstance(story, list):
        return []
    if len(story) > limit:
        indices = sorted({round(index * (len(story) - 1) / (limit - 1)) for index in range(limit)})
        story = [story[index] for index in indices]
    compact: list[Any] = []
    for item in story:
        if isinstance(item, dict):
            compact.append({str(key): _short_text(value) for key, value in item.items() if value not in (None, "", [], {})})
        else:
            compact.append(_short_text(item))
    return compact


def _final_review_context(brief: dict[str, Any], accepted_facts: list[str] | None = None) -> dict[str, Any]:
    return {
        "target": {"effect_summary": _short_text(brief.get("effect_summary")), "temporal_story": _compact_temporal_story(brief)},
        "pass_map": [
            {
                "pass": index,
                "name": item.get("name"),
                "role": _short_text(item.get("role")),
                "inputs": item.get("inputs", {}),
                "output": item.get("output"),
                "dynamic": item.get("dynamic", False),
                "output_semantics": _short_text((item.get("output_contract") or {}).get("semantics")),
            }
            for index, item in enumerate(brief["passes"], 1)
        ],
        "accepted_facts": _short_list(accepted_facts or [], 6),
    }


def _normalize_repair(payload: dict[str, Any], pass_count: int) -> dict[str, Any]:
    if payload.get("decision") == "done":
        return {"decision": "done", "observation": str(payload.get("observation", "")), "preserve": list(payload.get("preserve", []))}
    scope = str(payload.get("scope", "single_pass"))
    if scope not in {"parameter", "single_pass", "multi_pass", "graph"}:
        raise ValueError("Repair scope must be parameter, single_pass, multi_pass, or graph")
    raw_passes = payload.get("responsible_passes")
    if raw_passes is None and payload.get("responsible_pass") is not None:
        raw_passes = [payload["responsible_pass"]]
    if not isinstance(raw_passes, list):
        raw_passes = []
    responsible = sorted({int(value) for value in raw_passes})
    if any(value not in range(1, pass_count + 1) for value in responsible):
        raise ValueError("Repair references an unknown pass")
    if scope == "single_pass" and len(responsible) != 1:
        raise ValueError("single_pass repair must select exactly one pass")
    if scope == "multi_pass" and len(responsible) < 2:
        raise ValueError("multi_pass repair must select at least two passes")
    if scope in {"parameter", "graph"} and not responsible:
        responsible = list(range(1, pass_count + 1))
    instruction = str(payload.get("instruction", "")).strip()
    required = str(payload.get("required_visible_change", "")).strip()
    criteria = payload.get("acceptance_criteria", [])
    if not instruction or not required or not isinstance(criteria, list) or not criteria:
        raise ValueError("Repair must include instruction, required_visible_change, and acceptance_criteria")
    patch = payload.get("graph_patch", {})
    if not isinstance(patch, dict):
        raise ValueError("graph_patch must be an object")
    if scope == "parameter" and not (isinstance(patch.get("parameters"), dict) and patch["parameters"]):
        raise ValueError("parameter repair must provide graph_patch.parameters")
    if scope == "graph" and not (
        (isinstance(patch.get("parameters"), dict) and patch["parameters"])
        or (isinstance(patch.get("pass_updates"), list) and patch["pass_updates"])
    ):
        raise ValueError("graph repair must provide parameters or pass_updates")
    return {
        "decision": "revise",
        "scope": scope,
        "responsible_passes": responsible,
        "observation": str(payload.get("observation", "")),
        "instruction": instruction,
        "required_visible_change": required,
        "acceptance_criteria": [str(item) for item in criteria if str(item).strip()],
        "preserve": [str(item) for item in payload.get("preserve", []) if str(item).strip()],
        "graph_patch": patch,
    }


def _validated_json_call(
    *,
    content: list[dict[str, Any]],
    model: str,
    temperature: float,
    label: str,
    validator: Callable[[dict[str, Any]], dict[str, Any]],
    attempts: int = 2,
    work_dir: Path | None = None,
) -> dict[str, Any]:
    error = ""
    call_id = uuid.uuid4().hex[:8]
    for attempt in range(1, attempts + 1):
        retry = [] if attempt == 1 else [{"type": "text", "text": f"Your previous JSON contract was invalid: {error}. Return one complete corrected JSON object only."}]
        raw = generate_messages([{"role": "user", "content": [*content, *retry]}], model=model, temperature=temperature)
        if work_dir is not None:
            safe_label = "".join(character if character.isalnum() or character in "_-" else "_" for character in label)
            (work_dir / f"{safe_label}_{call_id}_{attempt:02d}.txt").write_text(raw, encoding="utf-8")
        try:
            return validator(_json(raw, label))
        except (ValueError, TypeError, KeyError) as exc:
            error = str(exc)
    raise ValueError(f"{label} failed after {attempts} attempts: {error}")


def _apply_graph_patch(brief: dict[str, Any], repair: dict[str, Any]) -> dict[str, Any]:
    candidate = copy.deepcopy(brief)
    patch = repair.get("graph_patch", {})
    parameters = patch.get("parameters")
    if isinstance(parameters, dict):
        candidate.setdefault("parameters", {}).update(parameters)
    updates = patch.get("pass_updates", [])
    if updates is None:
        updates = []
    if not isinstance(updates, list):
        raise ValueError("graph_patch.pass_updates must be a list")
    allowed = {"inputs", "scale", "progress_behavior"}
    for update in updates:
        if not isinstance(update, dict):
            raise ValueError("Each pass update must be an object")
        unknown = set(update).difference(allowed | {"pass"})
        if unknown:
            raise ValueError(f"Graph patch contains unsupported pass fields: {sorted(unknown)}")
        index = int(update.get("pass", 0))
        if index not in range(1, len(candidate["passes"]) + 1):
            raise ValueError("Graph patch references an unknown pass")
        for key in allowed:
            if key in update:
                candidate["passes"][index - 1][key] = update[key]
    return validate_expert_brief(candidate)


def _dirty_passes_for_graph_patch(brief: dict[str, Any], repair: dict[str, Any]) -> list[int]:
    """Return graph-patched passes and every transitive consumer of their outputs."""
    updates = (repair.get("graph_patch") or {}).get("pass_updates") or []
    dirty = {int(item.get("pass", 0)) for item in updates if isinstance(item, dict)}
    dirty.discard(0)
    changed_resources = {
        brief["passes"][index - 1]["output"]
        for index in dirty
        if index in range(1, len(brief["passes"]) + 1)
    }
    for index, spec in enumerate(brief["passes"], 1):
        if index in dirty:
            continue
        if any(resource in changed_resources for resource in (spec.get("inputs") or {}).values()):
            dirty.add(index)
            changed_resources.add(spec["output"])
    return sorted(dirty)


def _resource_sheets_for_pass(
    brief: dict[str, Any], index: int, prefix_sheets: list[Path]
) -> dict[str, Path]:
    """Map each declared non-source input to the concrete producing-pass sheet."""
    producer = {
        spec["output"]: prefix_sheets[position - 1]
        for position, spec in enumerate(brief["passes"][: len(prefix_sheets)], 1)
    }
    resources: dict[str, Path] = {}
    for resource in (brief["passes"][index - 1].get("inputs") or {}).values():
        if resource not in {"source", "input", "previous"} and resource in producer:
            resources[resource] = producer[resource]
    return resources


def _named_intermediate_parts(brief: dict[str, Any], prefix_sheets: list[Path]) -> list[dict[str, Any]]:
    parts: list[dict[str, Any]] = []
    for index, sheet in enumerate(prefix_sheets, 1):
        spec = brief["passes"][index - 1]
        contract = spec.get("output_contract") or {}
        parts.extend([
            {
                "type": "text",
                "text": (
                    f"RESOURCE {spec['output']} (produced by pass {index}: {spec['name']}): "
                    f"{contract.get('semantics', spec['role'])}"
                ),
            },
            _contact_part(sheet),
        ])
    return parts


def _inspect_contract_sheet(sheet: Path, spec: dict[str, Any]) -> dict[str, Any]:
    """Cheap render sanity probe; it records evidence and only flags obvious failures."""
    import cv2
    import numpy as np

    image = cv2.imread(str(sheet), cv2.IMREAD_COLOR)
    if image is None or image.shape[1] < 3:
        return {"usable": False, "warnings": ["prefix contact sheet is unreadable"]}
    tile_width = image.shape[1] // 3
    frames = [image[:, offset * tile_width:(offset + 1) * tile_width] for offset in range(3)]
    # Ignore the small timestamp label inserted by the local renderer.
    frames = [frame[min(32, frame.shape[0] // 4):] for frame in frames]
    differences = [float(np.mean(cv2.absdiff(frames[0], frame))) for frame in frames[1:]]
    dynamic_detected = max(differences, default=0.0) > 1.5
    nearly_black = all(float(frame.mean()) < 1.0 and float(frame.std()) < 1.0 for frame in frames)
    warnings: list[str] = []
    if nearly_black:
        warnings.append("all sampled output frames are nearly black")
    if spec.get("dynamic") and not dynamic_detected:
        warnings.append("the pass is declared dynamic but its sampled output appears static")
    return {
        "usable": not warnings,
        "fatal": nearly_black,
        "declared_semantics": (spec.get("output_contract") or {}).get("semantics", ""),
        "declared_dynamic": bool(spec.get("dynamic")),
        "dynamic_detected": dynamic_detected,
        "warnings": warnings,
    }


def _generate_pass(
    *,
    brief: dict[str, Any],
    index: int,
    visual: list[dict[str, Any]],
    resource_sheets: dict[str, Path] | None,
    model: str,
    temperature: float,
    code_attempts: int,
    work_dir: Path,
    label: str,
    current: dict[str, str] | None = None,
    instruction: str = "",
    human_plan: str,
) -> dict[str, str]:
    require_vertex = brief["passes"][index - 1]["shader_stages"] == ["vertex", "fragment"]
    context = _interface_summary(brief, index)
    revision = ""
    if current is not None:
        revision = "\nCURRENT SHADER PACKAGE:\n" + _package_text(current) + "\nMANDATORY REVISION:\n" + instruction
    previous: list[dict[str, Any]] = []
    for resource, sheet in (resource_sheets or {}).items():
        previous.extend([
            {"type": "text", "text": f"DECLARED INPUT RESOURCE `{resource}` (actual producing-pass output at p=0, 0.5, 1):"},
            _contact_part(sheet),
        ])
    last_error = ""
    for attempt in range(1, code_attempts + 1):
        correction = "" if attempt == 1 else f"\nThe prior response was unusable: {last_error}. Return the complete shader package again."
        prompt = PASS_IMPLEMENTER_PROMPT + "\nPASS_IMPLEMENTATION_REFERENCE (verbatim; structure binding, visually calibrated against target samples):\n---\n" + human_plan.strip() + "\n---\nREQUESTED STAGES: " + ("vertex_and_fragment" if require_vertex else "fragment_only") + "\nVISUALLY GROUNDED COMPILED CONTRACT:\n" + json.dumps(context, ensure_ascii=False) + revision + correction
        raw = generate_messages([{"role": "user", "content": [{"type": "text", "text": prompt}, *visual, *previous]}], model=model, temperature=temperature)
        (work_dir / f"{label}_code_{attempt:02d}.txt").write_text(raw, encoding="utf-8")
        try:
            return _shader_package(raw, require_vertex)
        except ValueError as exc:
            last_error = str(exc)
    raise ValueError(f"Pass {index} code generation failed: {last_error}")


def _observe_final(
    *,
    brief: dict[str, Any],
    candidate_video: Path,
    prefix_sheets: list[Path],
    visual: list[dict[str, Any]],
    model: str,
    temperature: float,
    work_dir: Path,
    accepted_facts: list[str] | None = None,
) -> dict[str, Any]:
    candidate_sheet, _ = build_target_contact_sheet_data_url(candidate_video, frame_count=11, work_dir=work_dir)
    prompt = FINAL_AGENT_PROMPT + "\nCOMPACT REVIEW CONTEXT:\n" + json.dumps(
        _final_review_context(brief, accepted_facts), ensure_ascii=False
    )
    content: list[dict[str, Any]] = [
        {"type": "text", "text": prompt},
        *visual,
        {"type": "text", "text": "CANDIDATE_VIDEO_SAMPLES (current complete graph):"},
        {"type": "image_url", "image_url": {"url": candidate_sheet}},
        {"type": "text", "text": "NAMED INTERMEDIATE RESOURCES (actual outputs, not inferred descriptions):"},
        *_named_intermediate_parts(brief, prefix_sheets),
    ]
    def validate(payload: dict[str, Any]) -> dict[str, Any]:
        if payload.get("decision") not in {"done", "revise"}:
            raise ValueError("Final agent decision must be done or revise")
        return _normalize_repair(payload, len(brief["passes"]))
    return _validated_json_call(content=content, model=model, temperature=temperature, label="final_agent_observer", validator=validate, work_dir=work_dir)


def _interpret_human_feedback(
    *,
    feedback: str,
    brief: dict[str, Any],
    candidate_video: Path,
    prefix_sheets: list[Path],
    visual: list[dict[str, Any]],
    model: str,
    temperature: float,
    work_dir: Path,
) -> dict[str, Any]:
    candidate_sheet, _ = build_target_contact_sheet_data_url(candidate_video, frame_count=11, work_dir=work_dir)
    prompt = (
        HUMAN_FEEDBACK_PROMPT
        + "\nHUMAN FEEDBACK (verbatim):\n---\n" + feedback.strip() + "\n---"
        + "\nCOMPACT REVIEW CONTEXT:\n" + json.dumps(_final_review_context(brief), ensure_ascii=False)
    )
    content: list[dict[str, Any]] = [
        {"type": "text", "text": prompt},
        *visual,
        {"type": "text", "text": "CANDIDATE_VIDEO_SAMPLES (current stage-two result):"},
        {"type": "image_url", "image_url": {"url": candidate_sheet}},
        {"type": "text", "text": "NAMED INTERMEDIATE RESOURCES (actual outputs, not inferred descriptions):"},
        *_named_intermediate_parts(brief, prefix_sheets),
    ]
    def validate(payload: dict[str, Any]) -> dict[str, Any]:
        payload["decision"] = "revise"
        return _normalize_repair(payload, len(brief["passes"]))
    return _validated_json_call(content=content, model=model, temperature=temperature, label="human_feedback_interpreter", validator=validate, work_dir=work_dir)


def _verify_repair(
    *,
    repair: dict[str, Any],
    target_video: Path,
    before_video: Path,
    after_video: Path,
    visual: list[dict[str, Any]],
    model: str,
    temperature: float,
    work_dir: Path,
) -> dict[str, Any]:
    target_sheet, _ = build_target_contact_sheet_data_url(target_video, frame_count=7, work_dir=work_dir)
    before_sheet, _ = build_target_contact_sheet_data_url(before_video, frame_count=7, work_dir=work_dir)
    after_sheet, _ = build_target_contact_sheet_data_url(after_video, frame_count=7, work_dir=work_dir)
    content: list[dict[str, Any]] = [
        {"type": "text", "text": REPAIR_VERIFIER_PROMPT + "\nREPAIR CONTRACT:\n" + json.dumps(repair, ensure_ascii=False)},
        *visual[:2],
        {"type": "text", "text": "TARGET_VIDEO_SAMPLES (ground truth):"},
        {"type": "image_url", "image_url": {"url": target_sheet}},
        {"type": "text", "text": "BEFORE_VIDEO_SAMPLES (accepted baseline):"},
        {"type": "image_url", "image_url": {"url": before_sheet}},
        {"type": "text", "text": "AFTER_VIDEO_SAMPLES (proposed transaction result):"},
        {"type": "image_url", "image_url": {"url": after_sheet}},
    ]
    def validate(result: dict[str, Any]) -> dict[str, Any]:
        if result.get("outcome") not in {"fulfilled", "partial", "failed", "regressed"}:
            raise ValueError("Repair verifier outcome must be fulfilled, partial, failed, or regressed")
        result["requirement_check"] = str(result.get("requirement_check", ""))
        result["regressions"] = [str(item) for item in result.get("regressions", []) if str(item).strip()][:2]
        result["next_instruction"] = str(result.get("next_instruction", "")).strip()
        result["accepted_facts"] = [str(item) for item in result.get("accepted_facts", []) if str(item).strip()][:3]
        return result
    return _validated_json_call(content=content, model=model, temperature=temperature, label="repair_verifier", validator=validate, work_dir=work_dir)


def _execute_repair_transaction(
    *,
    repair: dict[str, Any],
    brief: dict[str, Any],
    packages: list[dict[str, str]],
    target_video: Path,
    before_video: Path,
    input_image: Path,
    repo: Path,
    studio: Path,
    studio_url: str,
    job_dir: Path,
    job_id: str,
    out: Path,
    visual: list[dict[str, Any]],
    model: str,
    temperature: float,
    code_attempts: int,
    transaction_attempts: int,
    label: str,
    accepted_facts: list[str],
    stage_unfulfilled: bool = False,
) -> tuple[dict[str, Any], list[dict[str, str]], Path, Path, dict[str, Any]]:
    baseline_brief = copy.deepcopy(brief)
    baseline_packages = copy.deepcopy(packages)
    working_brief = copy.deepcopy(brief)
    working_packages = copy.deepcopy(packages)
    active_repair = copy.deepcopy(repair)
    transaction: dict[str, Any] = {
        "label": label,
        "repair": repair,
        "baseline_video": str(before_video),
        "attempts": [],
        "committed": False,
    }
    last_partial: tuple[dict[str, Any], list[dict[str, str]], Path, Path] | None = None
    for attempt in range(1, transaction_attempts + 1):
        attempt_event: dict[str, Any] = {"attempt": attempt, "repair": copy.deepcopy(active_repair)}
        try:
            dirty_graph_passes = _dirty_passes_for_graph_patch(working_brief, active_repair)
            working_brief = _apply_graph_patch(working_brief, active_repair)
            rewrite_passes = (
                active_repair["responsible_passes"]
                if active_repair["scope"] in {"single_pass", "multi_pass"}
                else dirty_graph_passes if active_repair["scope"] == "graph" else []
            )
            attempt_event["dependency_invalidated_passes"] = dirty_graph_passes
            if rewrite_passes:
                for index in rewrite_passes:
                    prefix_sheets: list[Path] = []
                    if index > 1:
                        upstream_graph = _write_graph(job_dir, job_id, input_image, working_brief, working_packages)
                        prefix_sheets = _render_prefixes(
                            repo, studio, studio_url, upstream_graph, job_id, out, index - 1,
                            f"{label}_attempt_{attempt:02d}_pass_{index:02d}_inputs",
                        )
                    resource_sheets = _resource_sheets_for_pass(working_brief, index, prefix_sheets)
                    instruction = (
                        active_repair["instruction"]
                        + "\nREQUIRED VISIBLE CHANGE: " + active_repair["required_visible_change"]
                        + "\nACCEPTANCE CRITERIA: " + json.dumps(active_repair["acceptance_criteria"], ensure_ascii=False)
                        + "\nPRESERVE: " + json.dumps(active_repair["preserve"], ensure_ascii=False)
                    )
                    working_packages[index - 1] = _generate_pass(
                        brief=working_brief, index=index, visual=visual, resource_sheets=resource_sheets,
                        model=model, temperature=temperature, code_attempts=code_attempts, work_dir=out,
                        label=f"{label}_attempt_{attempt:02d}_pass_{index:02d}", current=working_packages[index - 1],
                        instruction=instruction, human_plan=_compact_working_memory(working_brief, accepted_facts, active_repair),
                    )
            graph = _write_graph(job_dir, job_id, input_image, working_brief, working_packages)
            rendered = _studio_task(repo, studio, studio_url, graph, job_id, out, reveal_after_render=True)
            candidate = out / f"{label}_attempt_{attempt:02d}{rendered.suffix}"
            shutil.copy2(rendered, candidate)
            verification = _verify_repair(
                repair=active_repair, target_video=target_video, before_video=before_video, after_video=candidate,
                visual=visual, model=model, temperature=temperature, work_dir=out,
            )
            if verification["outcome"] == "partial":
                last_partial = (copy.deepcopy(working_brief), copy.deepcopy(working_packages), candidate, graph)
            attempt_event.update({"candidate_video": str(candidate), "verification": verification})
        except Exception as exc:
            attempt_event["error"] = str(exc)
            verification = {"outcome": "failed", "requirement_check": "transaction execution failed", "regressions": [], "next_instruction": str(exc), "accepted_facts": []}
            attempt_event["verification"] = verification
        transaction["attempts"].append(attempt_event)
        if verification["outcome"] == "fulfilled":
            transaction["committed"] = True
            transaction["committed_attempt"] = attempt
            transaction["accepted_facts"] = verification["accepted_facts"]
            return working_brief, working_packages, candidate, graph, transaction
        correction = verification.get("next_instruction") or verification.get("requirement_check") or "Implement the required visible change more directly."
        active_repair["instruction"] = active_repair["instruction"] + "\nVERIFIER CORRECTION: " + correction
        if verification["outcome"] in {"failed", "regressed"}:
            working_brief = copy.deepcopy(baseline_brief)
            working_packages = copy.deepcopy(baseline_packages)
    transaction["rollback_reason"] = transaction["attempts"][-1]["verification"]
    if stage_unfulfilled and last_partial is not None:
        staged_brief, staged_packages, staged_video, _ = last_partial
        preview_dir = job_dir / "previews" / label
        preview_graph = _write_graph(preview_dir, job_id, input_image, staged_brief, staged_packages)
        preview_brief = preview_dir / "compiled_pass_graph.json"
        preview_brief.write_text(json.dumps(staged_brief, ensure_ascii=False, indent=2), encoding="utf-8")
        transaction["staged_for_human_review"] = True
        transaction["staged_video"] = str(staged_video)
        transaction["staged_graph"] = str(preview_graph)
        transaction["staged_brief"] = str(preview_brief)
        transaction["preview_only"] = True
        rollback_graph = _write_graph(job_dir, job_id, input_image, baseline_brief, baseline_packages)
        return baseline_brief, baseline_packages, before_video, rollback_graph, transaction
    rollback_graph = _write_graph(job_dir, job_id, input_image, baseline_brief, baseline_packages)
    return baseline_brief, baseline_packages, before_video, rollback_graph, transaction


def _render_prefixes(
    repo: Path,
    studio: Path,
    studio_url: str,
    graph: Path,
    job_id: str,
    out: Path,
    count: int,
    label: str,
) -> list[Path]:
    results: list[Path] = []
    for pass_count in range(1, count + 1):
        current = _studio_task(repo, studio, studio_url, graph, job_id, out, pass_count)
        archived = out / f"{label}_prefix_{pass_count:02d}.jpg"
        shutil.copy2(current, archived)
        results.append(archived)
    return results


def _write_report(path: Path, state: dict[str, Any], packages: list[dict[str, str]]) -> None:
    brief = state["compiled_pass_graph"]
    dense_timeline = state.get("dense_timeline", {})
    input_heading = "Dense timeline observation" if dense_timeline.get("enabled") else "Human pass plan (verbatim)"
    input_text = (
        json.dumps(brief.get("visual_only_observation", {}), ensure_ascii=False, indent=2)
        if dense_timeline.get("enabled")
        else str(state.get("human_pass_input") or "(none; inferred by model)")
    )
    lines = [
        "# Dense Timeline → Agent Multi-Pass Translation" if dense_timeline.get("enabled") else "# Human Plan → Agent Multi-Pass Translation", "",
        "## Run summary", "",
        f"- Agent mode: `{state['agent_mode']}`",
        f"- Final phase: `{state.get('phase', 'unknown')}`",
        f"- Successful full videos: `{len(state.get('round_videos', []))}`",
        f"- Human feedback events: `{len(state.get('human_feedback', []))}`",
        f"- Render failures: `{len(state.get('render_failures', []))}`", "",
        f"## {input_heading}", "", input_text, "",
        "## Compiled render-graph contract", "", "```json",
        json.dumps(brief, ensure_ascii=False, indent=2), "```", "",
    ]
    for index, package in enumerate(packages, 1):
        spec = brief["passes"][index - 1]
        lines += [f"## Pass {index}: {spec['name']}", "", f"- Goal: {spec['pass_goal']}", f"- Inputs: `{json.dumps(spec['inputs'], ensure_ascii=False)}`", f"- Scale: `{spec['scale']}`", ""]
        if package["vertex"]:
            lines += ["### Vertex", "", "```glsl", package["vertex"], "```", ""]
        lines += ["### Fragment", "", "```glsl", package["fragment"], "```", ""]
    lines += ["## Per-pass agent history", "", "```json", json.dumps(state["pass_agents"], ensure_ascii=False, indent=2), "```", "", "## Final agent history", "", "```json", json.dumps(state["final_agent"], ensure_ascii=False, indent=2), "```", ""]
    if state.get("human_feedback"):
        lines += ["## Human feedback", "", "```json", json.dumps(state["human_feedback"], ensure_ascii=False, indent=2), "```", ""]
    if state.get("repair_transactions"):
        lines += ["## Repair transactions", "", "```json", json.dumps(state["repair_transactions"], ensure_ascii=False, indent=2), "```", ""]
    if state.get("accepted_facts"):
        lines += ["## Compact accepted facts", "", "```json", json.dumps(state["accepted_facts"], ensure_ascii=False, indent=2), "```", ""]
    lines += ["## Successful full-video history", "", "```json", json.dumps(state.get("round_videos", []), ensure_ascii=False, indent=2), "```", ""]
    if state.get("render_failures"):
        lines += ["## Render failures and rollbacks", "", "```json", json.dumps(state["render_failures"], ensure_ascii=False, indent=2), "```", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Human pass design followed by agentic per-pass shader implementation")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--work-dir", type=Path, default=Path("runs/multi_pass/human_agent_runs"))
    parser.add_argument("--studio-root", type=Path, default=Path("muti_pass/multipass-studio"))
    parser.add_argument("--studio-url", default="http://localhost:3001")
    parser.add_argument("--agent-model", default=os.environ.get("EFFECT_IR_CODE_LLM_MODEL") or os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--frame-count", type=int, default=16)
    parser.add_argument("--dense-timeline", action="store_true", help="Infer no pass prior; first describe every sampled time interval, then let the Agent plan from that description")
    parser.add_argument("--timeline-interval", type=float, default=0.2, help="Seconds between dense timeline samples")
    parser.add_argument("--timeline-max-frames", type=int, default=60, help="Safety limit for dense timeline samples")
    parser.add_argument("--pass-count", type=int, default=0, help="Optional human pass-count constraint; 0 lets the model infer it")
    parser.add_argument("--effect-description", default="", help="Optional human description of the visible effect; omitted information is inferred")
    parser.add_argument("--plan-attempts", type=int, default=3, help="Stage-two attempts to compile free-form human intent into a render graph")
    parser.add_argument("--code-attempts", type=int, default=3)
    parser.add_argument("--contract-revisions", type=int, default=1, help="Maximum local sanity-driven rewrites for an obviously black or unexpectedly static initial pass")
    parser.add_argument("--final-revisions", type=int, default=2)
    parser.add_argument("--transaction-attempts", type=int, default=2, help="Maximum implement/verify attempts before a repair is rolled back")
    parser.add_argument("--human-transaction-attempts", type=int, default=1, help="Maximum implement/verify attempts for each interactive human feedback round")
    parser.add_argument("--wait-for-feedback", action="store_true", help="After every complete result, wait for website feedback until the human accepts")
    parser.add_argument("--feedback-timeout", type=int, default=1800, help="Seconds to wait for website feedback")
    parser.add_argument("--max-feedback-rounds", type=int, default=0, help="Maximum human-requested revisions; 0 continues until the human accepts the result")
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--job-id", default="")
    parser.add_argument("--resume", action="store_true", help="Resume this job from its last durable pass checkpoint")
    plan_group = parser.add_mutually_exclusive_group()
    plan_group.add_argument("--pass-plan", type=Path, help="Optional human-authored .txt/.md responsibilities or complete JSON contract")
    plan_group.add_argument("--pass-description", help="Optional per-pass responsibilities written inline")
    args = parser.parse_args()

    if min(args.frame_count, args.plan_attempts, args.code_attempts, args.transaction_attempts, args.human_transaction_attempts) < 1 or args.final_revisions < 0 or args.contract_revisions < 0:
        raise ValueError("Frame/attempt counts must be positive and revision counts non-negative")
    has_pass_responsibilities = bool(args.pass_plan or str(args.pass_description or "").strip())
    effect_description = str(args.effect_description or "").strip()
    if args.pass_count < 0:
        raise ValueError("--pass-count must be zero (infer) or a positive integer")
    if args.timeline_interval <= 0 or args.timeline_max_frames < 2:
        raise ValueError("Dense timeline interval must be positive and maximum frames must be at least two")
    if args.dense_timeline and (has_pass_responsibilities or args.pass_count or effect_description):
        raise ValueError("--dense-timeline is an ablation mode and cannot receive pass count, pass responsibilities, or effect description")
    if args.feedback_timeout < 1:
        raise ValueError("--feedback-timeout must be positive")
    if args.max_feedback_rounds < 0:
        raise ValueError("--max-feedback-rounds must be non-negative")
    repo = args.repo_root.resolve()
    video = resolve_repo_path(repo, str(args.video_path))
    image = resolve_repo_path(repo, str(args.input_image))
    studio = resolve_repo_path(repo, str(args.studio_root))
    out = resolve_repo_path(repo, str(args.work_dir))
    out.mkdir(parents=True, exist_ok=True)
    if not video.exists() or not image.exists() or not (studio / "public").is_dir():
        raise FileNotFoundError("Target video, input image, or studio is missing")
    job_id = "".join(character if character.isalnum() or character in "_-" else "_" for character in (args.job_id or f"human_agent_{video.stem}_{uuid.uuid4().hex[:8]}")).strip("_")
    state_path = out / f"{job_id}_agent_state.json"
    existing_state = json.loads(state_path.read_text(encoding="utf-8")) if args.resume and state_path.is_file() else None
    if args.resume and existing_state is None:
        raise FileNotFoundError(f"No resumable state exists for job {job_id}")

    # Each of the three planning inputs is an independent optional constraint.
    # The planner owns every field that the human leaves unspecified.
    if args.pass_plan:
        plan_path = resolve_repo_path(repo, str(args.pass_plan))
        if not plan_path.is_file():
            raise FileNotFoundError(f"Human pass plan is missing: {plan_path}")
        human_plan = plan_path.read_text(encoding="utf-8")
        human_plan_source = str(plan_path)
    elif args.pass_description:
        human_plan = str(args.pass_description)
        human_plan_source = "inline CLI input"
    else:
        human_plan = ""
        human_plan_source = "model inferred from the supplied optional constraints and visual evidence"

    # Stage two starts with a protected visual-only observation. This call never
    # receives auxiliary prose, preventing wording from anchoring video understanding.
    raw_visual, indices = _visual_evidence(image, video, image_size=256, frame_count=args.frame_count, work_dir=out)
    visual = [
        {"type": "text", "text": "SOURCE_IMAGE (clean original):"},
        raw_visual[0],
        {"type": "text", "text": "TARGET_VIDEO_SAMPLES (chronological, left-to-right and top-to-bottom):"},
        raw_visual[1],
    ]
    dense_timeline_samples: list[dict[str, float | int]] = []
    dense_interval_observation: dict[str, Any] | None = None
    if existing_state is not None:
        brief_from_state = existing_state.get("compiled_pass_graph") or {}
        visual_observation = brief_from_state.get("visual_only_observation") or {}
        dense_timeline_samples = (existing_state.get("dense_timeline") or {}).get("samples", [])
        raw_observation_value = (existing_state.get("dense_timeline") or {}).get("interval_observation")
        raw_observation_path = Path(str(raw_observation_value)) if raw_observation_value else None
        if raw_observation_path is not None and raw_observation_path.is_file():
            dense_interval_observation = json.loads(raw_observation_path.read_text(encoding="utf-8"))
    elif args.dense_timeline:
        dense_interval_observation, dense_timeline_samples = _observe_dense_timeline(
            source_part=raw_visual[0],
            video=video,
            interval_seconds=args.timeline_interval,
            maximum_frames=args.timeline_max_frames,
            model=args.agent_model,
            temperature=args.temperature,
            work_dir=out,
            job_id=job_id,
        )
        dense_interval_path = out / f"{job_id}_dense_interval_observation.json"
        dense_interval_path.write_text(
            json.dumps(dense_interval_observation, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        visual_observation = _synthesize_dense_timeline(
            observation=dense_interval_observation,
            model=args.agent_model,
            temperature=args.temperature,
            work_dir=out,
            job_id=job_id,
        )
    else:
        visual_observation = _observe_visual_evidence(
            visual=visual,
            model=args.agent_model,
            temperature=args.temperature,
            work_dir=out,
            job_id=job_id,
        )
    visual_observation_path = out / f"{job_id}_visual_only_observation.json"
    visual_observation_path.write_text(
        json.dumps(visual_observation, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    compiler_responses: list[str] = []
    brief = validate_expert_brief(existing_state["compiled_pass_graph"]) if existing_state is not None else parse_complete_contract(human_plan) if human_plan else None
    if brief is not None:
        if args.pass_count and brief["pass_count"] != args.pass_count:
            raise ValueError(f"The complete JSON contract contains {brief['pass_count']} passes, but --pass-count is {args.pass_count}")
    else:
        brief, compiler_responses = _auto_plan_passes(
            visual=visual,
            visual_observation=visual_observation,
            effect_description=effect_description,
            pass_count_constraint=args.pass_count,
            pass_responsibilities=human_plan,
            model=args.agent_model,
            attempts=args.plan_attempts,
            temperature=args.temperature,
            work_dir=out,
            job_id=job_id,
        )
    brief["visual_only_observation"] = visual_observation
    supplied_responsibilities = human_plan
    human_constraints = {
        key: value for key, value in {
            "pass_count": args.pass_count or None,
            "pass_responsibilities": supplied_responsibilities.strip() or None,
        }.items() if value is not None
    }
    if human_constraints:
        brief["human_constraints"] = human_constraints
    (out / f"{job_id}_human_pass_input.txt").write_text(supplied_responsibilities.rstrip() + "\n", encoding="utf-8")
    effect_description_path: Path | None = None
    if effect_description:
        effect_description_path = out / f"{job_id}_effect_description.txt"
        effect_description_path.write_text(effect_description + "\n", encoding="utf-8")
    (out / f"{job_id}_compiled_pass_graph.json").write_text(json.dumps(brief, ensure_ascii=False, indent=2), encoding="utf-8")
    execution_reference = _compact_working_memory(brief)

    new_state: dict[str, Any] = {
        "workflow": "dense_timeline_to_agent_multipass" if args.dense_timeline else "pass_plan_to_agent_multipass",
        "planning_mode": "dense_timeline" if args.dense_timeline else "constrained" if (has_pass_responsibilities or args.pass_count or effect_description) else "model",
        "agent_mode": "continuous_human_feedback" if args.wait_for_feedback else "automatic_final_review",
        "agent_policy": {
            "evidence": "target video samples dominate; optional effect wording is checked once and then removed from execution context",
            "observe": ("each pass receives a local output-contract sanity probe; human reviews every complete video" if args.wait_for_feedback else "each pass receives a local output-contract sanity probe; model reviews only complete videos"),
            "plan": "turn one visible mismatch into a scoped, observable repair contract",
            "act": "apply parameter, single-pass, multi-pass, or graph repair inside a transaction",
            "verify": "compare accepted BEFORE with proposed AFTER; commit only fulfilled repairs and otherwise retry or roll back",
            "stop": "human accepts current result" if args.wait_for_feedback else "model reports done or revision limit is reached",
        },
        "job_id": job_id,
        "phase": "pass_implementation",
        "target_frame_indices": indices,
        "dense_timeline": {
            "enabled": args.dense_timeline,
            "interval_seconds": args.timeline_interval if args.dense_timeline else None,
            "samples": dense_timeline_samples,
            "interval_observation": str(out / f"{job_id}_dense_interval_observation.json") if args.dense_timeline else None,
            "process_synthesis": str(visual_observation_path) if args.dense_timeline else None,
            "description": str(visual_observation_path) if args.dense_timeline else None,
            "policy": "first observe every visible interval without implementation priors; then synthesize a detailed continuous process from those notes; only then plan the render graph",
        },
        "stage_two_inputs": {
            "source_image": str(image),
            "target_video": str(video),
            "target_frame_indices": indices,
            "visual_only_observation": str(visual_observation_path),
            "pass_implementation_reference": str(out / f"{job_id}_human_pass_input.txt"),
            "effect_description": str(effect_description_path) if effect_description_path else None,
        },
        "stage_two_objective": "Render source_image through the referenced fixed pass structure so its visible appearance and motion match target_video as closely as possible.",
        "human_pass_input": supplied_responsibilities or None,
        "human_pass_input_source": human_plan_source,
        "effect_description": effect_description or None,
        "effect_description_policy": "auxiliary hypothesis used only during graph planning; target frames override it and raw wording is excluded from pass execution memory",
        "human_declared_pass_count": args.pass_count or None,
        "resolved_pass_count": brief["pass_count"],
        "compiled_pass_graph": brief,
        "plan_compiler_responses": compiler_responses,
        "pass_agents": [],
        "final_agent": [],
        "human_feedback": [],
        "round_videos": [],
        "render_failures": [],
        "accepted_facts": [],
        "repair_transactions": [],
        "contract_checks": [],
        "preview_candidates": [],
    }
    state = existing_state or new_state
    state["phase"] = "pass_implementation"
    state["compiled_pass_graph"] = brief
    state.setdefault("accepted_facts", [])
    state.setdefault("pass_agents", [])
    state.setdefault("round_videos", [])
    state.setdefault("final_agent", [])
    state.setdefault("human_feedback", [])
    state.setdefault("render_failures", [])
    state.setdefault("repair_transactions", [])
    state.setdefault("contract_checks", [])
    state.setdefault("preview_candidates", [])
    if existing_state:
        state["last_resumed_at"] = time.time()
        _write_state(state_path, state)
    else:
        _write_state(state_path, state, "planning_complete")
    job_dir = studio / "public" / "generated" / job_id
    packages = _load_shader_packages(job_dir, len(brief["passes"])) if existing_state else []
    completed_passes = len(state["pass_agents"])
    accepted_prefixes = [
        Path(str(item["accepted_prefix"])) for item in state["pass_agents"][:completed_passes]
        if item.get("accepted_prefix") and Path(str(item["accepted_prefix"])).is_file()
    ]
    if len(accepted_prefixes) != completed_passes:
        raise RuntimeError("Resume checkpoint is incomplete: an accepted upstream prefix is missing")

    for index in range(completed_passes + 1, len(brief["passes"]) + 1):
        resource_sheets = _resource_sheets_for_pass(brief, index, accepted_prefixes)
        if len(packages) < index:
            package = _generate_pass(brief=brief, index=index, visual=visual, resource_sheets=resource_sheets, model=args.agent_model, temperature=args.temperature, code_attempts=args.code_attempts, work_dir=out, label=f"{job_id}_pass_{index:02d}_initial", human_plan=execution_reference)
            packages.append(package)
            _write_graph(job_dir, job_id, image, brief, packages)
            _write_state(state_path, state, f"pass_{index:02d}_generated")
        elif len(packages) > index:
            packages = packages[:index]
        history = {"pass": index, "name": brief["passes"][index - 1]["name"], "mode": "generation_with_local_contract_probe"}
        checkpoint = state.get("checkpoint", {}) if existing_state else {}
        resumed_render = checkpoint.get("stage") == f"pass_{index:02d}_rendered"
        resumed_sheet_value = checkpoint.get("prefix_sheet") if resumed_render else None
        resumed_sheet = Path(str(resumed_sheet_value)) if resumed_sheet_value else out / f"{job_id}_pass_{index:02d}.jpg"
        graph = _write_graph(job_dir, job_id, image, brief, packages)
        if resumed_render and resumed_sheet.is_file():
            accepted_sheet = resumed_sheet
        else:
            prefix = _studio_task(repo, studio, args.studio_url, graph, job_id, out, len(packages))
            accepted_sheet = out / f"{job_id}_pass_{index:02d}.jpg"
            shutil.copy2(prefix, accepted_sheet)
            _write_state(
                state_path, state, f"pass_{index:02d}_rendered",
                pass_index=index, prefix_sheet=str(accepted_sheet),
            )
        contract_check = _inspect_contract_sheet(accepted_sheet, brief["passes"][index - 1])
        for revision in range(1, args.contract_revisions + 1):
            if contract_check["usable"]:
                break
            package = _generate_pass(
                brief=brief, index=index, visual=visual, resource_sheets=resource_sheets,
                model=args.agent_model, temperature=args.temperature, code_attempts=args.code_attempts,
                work_dir=out, label=f"{job_id}_pass_{index:02d}_contract_revision_{revision:02d}",
                current=packages[index - 1],
                instruction=(
                    "The local output-contract probe found an obvious implementation problem: "
                    + "; ".join(contract_check["warnings"])
                    + ". Repair that problem while preserving the assigned pass responsibility and output semantics."
                ),
                human_plan=execution_reference,
            )
            packages[index - 1] = package
            graph = _write_graph(job_dir, job_id, image, brief, packages)
            prefix = _studio_task(repo, studio, args.studio_url, graph, job_id, out, len(packages))
            shutil.copy2(prefix, accepted_sheet)
            contract_check = _inspect_contract_sheet(accepted_sheet, brief["passes"][index - 1])
        contract_event = {"pass": index, "output": brief["passes"][index - 1]["output"], **contract_check}
        state["contract_checks"].append(contract_event)
        history["contract_check"] = contract_event
        accepted_prefixes.append(accepted_sheet)
        history["accepted_prefix"] = str(accepted_sheet)
        history["rendered"] = True
        state["pass_agents"].append(history)
        _write_state(state_path, state, f"pass_{index:02d}_complete")

    state["phase"] = "final_refinement"
    graph = _write_graph(job_dir, job_id, image, brief, packages)
    previous_video = Path(str(state["round_videos"][-1]["video"])) if state["round_videos"] else None
    if previous_video is not None and previous_video.is_file():
        final = previous_video
    else:
        final = _studio_task(repo, studio, args.studio_url, graph, job_id, out, reveal_after_render=True)
        final = _archive_round_video(final, out, job_id, len(state["round_videos"]))
        state["round_videos"].append({"round": len(state["round_videos"]), "video": str(final)})
        _write_state(state_path, state, "complete_video_rendered", video=str(final))

    # Human-in-the-loop mode hands every accepted complete video to the human.
    # Unattended repairs use the same implement/verify/commit transaction.
    for round_number in range(0 if args.wait_for_feedback else args.final_revisions + 1):
        prefix_sheets = _render_prefixes(repo, studio, args.studio_url, graph, job_id, out, max(0, len(packages) - 1), f"{job_id}_final_{round_number:02d}")
        decision = _observe_final(brief=brief, candidate_video=Path(state["round_videos"][-1]["video"]), prefix_sheets=prefix_sheets, visual=visual, model=args.agent_model, temperature=args.temperature, work_dir=out, accepted_facts=state["accepted_facts"])
        event = {"round": round_number, "video": str(final), "prefix_sheets": [str(path) for path in prefix_sheets], "decision": decision}
        state["final_agent"].append(event)
        (out / f"{job_id}_final_agent_{round_number:02d}.json").write_text(json.dumps(event, ensure_ascii=False, indent=2), encoding="utf-8")
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
        if decision["decision"] == "done" or round_number == args.final_revisions:
            break
        state["phase"] = "applying_repair_transaction"
        state["current_obligation"] = decision
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
        before_video = Path(state["round_videos"][-1]["video"])
        brief, packages, candidate, graph, transaction = _execute_repair_transaction(
            repair=decision, brief=brief, packages=packages, target_video=video, before_video=before_video, input_image=image,
            repo=repo, studio=studio, studio_url=args.studio_url, job_dir=job_dir, job_id=job_id, out=out,
            visual=visual, model=args.agent_model, temperature=args.temperature, code_attempts=args.code_attempts,
            transaction_attempts=args.transaction_attempts, label=f"{job_id}_final_transaction_{round_number + 1:02d}",
            accepted_facts=state["accepted_facts"],
        )
        state["repair_transactions"].append(transaction)
        state.pop("current_obligation", None)
        if not transaction["committed"]:
            final = before_video
            state["phase"] = "final_refinement"
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            break
        final = candidate
        state["compiled_pass_graph"] = brief
        state["accepted_facts"].extend(transaction.get("accepted_facts", []))
        state["accepted_facts"] = state["accepted_facts"][-8:]
        final = _archive_round_video(final, out, job_id, round_number + 1)
        state["round_videos"].append({"round": round_number + 1, "source": "automatic_transaction", "video": str(final)})
        state["phase"] = "final_refinement"
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")

    if args.wait_for_feedback:
        feedback_round = len(state["human_feedback"])
        while args.max_feedback_rounds == 0 or feedback_round < args.max_feedback_rounds:
            state["phase"] = "waiting_for_human_feedback"
            state["feedback_round"] = feedback_round
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            feedback_job = f"{job_id}_feedback_{feedback_round:02d}"
            feedback_path = out / f"{feedback_job}_web_feedback.json"
            feedback_path.unlink(missing_ok=True)
            print(f"Waiting for website feedback round {feedback_round}: {feedback_path}", flush=True)
            feedback_input = _wait_for_web_feedback_event(feedback_path, args.feedback_timeout)

            if feedback_input["action"] == "finish":
                adopted_preview: dict[str, Any] | None = None
                if state["preview_candidates"]:
                    preview = state["preview_candidates"][-1]
                    preview_brief_path = Path(str(preview.get("brief", "")))
                    preview_graph_dir = Path(str(preview.get("graph", ""))).parent
                    preview_video = Path(str(preview.get("video", "")))
                    if preview_brief_path.is_file() and preview_video.is_file():
                        preview_brief = validate_expert_brief(json.loads(preview_brief_path.read_text(encoding="utf-8")))
                        preview_packages = _load_shader_packages(preview_graph_dir, len(preview_brief["passes"]))
                        if len(preview_packages) == len(preview_brief["passes"]):
                            brief, packages = preview_brief, preview_packages
                            graph = _write_graph(job_dir, job_id, image, brief, packages)
                            next_round = max((int(item["round"]) for item in state["round_videos"]), default=-1) + 1
                            final = _archive_round_video(preview_video, out, job_id, next_round)
                            adopted_preview = {
                                "round": next_round, "source": "human_accepted_preview",
                                "feedback_round": feedback_round, "video": str(final),
                                "verifier_accepted": False, "human_accepted": True,
                            }
                            state["round_videos"].append(adopted_preview)
                            state["compiled_pass_graph"] = brief
                            state["preview_candidates"] = []
                finish_event = {
                    "round": feedback_round,
                    "action": "finish",
                    "feedback": feedback_input["feedback"],
                    "accepted_video": state["round_videos"][-1]["video"],
                    "human_accepted_preview": adopted_preview is not None,
                }
                state["human_feedback"].append(finish_event)
                (out / f"{job_id}_human_feedback_{feedback_round:02d}.json").write_text(
                    json.dumps(finish_event, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                break

            feedback = feedback_input["feedback"]
            state["phase"] = "applying_human_feedback"
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            reviewed_video = Path(
                state["preview_candidates"][-1]["video"]
                if state["preview_candidates"] else state["round_videos"][-1]["video"]
            )
            prefix_sheets = _render_prefixes(
                repo,
                studio,
                args.studio_url,
                graph,
                job_id,
                out,
                max(0, len(packages) - 1),
                f"{job_id}_human_feedback_{feedback_round:02d}",
            )
            interpreted = _interpret_human_feedback(
                feedback=feedback,
                brief=brief,
                candidate_video=reviewed_video,
                prefix_sheets=prefix_sheets,
                visual=visual,
                model=args.agent_model,
                temperature=args.temperature,
                work_dir=out,
            )
            feedback_event: dict[str, Any] = {
                "round": feedback_round,
                "action": "revise",
                "feedback": feedback,
                "pre_feedback_video": str(reviewed_video),
                "accepted_baseline_video": state["round_videos"][-1]["video"],
                "prefix_sheets": [str(path) for path in prefix_sheets],
                "interpreted_change": interpreted,
                "applied": False,
            }
            state["current_obligation"] = interpreted
            state["phase"] = "applying_repair_transaction"
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            before_video = Path(state["round_videos"][-1]["video"])
            brief, packages, candidate, graph, transaction = _execute_repair_transaction(
                repair=interpreted, brief=brief, packages=packages, target_video=video, before_video=before_video, input_image=image,
                repo=repo, studio=studio, studio_url=args.studio_url, job_dir=job_dir, job_id=job_id, out=out,
                visual=visual, model=args.agent_model, temperature=args.temperature, code_attempts=args.code_attempts,
                transaction_attempts=args.human_transaction_attempts, label=f"{job_id}_human_transaction_{feedback_round:02d}",
                accepted_facts=state["accepted_facts"], stage_unfulfilled=True,
            )
            state["repair_transactions"].append(transaction)
            state.pop("current_obligation", None)
            feedback_event["transaction"] = transaction
            if transaction["committed"]:
                final = candidate
                state["compiled_pass_graph"] = brief
                next_round = max((int(item["round"]) for item in state["round_videos"]), default=-1) + 1
                archived = _archive_round_video(final, out, job_id, next_round)
                final = archived
                last_verification = transaction["attempts"][-1].get("verification", {})
                state["round_videos"].append({
                    "round": next_round,
                    "source": "human_feedback",
                    "feedback_round": feedback_round,
                    "video": str(archived),
                    "verifier_accepted": True,
                    "verification_outcome": last_verification.get("outcome"),
                })
                feedback_event["applied"] = True
                feedback_event["post_feedback_video"] = str(archived)
                feedback_event["verifier_accepted"] = True
                state["accepted_facts"].extend(transaction.get("accepted_facts", []))
                state["accepted_facts"] = state["accepted_facts"][-8:]
                state["preview_candidates"] = []
            elif transaction.get("staged_for_human_review"):
                final = before_video
                preview_event = {
                    "feedback_round": feedback_round,
                    "video": transaction["staged_video"],
                    "status": "preview_only",
                    "verification_outcome": transaction["attempts"][-1].get("verification", {}).get("outcome"),
                    "accepted_baseline_video": str(before_video),
                    "graph": transaction["staged_graph"],
                    "brief": transaction["staged_brief"],
                }
                state["preview_candidates"].append(preview_event)
                feedback_event["previewed"] = True
                feedback_event["post_feedback_video"] = transaction["staged_video"]
                feedback_event["verifier_accepted"] = False
            else:
                final = before_video
                feedback_event["rollback"] = transaction.get("rollback_reason")
            state["human_feedback"].append(feedback_event)
            (out / f"{job_id}_human_feedback_{feedback_round:02d}.json").write_text(
                json.dumps(feedback_event, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            feedback_round += 1

    state["phase"] = "complete"
    state["website_graph"] = str(graph)
    state["rendered_video"] = str(final)
    report = out / f"{job_id}_report.md"
    _write_report(report, state, packages)
    state["report"] = str(report)
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    result_path = out / f"{job_id}_result.json"
    result_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"result": str(result_path), "rendered_video": str(final), "report": str(report)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
