"""Minimal iterative baseline: direct generation followed by direct rewrites.

This deliberately excludes library retrieval, structured IR, edit plans, scores,
and acceptance rules.  Each later round sees only the source image, sampled
target frames, sampled previous-candidate frames, and the previous shader.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .closed_loop_shader_iter import (
    ensure_shader_precision_preamble,
    run_shader_lab_render,
    validate_rendered_video,
    validate_shader_text,
    write_shader_files,
)
from .direct_shader_baseline import _encode_jpeg_data_url, _read_progress_frame_indices, build_direct_shader_baseline_content
from .manifest import resolve_repo_path
from .model_client import generate_messages
from .visual_observation import sample_video_frames


def _video_sheet(video_path: Path, *, label: str, image_size: int, frame_count: int) -> tuple[str, list[int]]:
    indices = _read_progress_frame_indices(video_path, frame_count)
    frames = sample_video_frames(video_path, indices)
    tiles: list[np.ndarray] = []
    for index, frame in enumerate(frames):
        tile = cv2.resize(np.flipud(frame), (image_size, image_size), interpolation=cv2.INTER_AREA)
        canvas = np.full((image_size + 26, image_size, 3), 255, dtype=np.uint8)
        canvas[26:, :] = tile
        p = 0.0 if len(frames) == 1 else index / (len(frames) - 1)
        cv2.putText(canvas, f"{label} p={p:.2f}", (7, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (20, 20, 20), 1, cv2.LINE_AA)
        tiles.append(canvas)
    return _encode_jpeg_data_url(np.concatenate(tiles, axis=1)), indices


def _rewrite_content(*, input_image: Path, target_video: Path, candidate_video: Path, previous_shader: str, image_size: int, frame_count: int) -> list[dict[str, Any]]:
    source = cv2.imread(str(input_image), cv2.IMREAD_COLOR)
    if source is None:
        raise FileNotFoundError(f"Cannot read input image: {input_image}")
    target_sheet, _ = _video_sheet(target_video, label="TARGET", image_size=image_size, frame_count=frame_count)
    candidate_sheet, _ = _video_sheet(candidate_video, label="CURRENT", image_size=image_size, frame_count=frame_count)
    instruction = (
        "Improve the CURRENT shader so its rendered video matches TARGET more closely. "
        "Images are chronological from p=0 to p=1. Compare what visibly happens over time and rewrite the shader directly. "
        "Do not use IR, library references, edit plans, scores, reviews, or explanations. "
        "Keep useful behavior from the current shader, but make any change needed for the visible mismatch. "
        "Output exactly two fenced ```glsl blocks and nothing else: vertex first, fragment second. "
        "The fragment may use only inputImageTexture, uProgress, and uTime; it must sample inputImageTexture and assign gl_FragColor.\n\n"
        "CURRENT_SHADER:\n" + previous_shader
    )
    return [
        {"type": "text", "text": instruction},
        {"type": "image_url", "image_url": {"url": _encode_jpeg_data_url(np.flipud(source))}},
        {"type": "image_url", "image_url": {"url": target_sheet}},
        {"type": "image_url", "image_url": {"url": candidate_sheet}},
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Minimal direct iterative image+video-to-shader baseline.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--work-dir", type=Path, default=Path("effect_ir_pipeline/baselines/simple_iterative"))
    parser.add_argument("--max-iters", type=int, default=5)
    parser.add_argument("--model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--frame-count", type=int, default=5, help="Chronological frames per target/candidate contact sheet.")
    parser.add_argument("--max-generation-attempts", type=int, default=3)
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", "http://172.22.112.93:8788"))
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", ""))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    args = parser.parse_args()
    if args.max_iters <= 0 or args.max_generation_attempts <= 0 or args.frame_count <= 0:
        raise ValueError("max-iters, max-generation-attempts, and frame-count must be positive")

    root = args.repo_root.resolve()
    input_image = resolve_repo_path(root, str(args.input_image))
    target_video = resolve_repo_path(root, str(args.video_path))
    if not input_image.exists() or not target_video.exists():
        raise FileNotFoundError("Both input image and target video must exist")
    args.work_dir.mkdir(parents=True, exist_ok=True)

    current_shader: str | None = None
    current_video: Path | None = None
    iterations: list[dict[str, Any]] = []
    for iteration in range(1, args.max_iters + 1):
        if iteration == 1:
            content, target_indices = build_direct_shader_baseline_content(
                input_image=input_image, target_video=target_video, image_size=args.image_size
                , frame_count=args.frame_count
            )
            stage = "direct_generation"
        else:
            assert current_shader is not None and current_video is not None
            content = _rewrite_content(
                input_image=input_image, target_video=target_video, candidate_video=current_video,
                previous_shader=current_shader, image_size=args.image_size, frame_count=args.frame_count,
            )
            target_indices = _read_progress_frame_indices(target_video, args.frame_count)
            stage = "direct_rewrite"

        last_error = ""
        for attempt in range(1, args.max_generation_attempts + 1):
            print(f"[{iteration}] {stage} (attempt {attempt})", flush=True)
            response = generate_messages([{"role": "user", "content": content}], model=args.model, temperature=args.temperature)
            try:
                shader = ensure_shader_precision_preamble(response)
                valid, reason = validate_shader_text(shader)
                if not valid:
                    raise ValueError(reason)
                shader_path = args.work_dir / f"iter_{iteration:02d}_shader_source.md"
                shader_path.write_text(shader, encoding="utf-8")
                vertex, fragment = write_shader_files(shader, args.work_dir, iteration)
                rendered = args.work_dir / f"iter_{iteration:02d}_rendered.mp4"
                print(f"[{iteration}] render", flush=True)
                render_job = run_shader_lab_render(
                    base_url=args.shader_lab_url, token=args.shader_lab_token,
                    vertex_shader=vertex, fragment_shader=fragment, input_image=input_image,
                    output_video=rendered, timeout=args.shader_lab_timeout, poll_interval=args.shader_lab_poll_interval,
                )
                valid, reason = validate_rendered_video(rendered)
                if not valid:
                    raise RuntimeError(reason)
                current_shader, current_video = shader, rendered
                iterations.append({
                    "iteration": iteration, "stage": stage, "shader_source_markdown": str(shader_path),
                    "rendered_video": str(rendered), "shader_lab_job": render_job,
                })
                break
            except Exception as exc:
                last_error = str(exc)
                (args.work_dir / f"iter_{iteration:02d}_attempt_{attempt:02d}_raw_response.md").write_text(response, encoding="utf-8")
        else:
            raise RuntimeError(f"Iteration {iteration} failed after technical retries: {last_error}")

    result = {
        "baseline": "direct_generation_then_simple_rewrite",
        "model_calls": len(iterations),
        "input_image_path": str(input_image),
        "target_video_path": str(target_video),
        "target_frame_indices": target_indices,
        "iterations": iterations,
        "final_candidate_video": str(current_video) if current_video else None,
    }
    result_path = args.work_dir / "simple_iterative_baseline_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"result": str(result_path), "final_candidate_video": result["final_candidate_video"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
