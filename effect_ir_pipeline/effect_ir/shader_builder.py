from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any, Callable


LLMCall = Callable[[str, str, float, int, float], str]
GEOMETRY_PRIMITIVES = {
    "translate", "scale_x", "scale_y", "rotate", "flip_x", "flip_y",
    "crop_or_pad", "perspective_skew", "radial_swirl", "wave_warp",
}
APPEARANCE_PRIMITIVES = {"brightness", "exposure", "contrast", "saturation", "rgb_shift", "color_remap", "blur", "sharpen", "vignette"}
COMPOSITING_MODES = {"replace_source", "preserve_source", "local_overlay"}
INITIAL_CANVAS_MODES = {"black", "source", "transformed_effect"}
OUTSIDE_FILL_MODES = {"black", "source", "clamp_to_edge"}
TEMPORAL_MODES = {"continuous_monotonic", "cyclic", "impulse", "freeform"}
CONTINUOUS_CURVES = {"linear", "ease_in", "ease_out", "ease_in_out", "early_progressive"}
PROGRAMMATIC_PRIMITIVES = {
    "identity", "translate", "scale_x", "scale_y", "flip_x", "flip_y", "wave_warp",
    "brightness", "exposure", "contrast", "saturation", "rgb_shift", "color_remap",
    "blur", "vignette", "pixelation",
}


VERTEX_SHADER = """```glsl
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
```"""


@dataclass
class ShaderBuildResult:
    shader_text: str
    backend: str
    normalized_edit_plan: dict[str, Any]
    builder_notes: list[str]
    draft_shader_text: str | None = None
    code_model: str | None = None

    def to_jsonable(self) -> dict[str, Any]:
        return {
            "backend": self.backend,
            "normalized_edit_plan": self.normalized_edit_plan,
            "builder_notes": self.builder_notes,
            "draft_shader_text": self.draft_shader_text,
            "code_model": self.code_model,
        }


def extract_feedback_edit_plan(llm_visual_feedback: dict[str, Any] | None) -> dict[str, Any] | None:
    parsed = llm_visual_feedback.get("parsed") if isinstance(llm_visual_feedback, dict) else None
    if not isinstance(parsed, dict):
        return None
    plan = parsed.get("primitive_edit_plan")
    if not isinstance(plan, dict):
        return None
    return plan


def merge_edit_plan_delta(previous: dict[str, Any] | None, delta: dict[str, Any] | None) -> dict[str, Any]:
    """Merge a reviewer delta with the last executable plan state.

    Reviewers naturally mention only operations that need changing. Carry
    forward unchanged primitives, while explicit rejections/removals remain
    authoritative.
    """
    if not isinstance(previous, dict):
        return dict(delta or {})
    if not isinstance(delta, dict):
        return dict(previous)
    rejected = delta.get("rejected_primitives", [])
    rejected_names = {_primitive_name(item) for item in rejected if _primitive_name(item)} if isinstance(rejected, list) else set()
    previous_selected = previous.get("selected_primitives", [])
    delta_selected = delta.get("selected_primitives", [])
    merged_by_name: dict[str, dict[str, Any]] = {}
    for item in previous_selected if isinstance(previous_selected, list) else []:
        if isinstance(item, dict):
            name = _canonical_primitive_name(str(item.get("name", "")).strip().lower())
            if name and name not in rejected_names:
                merged_by_name[name] = dict(item)
    for item in delta_selected if isinstance(delta_selected, list) else []:
        if isinstance(item, dict):
            name = _canonical_primitive_name(str(item.get("name", "")).strip().lower())
            if name and name not in rejected_names:
                merged_by_name[name] = dict(item)
    merged = {**previous, **delta}
    merged["selected_primitives"] = list(merged_by_name.values())
    merged["rejected_primitives"] = rejected
    merged.pop("implementation_notes", None)
    merged.pop("process_stages", None)
    merged.pop("handoff_constraints", None)
    merged["source"] = "merged_previous_state_plus_review_delta"
    return merged


def _normalize_temporal_controller(
    value: Any,
    *,
    target_ir: dict[str, Any],
) -> dict[str, Any]:
    raw = value if isinstance(value, dict) else {}
    mode = str(raw.get("mode", "")).strip().lower()
    if mode not in TEMPORAL_MODES:
        temporal_pattern = str(target_ir.get("temporal_pattern", "")).strip().lower()
        mode = "cyclic" if temporal_pattern in {"periodic", "cyclic"} else "impulse" if temporal_pattern in {"impulse", "flicker"} else "continuous_monotonic" if temporal_pattern in {"", "progressive", "linear", "monotonic"} else "freeform"
    curve = str(raw.get("shared_progress_curve", raw.get("curve", "ease_in_out"))).strip().lower()
    if curve not in CONTINUOUS_CURVES:
        curve = "ease_in_out"
    return {
        "mode": mode,
        "curve": curve,
    }


def build_initial_edit_plan_from_ir(target_ir: dict[str, Any]) -> dict[str, Any]:
    selected: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    text = _flatten_text(target_ir)
    geometry_ops = {str(item).lower() for item in target_ir.get("geometry_ops", []) or []}
    appearance_ops = {str(item).lower() for item in target_ir.get("appearance_ops", []) or []}
    transform_primitives = {str(item).lower() for item in target_ir.get("transform_primitives", []) or []}
    temporal = _infer_temporal_from_text(text)

    if "pixelation_mosaic" in appearance_ops or _has_any(text, ["pixel", "mosaic", "马赛克", "像素", "grid"]):
        selected.append(_primitive("pixelation", "primary", "none", "medium", temporal, "target_ir indicates pixel/block/mosaic appearance"))

    if _has_any(text, ["horizontal", "x-axis", "x axis", "水平"]) and _has_any(text, ["jitter", "flicker", "抖动", "glitch"]):
        selected.append(_primitive("translate", "secondary", "x", "medium", temporal, "target_ir indicates horizontal jitter/displacement"))
    elif "translate_x" in transform_primitives or ("displacement" in geometry_ops and _has_any(text, ["horizontal", "x-axis", "水平"])):
        selected.append(_primitive("translate", "primary", "x", "medium", temporal, "target_ir indicates horizontal displacement"))
    elif "translate_y" in transform_primitives or ("displacement" in geometry_ops and _has_any(text, ["vertical", "y-axis", "垂直"])):
        selected.append(_primitive("translate", "primary", "y", "medium", temporal, "target_ir indicates vertical displacement"))

    if "flip_x" in transform_primitives or _has_any(text, ["horizontal_flip", "flip_x", "mirror horizontal", "水平翻转"]):
        selected.append(_primitive("flip_x", "primary", "x", "strong", temporal, "target_ir indicates horizontal flip"))
    if "flip_y" in transform_primitives or _has_any(text, ["vertical_flip", "flip_y", "垂直翻转"]):
        selected.append(_primitive("flip_y", "primary", "y", "strong", temporal, "target_ir indicates vertical flip"))
    if "scale_x" in transform_primitives or _has_any(text, ["stretch_x", "scale_x", "horizontal stretch", "水平拉伸"]):
        selected.append(_primitive("scale_x", "secondary", "x", "medium", temporal, "target_ir indicates horizontal stretch"))
    if "scale_y" in transform_primitives or _has_any(text, ["stretch_y", "scale_y", "vertical stretch", "垂直拉伸"]):
        selected.append(_primitive("scale_y", "secondary", "y", "medium", temporal, "target_ir indicates vertical stretch"))

    if "blur" in appearance_ops or _has_any(text, ["smear", "motion blur", "blur", "拖影", "模糊", "拉丝"]):
        axis = "x" if _has_any(text, ["horizontal", "x-axis", "水平"]) else "y" if _has_any(text, ["vertical", "y-axis", "垂直"]) else "none"
        selected.append(_primitive("blur", "secondary", axis, "medium", temporal, "target_ir indicates blur/smear"))
    if "rgb_shift" in appearance_ops or _has_any(text, ["rgb", "chromatic", "色差"]):
        selected.append(_primitive("rgb_shift", "secondary", "x", "weak", temporal, "target_ir indicates RGB/chromatic shift"))
    if "brightness" in appearance_ops:
        selected.append(_primitive("brightness", "secondary", "none", "weak", temporal, "target_ir indicates brightness change"))
    if "contrast" in appearance_ops:
        selected.append(_primitive("contrast", "secondary", "none", "weak", temporal, "target_ir indicates contrast change"))

    if not selected:
        selected.append(_primitive("identity", "primary", "none", "weak", "linear", "no confident primitive found; start conservatively"))
        rejected.append({"name": "wave_warp", "reason": "not selected unless direct evidence exists"})

    return {
        "selected_primitives": selected[:4],
        "rejected_primitives": rejected,
        "compositing_mode": _infer_compositing_mode(selected, target_ir=target_ir),
        "background_policy": _infer_background_policy(target_ir=target_ir),
        "source": "initial_target_ir",
    }


