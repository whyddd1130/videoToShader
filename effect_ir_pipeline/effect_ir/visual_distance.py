from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np


FRAME_COMPONENT_WEIGHTS = {
    "pixel_error": 0.35,
    "structural_error": 0.35,
    "sharpness_error": 0.15,
    "color_histogram": 0.15,
}

VIDEO_COMPONENT_WEIGHTS = {
    "appearance": 0.85,
    "temporal": 0.10,
    "duration": 0.03,
    "aspect_ratio": 0.02,
}

PIXEL_TOLERANCE = 0.20
STRUCTURE_TOLERANCE = 0.50
TEMPORAL_TOLERANCE = 0.20


def compare_video_visual_distance(
    target_video: Path,
    candidate_video: Path,
    *,
    sample_fps: float = 2.0,
    image_size: int = 256,
    max_frames: int = 16,
) -> dict[str, Any]:
    """Compare two videos directly at aligned relative timeline positions.

    Frames are sampled from the full relative timeline, including progress=0.
    The source image is provided separately in the current pipeline, so the
    target video's first frame may already contain an effect and should remain
    part of visual diagnostics. The returned distance is normalized to [0, 1].
    """
    if sample_fps <= 0:
        raise ValueError("sample_fps must be greater than zero")
    if image_size <= 0:
        raise ValueError("image_size must be greater than zero")
    if max_frames <= 0:
        raise ValueError("max_frames must be greater than zero")

    target_meta = _read_video_metadata(target_video)
    candidate_meta = _read_video_metadata(candidate_video)
    reference_duration = max(target_meta["duration_seconds"], candidate_meta["duration_seconds"])
    sample_count = max(1, min(max_frames, int(math.ceil(reference_duration * sample_fps))))
    progress_values = np.linspace(0.0, 1.0, sample_count, dtype=np.float32)

    target_frames = _sample_frames_at_progress(
        target_video,
        total_frames=target_meta["frame_count"],
        progress_values=progress_values,
        image_size=image_size,
    )
    candidate_frames = _sample_frames_at_progress(
        candidate_video,
        total_frames=candidate_meta["frame_count"],
        progress_values=progress_values,
        image_size=image_size,
    )

    per_frame: list[dict[str, float]] = []
    for progress, target_frame, candidate_frame in zip(progress_values, target_frames, candidate_frames):
        components = _frame_distance_components(target_frame, candidate_frame)
        per_frame.append(
            {
                "progress": round(float(progress), 6),
                **{key: round(float(value), 6) for key, value in components.items()},
            }
        )

    frame_scores = [frame["overall"] for frame in per_frame]
    mean_components = {key: float(np.mean([frame[key] for frame in per_frame])) for key in FRAME_COMPONENT_WEIGHTS}
    mean_frame_distance = float(np.mean(frame_scores))
    p90_frame_distance = float(np.percentile(frame_scores, 90))
    max_frame_distance = float(np.max(frame_scores))
    appearance_distance = _clamp01(0.7 * mean_frame_distance + 0.3 * p90_frame_distance)
    temporal_distance = _temporal_distance(target_frames, candidate_frames)
    duration_distance = _relative_scalar_distance(
        target_meta["duration_seconds"],
        candidate_meta["duration_seconds"],
    )
    aspect_ratio_distance = _relative_scalar_distance(
        target_meta["aspect_ratio"],
        candidate_meta["aspect_ratio"],
    )
    overall = (
        VIDEO_COMPONENT_WEIGHTS["appearance"] * appearance_distance
        + VIDEO_COMPONENT_WEIGHTS["temporal"] * temporal_distance
        + VIDEO_COMPONENT_WEIGHTS["duration"] * duration_distance
        + VIDEO_COMPONENT_WEIGHTS["aspect_ratio"] * aspect_ratio_distance
    )
    overall = _clamp01(overall)

    return {
        "overall": overall,
        "distance_mode": "direct_visual",
        "sample_count": sample_count,
        "sample_progress": [round(float(value), 6) for value in progress_values],
        "image_size": image_size,
        "frame_component_weights": FRAME_COMPONENT_WEIGHTS,
        "video_component_weights": VIDEO_COMPONENT_WEIGHTS,
        "component_tolerances": {
            "pixel_error": PIXEL_TOLERANCE,
            "structural_error": STRUCTURE_TOLERANCE,
            "temporal": TEMPORAL_TOLERANCE,
        },
        "appearance_distance": appearance_distance,
        "mean_frame_distance": mean_frame_distance,
        "p90_frame_distance": p90_frame_distance,
        "max_frame_distance": max_frame_distance,
        "mean_frame_components": mean_components,
        "temporal_distance": temporal_distance,
        "duration_distance": duration_distance,
        "aspect_ratio_distance": aspect_ratio_distance,
        "target_metadata": target_meta,
        "candidate_metadata": candidate_meta,
        "per_frame": per_frame,
    }


def _read_video_metadata(video_path: Path) -> dict[str, Any]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    try:
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    finally:
        cap.release()
    if frame_count <= 0:
        raise RuntimeError(f"Video has no readable frames: {video_path}")
    if fps <= 0:
        fps = 25.0
    if width <= 0 or height <= 0:
        raise RuntimeError(f"Video has invalid dimensions: {video_path}")
    return {
        "frame_count": frame_count,
        "fps": fps,
        "width": width,
        "height": height,
        "duration_seconds": frame_count / fps,
        "aspect_ratio": width / height,
    }


