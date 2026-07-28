from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .schema_ir import normalize_structured_ir
from .structured_similarity import structured_ir_similarity


CORE_BUCKETS = [
    "geometry_warp",
    "transform_transition",
    "color_tone",
    "blur_bokeh",
    "pixel_style",
    "edge_outline",
    "mask_composite",
    "light_glow_flash",
    "subject_face",
]


def library_id(row: dict[str, Any]) -> str:
    return str(row.get("library_id") or row.get("sample_id") or row["effect_name"])


def display_name(row: dict[str, Any]) -> str:
    lid = library_id(row)
    effect_name = str(row.get("effect_name", lid))
    sample_id = str(row.get("sample_id") or "")
    if lid == effect_name:
        return f"{effect_name} [{sample_id}]" if sample_id and sample_id != effect_name else effect_name
    return f"{lid} ({effect_name})"


def category_weights_from_ir(query_ir: dict[str, Any]) -> dict[str, float]:
    weights = {bucket: 0.0 for bucket in CORE_BUCKETS}
    geometry_ops = set(query_ir.get("geometry_ops", []))
    appearance_ops = set(query_ir.get("appearance_ops", []))
    region_scope = str(query_ir.get("region_scope", "full_frame"))
    mask_shape_source = str(query_ir.get("mask_shape_source", "none"))
    geometry_pattern = str(query_ir.get("geometry_pattern", "none"))
    motion_hint = str(query_ir.get("motion_hint", "none"))
    color_hint = str(query_ir.get("color_hint", "none"))
    edge_hint = str(query_ir.get("edge_hint", "none"))
    shape_hint = str(query_ir.get("shape_hint", "none"))
    subject_hint = str(query_ir.get("subject_hint", "none"))

    if geometry_ops & {"warp", "displacement", "lens_distortion", "bulge_twirl"}:
        weights["geometry_warp"] += 1.0
    if geometry_ops & {"crop_transform", "fold_page", "mirror_repeat"}:
        weights["transform_transition"] += 1.0
    if geometry_pattern in {"global", "directional", "tiled"} or motion_hint in {"translate", "grow_shrink"}:
        weights["transform_transition"] += 0.55
    if geometry_pattern in {"radial", "swirl", "localized"} or motion_hint in {"deform", "rotate"}:
        weights["geometry_warp"] += 0.55

    if appearance_ops & {"color_adjust", "channel_shift"} or color_hint != "none":
        weights["color_tone"] += 1.0
    if "blur_bokeh" in appearance_ops or edge_hint == "soften":
        weights["blur_bokeh"] += 1.0
    if "pixelation_mosaic" in appearance_ops or shape_hint == "grid_tile":
        weights["pixel_style"] += 1.0
    if "edge_outline_emboss" in appearance_ops or edge_hint in {"enhance", "outline"} or mask_shape_source == "edge_map":
        weights["edge_outline"] += 1.0
    if "composite_cutout" in appearance_ops or mask_shape_source in {"analytic_shape", "luminance_alpha"} or region_scope in {"masked_region", "circular_region"}:
        weights["mask_composite"] += 1.0
    if "light_glow_flash" in appearance_ops or color_hint == "highlight_boost" or motion_hint == "flicker":
        weights["light_glow_flash"] += 1.0
    if subject_hint in {"face", "eyes", "hair"} or region_scope == "face_region" or mask_shape_source == "subject_segmentation":
        weights["subject_face"] += 1.0

    nonzero = {bucket: value for bucket, value in weights.items() if value > 0.0}
    if not nonzero:
        return {"geometry_warp": 0.35, "color_tone": 0.35, "transform_transition": 0.20, "blur_bokeh": 0.10}
    total = sum(nonzero.values())
    return {bucket: round(value / total, 4) for bucket, value in sorted(nonzero.items(), key=lambda item: (-item[1], item[0]))}


