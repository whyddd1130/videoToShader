from __future__ import annotations

import json
from typing import Any


REGION_SCOPE_VALUES = {
    "full_frame",
    "local_region",
    "masked_region",
    "circular_region",
    "face_region",
    "edge_region",
    "multi_region",
}

GEOMETRY_OP_VALUES = {
    "none",
    "warp",
    "lens_distortion",
    "bulge_twirl",
    "displacement",
    "fold_page",
    "mirror_repeat",
    "crop_transform",
}

APPEARANCE_OP_VALUES = {
    "none",
    "blur_bokeh",
    "pixelation_mosaic",
    "edge_outline_emboss",
    "color_adjust",
    "channel_shift",
    "light_glow_flash",
    "composite_cutout",
}

TEMPORAL_PATTERN_VALUES = {
    "static",
    "periodic",
    "continuous",
    "progressive",
    "random",
}

MASK_DEPENDENCY_VALUES = {
    "none",
    "weak",
    "strong",
}

STRENGTH_VALUES = {
    "weak",
    "medium",
    "strong",
}

MOTION_HINT_VALUES = {
    "none",
    "rotate",
    "translate",
    "pulse",
    "flicker",
    "grow_shrink",
    "deform",
    "randomized",
}

COLOR_HINT_VALUES = {
    "none",
    "brightness",
    "contrast",
    "hue_saturation",
    "invert",
    "channel_isolation",
    "highlight_boost",
}

EDGE_HINT_VALUES = {
    "none",
    "soften",
    "enhance",
    "outline",
}

SHAPE_HINT_VALUES = {
    "none",
    "ring",
    "circle",
    "polygon",
    "hexagon",
    "star",
    "line_band",
    "grid_tile",
}

SUBJECT_HINT_VALUES = {
    "none",
    "face",
    "eyes",
    "mouth",
    "hair",
    "foreground_object",
    "background",
}

GEOMETRY_PATTERN_VALUES = {
    "none",
    "global",
    "radial",
    "directional",
    "swirl",
    "tiled",
    "localized",
}

MASK_SHAPE_SOURCE_VALUES = {
    "none",
    "analytic_shape",
    "subject_segmentation",
    "edge_map",
    "luminance_alpha",
    "texture_pattern",
}

TRANSFORM_PRIMITIVE_VALUES = {
    "none",
    "horizontal_flip",
    "vertical_flip",
    "mirror_flip",
    "linear_stretch_x",
    "linear_stretch_y",
    "uniform_scale",
    "translate_x",
    "translate_y",
    "directional_smear_x",
    "directional_smear_y",
}

COMPLEXITY_VALUES = {
    "simple",
    "medium",
    "complex",
}

OPERATION_FAMILY_VALUES = {
    "identity_none",
    "simple_transform",
    "geometry_warp",
    "glitch_noise",
    "blur",
    "color",
    "pixel_style",
    "edge_outline",
    "mask_composite",
    "light",
    "subject_face",
}


STRUCTURED_IR_SCHEMA = {
    "region_scope": sorted(REGION_SCOPE_VALUES),
    "geometry_ops": sorted(GEOMETRY_OP_VALUES),
    "appearance_ops": sorted(APPEARANCE_OP_VALUES),
    "temporal_pattern": sorted(TEMPORAL_PATTERN_VALUES),
    "mask_dependency": sorted(MASK_DEPENDENCY_VALUES),
    "strength": sorted(STRENGTH_VALUES),
    "motion_hint": sorted(MOTION_HINT_VALUES),
    "color_hint": sorted(COLOR_HINT_VALUES),
    "edge_hint": sorted(EDGE_HINT_VALUES),
    "shape_hint": sorted(SHAPE_HINT_VALUES),
    "subject_hint": sorted(SUBJECT_HINT_VALUES),
    "geometry_pattern": sorted(GEOMETRY_PATTERN_VALUES),
    "mask_shape_source": sorted(MASK_SHAPE_SOURCE_VALUES),
    "transform_primitives": sorted(TRANSFORM_PRIMITIVE_VALUES),
    "complexity": sorted(COMPLEXITY_VALUES),
    "operation_family": sorted(OPERATION_FAMILY_VALUES),
}


