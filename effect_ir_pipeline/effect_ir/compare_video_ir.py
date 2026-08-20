from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from .llm_adapter import generate_video_structured_ir_prompt
from .library_retrieval import rank_library, select_top_reference
from .manifest import read_jsonl, resolve_repo_path
from .model_client import generate_text
from .schema_ir import build_structured_ir_summary, normalize_structured_ir, parse_structured_ir_response
from .structured_similarity import STRATEGY_CONFIGS
from .visual_observation import build_visual_observation_data, build_visual_observation_prompt, sample_frame_indices_for_video


def build_structured_visual_observation_prompt(
    sample: dict[str, Any],
    *,
    repo_root: Path,
    frame_indices: list[int],
    image_size: int,
) -> str:
    observation_prompt = build_visual_observation_prompt(
        sample,
        repo_root=repo_root,
        frame_indices=frame_indices,
        image_size=image_size,
    )
    observation_payload = observation_prompt.split("observations:\n", 1)[-1].rsplit("\nReturn only", 1)[0].strip()
    return (
        f"{generate_video_structured_ir_prompt(sample)}\n"
        "Use the following structured visual observations extracted from the source image and video frames.\n"
        f"observations:\n{observation_payload}\n"
        "Return only JSON.\n"
    )


def apply_observation_guardrails_to_ir(structured_ir: dict[str, Any], observation: dict[str, Any]) -> dict[str, Any]:
    adjusted = dict(structured_ir)
    aggregate = observation.get("aggregate", {}) if isinstance(observation, dict) else {}
    effect_profile = observation.get("estimated_effect_profile", {}) if isinstance(observation, dict) else {}
    shape_bias_hint = str(aggregate.get("shape_bias_hint", ""))
    motion_bias_hint = str(aggregate.get("motion_bias_hint", ""))
    transform_bias_hint = str(aggregate.get("transform_bias_hint", ""))
    sampling_axis_hint = str(aggregate.get("sampling_axis_hint", "")).lower()
    horizontal_line_strength = float(effect_profile.get("horizontal_line_strength", 0.0) or 0.0)
    vertical_line_strength = float(effect_profile.get("vertical_line_strength", 0.0) or 0.0)
    dominant_line_axis_ratio = float(effect_profile.get("dominant_line_axis_ratio", 0.0) or 0.0)
    pixelation_strength = float(effect_profile.get("pixelation_strength", 0.0) or 0.0)
    edge_emphasis = float(effect_profile.get("edge_emphasis", 0.0) or 0.0)
    blur_strength = float(effect_profile.get("blur_strength", 0.0) or 0.0)
    jitter_x = float(effect_profile.get("jitter_x", 0.0) or 0.0)
    jitter_y = float(effect_profile.get("jitter_y", 0.0) or 0.0)
    dominant_motion_axis_ratio = float(effect_profile.get("dominant_motion_axis_ratio", 0.0) or 0.0)
    sampling_blur_x = float(effect_profile.get("sampling_blur_x", 0.0) or 0.0)
    sampling_blur_y = float(effect_profile.get("sampling_blur_y", 0.0) or 0.0)
    sampling_axis_confidence = float(effect_profile.get("sampling_axis_confidence", 0.0) or 0.0)

    # Feature orientation and sampling displacement are different quantities:
    # an X blur often leaves vertical bands/edges. Prefer the gradient-based
    # sampling hint over optical flow when it is reliable.
    blur_axis = sampling_axis_hint if sampling_axis_hint in {"x", "y"} else None
    if blur_axis is None and sampling_axis_confidence >= 0.20 and max(sampling_blur_x, sampling_blur_y) >= 0.08:
        blur_axis = "x" if sampling_blur_x > sampling_blur_y else "y"

    if shape_bias_hint == "line_band_likely" and adjusted.get("shape_hint") == "grid_tile":
        adjusted["shape_hint"] = "line_band"
    if shape_bias_hint == "line_band_likely" and adjusted.get("geometry_pattern") == "tiled":
        adjusted["geometry_pattern"] = "directional"
    if motion_bias_hint == "directional_jitter_likely" and adjusted.get("motion_hint") in {"none", "randomized"}:
        adjusted["motion_hint"] = "flicker" if adjusted.get("temporal_pattern") == "periodic" else "translate"

    if (
        shape_bias_hint == "line_band_likely"
        and dominant_line_axis_ratio >= 0.28
        and max(horizontal_line_strength, vertical_line_strength) >= 0.45
        and adjusted.get("shape_hint") != "line_band"
    ):
        adjusted["shape_hint"] = "line_band"

    if _looks_like_simple_directional_transform(
        adjusted,
        shape_bias_hint=shape_bias_hint,
        motion_bias_hint=motion_bias_hint,
        horizontal_line_strength=horizontal_line_strength,
        vertical_line_strength=vertical_line_strength,
        dominant_line_axis_ratio=dominant_line_axis_ratio,
        pixelation_strength=pixelation_strength,
        edge_emphasis=edge_emphasis,
        blur_strength=blur_strength,
        jitter_x=jitter_x,
        jitter_y=jitter_y,
        dominant_motion_axis_ratio=dominant_motion_axis_ratio,
    ):
        axis = blur_axis or ("x" if jitter_x >= jitter_y else "y")
        transform_primitives = [
            f"linear_stretch_{axis}",
            f"directional_smear_{axis}",
        ]
        if transform_bias_hint == "horizontal_flip_likely":
            transform_primitives = ["horizontal_flip", "mirror_flip", *transform_primitives]
        elif transform_bias_hint == "vertical_flip_likely":
            transform_primitives = ["vertical_flip", "mirror_flip", *transform_primitives]
        adjusted["geometry_ops"] = ["crop_transform"]
        adjusted["appearance_ops"] = ["none"] if blur_strength < 0.18 else ["blur_bokeh"]
        adjusted["motion_hint"] = "translate"
        adjusted["shape_hint"] = "line_band"
        adjusted["geometry_pattern"] = "directional"
        adjusted["mask_dependency"] = "none"
        adjusted["mask_shape_source"] = "none"
        adjusted["complexity"] = "simple"
        adjusted["operation_family"] = "simple_transform"
        adjusted["transform_primitives"] = transform_primitives
        adjusted["summary"] = (
            f"Simple full-frame directional transform: {', '.join(transform_primitives)} along {axis.upper()} axis, "
            "without glitch, pixelation, mask, or external texture dependency."
        )

    # The LLM may already have emitted a directional primitive before the
    # simple-transform guardrail activates. Correct only its sampling axis;
    # shape_hint still describes the visible band orientation independently.
    existing_primitives = [str(item) for item in adjusted.get("transform_primitives", []) or []]
    has_directional_primitive = any(
        item in {"linear_stretch_x", "linear_stretch_y", "directional_smear_x", "directional_smear_y"}
        for item in existing_primitives
    )
    directional_shape = adjusted.get("geometry_pattern") == "directional" and adjusted.get("shape_hint") == "line_band"
    if blur_axis and (has_directional_primitive or directional_shape):
        retained = [
            item for item in existing_primitives
            if item not in {"linear_stretch_x", "linear_stretch_y", "directional_smear_x", "directional_smear_y"}
        ]
        adjusted["transform_primitives"] = [
            *retained,
            f"linear_stretch_{blur_axis}",
            f"directional_smear_{blur_axis}",
        ]
        adjusted["summary"] = (
            f"Full-frame directional blur/transform with sampling along {blur_axis.upper()} axis; "
            "visible line/band orientation is retained separately and does not determine sampling axis."
        )

    return normalize_structured_ir(adjusted)