def _infer_compositing_mode(primitives: list[dict[str, Any]], *, target_ir: dict[str, Any]) -> str:
    """Choose a safe default without silently retaining the unwarped source."""
    names = {str(item.get("name", "")) for item in primitives if isinstance(item, dict)}
    text = _flatten_text(target_ir).lower()
    if _has_any(text, ["local overlay", "local mask", "sticker", "贴纸", "局部叠加", "局部蒙版", "局部效果"]):
        return "local_overlay"
    # Geometry and full-frame resampling effects must not be mixed back over an
    # unwarped source; that creates the persistent ghost/base-image artifact.
    if names & (GEOMETRY_PRIMITIVES | {"pixelation", "blur", "rgb_shift"}):
        return "replace_source"
    if _has_any(text, ["flip", "mirror", "stretch", "scale", "zoom", "warp", "pixel", "mosaic", "blur", "rgb", "翻转", "拉伸", "放大", "缩放", "形变", "马赛克", "模糊", "色差"]):
        return "replace_source"
    return "preserve_source"


def _infer_background_policy(*, target_ir: dict[str, Any], feedback: dict[str, Any] | None = None) -> dict[str, str]:
    render_contract = target_ir.get("render_contract") if isinstance(target_ir, dict) else None
    if isinstance(render_contract, dict):
        initial_canvas = str(render_contract.get("initial_canvas", "")).strip().lower()
        outside_fill = str(render_contract.get("outside_effect_region", "")).strip().lower()
        if initial_canvas in INITIAL_CANVAS_MODES or outside_fill in OUTSIDE_FILL_MODES:
            return {
                "initial_canvas": initial_canvas if initial_canvas in INITIAL_CANVAS_MODES else "transformed_effect",
                "outside_effect_region": outside_fill if outside_fill in OUTSIDE_FILL_MODES else "clamp_to_edge",
                "source_visibility": str(render_contract.get("source_visibility", "transformed_region_only" if outside_fill == "black" else "full_canvas")),
            }
    text = _flatten_text({"target_ir": target_ir, "feedback": feedback}).lower()
    black_start = _has_any(text, ["black start", "starts black", "initial black", "p=0 black", "黑场起步", "黑场开始", "起始为全黑", "p=0 完全黑", "p=0为黑场"])
    black_outside = _has_any(text, ["outside black", "black outside", "outside-fill black", "范围外为黑", "区域外为黑", "遮罩外输出黑", "画面块外", "平面外区域保持黑"])
    return {
        "initial_canvas": "black" if black_start else "transformed_effect",
        "outside_effect_region": "black" if black_outside or black_start else "clamp_to_edge",
        "source_visibility": "transformed_region_only" if black_outside or black_start else "full_canvas",
    }


def build_shader_from_edit_plan(
    *,
    edit_plan: dict[str, Any] | None,
    target_ir: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    llm_visual_feedback: dict[str, Any] | None,
    current_shader: str | None,
    selected_sources: str | None,
    selected_references: list[dict[str, Any]] | None,
    iteration: int,
    backend: str = "programmatic",
    code_model: str | None = None,
    temperature: float = 0.0,
    previous_failure: str | None = None,
    llm_call: LLMCall | None = None,
) -> ShaderBuildResult:
    normalized_plan = normalize_edit_plan(edit_plan or build_initial_edit_plan_from_ir(target_ir), target_ir=target_ir, llm_visual_feedback=llm_visual_feedback)
    draft = build_programmatic_shader(normalized_plan, target_ir=target_ir, candidate_ir=candidate_ir)
    notes = list(normalized_plan.get("_builder_notes", []))
    if backend == "programmatic":
        return ShaderBuildResult(shader_text=draft, backend=backend, normalized_edit_plan=normalized_plan, builder_notes=notes)
    if backend == "code_model":
        if llm_call is None:
            raise ValueError("backend='code_model' requires llm_call")
        model = code_model or os.environ.get("EFFECT_IR_CODE_LLM_MODEL") or os.environ.get("EFFECT_IR_LLM_MODEL", "")
        prompt = build_code_model_prompt(
            normalized_plan=normalized_plan,
            target_ir=target_ir,
            candidate_ir=candidate_ir,
            llm_visual_feedback=llm_visual_feedback,
            current_shader=current_shader,
            selected_sources=selected_sources,
            selected_references=selected_references,
            draft_shader=draft,
            iteration=iteration,
            previous_failure=previous_failure,
        )
        code_model_error = None
        try:
            shader_text = llm_call(
                prompt,
                model,
                temperature,
                int(os.environ.get("EFFECT_IR_CODE_LLM_MAX_TOKENS", "3600")),
                float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
            )
        except Exception as exc:
            code_model_error = str(exc)
            shader_text = draft
        return ShaderBuildResult(
            shader_text=shader_text,
            backend=backend if code_model_error is None else "programmatic_fallback_after_code_model_error",
            normalized_edit_plan=normalized_plan,
            builder_notes=notes + ([] if code_model_error is None else [f"code_model_error: {code_model_error}"]),
            draft_shader_text=draft,
            code_model=model,
        )
    raise ValueError(f"Unknown shader builder backend: {backend}")


