from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


ATOMIC_BUCKETS: dict[str, tuple[str, list[str]]] = {
    # Geometry / transform
    "BezierWarp": ("geometry_warp", ["bezier_warp", "warp"]),
    "WaveWarp": ("geometry_warp", ["wave_warp"]),
    "Bulge": ("geometry_warp", ["bulge"]),
    "Twirl": ("geometry_warp", ["twirl", "radial_warp"]),
    "LensDistortion2": ("geometry_warp", ["lens_distortion"]),
    "OpticsCompensation": ("geometry_warp", ["lens_distortion"]),
    "DisplacementMap": ("geometry_warp", ["displacement"]),
    "edgeStretch": ("geometry_warp", ["edge_stretch", "warp"]),
    "Inhalation": ("geometry_warp", ["center_inhalation", "warp", "scale"]),
    "Transform": ("transform_transition", ["translate", "scale", "crop_transform"]),
    "CCPageTurn2": ("transform_transition", ["page_fold"]),
    "Fold": ("transform_transition", ["fold_page", "warp"]),
    # Color
    "ColorBalanceHLS": ("color_tone", ["hue_shift", "saturation", "lightness"]),
    "Lumetri": ("color_tone", ["contrast", "color_adjust"]),
    "Invert": ("color_tone", ["invert"]),
    "ExtractChannel": ("color_tone", ["channel_isolation"]),
    "ShiftChannels": ("color_tone", ["rgb_shift", "channel_shift"]),
    "FourColorGradient": ("color_tone", ["gradient_color_map"]),
    "FlashWarning": ("color_tone", ["hue_saturation"]),
    "LeaveColor": ("color_tone", ["selective_saturation"]),
    "HairDyeing": ("color_tone", ["hair_color_shift", "hue_shift"]),
    # Blur / bokeh
    "MipmapBlur": ("blur_bokeh", ["mipmap_blur"]),
    "SurfaceBlur": ("blur_bokeh", ["surface_blur"]),
    "motionBlur": ("blur_bokeh", ["directional_blur", "motion_blur"]),
    "Bokeh": ("blur_bokeh", ["bokeh_blur"]),
    "DiamondBokeh": ("blur_bokeh", ["bokeh_blur", "diamond_kernel"]),
    "HexagonalBokeh": ("blur_bokeh", ["bokeh_blur", "hexagon_kernel"]),
    "PolygonBokeh": ("blur_bokeh", ["bokeh_blur", "polygon_kernel"]),
    # Pixel style
    "LowPixel": ("pixel_style", ["square_pixelate"]),
    "MosaicHexagon": ("pixel_style", ["hex_pixelate"]),
    "MosaicBuilding": ("pixel_style", ["grid_mosaic", "edge_outline"]),
    "Newsprint": ("pixel_style", ["halftone", "posterize"]),
    "AsciiArtStyle": ("pixel_style", ["ascii_luma_blocks", "grid_tile"]),
    "Pattaizer": ("pixel_style", ["pattern_tile", "star_mask"]),
    # Edge / outline
    "Sketch": ("edge_outline", ["edge_detect", "sketch"]),
    "EmbossNew": ("edge_outline", ["emboss"]),
    "Engrave": ("edge_outline", ["engrave"]),
    "Outline": ("edge_outline", ["outline"]),
    "Stroke": ("edge_outline", ["stroke", "outline"]),
    "LayerOutline": ("edge_outline", ["layer_outline", "edge_glow"]),
    # Mask / composite
    "GradientWipe": ("mask_composite", ["gradient_wipe"]),
    "LayerMask": ("mask_composite", ["mask_composite"]),
    "Progress": ("mask_composite", ["progress_reveal", "circle_mask"]),
    "RandomImage": ("mask_composite", ["random_image_composite"]),
    "pointNine": ("mask_composite", ["nine_patch_composite"]),
    # Light
    "BlingBling": ("light_glow_flash", ["sparkle", "star_glow"]),
    "CCLightSweep": ("light_glow_flash", ["light_sweep"]),
    "EdgeGlow": ("light_glow_flash", ["edge_glow"]),
    "NeonArc": ("light_glow_flash", ["neon_edge_glow", "channel_shift", "displacement"]),
}


