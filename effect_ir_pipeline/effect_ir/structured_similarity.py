from __future__ import annotations

from typing import Any


STRATEGY_CONFIGS: dict[str, dict[str, Any]] = {
    "balanced": {
        "weights": {
            "region_score": 0.15,
            "geometry_score": 0.14,
            "appearance_score": 0.15,
            "temporal_score": 0.08,
            "mask_score": 0.08,
            "strength_score": 0.06,
            "motion_score": 0.06,
            "color_score": 0.05,
            "edge_score": 0.05,
            "shape_score": 0.04,
            "subject_score": 0.06,
            "geometry_pattern_score": 0.05,
            "mask_shape_source_score": 0.03,
        },
        "penalties": {
            "region": 0.10,
            "mask": 0.10,
            "geometry_disjoint": 0.12,
            "appearance_disjoint": 0.12,
            "subject_incompatible": 0.16,
            "geometry_pattern_incompatible": 0.08,
            "mask_shape_source_incompatible": 0.14,
            "subject_missing": 0.08,
            "mask_shape_missing": 0.06,
            "warp_pattern_missing": 0.05,
        },
    },
    "gated": {
        "weights": {
            "region_score": 0.14,
            "geometry_score": 0.13,
            "appearance_score": 0.13,
            "temporal_score": 0.06,
            "mask_score": 0.09,
            "strength_score": 0.05,
            "motion_score": 0.05,
            "color_score": 0.04,
            "edge_score": 0.04,
            "shape_score": 0.05,
            "subject_score": 0.10,
            "geometry_pattern_score": 0.06,
            "mask_shape_source_score": 0.06,
        },
        "penalties": {
            "region": 0.14,
            "mask": 0.12,
            "geometry_disjoint": 0.14,
            "appearance_disjoint": 0.12,
            "subject_incompatible": 0.22,
            "geometry_pattern_incompatible": 0.12,
            "mask_shape_source_incompatible": 0.18,
            "subject_missing": 0.12,
            "mask_shape_missing": 0.10,
            "warp_pattern_missing": 0.08,
        },
    },
    "operation_first": {
        "weights": {
            "region_score": 0.10,
            "geometry_score": 0.18,
            "appearance_score": 0.18,
            "temporal_score": 0.05,
            "mask_score": 0.06,
            "strength_score": 0.05,
            "motion_score": 0.07,
            "color_score": 0.05,
            "edge_score": 0.05,
            "shape_score": 0.03,
            "subject_score": 0.08,
            "geometry_pattern_score": 0.07,
            "mask_shape_source_score": 0.03,
        },
        "penalties": {
            "region": 0.08,
            "mask": 0.08,
            "geometry_disjoint": 0.16,
            "appearance_disjoint": 0.16,
            "subject_incompatible": 0.12,
            "geometry_pattern_incompatible": 0.12,
            "mask_shape_source_incompatible": 0.10,
            "subject_missing": 0.06,
            "mask_shape_missing": 0.04,
            "warp_pattern_missing": 0.08,
        },
    },
    "mask_subject_first": {
        "weights": {
            "region_score": 0.12,
            "geometry_score": 0.10,
            "appearance_score": 0.12,
            "temporal_score": 0.05,
            "mask_score": 0.10,
            "strength_score": 0.05,
            "motion_score": 0.05,
            "color_score": 0.04,
            "edge_score": 0.04,
            "shape_score": 0.06,
            "subject_score": 0.12,
            "geometry_pattern_score": 0.05,
            "mask_shape_source_score": 0.10,
        },
        "penalties": {
            "region": 0.10,
            "mask": 0.12,
            "geometry_disjoint": 0.10,
            "appearance_disjoint": 0.10,
            "subject_incompatible": 0.22,
            "geometry_pattern_incompatible": 0.08,
            "mask_shape_source_incompatible": 0.20,
            "subject_missing": 0.12,
            "mask_shape_missing": 0.10,
            "warp_pattern_missing": 0.04,
        },
    },
}