def normalize_edit_plan(edit_plan: dict[str, Any], *, target_ir: dict[str, Any], llm_visual_feedback: dict[str, Any] | None) -> dict[str, Any]:
    selected = edit_plan.get("selected_primitives", []) if isinstance(edit_plan, dict) else []
    rejected = edit_plan.get("rejected_primitives", []) if isinstance(edit_plan, dict) else []
    notes = edit_plan.get("implementation_notes", []) if isinstance(edit_plan, dict) else []
    if not isinstance(selected, list):
        selected = []
    if not isinstance(rejected, list):
        rejected = []
    if not isinstance(notes, list):
        notes = [str(notes)]

    rejected_names = {_primitive_name(item) for item in rejected}
    # The planner sometimes expresses a removal as an implementation note
    # instead of filling rejected_primitives.  Interpret only explicit
    # imperative notes (never the full historical review) as hard rejection.
    note_rejections = {
        "pixelation": ["pixel", "mosaic", "马赛克", "像素", "grid", "网格", "floor("],
        "wave_warp": ["wave_warp", "wave", "正弦", "波浪"],
    }
    removal_words = ["remove", "delete", "do not use", "without", "avoid", "移除", "删除", "去除", "不要", "禁用"]
    for primitive, words in note_rejections.items():
        if any(_has_any(str(note).lower(), removal_words) and _has_any(str(note).lower(), words) for note in notes):
            rejected_names.add(primitive)
    normalized_selected: list[dict[str, Any]] = []
    builder_notes: list[str] = []
    for item in selected:
        if not isinstance(item, dict):
            continue
        name = _canonical_primitive_name(str(item.get("name", "")).strip().lower())
        if not name:
            continue
        params = item.get("params") if isinstance(item.get("params"), dict) else {}
        evidence = str(item.get("evidence", ""))
        # Distinguish spatial channel separation from a true channel/tone
        # remap. Visual reviewers sometimes call both "rgb_shift"; an axisless
        # RGB target vector or explicit remap evidence is a color operation.
        target_value = params.get("to")
        if name == "rgb_shift" and (
            (_normalize_axis(params.get("axis", item.get("axis", "none"))) == "none" and isinstance(target_value, list))
            or _has_any(evidence, ["remap", "re-map", "重映射", "换色", "综合色彩"])
        ):
            name = "color_remap"
            builder_notes.append("canonicalized axisless rgb_shift evidence to color_remap")
        if name in rejected_names:
            builder_notes.append(f"skip selected primitive also rejected: {name}")
            continue
        normalized_selected.append(
            {
                "name": name,
                "role": str(item.get("role", "secondary")),
                "axis": _normalize_axis(params.get("axis", item.get("axis", "none"))),
                "strength": _normalize_strength(params.get("strength", item.get("strength", "medium"))),
                "temporal": _normalize_temporal(item.get("temporal")),
                "confidence": _safe_float(item.get("confidence"), 0.5),
                "evidence": evidence,
                "params": params,
            }
        )

    # Enforce explicit and note-derived rejections after all selected entries
    # have been normalized, including aliases such as mosaic -> pixelation.
    before_rejection_filter = len(normalized_selected)
    normalized_selected = [item for item in normalized_selected if item["name"] not in rejected_names]
    if len(normalized_selected) != before_rejection_filter:
        builder_notes.append("removed selected primitive because it is explicitly rejected")

    # The structured plan is authoritative.  In particular, do not scan the
    # review prose for primitive names: phrases such as "remove pixel grid"
    # and historical rejected alternatives contain the same keywords as a
    # positive request and previously reintroduced unwanted effects.
    # Target-IR keyword inference is limited to build_initial_edit_plan_from_ir.

    if not normalized_selected:
        normalized_selected = build_initial_edit_plan_from_ir(target_ir)["selected_primitives"]
        builder_notes.append("fallback to target_ir-derived initial edit plan")

    normalized_rejected = []
    for item in rejected:
        if isinstance(item, dict):
            name = _canonical_primitive_name(str(item.get("name", "")).strip().lower()) or str(item.get("name", "")).strip().lower()
            normalized_rejected.append({"name": name, "reason": str(item.get("reason", ""))})
        else:
            normalized_rejected.append({"name": str(item), "reason": ""})
    normalized_rejected.extend({"name": name, "reason": "normalized rejection"} for name in sorted(rejected_names) if name)

    parsed_feedback = llm_visual_feedback.get("parsed") if isinstance(llm_visual_feedback, dict) else None
    raw_priority = parsed_feedback.get("optimization_priority") if isinstance(parsed_feedback, dict) else None
    raw_priority = raw_priority if isinstance(raw_priority, dict) else {}
    blocking = [str(item).strip().lower() for item in raw_priority.get("blocking_dimensions", [])]
    blocking = [item for item in blocking if item in {"geometry_motion", "temporal_process", "effect_region", "appearance"}]
    priority = {
        "blocking_dimensions": list(dict.fromkeys(blocking)),
        "primary_focus": str(raw_priority.get("primary_focus", "appearance")),
        "appearance_edits_allowed": bool(raw_priority.get("appearance_edits_allowed", not blocking)),
        "required_changes": [
            {"id": str(item.get("id", "")), "change": str(item.get("change", ""))}
            for item in raw_priority.get("required_changes", [])
            if isinstance(item, dict) and str(item.get("change", "")).strip()
        ][:4],
        "frozen_constraints": [
            str(item) for item in raw_priority.get("frozen_constraints", []) if str(item).strip()
        ][:8],
        "reason": str(raw_priority.get("reason", "")),
    }
    temporal_controller = _normalize_temporal_controller(
        edit_plan.get("temporal_controller") if isinstance(edit_plan, dict) else None,
        target_ir=target_ir,
    )
    if temporal_controller["mode"] == "continuous_monotonic":
        shared_curve = temporal_controller["curve"]
        for primitive in normalized_selected:
            params = primitive.get("params") if isinstance(primitive.get("params"), dict) else {}
            primitive["params"] = {
                key: value
                for key, value in params.items()
                if key not in {"weight_keyframes", "value_keyframes", "keyframes", "curve_points", "after"}
            }
            primitive["temporal"] = shared_curve
        builder_notes.append("continuous_monotonic temporal mode removed per-primitive keyframes")

    # Enforce the reviewer's perceptual priority in the actual executable
    # plan. If the central spatial process is missing, retain visual tweaks as
    # secondary only and inject target-IR geometry if the LLM forgot to add it.
    if "geometry_motion" in priority["blocking_dimensions"]:
        geometry_names = {p["name"] for p in normalized_selected if p["name"] in GEOMETRY_PRIMITIVES}
        if not geometry_names:
            fallback_geometry = [
                p for p in build_initial_edit_plan_from_ir(target_ir)["selected_primitives"]
                if p.get("name") in GEOMETRY_PRIMITIVES
            ]
            normalized_selected = fallback_geometry + normalized_selected
            if fallback_geometry:
                builder_notes.append("injected target-IR geometry primitives because geometry/motion is blocking")
        for primitive in normalized_selected:
            if primitive["name"] in APPEARANCE_PRIMITIVES:
                primitive["role"] = "secondary"
        notes.insert(0, "MANDATORY: implement the missing geometry/motion process before any colour, brightness, or texture tuning.")
        priority["appearance_edits_allowed"] = False
    if "effect_region" in priority["blocking_dimensions"]:
        notes.insert(0, "MANDATORY: make the effect act in the target's correct global/local region before appearance tuning.")
        priority["appearance_edits_allowed"] = False
    if "temporal_process" in priority["blocking_dimensions"]:
        if temporal_controller["mode"] == "continuous_monotonic":
            notes.insert(
                0,
                "MANDATORY: define one shared continuous progress q and drive all related primitives from q; "
                "do not create piecewise stages, per-primitive temporal envelopes, threshold restarts, or handoffs.",
            )
        else:
            notes.insert(0, "Implement the observed temporal process directly from the video description without a rigid stage template.")
    if "appearance" in priority["blocking_dimensions"]:
        notes.insert(0, "MANDATORY: implement the requested exposure/contrast/color-remap operation with its own parameter envelope.")

    feedback_compositing = parsed_feedback.get("compositing_mode") if isinstance(parsed_feedback, dict) else None
    compositing_mode = str(feedback_compositing or edit_plan.get("compositing_mode", "")).strip().lower()
    if compositing_mode not in COMPOSITING_MODES:
        compositing_mode = _infer_compositing_mode(normalized_selected, target_ir=target_ir)
    if compositing_mode == "replace_source":
        notes.insert(0, "COMPOSITING: output the processed sample directly; never mix the unwarped source below it.")
    elif compositing_mode == "local_overlay":
        notes.insert(0, "COMPOSITING: retain source only outside an explicit target-supported local mask.")

    raw_background = parsed_feedback.get("background_policy") if isinstance(parsed_feedback, dict) else None
    raw_background = raw_background if isinstance(raw_background, dict) else {}
    inferred_background = _infer_background_policy(target_ir=target_ir, feedback=llm_visual_feedback)
    initial_canvas = str(raw_background.get("initial_canvas", inferred_background["initial_canvas"])).strip().lower()
    outside_fill = str(raw_background.get("outside_effect_region", inferred_background["outside_effect_region"])).strip().lower()
    source_visibility = str(raw_background.get("source_visibility", inferred_background["source_visibility"])).strip().lower()
    background_policy = {
        "initial_canvas": initial_canvas if initial_canvas in INITIAL_CANVAS_MODES else inferred_background["initial_canvas"],
        "outside_effect_region": outside_fill if outside_fill in OUTSIDE_FILL_MODES else inferred_background["outside_effect_region"],
        "source_visibility": source_visibility if source_visibility in {"full_canvas", "transformed_region_only"} else inferred_background["source_visibility"],
    }
    if background_policy["initial_canvas"] == "black" or background_policy["outside_effect_region"] == "black":
        compositing_mode = "replace_source"
        notes.insert(0, "BACKGROUND: start from black and/or keep transformed-region exterior black; never initialize finalRgb from source.rgb.")

    execution_contract = build_required_change_execution_contract(priority["required_changes"])
    return {
        "selected_primitives": normalized_selected[:5],
        "freeform_primitives": [
            item for item in normalized_selected[:5]
            if str(item.get("name", "")) not in PROGRAMMATIC_PRIMITIVES
        ],
        "rejected_primitives": normalized_rejected,
        "implementation_notes": [str(item) for item in notes],
        "temporal_controller": temporal_controller,
        "compositing_mode": compositing_mode,
        "background_policy": background_policy,
        "optimization_priority": priority,
        "execution_contract": execution_contract,
        "_builder_notes": builder_notes,
    }


