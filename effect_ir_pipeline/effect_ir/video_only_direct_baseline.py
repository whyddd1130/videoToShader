"""One-shot video-only shader baseline with no source image sent to the model."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import cv2

from .closed_loop_shader_iter import (
    ensure_shader_precision_preamble,
    run_shader_lab_render,
    validate_rendered_video,
    validate_shader_text,
    write_shader_files,
)
from .direct_shader_baseline import build_target_contact_sheet_data_url
from .manifest import resolve_repo_path
from .model_client import generate_messages


def _first_frame_proxy(video_path: Path, output_path: Path) -> Path:
    cap = cv2.VideoCapture(str(video_path))
    try:
        ok, frame = cap.read()
    finally:
        cap.release()
    if not ok:
        raise RuntimeError(f"Cannot read first frame from {video_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output_path), frame):
        raise RuntimeError(f"Cannot save render proxy: {output_path}")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description="One-shot video-only direct shader baseline.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--work-dir", type=Path, default=Path("effect_ir_pipeline/baselines/video_only_direct"))
    parser.add_argument("--frame-count", type=int, default=10)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--render-input-image", type=Path, help="Optional proxy image used only by Shader Lab, never sent to the model.")
    parser.add_argument("--model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", "http://172.22.112.93:8788"))
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", ""))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    args = parser.parse_args()
    if args.frame_count <= 0:
        raise ValueError("frame-count must be positive")

    root = args.repo_root.resolve()
    target_video = resolve_repo_path(root, str(args.video_path))
    if not target_video.exists():
        raise FileNotFoundError(target_video)
    args.work_dir.mkdir(parents=True, exist_ok=True)
    sheet, indices = build_target_contact_sheet_data_url(
        target_video, image_size=args.image_size, frame_count=args.frame_count
    )
    prompt = (
        "These are chronological frames from one video effect. Write a GLSL ES shader that recreates its visible temporal process. "
        "No original image is available. Use inputImageTexture as a general source when needed. "
        "Output exactly two fenced ```glsl blocks and nothing else: vertex first, fragment second. "
        "The vertex block must declare `attribute vec2 position`, map `textureCoord = position * 0.5 + 0.5`, and assign gl_Position. "
        "The fragment may use only inputImageTexture, uProgress, and uTime."
    )
    print("[1] direct video-only shader generation", flush=True)
    response = generate_messages(
        [{"role": "user", "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": sheet}},
        ]}],
        model=args.model,
        temperature=args.temperature,
    )
    shader = ensure_shader_precision_preamble(response)
    valid, reason = validate_shader_text(shader)
    if not valid:
        raise ValueError(f"Generated shader is invalid: {reason}")
    source_path = args.work_dir / "video_only_shader_source.md"
    source_path.write_text(shader, encoding="utf-8")
    vertex, fragment = write_shader_files(shader, args.work_dir, 1)

    if args.render_input_image:
        render_input = resolve_repo_path(root, str(args.render_input_image))
    else:
        render_input = _first_frame_proxy(target_video, args.work_dir / "render_proxy_first_frame.png")
    print("[2] render (proxy image is not model input)", flush=True)
    rendered = args.work_dir / "video_only_direct_rendered.mp4"
    job = run_shader_lab_render(
        base_url=args.shader_lab_url, token=args.shader_lab_token,
        vertex_shader=vertex, fragment_shader=fragment, input_image=render_input,
        output_video=rendered, timeout=args.shader_lab_timeout, poll_interval=args.shader_lab_poll_interval,
    )
    valid, reason = validate_rendered_video(rendered)
    if not valid:
        raise RuntimeError(reason)
    result = {
        "baseline": "video_only_direct_shader",
        "model_input": "target_video_samples_only",
        "target_video_path": str(target_video),
        "target_frame_indices": indices,
        "render_proxy_image": str(render_input),
        "shader_source_markdown": str(source_path),
        "rendered_video": str(rendered),
        "shader_lab_job": job,
    }
    result_path = args.work_dir / "video_only_direct_baseline_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"result": str(result_path), "rendered_video": str(rendered)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
