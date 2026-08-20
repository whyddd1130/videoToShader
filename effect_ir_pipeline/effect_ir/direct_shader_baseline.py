"""Direct image-and-video to shader baseline.

This is intentionally a minimal comparison method: one multimodal model call
receives the input image and sampled target-video frames, then emits a shader.
It does not retrieve library IR, create an edit plan, inspect a candidate, or
iterate using visual feedback.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import uuid
from pathlib import Path
from typing import Any
from urllib import request

import cv2
import numpy as np

from .closed_loop_shader_iter import (
    ensure_shader_precision_preamble,
    extract_glsl_blocks,
    run_shader_lab_render,
    validate_rendered_video,
    validate_shader_text,
    write_shader_files,
)
from .manifest import resolve_repo_path
from .model_client import generate_messages
from .visual_observation import sample_video_frames


_FIXED_VERTEX_SHADER = """attribute vec2 position;
varying vec2 textureCoord;
void main() {
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
"""


def _encode_jpeg_data_url(image_bgr: np.ndarray) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(_encode_jpeg(image_bgr)).decode("ascii")


def _encode_jpeg(image_bgr: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".jpg", image_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
    if not ok:
        raise RuntimeError("Could not encode image for direct baseline prompt")
    return encoded.tobytes()


def _upload_temporary_image(image_bgr: np.ndarray, *, upload_url: str, label: str, work_dir: Path) -> str:
    """Upload a model input image and return a provider-accessible HTTP URL.

    The uploader deliberately uses a generic multipart form (field name: ``file``),
    which is supported by common temporary hosts and can be pointed at an internal
    object-storage upload gateway through ``--temporary-image-upload-url``.
    """
    image_bytes = _encode_jpeg(image_bgr)
    local_copy = work_dir / f"{label}.jpg"
    local_copy.write_bytes(image_bytes)
    boundary = f"----videoToShader{uuid.uuid4().hex}"
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{label}.jpg"\r\n'.encode(),
        b"Content-Type: image/jpeg\r\n\r\n",
        image_bytes,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    req = request.Request(
        upload_url,
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Accept": "application/json, text/plain",
            "User-Agent": "videoToShader-temporary-upload/1.0",
        },
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=60) as response:
            response_text = response.read().decode("utf-8", errors="replace").strip()
    except Exception as exc:
        raise RuntimeError(f"Temporary image upload failed for {label}: {exc}") from exc
    try:
        payload = json.loads(response_text)
        candidates = [payload.get("url"), payload.get("link")]
        if isinstance(payload.get("data"), dict):
            candidates.extend([payload["data"].get("url"), payload["data"].get("link")])
        image_url = next((str(value) for value in candidates if isinstance(value, str) and value.startswith(("http://", "https://"))), "")
    except json.JSONDecodeError:
        match = re.search(r"https?://[^\s\"']+", response_text)
        image_url = match.group(0) if match else ""
    if not image_url:
        raise RuntimeError(f"Temporary image upload returned no HTTP URL for {label}: {response_text[:300]}")
    # tmpfiles.org returns a human-facing landing page in its JSON response.
    # Resolve its actual download URL so multimodal models receive image bytes,
    # rather than an HTML page. Other upload services already return a direct URL.
    if "tmpfiles.org/" in image_url and "/dl/" not in image_url:
        try:
            landing_request = request.Request(image_url, headers={"User-Agent": "videoToShader-temporary-upload/1.0"})
            with request.urlopen(landing_request, timeout=30) as response:
                landing_page = response.read().decode("utf-8", errors="replace")
            direct_match = re.search(r"https://tmpfiles\.org/dl/[^\s\"']+", landing_page)
            if direct_match:
                image_url = direct_match.group(0)
        except Exception as exc:
            raise RuntimeError(f"Could not resolve temporary image download URL for {label}: {exc}") from exc
    return image_url


def _read_progress_frame_indices(video_path: Path, count: int = 5) -> list[int]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    try:
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    finally:
        cap.release()
    if total <= 0:
        raise RuntimeError(f"Video has no readable frames: {video_path}")
    return sorted({int(round(value)) for value in np.linspace(0, total - 1, max(1, count))})


def _wrap_compact_fragment_response(response: str) -> str:
    """Pair a compact model-produced fragment with the fixed platform vertex shader."""
    blocks = re.findall(r"```(?:glsl)?\s*\n(.*?)```", response, flags=re.IGNORECASE | re.DOTALL)
    fragment = (blocks[0] if blocks else response).strip()
    if not fragment:
        raise ValueError("Compact model response contains no fragment shader")
    return f"```glsl\n{_FIXED_VERTEX_SHADER.strip()}\n```\n\n```glsl\n{fragment}\n```"


def build_target_contact_sheet_data_url(
    video_path: Path,
    *,
    image_size: int = 256,
    frame_count: int = 5,
    temporary_upload_url: str = "",
    work_dir: Path | None = None,
) -> tuple[str, list[int]]:
    """Make chronological samples in normal human-view orientation."""
    indices = _read_progress_frame_indices(video_path, frame_count)
    frames = sample_video_frames(video_path, indices)
    tiles: list[np.ndarray] = []
    for position, frame in enumerate(frames):
        # Models reason about visible pictures, not WebGL's coordinate origin.
        # Keep evidence upright; the renderer owns the sole Y conversion.
        tile = cv2.resize(frame, (image_size, image_size), interpolation=cv2.INTER_AREA)
        canvas = np.full((image_size + 26, image_size, 3), 255, dtype=np.uint8)
        canvas[26:, :] = tile
        progress = 0.0 if len(frames) == 1 else position / (len(frames) - 1)
        cv2.putText(canvas, f"TARGET p={progress:.2f}", (7, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (20, 20, 20), 1, cv2.LINE_AA)
        tiles.append(canvas)
    sheet = np.concatenate(tiles, axis=1)
    if temporary_upload_url:
        if work_dir is None:
            raise ValueError("work_dir is required when uploading the target contact sheet")
        return _upload_temporary_image(sheet, upload_url=temporary_upload_url, label="target_contact_sheet", work_dir=work_dir), indices
    return _encode_jpeg_data_url(sheet), indices


def build_timeline_contact_sheet_data_urls(
    video_path: Path,
    *,
    interval_seconds: float = 0.2,
    image_size: int = 192,
    frames_per_sheet: int = 8,
    maximum_frames: int = 60,
) -> tuple[list[str], list[dict[str, float | int]]]:
    """Sample a video by wall-clock time and return several readable sheets.

    Unlike the ordinary evenly-spaced contact sheet, this preserves actual
    timestamps.  Splitting the evidence keeps labels and small movements
    legible instead of squeezing an entire dense timeline into one wide image.
    """
    if interval_seconds <= 0 or frames_per_sheet < 1 or maximum_frames < 2:
        raise ValueError("Timeline sampling settings must be positive")
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    try:
        fps = float(capture.get(cv2.CAP_PROP_FPS))
        total = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    finally:
        capture.release()
    if fps <= 0 or total < 1:
        raise RuntimeError(f"Video has no valid timeline: {video_path}")
    duration = max(0.0, (total - 1) / fps)
    requested_times = list(np.arange(0.0, duration + interval_seconds * 0.25, interval_seconds))
    if not requested_times or requested_times[-1] < duration - interval_seconds * 0.25:
        requested_times.append(duration)
    else:
        requested_times[-1] = min(requested_times[-1], duration)
    indices_and_times: list[tuple[int, float]] = []
    for timestamp in requested_times:
        index = min(total - 1, int(round(timestamp * fps)))
        actual_time = index / fps
        if not indices_and_times or index != indices_and_times[-1][0]:
            indices_and_times.append((index, actual_time))
    if len(indices_and_times) > maximum_frames:
        raise ValueError(
            f"Dense timeline needs {len(indices_and_times)} frames, above the safety limit {maximum_frames}; "
            "increase --timeline-max-frames or use a larger interval"
        )
    frames = sample_video_frames(video_path, [item[0] for item in indices_and_times])
    entries = [
        {"sequence": position, "frame_index": index, "time_seconds": round(timestamp, 4)}
        for position, (index, timestamp) in enumerate(indices_and_times)
    ]
    urls: list[str] = []
    for start in range(0, len(frames), frames_per_sheet):
        tiles: list[np.ndarray] = []
        for frame, entry in zip(frames[start:start + frames_per_sheet], entries[start:start + frames_per_sheet]):
            tile = cv2.resize(frame, (image_size, image_size), interpolation=cv2.INTER_AREA)
            canvas = np.full((image_size + 28, image_size, 3), 255, dtype=np.uint8)
            canvas[28:, :] = tile
            cv2.putText(
                canvas, f"#{entry['sequence']:02d}  t={entry['time_seconds']:.2f}s", (7, 19),
                cv2.FONT_HERSHEY_SIMPLEX, 0.43, (15, 15, 15), 1, cv2.LINE_AA,
            )
            tiles.append(canvas)
        urls.append(_encode_jpeg_data_url(np.concatenate(tiles, axis=1)))
    return urls, entries


def build_direct_shader_baseline_content(
    *,
    input_image: Path,
    target_video: Path,
    image_size: int = 256,
    frame_count: int = 5,
    temporary_upload_url: str = "",
    work_dir: Path | None = None,
    shader_complexity: str = "standard",
) -> tuple[list[dict[str, Any]], list[int]]:
    source = cv2.imread(str(input_image), cv2.IMREAD_COLOR)
    if source is None:
        raise FileNotFoundError(f"Cannot read input image: {input_image}")
    target_sheet_url, indices = build_target_contact_sheet_data_url(
        target_video,
        image_size=image_size,
        frame_count=frame_count,
        temporary_upload_url=temporary_upload_url,
        work_dir=work_dir,
    )
    source_for_model = source
    source_url = (
        _upload_temporary_image(source_for_model, upload_url=temporary_upload_url, label="source_image", work_dir=work_dir)
        if temporary_upload_url
        else _encode_jpeg_data_url(source_for_model)
    )
    instruction = (
        "You are given SOURCE_IMAGE and TARGET_VIDEO_SAMPLES. TARGET_VIDEO_SAMPLES are ordered left to right from p=0 to p=1. "
        "Write one GLSL ES shader that transforms SOURCE_IMAGE into the target video effect. "
        "Infer the complete dynamic process directly from the images. Do not describe your reasoning. "
        "When the target samples visibly change over time, make uProgress drive a clearly visible coordinate or color change "
        "through the middle of the video; do not return an unchanged source image except where the target sample shows one. "
        "Do not use library references, IR, edit plans, score, review, or any additional textures. "
        "Output exactly two fenced ```glsl blocks and nothing else: first a vertex shader, then a fragment shader. "
        "The vertex shader must use `attribute vec2 position`, set `textureCoord = position * 0.5 + 0.5`, and assign gl_Position. "
        "The fragment shader may use only `inputImageTexture`, `uProgress`, and `uTime` uniforms; it must sample inputImageTexture and assign gl_FragColor. "
        "All supplied images are upright in normal human-view orientation. Use textureCoord unchanged by default; never flip or rotate UVs unless TARGET_VIDEO_SAMPLES visibly flip or rotate relative to SOURCE_IMAGE."
    )
    if shader_complexity == "compact":
        instruction = (
            "SOURCE_IMAGE and TARGET_VIDEO_SAMPLES are shown below. TARGET samples are left-to-right from p=0 to p=1. "
            "Write only the fragment shader for the dominant dynamic effect from SOURCE_IMAGE to TARGET_VIDEO_SAMPLES. "
            "A fixed compatible vertex shader will be supplied automatically. Output exactly one fenced ```glsl block and nothing else. "
            "Use only inputImageTexture, uProgress and uTime. Keep it under 28 non-empty lines, with at most three texture2D samples, "
            "no loops and no helper functions. Implement one clear uProgress-driven change; ignore secondary details. "
            "The fragment must declare varying vec2 textureCoord, sample inputImageTexture, and assign gl_FragColor."
        )
    return [
        {"type": "text", "text": instruction},
        {"type": "image_url", "image_url": {"url": source_url}},
        {"type": "image_url", "image_url": {"url": target_sheet_url}},
    ], indices


def main() -> None:
    parser = argparse.ArgumentParser(description="One-shot direct image+video-to-shader baseline.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--work-dir", type=Path, default=Path("runs/single_pass/direct_shader"))
    parser.add_argument("--model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--frame-count", type=int, default=5, help="Chronological target frames supplied to the model.")
    parser.add_argument("--shader-complexity", choices=["standard", "compact"], default="standard")
    parser.add_argument(
        "--temporary-image-upload-url",
        default=os.environ.get("EFFECT_IR_TEMP_IMAGE_UPLOAD_URL", ""),
        help="Optional multipart upload endpoint. When set, SOURCE_IMAGE and the target contact sheet are uploaded and passed to the model as HTTP URLs.",
    )
    parser.add_argument("--model-source-image-url", default="", help="Existing HTTP URL for SOURCE_IMAGE; use together with --model-target-contact-sheet-url.")
    parser.add_argument("--model-target-contact-sheet-url", default="", help="Existing HTTP URL for TARGET_VIDEO_SAMPLES; use together with --model-source-image-url.")
    parser.add_argument("--max-generation-attempts", type=int, default=3)
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", ""))
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", ""))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    args = parser.parse_args()
    if args.max_generation_attempts <= 0 or args.frame_count <= 0:
        raise ValueError("max-generation-attempts and frame-count must be positive")
    if not args.shader_lab_url:
        raise ValueError("Set SHADER_LAB_URL or pass --shader-lab-url before rendering")

    repo_root = args.repo_root.resolve()
    input_image = resolve_repo_path(repo_root, str(args.input_image))
    target_video = resolve_repo_path(repo_root, str(args.video_path))
    if not input_image.exists() or not target_video.exists():
        raise FileNotFoundError("Both --input-image and video_path must exist")
    work_dir = args.work_dir
    work_dir.mkdir(parents=True, exist_ok=True)
    if bool(args.model_source_image_url) != bool(args.model_target_contact_sheet_url):
        raise ValueError("--model-source-image-url and --model-target-contact-sheet-url must be provided together")
    if (args.model_source_image_url or args.model_target_contact_sheet_url) and args.temporary_image_upload_url:
        raise ValueError("Use either supplied model image URLs or --temporary-image-upload-url, not both")
    content, frame_indices = build_direct_shader_baseline_content(
        input_image=input_image,
        target_video=target_video,
        image_size=args.image_size,
        frame_count=args.frame_count,
        temporary_upload_url=args.temporary_image_upload_url,
        work_dir=work_dir,
        shader_complexity=args.shader_complexity,
    )
    if args.model_source_image_url:
        image_parts = [part for part in content if part.get("type") == "image_url"]
        image_parts[0]["image_url"]["url"] = args.model_source_image_url
        image_parts[1]["image_url"]["url"] = args.model_target_contact_sheet_url
    if args.temporary_image_upload_url or args.model_source_image_url:
        uploaded_urls = [part["image_url"]["url"] for part in content if part.get("type") == "image_url"]
        (work_dir / "model_input_urls.json").write_text(json.dumps({"urls": uploaded_urls}, ensure_ascii=False, indent=2), encoding="utf-8")
    failures: list[dict[str, str]] = []
    for attempt in range(1, args.max_generation_attempts + 1):
        print(f"[1] direct multimodal shader generation (attempt {attempt})", flush=True)
        response = generate_messages([{"role": "user", "content": content}], model=args.model, temperature=args.temperature)
        try:
            shader_text = _wrap_compact_fragment_response(response) if args.shader_complexity == "compact" else response
            shader_text = ensure_shader_precision_preamble(shader_text)
            valid, reason = validate_shader_text(shader_text)
            if not valid:
                raise ValueError(reason)
            shader_path = work_dir / "direct_shader_source.md"
            shader_path.write_text(shader_text, encoding="utf-8")
            vertex_path, fragment_path = write_shader_files(shader_text, work_dir, 1)
            print("[2] render direct baseline shader", flush=True)
            rendered_video = work_dir / "direct_rendered.mp4"
            render_job = run_shader_lab_render(
                base_url=args.shader_lab_url,
                token=args.shader_lab_token,
                vertex_shader=vertex_path,
                fragment_shader=fragment_path,
                input_image=input_image,
                output_video=rendered_video,
                timeout=args.shader_lab_timeout,
                poll_interval=args.shader_lab_poll_interval,
            )
            valid, reason = validate_rendered_video(rendered_video)
            if not valid:
                raise RuntimeError(reason)
            result = {
                "baseline": "direct_multimodal_image_video_to_shader",
                "model_calls": 1,
                "input_image_path": str(input_image),
                "target_video_path": str(target_video),
                "target_frame_indices": frame_indices,
                "shader_source_markdown": str(shader_path),
                "rendered_video": str(rendered_video),
                "vertex_shader": str(vertex_path),
                "fragment_shader": str(fragment_path),
                "shader_lab_job": render_job,
                "technical_failures_before_success": failures,
            }
            result_path = work_dir / "direct_baseline_result.json"
            result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({"result": str(result_path), "rendered_video": str(rendered_video)}, ensure_ascii=False))
            return
        except Exception as exc:
            failures.append({"attempt": str(attempt), "reason": str(exc)})
            (work_dir / f"attempt_{attempt:02d}_raw_response.md").write_text(response, encoding="utf-8")
            print(f"[failure] {exc}", flush=True)
    raise RuntimeError(f"Direct baseline failed after {args.max_generation_attempts} technical attempts: {failures}")


if __name__ == "__main__":
    main()