def structured_ir_similarity(query_ir: dict[str, Any], library_ir: dict[str, Any], *, strategy: str = "balanced") -> dict[str, Any]:
    if strategy not in STRATEGY_CONFIGS:
        raise ValueError(f"Unknown structured IR similarity strategy: {strategy}")
    config = STRATEGY_CONFIGS[strategy]
    weights = config["weights"]
    penalties = config["penalties"]

    region_score = 1.0 if query_ir["region_scope"] == library_ir["region_scope"] else 0.0
    temporal_score = 1.0 if query_ir["temporal_pattern"] == library_ir["temporal_pattern"] else 0.0
    mask_score = 1.0 if query_ir["mask_dependency"] == library_ir["mask_dependency"] else 0.0
    strength_score = 1.0 if query_ir["strength"] == library_ir["strength"] else 0.5 if "medium" in {query_ir["strength"], library_ir["strength"]} else 0.0
    motion_score = 1.0 if query_ir["motion_hint"] == library_ir["motion_hint"] else 0.0
    color_score = 1.0 if query_ir["color_hint"] == library_ir["color_hint"] else 0.0
    edge_score = 1.0 if query_ir["edge_hint"] == library_ir["edge_hint"] else 0.0
    shape_score = 1.0 if query_ir["shape_hint"] == library_ir["shape_hint"] else 0.0
    subject_score = 1.0 if query_ir["subject_hint"] == library_ir["subject_hint"] else 0.0
    geometry_pattern_score = 1.0 if query_ir["geometry_pattern"] == library_ir["geometry_pattern"] else 0.0
    mask_shape_source_score = 1.0 if query_ir["mask_shape_source"] == library_ir["mask_shape_source"] else 0.0
    geometry_score = list_jaccard(query_ir["geometry_ops"], library_ir["geometry_ops"])
    appearance_score = list_jaccard(query_ir["appearance_ops"], library_ir["appearance_ops"])

    conflict_penalty = 0.0
    if query_ir["region_scope"] != library_ir["region_scope"]:
        conflict_penalty += penalties["region"]
    if query_ir["mask_dependency"] != library_ir["mask_dependency"]:
        conflict_penalty += penalties["mask"]
    if disjoint_non_none(query_ir["geometry_ops"], library_ir["geometry_ops"]):
        conflict_penalty += penalties["geometry_disjoint"]
    if disjoint_non_none(query_ir["appearance_ops"], library_ir["appearance_ops"]):
        conflict_penalty += penalties["appearance_disjoint"]
    if incompatible_non_none(query_ir["subject_hint"], library_ir["subject_hint"]):
        conflict_penalty += penalties["subject_incompatible"]
    if incompatible_non_none(query_ir["geometry_pattern"], library_ir["geometry_pattern"]):
        conflict_penalty += penalties["geometry_pattern_incompatible"]
    if incompatible_non_none(query_ir["mask_shape_source"], library_ir["mask_shape_source"]):
        conflict_penalty += penalties["mask_shape_source_incompatible"]

    gate_penalty = 0.0
    if query_ir["subject_hint"] != "none" and library_ir["subject_hint"] == "none":
        gate_penalty += penalties["subject_missing"]
    if query_ir["mask_shape_source"] != "none" and library_ir["mask_shape_source"] == "none":
        gate_penalty += penalties["mask_shape_missing"]
    if "warp" in query_ir["geometry_ops"] and library_ir["geometry_pattern"] == "none":
        gate_penalty += penalties["warp_pattern_missing"]

    component_scores = {
        "region_score": region_score,
        "geometry_score": geometry_score,
        "appearance_score": appearance_score,
        "temporal_score": temporal_score,
        "mask_score": mask_score,
        "strength_score": strength_score,
        "motion_score": motion_score,
        "color_score": color_score,
        "edge_score": edge_score,
        "shape_score": shape_score,
        "subject_score": subject_score,
        "geometry_pattern_score": geometry_pattern_score,
        "mask_shape_source_score": mask_shape_source_score,
    }
    overall = sum(weights[name] * value for name, value in component_scores.items()) - conflict_penalty - gate_penalty
    overall = max(0.0, min(1.0, overall))
    return {
        "strategy": strategy,
        "overall": overall,
        **component_scores,
        "conflict_penalty": conflict_penalty,
        "gate_penalty": gate_penalty,
    }


def list_jaccard(left: list[str], right: list[str]) -> float:
    left_set = set(left)
    right_set = set(right)
    if not left_set and not right_set:
        return 1.0
    if not left_set or not right_set:
        return 0.0
    return len(left_set & right_set) / len(left_set | right_set)


def disjoint_non_none(left: list[str], right: list[str]) -> bool:
    left_set = {item for item in left if item != "none"}
    right_set = {item for item in right if item != "none"}
    if not left_set or not right_set:
        return False
    return not bool(left_set & right_set)


def incompatible_non_none(left: str, right: str) -> bool:
    return left != "none" and right != "none" and left != right