def rank_library(query_ir: dict[str, Any], library_rows: list[dict[str, Any]], *, strategy: str) -> list[dict[str, Any]]:
    scored = []
    query_ir = normalize_structured_ir(query_ir)
    for row in library_rows:
        library_ir = normalize_structured_ir(row["structured_ir"])
        breakdown = structured_ir_similarity(query_ir, library_ir, strategy=strategy)
        info = row.get("category_info") or {}
        priority = float(info.get("retrieval_priority", 1.0) if info.get("default_retrieval", True) else 0.0)
        retrieval_adjustment = retrieval_adjustment_for_ir(query_ir, library_ir, info)
        raw_retrieval_score = breakdown["overall"] * priority * retrieval_adjustment["multiplier"] + retrieval_adjustment["bonus"]
        retrieval_score = max(0.0, min(1.0, raw_retrieval_score))
        scored.append(
            {
                "library_id": library_id(row),
                "effect_name": row["effect_name"],
                "display_name": display_name(row),
                "similarity": breakdown["overall"],
                "retrieval_score": retrieval_score,
                "raw_retrieval_score": raw_retrieval_score,
                "retrieval_adjustment": retrieval_adjustment,
                "similarity_breakdown": breakdown,
                "library_ir": library_ir,
                "library_summary": row.get("summary", ""),
                "category_info": info,
                "code_dir": row.get("code_dir"),
                "source_dataset": row.get("source_dataset"),
                "input_variant": row.get("input_variant"),
            }
        )
    scored.sort(key=lambda item: (item["raw_retrieval_score"], item["retrieval_score"], item["similarity"]), reverse=True)
    return scored


def retrieval_adjustment_for_ir(query_ir: dict[str, Any], library_ir: dict[str, Any], info: dict[str, Any]) -> dict[str, Any]:
    query_family = str(query_ir.get("operation_family", "identity_none"))
    library_family = str(library_ir.get("operation_family", "identity_none"))
    query_complexity = str(query_ir.get("complexity", "medium"))
    library_complexity = str(library_ir.get("complexity", "medium"))
    query_transforms = {item for item in query_ir.get("transform_primitives", []) if item != "none"}
    library_transforms = {item for item in library_ir.get("transform_primitives", []) if item != "none"}
    library_primitives = {str(item) for item in info.get("primitives", [])}

    multiplier = 1.0
    bonus = 0.0
    reasons: list[str] = []

    if query_family == "simple_transform":
        if library_family == "simple_transform":
            multiplier *= 1.35
            bonus += 0.08
            reasons.append("simple_transform_family_match")
        elif library_family in {"glitch_noise", "pixel_style", "light", "mask_composite", "subject_face"}:
            multiplier *= 0.35
            reasons.append("simple_transform_rejects_complex_family")
        elif library_family == "geometry_warp":
            multiplier *= 0.60
            reasons.append("simple_transform_penalizes_freeform_warp")
        if library_complexity == "complex":
            multiplier *= 0.45
            reasons.append("simple_target_penalizes_complex_reference")
        elif library_complexity == "simple":
            multiplier *= 1.15
            reasons.append("simple_complexity_match")
        if query_transforms and library_transforms:
            overlap = len(query_transforms & library_transforms) / len(query_transforms | library_transforms)
            if overlap > 0:
                multiplier *= 1.0 + 0.35 * overlap
                bonus += 0.05 * overlap
                reasons.append("transform_primitive_overlap")
        if library_primitives & {"channel_shift", "pixelation_mosaic", "randomized", "flicker", "grid_tile", "tiled"}:
            multiplier *= 0.55
            reasons.append("simple_target_penalizes_glitch_primitives")
    else:
        if query_family != "identity_none" and library_family == query_family:
            multiplier *= 1.08
            reasons.append("family_match")
        if query_complexity == "simple" and library_complexity == "complex":
            multiplier *= 0.70
            reasons.append("simple_penalizes_complex")

    return {
        "multiplier": round(multiplier, 4),
        "bonus": round(bonus, 4),
        "query_family": query_family,
        "library_family": library_family,
        "query_complexity": query_complexity,
        "library_complexity": library_complexity,
        "reasons": reasons,
    }