def _looks_like_simple_directional_transform(
    ir: dict[str, Any],
    *,
    shape_bias_hint: str,
    motion_bias_hint: str,
    horizontal_line_strength: float,
    vertical_line_strength: float,
    dominant_line_axis_ratio: float,
    pixelation_strength: float,
    edge_emphasis: float,
    blur_strength: float,
    jitter_x: float,
    jitter_y: float,
    dominant_motion_axis_ratio: float,
) -> bool:
    appearance_ops = {str(item) for item in ir.get("appearance_ops", [])}
    appearance_is_simple = not (appearance_ops & {"pixelation_mosaic", "channel_shift", "color_adjust", "edge_outline_emboss", "light_glow_flash", "composite_cutout"})
    strong_directional_motion = (
        motion_bias_hint == "directional_jitter_likely"
        and dominant_motion_axis_ratio >= 0.25
        and max(jitter_x, jitter_y) >= 0.18
    )
    line_like = (
        shape_bias_hint == "line_band_likely"
        and dominant_line_axis_ratio >= 0.25
        and max(horizontal_line_strength, vertical_line_strength) >= 0.45
    )
    low_non_transform_artifacts = (
        pixelation_strength <= 0.20
        and edge_emphasis <= 0.18
        and blur_strength <= 0.25
    )
    return appearance_is_simple and strong_directional_motion and line_like and low_non_transform_artifacts