def build_required_change_execution_contract(required_changes: list[dict[str, Any]]) -> list[dict[str, str]]:
    """Translate visible must-change items into broad GLSL implementation obligations."""
    contract: list[dict[str, str]] = []
    for item in required_changes:
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("id", "")).strip()
        change = str(item.get("change", "")).strip()
        if not item_id or not change:
            continue
        text = change.lower()
        axis = ""
        axis_mentions = [
            (text.find(word), "x") for word in ("horizontal", "x-axis", "x axis", "横向", "水平方向", "水平") if text.find(word) >= 0
        ] + [
            (text.find(word), "y") for word in ("vertical", "y-axis", "y axis", "纵向", "垂直") if text.find(word) >= 0
        ]
        if axis_mentions:
            axis = min(axis_mentions, key=lambda item: item[0])[1]
        late = any(word in text for word in ("later", "late", "after midpoint", "second half", "后半", "中点后", "后段", "末段"))
        temporal = any(word in text for word in ("progress", "recover", "recovery", "transition", "渐变", "恢复", "前半", "后半", "中点", "过程", "随进度"))
        if axis:
            obligation = f"mutate sampleUv.{axis} with visible displacement"
            if late:
                obligation += " controlled by later uProgress"
            elif temporal:
                obligation += " controlled by uProgress"
            kind = "uv_axis_motion"
        elif temporal:
            obligation = "change a uProgress-driven envelope that controls visible effect strength"
            kind = "progress_envelope"
        else:
            obligation = "change a visible sampling or colour operation, not comments or unused constants"
            kind = "visible_output_change"
        contract.append({"id": item_id, "change": change, "kind": kind, "axis": axis or "none", "obligation": obligation})
    return contract


