"""Video-only input estimation for the blind video-to-shader experiment.

The original source image is unobserved in this mode.  We deliberately build a
*proxy* image rather than claiming to reconstruct it: the least distorted,
most temporally stable visible frame is a practical canvas on which candidate
shaders can be rendered.  A temporal disagreement mask records pixels for
which the proxy is unreliable, so callers can keep that uncertainty explicit.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np


def _unit_interval(values: np.ndarray) -> np.ndarray:
    """Robustly normalize a one-dimensional vector to [0, 1]."""
    if values.size == 0:
        return values
    low, high = np.percentile(values, [5, 95])
    if high - low < 1e-6:
        return np.full_like(values, 0.5, dtype=np.float32)
    return np.clip((values - low) / (high - low), 0.0, 1.0).astype(np.float32)


def _read_uniform_frames(video_path: Path, sample_count: int, max_side: int) -> tuple[list[int], list[np.ndarray], float, int]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    try:
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        if total_frames <= 0:
            raise RuntimeError(f"Video has no readable frames: {video_path}")
        indices = sorted({int(round(value)) for value in np.linspace(0, total_frames - 1, max(1, sample_count))})
        frames: list[np.ndarray] = []
        readable_indices: list[int] = []
        for index in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, index)
            ok, frame = cap.read()
            if not ok:
                continue
            height, width = frame.shape[:2]
            scale = min(1.0, float(max_side) / float(max(height, width)))
            if scale < 1.0:
                frame = cv2.resize(frame, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA)
            frames.append(frame)
            readable_indices.append(index)
    finally:
        cap.release()
    if not frames:
        raise RuntimeError(f"No readable frames in video: {video_path}")
    return readable_indices, frames, fps, total_frames


def estimate_proxy_input_from_video(
    video_path: Path,
    *,
    output_dir: Path,
    sample_count: int = 9,
    max_side: int = 512,
) -> dict[str, Any]:
    """Create a visible, stable proxy image and an uncertainty mask from a video.

    Selection balances sharpness, agreement with the temporal median and
    visibility.  It intentionally does not apply geometric alignment: unknown
    warps should remain uncertainty rather than being baked into a fake source.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    indices, frames, fps, total_frames = _read_uniform_frames(video_path, sample_count, max_side)
    reference_size = (frames[0].shape[1], frames[0].shape[0])
    frames = [
        frame if (frame.shape[1], frame.shape[0]) == reference_size
        else cv2.resize(frame, reference_size, interpolation=cv2.INTER_AREA)
        for frame in frames
    ]
    stack = np.stack([frame.astype(np.float32) for frame in frames], axis=0)
    median = np.median(stack, axis=0)
    gray_frames = [cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) for frame in frames]
    sharpness = np.asarray([cv2.Laplacian(gray, cv2.CV_32F).var() for gray in gray_frames], dtype=np.float32)
    brightness = np.asarray([float(gray.mean()) for gray in gray_frames], dtype=np.float32)
    disagreement = np.asarray(
        [float(np.mean(np.abs(frame.astype(np.float32) - median))) for frame in frames],
        dtype=np.float32,
    )
    sharpness_score = _unit_interval(sharpness)
    stability_score = 1.0 - _unit_interval(disagreement)
    # Extremely dark/bright frames usually reveal little reusable source
    # content.  The middle of the luminance range is a weak preference only.
    visibility_score = np.clip(1.0 - np.abs(brightness / 255.0 - 0.5) * 1.4, 0.0, 1.0)
    selection_score = 0.45 * sharpness_score + 0.45 * stability_score + 0.10 * visibility_score
    chosen_position = int(np.argmax(selection_score))
    proxy_bgr = frames[chosen_position]

    # High temporal median-absolute-deviation means that a pixel is likely
    # affected by the effect or missing in some frames.  This is a confidence
    # cue for future comparison logic, not a hard mask for rendering.
    per_pixel_mad = np.median(np.abs(stack - median), axis=(0, 3))
    uncertainty = np.clip(per_pixel_mad / 48.0 * 255.0, 0.0, 255.0).astype(np.uint8)
    proxy_path = output_dir / "estimated_input.png"
    uncertainty_path = output_dir / "estimated_input_uncertainty.png"
    cv2.imwrite(str(proxy_path), proxy_bgr)
    cv2.imwrite(str(uncertainty_path), uncertainty)

    metadata: dict[str, Any] = {
        "mode": "video_only_proxy",
        "source_video": str(video_path),
        "proxy_image_path": str(proxy_path),
        "uncertainty_mask_path": str(uncertainty_path),
        "sampled_frame_indices": indices,
        "selected_frame_index": indices[chosen_position],
        "video_fps": fps,
        "video_frame_count": total_frames,
        "selection": [
            {
                "frame_index": frame_index,
                "sharpness": round(float(sharpness[position]), 4),
                "temporal_disagreement": round(float(disagreement[position]), 4),
                "brightness": round(float(brightness[position]), 4),
                "selection_score": round(float(selection_score[position]), 4),
            }
            for position, frame_index in enumerate(indices)
        ],
        "proxy_confidence": round(float(1.0 - float(np.mean(uncertainty)) / 255.0), 4),
        "limitation": "Estimated proxy image, not a recovered ground-truth input. High-uncertainty regions should be judged by temporal effect behavior rather than source-pixel agreement.",
    }
    metadata_path = output_dir / "estimated_input_metadata.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    metadata["metadata_path"] = str(metadata_path)
    return metadata