def load_library_structured_rows(path: Path) -> list[dict[str, Any]]:
    rows = read_jsonl(path)
    for row in rows:
        if "structured_ir" not in row:
            raise ValueError(f"Missing structured_ir in {row.get('effect_name', '<unknown>')}")
        row["structured_ir"] = normalize_structured_ir(row["structured_ir"])
        row["summary"] = build_structured_ir_summary(row["structured_ir"])
    rows.sort(key=lambda row: str(row.get("library_id") or row["effect_name"]))
    return rows


def compare_video(
    video_path: Path,
    *,
    input_image: Path,
    repo_root: Path,
    library_structured: Path,
    output: Path,
    request_model: str,
    temperature: float,
    sample_fps: float,
    image_size: int,
    strategy: str,
    top_k: int,
) -> dict[str, Any]:
    resolved_video_path = resolve_repo_path(repo_root, str(video_path))
    sample = {
        "sample_id": video_path.stem,
        "effect_name": "unknown",
        "input_variant": "provided_image_and_video",
        "video_path": str(video_path),
        "input_image_path": str(input_image),
    }

    print(f"[1/5] video: {resolved_video_path}", flush=True)
    print(f"[1/5] input_image: {resolve_repo_path(repo_root, str(input_image))}", flush=True)
    frame_indices = sample_frame_indices_for_video(resolved_video_path, sample_fps=sample_fps)
    print(f"[2/5] sampled frames: {frame_indices}", flush=True)

    print("[3/5] generating structured IR from video observations...", flush=True)
    observation_data = build_visual_observation_data(
        sample,
        repo_root=repo_root,
        frame_indices=frame_indices,
        image_size=image_size,
    )
    prompt = build_structured_visual_observation_prompt(
        sample,
        repo_root=repo_root,
        frame_indices=frame_indices,
        image_size=image_size,
    )
    response = generate_text(prompt, model=request_model, temperature=temperature)
    query_ir = apply_observation_guardrails_to_ir(parse_structured_ir_response(response), observation_data)
    query_summary = build_structured_ir_summary(query_ir)
    print("[IR]", flush=True)
    print(json.dumps(query_ir, ensure_ascii=False, indent=2), flush=True)

    print(f"[4/5] comparing against library structured IR with strategy={strategy}...", flush=True)
    library_rows = load_library_structured_rows(library_structured)
    reference_selection = select_top_reference(query_ir, library_rows, strategy=strategy)
    scored = reference_selection["global_ranking"]

    print(f"[5/5] top {top_k} results:", flush=True)
    for rank, item in enumerate(scored[:top_k], start=1):
        print(
            f"{rank:02d}. {item['display_name']} similarity={item['similarity']:.4f} "
            f"retrieval={item['retrieval_score']:.4f}",
            flush=True,
        )
    selected_reference = reference_selection["selected_reference"]
    print(
        "[5/5] selected top1 reference: "
        f"{selected_reference['display_name']} score={selected_reference['retrieval_score']:.4f}",
        flush=True,
    )

    result = {
        "input_image_path": str(input_image),
        "video_path": str(video_path),
        "resolved_video_path": str(resolved_video_path),
        "frame_indices": frame_indices,
        "strategy": strategy,
        "query_structured_ir": query_ir,
        "query_summary": query_summary,
        "selected_reference": selected_reference,
        "selected_references": reference_selection["selected_references"],
        "top_results": scored[:top_k],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[saved] {output}", flush=True)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate structured IR from one video and compare it with library IR.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True, help="Source/original image used before the effect.")
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--library-structured", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--request-model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--sample-fps", type=float, default=2.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--strategy", choices=sorted(STRATEGY_CONFIGS), default="balanced")
    parser.add_argument("--top-k", type=int, default=10)
    args = parser.parse_args()

    output = args.output
    if output is None:
        output = Path("runs/single_pass/ir_compare") / f"{args.video_path.stem}_video_ir_compare.json"

    compare_video(
        args.video_path,
        input_image=args.input_image,
        repo_root=args.repo_root.resolve(),
        library_structured=args.library_structured,
        output=output,
        request_model=args.request_model,
        temperature=args.temperature,
        sample_fps=args.sample_fps,
        image_size=args.image_size,
        strategy=args.strategy,
        top_k=args.top_k,
    )


if __name__ == "__main__":
    main()