def _sample_frames_at_progress(
    video_path: Path,
    *,
    total_frames: int,
    progress_values: np.ndarray,
    image_size: int,
) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    frames: list[np.ndarray] = []
    try:
        for progress in progress_values:
            frame_index = min(total_frames - 1, max(0, int(round(float(progress) * (total_frames - 1)))))
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame_bgr = cap.read()
            if not ok:
                raise RuntimeError(f"Cannot read frame {frame_index} from {video_path}")
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            frame_rgb = cv2.resize(frame_rgb, (image_size, image_size), interpolation=cv2.INTER_AREA)
            frames.append(frame_rgb.astype(np.float32) / 255.0)
    finally:
        cap.release()
    return frames


def _frame_distance_components(target_rgb: np.ndarray, candidate_rgb: np.ndarray) -> dict[str, float]:
    if target_rgb.shape != candidate_rgb.shape:
        raise ValueError(f"Frame shapes must match: {target_rgb.shape} != {candidate_rgb.shape}")
    target_rgb = np.clip(target_rgb.astype(np.float32), 0.0, 1.0)
    candidate_rgb = np.clip(candidate_rgb.astype(np.float32), 0.0, 1.0)
    target_gray = cv2.cvtColor(target_rgb, cv2.COLOR_RGB2GRAY)
    candidate_gray = cv2.cvtColor(candidate_rgb, cv2.COLOR_RGB2GRAY)

    raw_pixel_l1 = float(np.mean(np.abs(target_rgb - candidate_rgb)))
    raw_structural_dissimilarity = _structural_dissimilarity(target_gray, candidate_gray)
    sharpness_error = _sharpness_distance(target_gray, candidate_gray)
    color_histogram = _color_histogram_distance(target_rgb, candidate_rgb)
    components = {
        "pixel_error": _clamp01(raw_pixel_l1 / PIXEL_TOLERANCE),
        "structural_error": _clamp01(raw_structural_dissimilarity / STRUCTURE_TOLERANCE),
        "sharpness_error": sharpness_error,
        "color_histogram": color_histogram,
    }
    overall = sum(FRAME_COMPONENT_WEIGHTS[key] * value for key, value in components.items())
    return {
        **components,
        "raw_pixel_l1": _clamp01(raw_pixel_l1),
        "raw_structural_dissimilarity": raw_structural_dissimilarity,
        "overall": _clamp01(overall),
    }


def _structural_dissimilarity(target_gray: np.ndarray, candidate_gray: np.ndarray) -> float:
    c1 = 0.01**2
    c2 = 0.03**2
    mu_target = cv2.GaussianBlur(target_gray, (11, 11), 1.5)
    mu_candidate = cv2.GaussianBlur(candidate_gray, (11, 11), 1.5)
    mu_target_sq = mu_target * mu_target
    mu_candidate_sq = mu_candidate * mu_candidate
    mu_cross = mu_target * mu_candidate
    sigma_target_sq = cv2.GaussianBlur(target_gray * target_gray, (11, 11), 1.5) - mu_target_sq
    sigma_candidate_sq = cv2.GaussianBlur(candidate_gray * candidate_gray, (11, 11), 1.5) - mu_candidate_sq
    sigma_cross = cv2.GaussianBlur(target_gray * candidate_gray, (11, 11), 1.5) - mu_cross
    numerator = (2.0 * mu_cross + c1) * (2.0 * sigma_cross + c2)
    denominator = (mu_target_sq + mu_candidate_sq + c1) * (sigma_target_sq + sigma_candidate_sq + c2)
    ssim_map = numerator / np.maximum(denominator, 1e-12)
    mean_ssim = float(np.mean(np.clip(ssim_map, -1.0, 1.0)))
    return _clamp01((1.0 - mean_ssim) / 2.0)


def _sharpness_distance(target_gray: np.ndarray, candidate_gray: np.ndarray) -> float:
    target_energy = _laplacian_energy(target_gray)
    candidate_energy = _laplacian_energy(candidate_gray)
    return _clamp01(abs(target_energy - candidate_energy) / (target_energy + candidate_energy + 1e-6))


def _laplacian_energy(gray: np.ndarray) -> float:
    laplacian = cv2.Laplacian(gray, cv2.CV_32F, ksize=3)
    return float(np.var(laplacian) / (np.var(gray) + 1e-3))


def _color_histogram_distance(target_rgb: np.ndarray, candidate_rgb: np.ndarray) -> float:
    distances: list[float] = []
    for channel in range(3):
        target_hist = cv2.calcHist([(target_rgb[:, :, channel] * 255.0).astype(np.uint8)], [0], None, [32], [0, 256])
        candidate_hist = cv2.calcHist([(candidate_rgb[:, :, channel] * 255.0).astype(np.uint8)], [0], None, [32], [0, 256])
        cv2.normalize(target_hist, target_hist, alpha=1.0, norm_type=cv2.NORM_L1)
        cv2.normalize(candidate_hist, candidate_hist, alpha=1.0, norm_type=cv2.NORM_L1)
        distances.append(float(cv2.compareHist(target_hist, candidate_hist, cv2.HISTCMP_BHATTACHARYYA)))
    return _clamp01(float(np.mean(distances)))


def _temporal_distance(target_frames: list[np.ndarray], candidate_frames: list[np.ndarray]) -> float:
    if len(target_frames) < 2 or len(candidate_frames) < 2:
        return 0.0
    distances: list[float] = []
    for index in range(1, min(len(target_frames), len(candidate_frames))):
        target_delta = target_frames[index] - target_frames[index - 1]
        candidate_delta = candidate_frames[index] - candidate_frames[index - 1]
        distances.append(float(np.mean(np.abs(target_delta - candidate_delta))) / TEMPORAL_TOLERANCE)
    return _clamp01(float(np.mean(distances)))


def _relative_scalar_distance(left: float, right: float) -> float:
    scale = max(abs(left), abs(right), 1e-8)
    return _clamp01(abs(left - right) / scale)


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))