def inspect_execution_contract(shader_text: str, contract: list[dict[str, Any]], *, baseline_shader: str | None) -> dict[str, Any]:
    """Verify that the new source materially changes the required operation family.

    This is a source-structure check, not a visual score or a text-pattern
    validator. The visual reviewer remains authoritative after rendering.
    """
    if not contract:
        return {"passed": True, "items": []}

    def fragment_lines(text: str | None) -> list[str]:
        if not text:
            return []
        blocks = re.findall(r"```(?:glsl)?\s*(.*?)```", text, flags=re.DOTALL | re.IGNORECASE)
        fragment = blocks[-1] if len(blocks) >= 2 else text
        return [" ".join(line.split()) for line in fragment.splitlines() if line.strip() and not line.lstrip().startswith("//")]

    current_lines = fragment_lines(shader_text)
    baseline_lines = fragment_lines(baseline_shader)
    baseline_set = set(baseline_lines)
    uses_progress = any("uProgress" in line for line in current_lines)
    items: list[dict[str, Any]] = []
    for requirement in contract:
        axis = str(requirement.get("axis", "none"))
        if axis in {"x", "y"}:
            # Hand-written shaders use different coordinate variable names.
            # Recognise their semantic role rather than requiring the builder's
            # preferred ``sampleUv`` spelling.
            targets = tuple(f"{root}.{axis}" for root in ("sampleUv", "uv", "warpUv", "coord", "distortedUv"))
            current_ops = [line for line in current_lines if any(target in line for target in targets) and any(op in line for op in ("+=", "-=", "="))]
            baseline_ops = [line for line in baseline_lines if any(target in line for target in targets) and any(op in line for op in ("+=", "-=", "="))]
            changed = bool(set(current_ops) - set(baseline_ops)) if baseline_shader else bool(current_ops)
            needs_progress = "uProgress" in str(requirement.get("obligation", ""))
            passed = bool(current_ops) and changed and (uses_progress if needs_progress else True)
            evidence = current_ops[:3]
        elif requirement.get("kind") == "progress_envelope":
            # Shaders commonly bind uProgress once (``float q = ...``) and
            # then use q in the actual UV/colour envelope. Track that alias so
            # a real formula change is not rejected merely because the binding
            # line itself stays unchanged.
            aliases = {"uProgress"}
            # Follow a small dependency chain: uProgress -> q -> envelope.
            # This is semantic data-flow, not a spelling-specific check.
            for _ in range(4):
                added = False
                for line in current_lines:
                    if "=" not in line or not any(alias in line for alias in aliases):
                        continue
                    left = line.split("=", 1)[0].replace("+", " ").replace("-", " ").strip().split()
                    if left:
                        name = left[-1].rstrip(";")
                        if name and name not in aliases:
                            aliases.add(name)
                            added = True
                if not added:
                    break
            progress_lines = [
                line for line in current_lines
                if any(alias in line for alias in aliases)
                and any(token in line for token in ("sampleUv", "uv", "mix(", "texture2D", "rgb", "color", "effect", "amount_"))
            ]
            changed = bool(set(progress_lines) - baseline_set) if baseline_shader else bool(progress_lines)
            passed = bool(progress_lines) and changed
            evidence = progress_lines[:3]
        else:
            changed_lines = [line for line in current_lines if line not in baseline_set]
            passed = bool(changed_lines) if baseline_shader else bool(current_lines)
            evidence = changed_lines[:3]
        items.append({"id": str(requirement.get("id", "")), "status": "implemented_in_source" if passed else "missing_in_source", "obligation": str(requirement.get("obligation", "")), "source_evidence": evidence})
    return {"passed": all(item["status"] == "implemented_in_source" for item in items), "items": items}