COMPOSITE_EFFECTS = {
    "CCPageTurn",
    "CCPageTurnWithBg",
    "CCSphere",
    "JellyDistortion",
    "kaleida",
    "Mercury",
    "Metalman",
    "MosaicBurr",
    "MosaicColor1",
    "MosaicColor2",
    "NeonArc",
    "NewShatter",
    "SlicingSlide",
    "Shatter",
    "Tornado",
    "Guoqing2021",
    "hahajing",
}


INACTIVE_ON_MODEL = {
    "BasicBlocks",
    "BrightFlash",
    "FaceLocation",
    "HeadMatting",
    "Illusion",
    "Lut",
    "Residual",
    "RightAlpha",
    "SEFaceSmooth",
    "SpillSuppressor",
}


NOOP_OR_TEST = {"Nothing", "TestPass"}


CONDITIONAL_REQUIRES: dict[str, list[str]] = {
    "FaceAnchor": ["face_tracking_or_landmarks"],
    "FaceLocation": ["face_tracking_or_landmarks"],
    "FaceRelocation": ["face_tracking_or_landmarks"],
    "HeadMatting": ["subject_segmentation"],
    "HeadTrack": ["face_tracking_or_landmarks"],
    "MagnifyHead": ["face_tracking_or_landmarks"],
    "EyesSticker": ["eye_landmarks"],
    "HairDyeing": ["hair_segmentation"],
    "SEFaceSmooth": ["face_region"],
    "SpillSuppressor": ["foreground_or_chroma_condition"],
}


def ordered_unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result


def buckets_from_ir(ir: dict[str, Any]) -> list[str]:
    buckets: list[str] = []
    geometry_ops = set(ir.get("geometry_ops", []))
    appearance_ops = set(ir.get("appearance_ops", []))
    transform_primitives = {item for item in ir.get("transform_primitives", []) if item != "none"}
    operation_family = str(ir.get("operation_family", "identity_none"))
    subject_hint = str(ir.get("subject_hint", "none"))
    region_scope = str(ir.get("region_scope", "full_frame"))
    mask_shape_source = str(ir.get("mask_shape_source", "none"))
    geometry_pattern = str(ir.get("geometry_pattern", "none"))
    edge_hint = str(ir.get("edge_hint", "none"))
    color_hint = str(ir.get("color_hint", "none"))

    if transform_primitives or operation_family == "simple_transform":
        buckets.append("transform_transition")
    if geometry_ops & {"warp", "displacement", "lens_distortion", "bulge_twirl"}:
        buckets.append("geometry_warp")
    if geometry_ops & {"crop_transform", "fold_page", "mirror_repeat"} or geometry_pattern in {"global", "directional", "tiled"}:
        buckets.append("transform_transition")
    if appearance_ops & {"color_adjust", "channel_shift"} or color_hint != "none":
        buckets.append("color_tone")
    if "blur_bokeh" in appearance_ops or edge_hint == "soften":
        buckets.append("blur_bokeh")
    if "light_glow_flash" in appearance_ops or color_hint == "highlight_boost":
        buckets.append("light_glow_flash")
    if "pixelation_mosaic" in appearance_ops or mask_shape_source == "texture_pattern":
        buckets.append("pixel_style")
    if "edge_outline_emboss" in appearance_ops or edge_hint in {"enhance", "outline"} or mask_shape_source == "edge_map":
        buckets.append("edge_outline")
    if "composite_cutout" in appearance_ops or mask_shape_source in {"analytic_shape", "luminance_alpha"}:
        buckets.append("mask_composite")
    if subject_hint in {"face", "eyes", "hair"} or region_scope == "face_region" or mask_shape_source == "subject_segmentation":
        buckets.append("subject_face")
    return ordered_unique(buckets) or ["identity_none"]


def primitives_from_ir(ir: dict[str, Any]) -> list[str]:
    primitives: list[str] = []
    for op in ir.get("transform_primitives", []):
        if op != "none":
            primitives.append(op)
    for op in ir.get("geometry_ops", []):
        if op != "none":
            primitives.append(op)
    for op in ir.get("appearance_ops", []):
        if op != "none":
            primitives.append(op)
    for field in ["motion_hint", "color_hint", "edge_hint", "shape_hint", "geometry_pattern", "mask_shape_source"]:
        value = str(ir.get(field, "none"))
        if value != "none":
            primitives.append(value)
    return ordered_unique(primitives)