def select_top_reference(
    query_ir: dict[str, Any],
    library_rows: list[dict[str, Any]],
    *,
    strategy: str,
    exclude_library_ids: set[str] | None = None,
    exclude_effect_names: set[str] | None = None,
) -> dict[str, Any]:
    exclude_library_ids = exclude_library_ids or set()
    exclude_effect_names = exclude_effect_names or set()
    ranked = rank_library(query_ir, library_rows, strategy=strategy)
    candidates = [
        item
        for item in ranked
        if item["library_id"] not in exclude_library_ids and item["effect_name"] not in exclude_effect_names
    ]
    if not candidates:
        raise RuntimeError("No library reference available after applying exclusions.")
    selected = dict(candidates[0])
    info = selected.get("category_info") or {}
    selected["bucket"] = info.get("primary_bucket", "top1")
    selected["category_weight"] = 1.0
    selected["weighted_reference_score"] = selected["retrieval_score"]
    return {
        "selected_reference": selected,
        "selected_references": [selected],
        "global_ranking": ranked,
    }


def select_category_references(
    query_ir: dict[str, Any],
    library_rows: list[dict[str, Any]],
    *,
    strategy: str,
    per_bucket: int = 1,
    max_references: int = 4,
    exclude_library_ids: set[str] | None = None,
    exclude_effect_names: set[str] | None = None,
    exclude_buckets: set[str] | None = None,
    boost_buckets: dict[str, float] | None = None,
) -> dict[str, Any]:
    category_weights = category_weights_from_ir(query_ir)
    if exclude_buckets:
        category_weights = {
            bucket: weight for bucket, weight in category_weights.items() if bucket not in exclude_buckets
        }
    if boost_buckets:
        category_weights = dict(category_weights)
        for bucket, boost in boost_buckets.items():
            category_weights[bucket] = category_weights.get(bucket, 0.0) + float(boost)
    if not category_weights:
        category_weights = {"transform_transition": 1.0}
    total_weight = sum(category_weights.values())
    if total_weight > 0:
        category_weights = {
            bucket: round(weight / total_weight, 4)
            for bucket, weight in sorted(category_weights.items(), key=lambda item: (-item[1], item[0]))
        }
    exclude_library_ids = exclude_library_ids or set()
    exclude_effect_names = exclude_effect_names or set()
    ranked = rank_library(query_ir, library_rows, strategy=strategy)
    ranked = [
        item
        for item in ranked
        if item["library_id"] not in exclude_library_ids and item["effect_name"] not in exclude_effect_names
    ]
    selected: list[dict[str, Any]] = []
    used_ids: set[str] = set()
    used_buckets: set[str] = set()
    used_effects: set[str] = set()
    bucket_results: dict[str, list[dict[str, Any]]] = {}

    for bucket, weight in category_weights.items():
        bucket_candidates = []
        for item in ranked:
            info = item.get("category_info") or {}
            if bucket not in info.get("buckets", []):
                continue
            if not info.get("default_retrieval", True):
                continue
            candidate = dict(item)
            candidate["bucket"] = bucket
            candidate["category_weight"] = weight
            candidate["weighted_reference_score"] = item["retrieval_score"] * weight
            bucket_candidates.append(candidate)
        bucket_candidates.sort(key=lambda item: item["weighted_reference_score"], reverse=True)
        preferred = [item for item in bucket_candidates if item["effect_name"] not in used_effects]
        bucket_results[bucket] = (preferred or bucket_candidates)[: max(1, per_bucket)]
        for candidate in bucket_results[bucket]:
            if candidate["library_id"] in used_ids:
                continue
            selected.append(candidate)
            used_ids.add(candidate["library_id"])
            used_buckets.add(bucket)
            used_effects.add(candidate["effect_name"])

    selected.sort(key=lambda item: item["weighted_reference_score"], reverse=True)
    if len(selected) < max_references:
        missing_weighted_buckets = [bucket for bucket in category_weights if bucket not in used_buckets]
        for bucket in missing_weighted_buckets:
            candidates = []
            for item in ranked:
                if item["library_id"] in used_ids:
                    continue
                info = item.get("category_info") or {}
                if bucket not in info.get("buckets", []):
                    continue
                if not info.get("default_retrieval", True):
                    continue
                candidate = dict(item)
                candidate["bucket"] = bucket
                candidate["category_weight"] = category_weights[bucket]
                candidate["weighted_reference_score"] = item["retrieval_score"] * category_weights[bucket]
                candidates.append(candidate)
            candidates.sort(key=lambda item: item["weighted_reference_score"], reverse=True)
            if candidates:
                preferred = [item for item in candidates if item["effect_name"] not in used_effects]
                candidate = (preferred or candidates)[0]
                selected.append(candidate)
                used_ids.add(candidate["library_id"])
                used_buckets.add(bucket)
                used_effects.add(candidate["effect_name"])
            if len(selected) >= max_references:
                break

    if len(selected) < max_references:
        for item in ranked:
            if item["library_id"] in used_ids:
                continue
            info = item.get("category_info") or {}
            if not info.get("default_retrieval", True):
                continue
            fallback = dict(item)
            fallback["bucket"] = info.get("primary_bucket", "fallback")
            fallback["category_weight"] = category_weights.get(fallback["bucket"], 0.0)
            fallback["weighted_reference_score"] = item["retrieval_score"] * max(fallback["category_weight"], 0.1)
            selected.append(fallback)
            used_ids.add(fallback["library_id"])
            used_buckets.add(fallback["bucket"])
            used_effects.add(fallback["effect_name"])
            if len(selected) >= max_references:
                break

    selected = selected[:max_references]
    return {
        "category_weights": category_weights,
        "selected_references": selected,
        "bucket_results": bucket_results,
        "global_ranking": ranked,
    }