def normalize_structured_ir(data: dict[str, Any]) -> dict[str, Any]:
    region_scope = _normalize_enum(data.get("region_scope"), REGION_SCOPE_VALUES, "full_frame")
    geometry_ops = _normalize_enum_list(data.get("geometry_ops"), GEOMETRY_OP_VALUES, ["none"])
    appearance_ops = _normalize_enum_list(data.get("appearance_ops"), APPEARANCE_OP_VALUES, ["none"])
    temporal_pattern = _normalize_enum(data.get("temporal_pattern"), TEMPORAL_PATTERN_VALUES, "static")
    mask_dependency = _normalize_enum(data.get("mask_dependency"), MASK_DEPENDENCY_VALUES, "none")
    strength = _normalize_enum(data.get("strength"), STRENGTH_VALUES, "medium")
    motion_hint = _normalize_enum(data.get("motion_hint"), MOTION_HINT_VALUES, "none")
    color_hint = _normalize_enum(data.get("color_hint"), COLOR_HINT_VALUES, "none")
    edge_hint = _normalize_enum(data.get("edge_hint"), EDGE_HINT_VALUES, "none")
    shape_hint = _normalize_enum(data.get("shape_hint"), SHAPE_HINT_VALUES, "none")
    subject_hint = _normalize_enum(data.get("subject_hint"), SUBJECT_HINT_VALUES, "none")
    geometry_pattern = _normalize_enum(data.get("geometry_pattern"), GEOMETRY_PATTERN_VALUES, "none")
    mask_shape_source = _normalize_enum(data.get("mask_shape_source"), MASK_SHAPE_SOURCE_VALUES, "none")
    transform_primitives = _normalize_enum_list(
        data.get("transform_primitives"),
        TRANSFORM_PRIMITIVE_VALUES,
        _infer_transform_primitives(data, geometry_ops, motion_hint, shape_hint, geometry_pattern),
    )
    complexity = _normalize_enum(
        data.get("complexity"),
        COMPLEXITY_VALUES,
        _infer_complexity(geometry_ops, appearance_ops, transform_primitives, motion_hint, shape_hint, geometry_pattern),
    )
    operation_family = _normalize_enum(
        data.get("operation_family"),
        OPERATION_FAMILY_VALUES,
        _infer_operation_family(geometry_ops, appearance_ops, transform_primitives, subject_hint, color_hint, edge_hint, shape_hint, mask_shape_source),
    )
    summary = str(data.get("summary", "")).strip()
    if not summary:
        summary = build_structured_ir_summary(
            {
                "region_scope": region_scope,
                "geometry_ops": geometry_ops,
                "appearance_ops": appearance_ops,
                "temporal_pattern": temporal_pattern,
                "mask_dependency": mask_dependency,
                "strength": strength,
                "motion_hint": motion_hint,
                "color_hint": color_hint,
                "edge_hint": edge_hint,
                "shape_hint": shape_hint,
                "subject_hint": subject_hint,
                "geometry_pattern": geometry_pattern,
                "mask_shape_source": mask_shape_source,
                "transform_primitives": transform_primitives,
                "complexity": complexity,
                "operation_family": operation_family,
            }
        )
    return {
        "region_scope": region_scope,
        "geometry_ops": geometry_ops,
        "appearance_ops": appearance_ops,
        "temporal_pattern": temporal_pattern,
        "mask_dependency": mask_dependency,
        "strength": strength,
        "motion_hint": motion_hint,
        "color_hint": color_hint,
        "edge_hint": edge_hint,
        "shape_hint": shape_hint,
        "subject_hint": subject_hint,
        "geometry_pattern": geometry_pattern,
        "mask_shape_source": mask_shape_source,
        "transform_primitives": transform_primitives,
        "complexity": complexity,
        "operation_family": operation_family,
        "summary": summary,
    }


def parse_structured_ir_response(text: str) -> dict[str, Any]:
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("Structured IR response must be a JSON object")
    return normalize_structured_ir(data)


def build_structured_ir_summary(structured_ir: dict[str, Any]) -> str:
    geometry = ", ".join(op for op in structured_ir["geometry_ops"] if op != "none") or "no_geometry_change"
    appearance = ", ".join(op for op in structured_ir["appearance_ops"] if op != "none") or "no_appearance_change"
    transform = ", ".join(op for op in structured_ir.get("transform_primitives", []) if op != "none") or "none"
    return (
        f"region={structured_ir['region_scope']}; "
        f"geometry={geometry}; "
        f"appearance={appearance}; "
        f"temporal={structured_ir['temporal_pattern']}; "
        f"mask={structured_ir['mask_dependency']}; "
        f"strength={structured_ir['strength']}; "
        f"motion={structured_ir['motion_hint']}; "
        f"color={structured_ir['color_hint']}; "
        f"edge={structured_ir['edge_hint']}; "
        f"shape={structured_ir['shape_hint']}; "
        f"subject={structured_ir['subject_hint']}; "
        f"geom_pattern={structured_ir['geometry_pattern']}; "
        f"mask_source={structured_ir['mask_shape_source']}; "
        f"transform={transform}; "
        f"complexity={structured_ir.get('complexity', 'medium')}; "
        f"family={structured_ir.get('operation_family', 'identity_none')}"
    )