def build_programmatic_shader(edit_plan: dict[str, Any], *, target_ir: dict[str, Any], candidate_ir: dict[str, Any] | None) -> str:
    primitives = edit_plan.get("selected_primitives", []) or []
    names = {str(p.get("name")) for p in primitives if isinstance(p, dict)}
    by_name = {str(p.get("name")): p for p in primitives if isinstance(p, dict)}
    text = _flatten_text({"edit_plan": edit_plan, "target_ir": target_ir, "candidate_ir": candidate_ir}).lower()

    temporal = _first_temporal(primitives, fallback=_infer_temporal_from_text(text))
    effect_factor = _temporal_expr(temporal)
    compositing_mode = str(edit_plan.get("compositing_mode", "")).strip().lower()
    if compositing_mode not in COMPOSITING_MODES:
        compositing_mode = _infer_compositing_mode(primitives, target_ir=target_ir)
    background_policy = edit_plan.get("background_policy") if isinstance(edit_plan.get("background_policy"), dict) else {}
    initial_canvas = str(background_policy.get("initial_canvas", "transformed_effect"))
    outside_fill = str(background_policy.get("outside_effect_region", "clamp_to_edge"))
    starts_from_source = _should_start_from_source(text, target_ir=target_ir)
    base_mix = 0.0 if compositing_mode == "replace_source" or starts_from_source else 0.25

    # Never infer an executable primitive from free-form review text here.
    # `names` has already been normalized against `rejected_primitives`.
    pixelation = "pixelation" in names
    wave = "wave_warp" in names
    flip_x = "flip_x" in names
    flip_y = "flip_y" in names
    scale_x = "scale_x" in names
    scale_y = "scale_y" in names
    translate = [p for p in primitives if isinstance(p, dict) and p.get("name") == "translate"]
    blur = [p for p in primitives if isinstance(p, dict) and p.get("name") == "blur"]
    rgb_shift = "rgb_shift" in names
    brightness = "brightness" in names
    exposure = "exposure" in names
    contrast = "contrast" in names
    saturation = "saturation" in names
    color_remap = "color_remap" in names

    uv_lines = [
        "    vec2 uv = textureCoord;",
        "    float p = clamp(uProgress, 0.0, 1.0);",
        f"    float effectAmount = {effect_factor};",
        f"    float visibleAmount = mix({base_mix:.2f}, 1.0, clamp(effectAmount, 0.0, 1.0));",
        "    vec2 sampleUv = uv;",
    ]
    amount_vars: dict[str, str] = {}
    for primitive in primitives:
        if not isinstance(primitive, dict):
            continue
        name = str(primitive.get("name", ""))
        if not name or name in amount_vars:
            continue
        variable = "amount_" + re.sub(r"[^A-Za-z0-9_]", "_", name)
        amount_vars[name] = variable
        uv_lines.append(f"    float {variable} = clamp({_primitive_weight_expr(primitive)}, 0.0, 1.0);")

    def amount(name: str) -> str:
        return amount_vars.get(name, "visibleAmount")
    notes: list[str] = []

    if flip_x:
        uv_lines.append(f"    sampleUv.x = mix(sampleUv.x, 1.0 - sampleUv.x, {amount('flip_x')});")
        notes.append("flip_x")
    if flip_y:
        uv_lines.append(f"    sampleUv.y = mix(sampleUv.y, 1.0 - sampleUv.y, {amount('flip_y')});")
        notes.append("flip_y")
    if scale_x or scale_y:
        sx = f"mix(1.0, 0.65, {amount('scale_x')})" if scale_x else "1.0"
        sy = f"mix(1.0, 0.65, {amount('scale_y')})" if scale_y else "1.0"
        uv_lines.append(f"    sampleUv = vec2(0.5) + (sampleUv - vec2(0.5)) * vec2({sx}, {sy});")
        notes.append("scale")
    if translate:
        axis = _dominant_axis(translate, fallback="x" if _has_any(text, ["horizontal", "水平", "x-axis"]) else "y" if _has_any(text, ["vertical", "垂直", "y-axis"]) else "x")
        amp = _strength_value(_dominant_strength(translate), weak=0.025, medium=0.055, strong=0.10)
        if _has_any(text, ["jitter", "flicker", "抖动", "glitch", "periodic"]):
            if axis == "y":
                uv_lines.append(f"    float band = floor(sampleUv.x * 12.0);")
                uv_lines.append(f"    sampleUv.y += sin(uTime * 10.0 + band * 1.73) * {amp:.4f} * {amount('translate')};")
            else:
                uv_lines.append(f"    float band = floor(sampleUv.y * 12.0);")
                uv_lines.append(f"    sampleUv.x += sin(uTime * 10.0 + band * 1.73) * {amp:.4f} * {amount('translate')};")
            notes.append("periodic band translate")
        elif axis == "y":
            uv_lines.append(f"    sampleUv.y += {amp:.4f} * {amount('translate')};")
            notes.append("translate_y")
        else:
            uv_lines.append(f"    sampleUv.x += {amp:.4f} * {amount('translate')};")
            notes.append("translate_x")
    if wave:
        amp = 0.035
        wave_primitive = next((p for p in primitives if isinstance(p, dict) and p.get("name") == "wave_warp"), {})
        axis = _normalize_axis(wave_primitive.get("axis", "none"))
        if axis == "none":
            axis = "x"
        if axis == "x":
            uv_lines.append(f"    sampleUv.x += sin(sampleUv.y * 24.0 + uTime * 5.0) * {amp:.4f} * {amount('wave_warp')};")
        else:
            uv_lines.append(f"    sampleUv.y += sin(sampleUv.x * 24.0 + uTime * 5.0) * {amp:.4f} * {amount('wave_warp')};")
        notes.append("wave_warp")

    color_lines: list[str] = []
    if pixelation:
        color_lines.extend(
            [
                f"    float gridSize = mix(96.0, 18.0, {amount('pixelation')});",
                "    vec2 gridUv = (floor(sampleUv * gridSize) + vec2(0.5)) / gridSize;",
                f"    sampleUv = mix(sampleUv, gridUv, {amount('pixelation')});",
            ]
        )
        notes.append("pixelation")
    color_lines.extend(
        [
            "    vec2 unclampedSampleUv = sampleUv;",
            "    float validSample = step(0.0, unclampedSampleUv.x) * step(unclampedSampleUv.x, 1.0) * step(0.0, unclampedSampleUv.y) * step(unclampedSampleUv.y, 1.0);",
            "    sampleUv = clamp(sampleUv, 0.0, 1.0);",
        ]
    )
    color_lines.append("    vec4 originalColor = texture2D(inputImageTexture, uv);")

    blur_axis = _dominant_axis(blur, fallback="x" if _has_any(text, ["horizontal", "水平", "x-axis"]) else "y" if _has_any(text, ["vertical", "垂直", "y-axis"]) else "none")
    if blur:
        blur_amp = _strength_value(_dominant_strength(blur), weak=0.015, medium=0.035, strong=0.07)
        blur_vec = f"vec2({blur_amp:.4f} * {amount('blur')}, 0.0)" if blur_axis == "x" else f"vec2(0.0, {blur_amp:.4f} * {amount('blur')})" if blur_axis == "y" else f"vec2({blur_amp:.4f} * {amount('blur')}, {blur_amp:.4f} * {amount('blur')})"
        color_lines.extend(
            [
                f"    vec2 blurStep = {blur_vec};",
                "    vec4 effectColor = vec4(0.0);",
                "    effectColor += texture2D(inputImageTexture, clamp(sampleUv - blurStep, 0.0, 1.0)) * 0.10;",
                "    effectColor += texture2D(inputImageTexture, clamp(sampleUv - blurStep * 0.5, 0.0, 1.0)) * 0.20;",
                "    effectColor += texture2D(inputImageTexture, sampleUv) * 0.40;",
                "    effectColor += texture2D(inputImageTexture, clamp(sampleUv + blurStep * 0.5, 0.0, 1.0)) * 0.20;",
                "    effectColor += texture2D(inputImageTexture, clamp(sampleUv + blurStep, 0.0, 1.0)) * 0.10;",
            ]
        )
        notes.append("directional_blur")
    elif rgb_shift:
        color_lines.extend(
            [
                f"    vec2 rgbOffset = vec2(0.018 * {amount('rgb_shift')}, 0.0);",
                "    vec4 centerColor = texture2D(inputImageTexture, sampleUv);",
                "    vec4 effectColor = vec4(",
                "        texture2D(inputImageTexture, clamp(sampleUv + rgbOffset, 0.0, 1.0)).r,",
                "        centerColor.g,",
                "        texture2D(inputImageTexture, clamp(sampleUv - rgbOffset, 0.0, 1.0)).b,",
                "        centerColor.a",
                "    );",
            ]
        )
        notes.append("rgb_shift")
    else:
        color_lines.append("    vec4 effectColor = texture2D(inputImageTexture, sampleUv);")

    if exposure:
        amp = _strength_value(str(by_name["exposure"].get("strength", "medium")), weak=0.7, medium=1.5, strong=3.0)
        exposure_expr = _primitive_scalar_expr(by_name["exposure"], weight=amount("exposure"), default_from=0.0, default_to=amp)
        color_lines.append(f"    effectColor.rgb *= pow(2.0, {exposure_expr});")
        notes.append("exposure")
    if brightness:
        amp = _strength_value(str(by_name["brightness"].get("strength", "medium")), weak=0.12, medium=0.45, strong=1.20)
        brightness_expr = _primitive_scalar_expr(by_name["brightness"], weight=amount("brightness"), default_from=0.0, default_to=amp)
        color_lines.append(f"    effectColor.rgb += {brightness_expr};")
        notes.append("brightness")
    if contrast:
        amp = _strength_value(str(by_name["contrast"].get("strength", "medium")), weak=0.25, medium=0.65, strong=1.35)
        contrast_expr = _primitive_scalar_expr(by_name["contrast"], weight=amount("contrast"), default_from=1.0, default_to=1.0 + amp)
        color_lines.append(f"    effectColor.rgb = (effectColor.rgb - vec3(0.5)) * ({contrast_expr}) + vec3(0.5);")
        notes.append("contrast")
    if saturation:
        color_lines.extend(
            [
                "    float luma = dot(effectColor.rgb, vec3(0.299, 0.587, 0.114));",
                f"    effectColor.rgb = mix(vec3(luma), effectColor.rgb, 1.0 + 0.75 * {amount('saturation')});",
            ]
        )
        notes.append("saturation")
    if color_remap:
        remap = amount("color_remap")
        remap_params = by_name["color_remap"].get("params") if isinstance(by_name["color_remap"].get("params"), dict) else {}
        matrix = remap_params.get("matrix")
        target = remap_params.get("to")
        color_lines.append("    // Late-stage channel/tone remapping, driven independently from exposure.")
        if isinstance(matrix, list) and len(matrix) == 9:
            values = [_safe_float(value, 0.0) for value in matrix]
            color_lines.append("    mat3 toneMatrix = mat3(" + ", ".join(f"{value:.5f}" for value in values) + ");")
            color_lines.append("    vec3 remappedColor = toneMatrix * effectColor.rgb;")
        elif isinstance(target, list) and len(target) >= 3:
            bias = [_safe_float(value, 0.0) for value in target[:3]]
            color_lines.append(f"    vec3 channelBias = vec3({bias[0]:.5f}, {bias[1]:.5f}, {bias[2]:.5f});")
            color_lines.append("    vec3 remappedColor = effectColor.rgb * (vec3(1.0) + abs(channelBias) * 0.65) + channelBias * 0.35;")
        else:
            color_lines.extend(
                [
                    "    vec3 remappedColor = vec3(",
                    "        effectColor.r * 0.58 + effectColor.b * 0.62,",
                    "        effectColor.g * 0.72 + effectColor.b * 0.38,",
                    "        effectColor.b * 0.52 + effectColor.r * 0.62",
                    "    );",
                ]
            )
        color_lines.append(f"    effectColor.rgb = mix(effectColor.rgb, remappedColor, {remap});")
        notes.append("color_remap")
    if compositing_mode == "replace_source":
        reveal_expr = "smoothstep(0.0, 0.08, p)" if initial_canvas == "black" else "1.0"
        valid_expr = "validSample" if outside_fill == "black" else "1.0"
        color_lines.extend(
            [
                "    // Full-frame effect: do not blend the unwarped source back underneath.",
                f"    float revealMask = {reveal_expr};",
                f"    vec3 finalRgb = vec3(0.0) + effectColor.rgb * ({valid_expr} * revealMask);",
                "    gl_FragColor = vec4(clamp(finalRgb, 0.0, 1.0), 1.0);",
            ]
        )
        notes.append("replace_source")
    else:
        color_lines.extend(
            [
                "    vec4 finalColor = mix(originalColor, effectColor, clamp(visibleAmount, 0.0, 1.0));",
                "    gl_FragColor = vec4(clamp(finalColor.rgb, 0.0, 1.0), 1.0);",
            ]
        )
        notes.append(compositing_mode)

    fragment = """```glsl
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main()
{
%s
%s
}
```""" % ("\n".join(uv_lines), "\n".join(color_lines))
    return VERTEX_SHADER + "\n\n" + fragment