def read_library_sources(row_or_item: dict[str, Any], repo_root: Path, *, max_chars: int = 18000) -> str:
    code_dir_raw = row_or_item.get("code_dir")
    if code_dir_raw:
        code_dir = Path(str(code_dir_raw))
        if not code_dir.is_absolute():
            code_dir = repo_root / code_dir
    else:
        code_dir = repo_root / "code" / str(row_or_item["effect_name"])
    chunks: list[str] = []
    filter_path = code_dir / "filter.json"
    if filter_path.exists():
        chunks.append(f"-- FILE: filter.json\n{filter_path.read_text(encoding='utf-8', errors='replace')}")
    for path in sorted(code_dir.rglob("*.lua")):
        chunks.append(f"-- FILE: {path.relative_to(code_dir)}\n{path.read_text(encoding='utf-8', errors='replace')}")
    for path in sorted(code_dir.rglob("*.glsl")):
        chunks.append(f"// FILE: {path.relative_to(code_dir)}\n{path.read_text(encoding='utf-8', errors='replace')}")
    for path in sorted(code_dir.rglob("*.frag")):
        chunks.append(f"// FILE: {path.relative_to(code_dir)}\n{path.read_text(encoding='utf-8', errors='replace')}")
    for path in sorted(code_dir.rglob("*.vert")):
        chunks.append(f"// FILE: {path.relative_to(code_dir)}\n{path.read_text(encoding='utf-8', errors='replace')}")
    return "\n\n".join(chunks)[:max_chars]


def build_reference_sources_block(selected_references: list[dict[str, Any]], repo_root: Path) -> str:
    blocks: list[str] = []
    per_source_chars = max(8000, 30000 // max(1, len(selected_references)))
    for index, item in enumerate(selected_references, start=1):
        source_text = read_library_sources(item, repo_root, max_chars=per_source_chars)
        metadata = {
            "rank": index,
            "library_id": item.get("library_id"),
            "effect_name": item.get("effect_name"),
            "bucket": item.get("bucket"),
            "category_weight": item.get("category_weight"),
            "similarity": item.get("similarity"),
            "weighted_reference_score": item.get("weighted_reference_score"),
            "summary": item.get("library_summary"),
            "category_info": item.get("category_info"),
        }
        blocks.append(
            "===== reference_shader "
            f"{index}: {item.get('display_name') or item.get('library_id')} =====\n"
            f"metadata:\n{json.dumps(metadata, ensure_ascii=False, indent=2)}\n\n"
            f"sources:\n{source_text or '[no readable source files]'}"
        )
    return "\n\n".join(blocks)