def library_id_for_row(row: dict[str, Any]) -> str:
    return str(row.get("library_id") or row.get("sample_id") or row["effect_name"])


def classify_row(row: dict[str, Any]) -> dict[str, Any]:
    name = row["effect_name"]
    library_id = library_id_for_row(row)
    ir = row["structured_ir"]
    derived_buckets = buckets_from_ir(ir)
    derived_primitives = primitives_from_ir(ir)
    requires = list(CONDITIONAL_REQUIRES.get(name, []))

    if row.get("source_dataset") == "jianying_single_pass":
        buckets = derived_buckets
        primary_bucket = buckets[0]
        primitives = derived_primitives
    elif name in ATOMIC_BUCKETS:
        primary_bucket, manual_primitives = ATOMIC_BUCKETS[name]
        buckets = ordered_unique([primary_bucket, *derived_buckets])
        primitives = ordered_unique([*manual_primitives, *derived_primitives])
    else:
        buckets = derived_buckets
        primary_bucket = buckets[0]
        primitives = derived_primitives

    atomicity = "atomic"
    source_quality = "good"
    retrieval_priority = 1.0
    default_retrieval = True
    notes: list[str] = []

    if name in COMPOSITE_EFFECTS:
        atomicity = "composite"
        source_quality = "mixed"
        retrieval_priority = 0.45
        notes.append("Composite business effect; use only primitives aligned with target_ir.")

    if "subject_face" in buckets:
        if atomicity == "atomic":
            atomicity = "conditional"
        retrieval_priority = min(retrieval_priority, 0.35)
        default_retrieval = False
        if not requires:
            requires.append("subject_or_face_evidence")
        notes.append("Conditional subject/face effect; enable only when target_ir supports it.")

    if name in INACTIVE_ON_MODEL:
        atomicity = "conditional"
        source_quality = "inactive_on_model"
        retrieval_priority = 0.0
        default_retrieval = False
        if not requires:
            requires.append("valid_trigger_or_effect_specific_assets")
        notes.append("Model input video was identical to Nothing__model.mp4; exclude from default retrieval.")

    if name in NOOP_OR_TEST:
        atomicity = "noop_or_test"
        source_quality = "not_for_generation"
        retrieval_priority = 0.0
        default_retrieval = False
        requires = []
        notes.append("No-op/test effect; do not use as default shader reference.")

    return {
        "primary_bucket": primary_bucket,
        "buckets": buckets,
        "atomicity": atomicity,
        "primitives": primitives,
        "operation_family": ir.get("operation_family", "identity_none"),
        "complexity": ir.get("complexity", "medium"),
        "source_quality": source_quality,
        "requires": ordered_unique(requires),
        "default_retrieval": default_retrieval,
        "retrieval_priority": retrieval_priority,
        "notes": notes,
        "library_id": library_id,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Add category_info metadata to library structured IR rows.")
    parser.add_argument("--input", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--output", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--summary", type=Path, default=Path("effect_ir_pipeline/library_category_summary.json"))
    args = parser.parse_args()

    rows = [json.loads(line) for line in args.input.read_text(encoding="utf-8").splitlines() if line.strip()]
    for row in rows:
        row["category_info"] = classify_row(row)

    args.output.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n", encoding="utf-8")

    bucket_counter = Counter()
    primary_counter = Counter()
    atomicity_counter = Counter()
    quality_counter = Counter()
    for row in rows:
        info = row["category_info"]
        primary_counter[info["primary_bucket"]] += 1
        atomicity_counter[info["atomicity"]] += 1
        quality_counter[info["source_quality"]] += 1
        for bucket in info["buckets"]:
            bucket_counter[bucket] += 1

    summary = {
        "total": len(rows),
        "primary_bucket_counts": dict(sorted(primary_counter.items())),
        "bucket_membership_counts": dict(sorted(bucket_counter.items())),
        "atomicity_counts": dict(sorted(atomicity_counter.items())),
        "source_quality_counts": dict(sorted(quality_counter.items())),
        "excluded_from_default_retrieval": [
            library_id_for_row(row) for row in rows if not row["category_info"]["default_retrieval"]
        ],
    }
    args.summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