def _compact_ir_for_code(value: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    keys = (
        "summary", "region_scope", "geometry_ops", "appearance_ops",
        "temporal_pattern", "motion_hint", "color_hint", "geometry_pattern",
        "transform_primitives", "operation_family", "render_contract",
    )
    return {key: value[key] for key in keys if key in value and value[key] not in (None, "", [], {})}


def _compact_feedback_for_code(value: dict[str, Any] | None) -> dict[str, Any] | None:
    parsed = value.get("parsed") if isinstance(value, dict) and "parsed" in value else value
    if not isinstance(parsed, dict):
        return None
    # primitive_edit_plan is intentionally omitted: normalized_plan below is
    # its executable, merged form. raw_response and frame-by-frame evidence
    # must never enter the code-model context.
    keys = (
        "temporal_process_observation", "candidate_process_observation",
        "key_transition_observation", "motion_signature", "most_important_gap",
        "optimization_priority", "next_change_in_plain_words",
        "optimization_plan", "compositing_mode", "background_policy",
        "required_change_check",
    )
    return {key: parsed[key] for key in keys if key in parsed and parsed[key] not in (None, "", [], {})}


def _compact_plan_for_code(value: dict[str, Any]) -> dict[str, Any]:
    selected = []
    for item in value.get("selected_primitives", [])[:5]:
        if not isinstance(item, dict):
            continue
        selected.append({
            key: item[key]
            for key in ("name", "temporal", "params")
            if key in item and item[key] not in (None, "", [], {})
        })
    priority = value.get("optimization_priority") if isinstance(value.get("optimization_priority"), dict) else {}
    background = value.get("background_policy") if isinstance(value.get("background_policy"), dict) else {}
    return {
        "selected_primitives": selected,
        "remove_primitives": [
            _primitive_name(item) for item in value.get("rejected_primitives", []) if _primitive_name(item)
        ],
        "temporal": value.get("temporal_controller"),
        "compositing_mode": value.get("compositing_mode"),
        "background": {key: background[key] for key in ("initial_canvas", "outside_effect_region") if key in background},
        "required_changes": priority.get("required_changes", []),
        "frozen_constraints": priority.get("frozen_constraints", []),
        "execution_contract": value.get("execution_contract", []),
    }


def build_code_model_prompt(
    *,
    normalized_plan: dict[str, Any],
    target_ir: dict[str, Any],
    candidate_ir: dict[str, Any] | None,
    llm_visual_feedback: dict[str, Any] | None,
    current_shader: str | None,
    selected_sources: str | None,
    selected_references: list[dict[str, Any]] | None,
    draft_shader: str,
    iteration: int,
    previous_failure: str | None,
) -> str:
    plan_context = _compact_plan_for_code(normalized_plan)
    freeform = [item for item in normalized_plan.get("freeform_primitives", []) if isinstance(item, dict)]
    freeform_instruction = (
        "以下 freeform_primitives 没有程序化模板，必须由你主动写出 GLSL 实现；"
        "它们不是可忽略的标签。为每项写清楚对应的 mask、离散/连续时间逻辑与 UV/采样操作，"
        "并让结果在渲染视频中可见："
        f"{json.dumps(freeform, ensure_ascii=False)}\n"
        if freeform else ""
    )
    feedback_context = _compact_feedback_for_code(llm_visual_feedback)
    reference_context = (selected_sources or "")[:4000] if iteration == 1 else ""
    previous_shader = (current_shader or "")[:6000] if iteration > 1 else ""
    retry_instruction = (
        "上一尝试未通过渲染或视觉落实验收。把 previous_attempt_shader 当作待修复代码，"
        "先根据 previous_failure 中的可见证据落实上一轮必改项；"
        "不要重新生成同一结构，也不要删除其他 selected_primitives。\n"
        if previous_failure else ""
    )
    return (
        "你是 GLSL shader 代码模型。按 visual_feedback 和 executable_plan 生成下一版，可大幅重写。\n"
        f"{retry_instruction}"
        "optimization_priority 是强制约束：geometry_motion 改 UV；temporal_process 按 temporal_controller 落实完整过程；effect_region 落实区域；appearance 落实曝光/颜色操作。\n"
        "逐项落实 optimization_priority.required_changes；每项只有一个可见目标。frozen_constraints 是已正确且禁止回退的行为，修改其他参数时必须保持。\n"
        "execution_contract 是本轮不可跳过的源码落实清单。对每项必须改写相应的 UV 采样轴或 uProgress 包络；仅改注释、无输出关联的常量、颜色微调，均视为未执行。\n"
        "若 required_change_check.items 中某项为 partial，只完成其 remaining_change；不得再次执行已经 implemented 的方向反转或其他已冻结变化。\n"
        "continuous_monotonic 模式必须只定义一个公共连续进度 q，所有相关操作从 q 派生；禁止按采样点建立 if/阈值分段或各自重启缓动。\n"
        "cyclic、impulse、freeform 模式直接依据视频过程描述实现，不使用固定峰值、阶段或 handoff 模板。逐项实现 selected_primitives；rejected_primitives 绝不能出现在代码中。\n"
        "实现随 uProgress 变化的完整过程，不拟合单帧位置。\n"
        "严格执行 compositing_mode/background_policy；replace_source 或黑场策略下禁止把原图重新混回底图。最终 uv/rgb clamp，alpha=1。\n"
        "programmatic_draft 是可运行起点；与反馈冲突时按反馈重写。\n"
        f"{freeform_instruction}"
        "只输出两个 ```glsl 代码块：Vertex、Fragment。Fragment 只允许 inputImageTexture/uProgress/uTime；不用外部纹理、resolution、uTexelSize、额外 uniform；不要假设 p=0 是原图。\n\n"
        f"iteration: {iteration}\n"
        f"previous_failure:{previous_failure or 'null'}\n"
        f"executable_plan:{json.dumps(plan_context, ensure_ascii=False)}\n"
        f"target_ir_summary:{json.dumps(_compact_ir_for_code(target_ir), ensure_ascii=False)}\n"
        f"candidate_ir_summary:{json.dumps(_compact_ir_for_code(candidate_ir), ensure_ascii=False)}\n"
        f"visual_feedback:{json.dumps(feedback_context, ensure_ascii=False)}\n"
        f"previous_attempt_shader_optional:\n{previous_shader or 'null'}\n\n"
        f"programmatic_draft:\n{draft_shader}\n\n"
        f"initial_reference_source_optional:\n{reference_context or 'null'}\n"
    )


def _primitive(name: str, role: str, axis: str, strength: str, temporal: str, evidence: str) -> dict[str, Any]:
    return {
        "name": name,
        "role": role,
        "axis": axis,
        "strength": strength,
        "temporal": temporal,
        "confidence": 0.8,
        "evidence": evidence,
        "params": {"axis": axis, "strength": strength},
    }


def _flatten_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value, ensure_ascii=False)
    except Exception:
        return str(value)