def _normalize_enum(value: Any, valid_values: set[str], default: str) -> str:
    candidate = str(value).strip().lower()
    return candidate if candidate in valid_values else default


def _normalize_enum_list(value: Any, valid_values: set[str], default: list[str]) -> list[str]:
    if not isinstance(value, list):
        return list(default)
    normalized = []
    for item in value:
        candidate = str(item).strip().lower()
        if candidate in valid_values and candidate not in normalized:
            normalized.append(candidate)
    return normalized or list(default)


def _infer_transform_primitives(
    data: dict[str, Any],
    geometry_ops: list[str],
    motion_hint: str,
    shape_hint: str,
    geometry_pattern: str,
) -> list[str]:
    text = " ".join(
        str(data.get(key, ""))
        for key in ["summary", "motion_hint", "shape_hint", "geometry_pattern"]
    ).lower()
    primitives: list[str] = []
    if "horizontal_flip" in text or "horizontal flip" in text or "flip horizontal" in text:
        primitives.append("horizontal_flip")
    if "vertical_flip" in text or "vertical flip" in text or "flip vertical" in text:
        primitives.append("vertical_flip")
    if "mirror" in text and "flip" in text:
        primitives.append("mirror_flip")
    if "stretch" in text and ("x" in text or "horizontal" in text):
        primitives.append("linear_stretch_x")
    if "stretch" in text and ("y" in text or "vertical" in text):
        primitives.append("linear_stretch_y")
    if "smear" in text and ("x" in text or "horizontal" in text):
        primitives.append("directional_smear_x")
    if "smear" in text and ("y" in text or "vertical" in text):
        primitives.append("directional_smear_y")
    if motion_hint == "translate" and geometry_pattern == "directional":
        primitives.append("translate_x")
    if not primitives and "mirror_repeat" in geometry_ops:
        primitives.append("mirror_flip")
    if not primitives and "crop_transform" in geometry_ops:
        primitives.append("uniform_scale")
    return _ordered_unique(primitives) or ["none"]


def _infer_complexity(
    geometry_ops: list[str],
    appearance_ops: list[str],
    transform_primitives: list[str],
    motion_hint: str,
    shape_hint: str,
    geometry_pattern: str,
) -> str:
    non_none_geometry = [item for item in geometry_ops if item != "none"]
    non_none_appearance = [item for item in appearance_ops if item != "none"]
    non_none_transform = [item for item in transform_primitives if item != "none"]
    complex_hints = {"randomized", "flicker"}
    complex_shapes = {"grid_tile"}
    if len(non_none_geometry) + len(non_none_appearance) >= 3:
        return "complex"
    if motion_hint in complex_hints or shape_hint in complex_shapes or geometry_pattern == "tiled":
        return "complex"
    if non_none_transform and len(non_none_appearance) == 0:
        return "simple"
    if len(non_none_geometry) <= 1 and len(non_none_appearance) == 0:
        return "simple"
    return "medium"


def _infer_operation_family(
    geometry_ops: list[str],
    appearance_ops: list[str],
    transform_primitives: list[str],
    subject_hint: str,
    color_hint: str,
    edge_hint: str,
    shape_hint: str,
    mask_shape_source: str,
) -> str:
    geometry_set = set(geometry_ops)
    appearance_set = set(appearance_ops)
    transform_set = {item for item in transform_primitives if item != "none"}
    if subject_hint in {"face", "eyes", "mouth", "hair"} or mask_shape_source == "subject_segmentation":
        return "subject_face"
    if appearance_set & {"pixelation_mosaic"} or shape_hint == "grid_tile":
        return "pixel_style"
    if appearance_set & {"channel_shift"}:
        return "glitch_noise"
    if appearance_set & {"blur_bokeh"} or edge_hint == "soften":
        return "blur"
    if appearance_set & {"color_adjust"} or color_hint != "none":
        return "color"
    if appearance_set & {"edge_outline_emboss"} or edge_hint in {"enhance", "outline"} or mask_shape_source == "edge_map":
        return "edge_outline"
    if appearance_set & {"composite_cutout"} or mask_shape_source in {"analytic_shape", "luminance_alpha", "texture_pattern"}:
        return "mask_composite"
    if appearance_set & {"light_glow_flash"}:
        return "light"
    if transform_set or geometry_set & {"crop_transform", "mirror_repeat", "fold_page"}:
        return "simple_transform"
    if geometry_set & {"warp", "displacement", "lens_distortion", "bulge_twirl"}:
        return "geometry_warp"
    return "identity_none"


def _ordered_unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result