def _has_any(text: str, needles: list[str]) -> bool:
    lower = text.lower()
    return any(needle.lower() in lower for needle in needles)


def _primitive_name(item: Any) -> str:
    if isinstance(item, dict):
        return _canonical_primitive_name(str(item.get("name", "")).strip().lower())
    return _canonical_primitive_name(str(item).strip().lower())


def _canonical_primitive_name(name: str) -> str:
    aliases = {
        "identity": "identity",
        "pixelate": "pixelation",
        "pixelation": "pixelation",
        "pixelation_mosaic": "pixelation",
        "mosaic": "pixelation",
        "horizontal_block_shift": "translate",
        "local_band_mask": "band_mask",
        "banded_mask": "band_mask",
        "discrete_band_switch": "discrete_region_switch",
        "band_jump": "discrete_region_switch",
        "fragment_x_displacement": "segmented_x_displacement",
        "local_segment_displacement": "segmented_x_displacement",
        "translate_x": "translate",
        "translate_y": "translate",
        "scale": "scale_x",
        "stretch_x": "scale_x",
        "stretch_y": "scale_y",
        "flip": "flip_x",
        "horizontal_flip": "flip_x",
        "vertical_flip": "flip_y",
        "blur_bokeh": "blur",
        "motion_blur": "blur",
        "directional_blur": "blur",
        "tone_remap": "color_remap",
        "color_matrix": "color_remap",
        "channel_remap": "color_remap",
        "sharpen": "contrast",
    }
    if name in aliases:
        return aliases[name]
    allowed = {
        "translate",
        "scale_x",
        "scale_y",
        "flip_x",
        "flip_y",
        "wave_warp",
        "band_mask",
        "discrete_region_switch",
        "segmented_x_displacement",
        "brightness",
        "exposure",
        "contrast",
        "saturation",
        "rgb_shift",
        "color_remap",
        "blur",
        "vignette",
        "pixelation",
        "identity",
    }
    return name if name in allowed else ""


def _normalize_axis(value: Any) -> str:
    text = str(value).lower()
    if text in {"x", "horizontal", "h"}:
        return "x"
    if text in {"y", "vertical", "v"}:
        return "y"
    if text == "radial":
        return "radial"
    return "none"


def _normalize_strength(value: Any) -> str:
    text = str(value).lower()
    if text in {"weak", "small", "low", "轻微"}:
        return "weak"
    if text in {"strong", "large", "high", "强"}:
        return "strong"
    return "medium"


def _normalize_temporal(value: Any) -> str:
    text = str(value).lower()
    # These are the visual-review vocabulary used by the planner.  Preserve
    # their intended timing instead of silently flattening both to linear.
    if text in {"early_progressive", "early progressive", "early"}:
        return "early_progressive"
    if text in {"late_progressive", "late progressive", "late"}:
        return "late_progressive"
    if text in {"periodic", "flicker"}:
        return "periodic"
    if text in {"ease_in", "ease_out", "ease_in_out", "linear"}:
        return text
    return "linear"


def _infer_temporal_from_text(text: str) -> str:
    if _has_any(text, ["periodic", "flicker", "jitter", "周期", "闪烁", "抖动"]):
        return "periodic"
    if "ease" in text:
        return "ease_in_out"
    return "linear"


def _should_start_from_source(text: str, *, target_ir: dict[str, Any]) -> bool:
    if _has_any(text, ["first frame already", "p=0 already", "首帧已经", "第一帧已经", "不要假设", "not assume"]):
        return False
    if _has_any(text, ["return to identity", "starts from source", "starts from original", "p=0 source", "p=0 original", "初始为原图", "从原图开始"]):
        return True
    return False


def _temporal_expr(temporal: str) -> str:
    if temporal == "periodic":
        return "clamp(p * (0.72 + 0.28 * sin(uTime * 12.0)), 0.0, 1.0)"
    if temporal == "ease_in":
        return "p * p"
    if temporal == "ease_out":
        return "1.0 - (1.0 - p) * (1.0 - p)"
    if temporal == "ease_in_out":
        return "smoothstep(0.0, 1.0, p)"
    if temporal == "early_progressive":
        return "smoothstep(0.0, 0.55, p)"
    if temporal == "late_progressive":
        return "smoothstep(0.65, 1.0, p)"
    return "p"


def _primitive_weight_expr(primitive: dict[str, Any]) -> str:
    temporal = _normalize_temporal(primitive.get("temporal"))
    return _temporal_expr(temporal)


def _first_temporal(primitives: list[Any], *, fallback: str) -> str:
    for item in primitives:
        if isinstance(item, dict):
            temporal = _normalize_temporal(item.get("temporal"))
            if temporal != "linear":
                return temporal
    return fallback


def _safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _primitive_scalar_expr(primitive: dict[str, Any], *, weight: str, default_from: float, default_to: float) -> str:
    params = primitive.get("params") if isinstance(primitive.get("params"), dict) else {}
    raw_from, raw_to = params.get("from"), params.get("to")
    start = _safe_float(raw_from, default_from) if raw_from is not None else default_from
    end = _safe_float(raw_to, default_to) if raw_to is not None else default_to
    return f"mix({start:.5f}, {end:.5f}, {weight})"


def _dominant_axis(primitives: list[dict[str, Any]], *, fallback: str) -> str:
    axes = [str(p.get("axis", "none")) for p in primitives]
    for axis in ["x", "y", "radial", "none"]:
        if axis in axes:
            return axis
    return fallback


def _dominant_strength(primitives: list[dict[str, Any]]) -> str:
    strengths = [str(p.get("strength", "medium")) for p in primitives]
    if "strong" in strengths:
        return "strong"
    if "weak" in strengths:
        return "weak"
    return "medium"


def _strength_value(strength: str, *, weak: float, medium: float, strong: float) -> float:
    if strength == "weak":
        return weak
    if strength == "strong":
        return strong
    return medium
