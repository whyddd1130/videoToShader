from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

from .manifest import resolve_repo_path


def sample_frame_indices_for_video(video_path: Path, *, sample_fps: float) -> list[int]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    try:
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        native_fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    finally:
        cap.release()

    if total_frames <= 0:
        raise RuntimeError(f"Video has no readable frames: {video_path}")
    if native_fps <= 0:
        native_fps = 25.0

    duration_seconds = total_frames / native_fps
    if duration_seconds <= 0:
        return [0]

    step_seconds = 1.0 / sample_fps
    timestamps: list[float] = []
    current = 0.0
    while current < duration_seconds:
        timestamps.append(current)
        current += step_seconds

    indices = sorted(
        {
            min(total_frames - 1, max(0, int(round(timestamp * native_fps))))
            for timestamp in timestamps
        }
    )
    return indices or [0]


def sample_video_frames(video_path: Path, frame_indices: list[int]) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    frames: list[np.ndarray] = []
    last_frame: np.ndarray | None = None
    try:
        for frame_index in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame = cap.read()
            if not ok:
                if last_frame is None:
                    raise RuntimeError(f"Cannot read frame {frame_index} from {video_path}")
                frame = last_frame.copy()
            last_frame = frame
            frames.append(frame.copy())
    finally:
        cap.release()
    return frames


def load_reference_rgb_from_video(video_path: Path, image_size: int) -> np.ndarray:
    first_frame = sample_video_frames(video_path, [0])[0]
    frame_rgb = cv2.cvtColor(first_frame, cv2.COLOR_BGR2RGB)
    image = Image.fromarray(frame_rgb)
    image.thumbnail((image_size, image_size))
    return np.asarray(image)


def load_reference_rgb_from_image(image_path: Path, image_size: int) -> np.ndarray:
    image = Image.open(image_path).convert("RGB")
    image.thumbnail((image_size, image_size))
    return np.asarray(image)


def load_reference_rgb(sample: dict[str, Any], *, repo_root: Path, video_path: Path, image_size: int) -> np.ndarray:
    input_image = sample.get("input_image_path")
    if input_image:
        return load_reference_rgb_from_image(resolve_repo_path(repo_root, str(input_image)), image_size)
    return load_reference_rgb_from_video(video_path, image_size)


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def resize_frame_like_input(frame_bgr: np.ndarray, input_rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    frame_rgb = np.asarray(Image.fromarray(frame_rgb).resize((input_rgb.shape[1], input_rgb.shape[0])))
    frame_gray = cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2GRAY)
    return frame_rgb, frame_gray


def laplacian_energy(gray: np.ndarray) -> float:
    return float(cv2.Laplacian(gray, cv2.CV_32F).var())


def edge_density(gray: np.ndarray) -> float:
    return float(np.mean(cv2.Canny(gray, 100, 200) > 0))


def line_structure_profile(gray: np.ndarray) -> dict[str, float]:
    edges = cv2.Canny(gray, 80, 180)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180.0, threshold=18, minLineLength=max(8, gray.shape[1] // 10), maxLineGap=3)
    if lines is None:
        return {
            "horizontal_line_strength": 0.0,
            "vertical_line_strength": 0.0,
            "dominant_line_axis_ratio": 0.0,
            "line_elongation_strength": 0.0,
        }

    horizontal = 0.0
    vertical = 0.0
    diagonal = 0.0
    total = 0.0
    norm = float(max(gray.shape[0], gray.shape[1]))
    for line in lines[:, 0, :]:
        x1, y1, x2, y2 = [float(v) for v in line]
        dx = x2 - x1
        dy = y2 - y1
        length = float(np.hypot(dx, dy))
        if length <= 1e-6:
            continue
        total += length
        if abs(dx) >= abs(dy) * 1.5:
            horizontal += length
        elif abs(dy) >= abs(dx) * 1.5:
            vertical += length
        else:
            diagonal += length
    if total <= 1e-6:
        return {
            "horizontal_line_strength": 0.0,
            "vertical_line_strength": 0.0,
            "dominant_line_axis_ratio": 0.0,
            "line_elongation_strength": 0.0,
        }
    axis_total = horizontal + vertical + diagonal
    dominant_axis_ratio = abs(horizontal - vertical) / max(horizontal + vertical, 1e-6)
    return {
        "horizontal_line_strength": clamp01(horizontal / axis_total),
        "vertical_line_strength": clamp01(vertical / axis_total),
        "dominant_line_axis_ratio": clamp01(dominant_axis_ratio),
        "line_elongation_strength": clamp01((total / norm) / 40.0),
    }


def blockiness_score(gray: np.ndarray, block: int = 8) -> float:
    strengths = block_boundary_profile(gray, block=block)
    baseline = max(strengths["interior_strength"], 1e-6)
    return float((strengths["vertical_boundary_strength"] + strengths["horizontal_boundary_strength"]) / baseline)


def block_boundary_profile(gray: np.ndarray, block: int = 8) -> dict[str, float]:
    if gray.shape[0] < block * 2 or gray.shape[1] < block * 2:
        return {
            "vertical_boundary_strength": 0.0,
            "horizontal_boundary_strength": 0.0,
            "interior_strength": 1e-6,
        }
    vertical_boundary = np.abs(np.diff(gray[:, block - 1 :: block].astype(np.float32), axis=1)).mean() if gray.shape[1] > block else 0.0
    horizontal_boundary = np.abs(np.diff(gray[block - 1 :: block, :].astype(np.float32), axis=0)).mean() if gray.shape[0] > block else 0.0
    interior_vertical = np.abs(np.diff(gray.astype(np.float32), axis=1)).mean()
    interior_horizontal = np.abs(np.diff(gray.astype(np.float32), axis=0)).mean()
    return {
        "vertical_boundary_strength": float(vertical_boundary),
        "horizontal_boundary_strength": float(horizontal_boundary),
        "interior_strength": float(interior_vertical + interior_horizontal),
    }


def band_orientation_profile(gray: np.ndarray) -> dict[str, float]:
    row_profile = np.mean(gray.astype(np.float32), axis=1)
    col_profile = np.mean(gray.astype(np.float32), axis=0)
    row_variation = float(np.mean(np.abs(np.diff(row_profile)))) if row_profile.size > 1 else 0.0
    col_variation = float(np.mean(np.abs(np.diff(col_profile)))) if col_profile.size > 1 else 0.0
    if row_variation + col_variation <= 1e-6:
        boundary = block_boundary_profile(gray)
        row_variation = boundary["horizontal_boundary_strength"]
        col_variation = boundary["vertical_boundary_strength"]
    total = row_variation + col_variation
    if total <= 1e-6:
        return {
            "horizontal_band_strength": 0.0,
            "vertical_band_strength": 0.0,
            "grid_balance": 0.0,
            "bandedness": 0.0,
        }
    horizontal_band_strength = row_variation / total
    vertical_band_strength = col_variation / total
    grid_balance = 1.0 - abs(horizontal_band_strength - vertical_band_strength)
    bandedness = clamp01(total / 24.0)
    return {
        "horizontal_band_strength": clamp01(horizontal_band_strength),
        "vertical_band_strength": clamp01(vertical_band_strength),
        "grid_balance": clamp01(grid_balance),
        "bandedness": bandedness,
    }


def grid_tiling_score(gray: np.ndarray) -> float:
    boundary = block_boundary_profile(gray)
    total_boundary = boundary["vertical_boundary_strength"] + boundary["horizontal_boundary_strength"]
    if total_boundary <= 1e-6:
        return 0.0
    balance = 1.0 - abs(boundary["vertical_boundary_strength"] - boundary["horizontal_boundary_strength"]) / total_boundary
    boundary_vs_interior = total_boundary / max(boundary["interior_strength"], 1e-6)
    return clamp01(balance * clamp01(boundary_vs_interior / 1.5))


def distortion_score(input_gray: np.ndarray, frame_gray: np.ndarray) -> float:
    flow = cv2.calcOpticalFlowFarneback(input_gray, frame_gray, None, 0.5, 3, 15, 3, 5, 1.2, 0)
    magnitude = np.linalg.norm(flow, axis=2)
    return clamp01(float(np.mean(magnitude)) / 12.0)


def directional_motion_profile(reference_gray: np.ndarray, frame_gray: np.ndarray) -> dict[str, float]:
    flow = cv2.calcOpticalFlowFarneback(reference_gray, frame_gray, None, 0.5, 3, 15, 3, 5, 1.2, 0)
    x_motion = clamp01(float(np.mean(np.abs(flow[:, :, 0]))) / 8.0)
    y_motion = clamp01(float(np.mean(np.abs(flow[:, :, 1]))) / 8.0)
    dominant_axis_ratio = clamp01(abs(x_motion - y_motion) / max(x_motion + y_motion, 1e-6))
    return {
        "jitter_x": x_motion,
        "jitter_y": y_motion,
        "dominant_motion_axis_ratio": dominant_axis_ratio,
    }


def directional_blur_profile(reference_gray: np.ndarray, frame_gray: np.ndarray) -> dict[str, float]:
    """Estimate the *sampling* axis of a directional blur.

    A blur along X mainly weakens X gradients (the gradients of vertical
    edges), while the visible residual bands themselves can still be vertical.
    This intentionally measures gradient attenuation rather than line
    orientation or optical-flow direction, which are both ambiguous for a
    multi-sample/max-filter effect.
    """
    def gradient_energy(gray: np.ndarray, dx: int, dy: int) -> float:
        gradient = cv2.Sobel(gray, cv2.CV_32F, dx, dy, ksize=3)
        return float(np.mean(np.abs(gradient)))

    ref_x = gradient_energy(reference_gray, 1, 0)
    ref_y = gradient_energy(reference_gray, 0, 1)
    frame_x = gradient_energy(frame_gray, 1, 0)
    frame_y = gradient_energy(frame_gray, 0, 1)
    blur_x = clamp01(max(0.0, 1.0 - frame_x / max(ref_x, 1e-6)))
    blur_y = clamp01(max(0.0, 1.0 - frame_y / max(ref_y, 1e-6)))
    confidence = clamp01(abs(blur_x - blur_y) / max(blur_x + blur_y, 1e-6))
    return {
        "sampling_blur_x": blur_x,
        "sampling_blur_y": blur_y,
        "sampling_axis_confidence": confidence,
    }


def change_localization_score(input_rgb: np.ndarray, frame_rgb: np.ndarray) -> float:
    diff_map = np.mean(np.abs(frame_rgb.astype(np.float32) - input_rgb.astype(np.float32)), axis=2) / 255.0
    flat = np.sort(diff_map.reshape(-1))
    if flat.size == 0:
        return 0.0
    total = float(np.sum(flat))
    if total <= 1e-8:
        return 0.0
    top_count = max(1, int(flat.size * 0.2))
    top_share = float(np.sum(flat[-top_count:])) / total
    return clamp01((top_share - 0.2) / 0.8)


def extract_visual_profile(
    sample: dict[str, Any],
    *,
    repo_root: Path,
    frame_indices: list[int],
    image_size: int,
) -> dict[str, float]:
    video_path = resolve_repo_path(repo_root, sample["video_path"])
    input_rgb = load_reference_rgb(sample, repo_root=repo_root, video_path=video_path, image_size=image_size)
    input_gray = cv2.cvtColor(input_rgb, cv2.COLOR_RGB2GRAY)
    input_brightness = float(np.mean(input_gray) / 255.0)
    input_contrast = float(np.std(input_gray) / 255.0)
    input_laplacian = laplacian_energy(input_gray)
    input_edges = edge_density(input_gray)
    input_blockiness = blockiness_score(input_gray)

    frames_bgr = sample_video_frames(video_path, frame_indices)
    brightness_changes: list[float] = []
    contrast_changes: list[float] = []
    color_shifts: list[float] = []
    blur_changes: list[float] = []
    edge_changes: list[float] = []
    pixelation_changes: list[float] = []
    distortion_changes: list[float] = []
    localization_changes: list[float] = []
    motion_changes: list[float] = []
    horizontal_band_changes: list[float] = []
    vertical_band_changes: list[float] = []
    grid_tiling_changes: list[float] = []
    horizontal_line_changes: list[float] = []
    vertical_line_changes: list[float] = []
    dominant_line_axis_changes: list[float] = []
    line_elongation_changes: list[float] = []
    jitter_x_changes: list[float] = []
    jitter_y_changes: list[float] = []
    dominant_motion_axis_changes: list[float] = []
    sampling_blur_x_changes: list[float] = []
    sampling_blur_y_changes: list[float] = []
    horizontal_flip_advantages: list[float] = []
    vertical_flip_advantages: list[float] = []
    prev_gray: np.ndarray | None = None
    flip_x_rgb = input_rgb[:, ::-1, :]
    flip_y_rgb = input_rgb[::-1, :, :]

    for frame_bgr in frames_bgr:
        frame_rgb, frame_gray = resize_frame_like_input(frame_bgr, input_rgb)
        brightness = float(np.mean(frame_gray) / 255.0)
        contrast = float(np.std(frame_gray) / 255.0)
        color_shift = float(np.mean(np.abs(frame_rgb.astype(np.float32) - input_rgb.astype(np.float32))) / 255.0)
        frame_laplacian = laplacian_energy(frame_gray)
        frame_edges = edge_density(frame_gray)
        frame_blockiness = blockiness_score(frame_gray)
        band_profile = band_orientation_profile(frame_gray)
        line_profile = line_structure_profile(frame_gray)
        motion_profile = directional_motion_profile(input_gray, frame_gray)
        blur_profile = directional_blur_profile(input_gray, frame_gray)
        diff_to_input = float(np.mean(np.abs(frame_rgb.astype(np.float32) - input_rgb.astype(np.float32))) / 255.0)
        diff_to_flip_x = float(np.mean(np.abs(frame_rgb.astype(np.float32) - flip_x_rgb.astype(np.float32))) / 255.0)
        diff_to_flip_y = float(np.mean(np.abs(frame_rgb.astype(np.float32) - flip_y_rgb.astype(np.float32))) / 255.0)

        brightness_changes.append(abs(brightness - input_brightness))
        contrast_changes.append(abs(contrast - input_contrast) * 2.0)
        color_shifts.append(color_shift)
        blur_changes.append(clamp01(max(0.0, (input_laplacian - frame_laplacian) / max(input_laplacian, 1e-6))))
        edge_changes.append(abs(frame_edges - input_edges) * 4.0)
        pixelation_changes.append(clamp01(max(0.0, frame_blockiness - input_blockiness) / 1.5))
        distortion_changes.append(distortion_score(input_gray, frame_gray))
        localization_changes.append(change_localization_score(input_rgb, frame_rgb))
        horizontal_band_changes.append(band_profile["horizontal_band_strength"])
        vertical_band_changes.append(band_profile["vertical_band_strength"])
        grid_tiling_changes.append(grid_tiling_score(frame_gray))
        horizontal_line_changes.append(line_profile["horizontal_line_strength"])
        vertical_line_changes.append(line_profile["vertical_line_strength"])
        dominant_line_axis_changes.append(line_profile["dominant_line_axis_ratio"])
        line_elongation_changes.append(line_profile["line_elongation_strength"])
        jitter_x_changes.append(motion_profile["jitter_x"])
        jitter_y_changes.append(motion_profile["jitter_y"])
        dominant_motion_axis_changes.append(motion_profile["dominant_motion_axis_ratio"])
        sampling_blur_x_changes.append(blur_profile["sampling_blur_x"])
        sampling_blur_y_changes.append(blur_profile["sampling_blur_y"])
        horizontal_flip_advantages.append(clamp01(diff_to_input - diff_to_flip_x))
        vertical_flip_advantages.append(clamp01(diff_to_input - diff_to_flip_y))

        if prev_gray is not None:
            motion_changes.append(float(np.mean(np.abs(frame_gray.astype(np.float32) - prev_gray.astype(np.float32))) / 255.0))
        prev_gray = frame_gray

    # Use an upper quantile: a periodic blur is only strongly visible in some
    # frames, and averaging it with its clear phases hides the axis evidence.
    sampling_blur_x = float(np.percentile(sampling_blur_x_changes, 75)) if sampling_blur_x_changes else 0.0
    sampling_blur_y = float(np.percentile(sampling_blur_y_changes, 75)) if sampling_blur_y_changes else 0.0
    sampling_axis_confidence = clamp01(
        abs(sampling_blur_x - sampling_blur_y) / max(sampling_blur_x + sampling_blur_y, 1e-6)
    )

    return {
        "color_shift": clamp01(float(np.mean(color_shifts)) if color_shifts else 0.0),
        "brightness_change": clamp01(float(np.mean(brightness_changes)) if brightness_changes else 0.0),
        "contrast_change": clamp01(float(np.mean(contrast_changes)) if contrast_changes else 0.0),
        "blur_strength": clamp01(float(np.mean(blur_changes)) if blur_changes else 0.0),
        "distortion_strength": clamp01(float(np.mean(distortion_changes)) if distortion_changes else 0.0),
        "pixelation_strength": clamp01(float(np.mean(pixelation_changes)) if pixelation_changes else 0.0),
        "edge_emphasis": clamp01(float(np.mean(edge_changes)) if edge_changes else 0.0),
        "mask_dependency": clamp01(float(np.mean(localization_changes)) if localization_changes else 0.0),
        "motion_intensity": clamp01(float(np.mean(motion_changes)) * 2.5 if motion_changes else 0.0),
        "horizontal_band_strength": clamp01(float(np.mean(horizontal_band_changes)) if horizontal_band_changes else 0.0),
        "vertical_band_strength": clamp01(float(np.mean(vertical_band_changes)) if vertical_band_changes else 0.0),
        "grid_tiling_strength": clamp01(float(np.mean(grid_tiling_changes)) if grid_tiling_changes else 0.0),
        "horizontal_line_strength": clamp01(float(np.mean(horizontal_line_changes)) if horizontal_line_changes else 0.0),
        "vertical_line_strength": clamp01(float(np.mean(vertical_line_changes)) if vertical_line_changes else 0.0),
        "dominant_line_axis_ratio": clamp01(float(np.mean(dominant_line_axis_changes)) if dominant_line_axis_changes else 0.0),
        "line_elongation_strength": clamp01(float(np.mean(line_elongation_changes)) if line_elongation_changes else 0.0),
        "jitter_x": clamp01(float(np.mean(jitter_x_changes)) if jitter_x_changes else 0.0),
        "jitter_y": clamp01(float(np.mean(jitter_y_changes)) if jitter_y_changes else 0.0),
        "dominant_motion_axis_ratio": clamp01(float(np.mean(dominant_motion_axis_changes)) if dominant_motion_axis_changes else 0.0),
        "sampling_blur_x": clamp01(sampling_blur_x),
        "sampling_blur_y": clamp01(sampling_blur_y),
        "sampling_axis_confidence": sampling_axis_confidence,
        "horizontal_flip_match": clamp01(float(np.max(horizontal_flip_advantages)) if horizontal_flip_advantages else 0.0),
        "vertical_flip_match": clamp01(float(np.max(vertical_flip_advantages)) if vertical_flip_advantages else 0.0),
        "final_horizontal_flip_match": clamp01(float(horizontal_flip_advantages[-1]) if horizontal_flip_advantages else 0.0),
        "final_vertical_flip_match": clamp01(float(vertical_flip_advantages[-1]) if vertical_flip_advantages else 0.0),
    }


def build_visual_observation_data(
    sample: dict[str, Any],
    *,
    repo_root: Path,
    frame_indices: list[int],
    image_size: int,
) -> dict[str, Any]:
    video_path = resolve_repo_path(repo_root, sample["video_path"])
    input_rgb = load_reference_rgb(sample, repo_root=repo_root, video_path=video_path, image_size=image_size)
    input_gray = cv2.cvtColor(input_rgb, cv2.COLOR_RGB2GRAY)
    frames_bgr = sample_video_frames(video_path, frame_indices)
    visual_profile = extract_visual_profile(sample, repo_root=repo_root, frame_indices=frame_indices, image_size=image_size)

    frame_stats: list[dict[str, Any]] = []
    prev_gray: np.ndarray | None = None
    diff_series: list[float] = []
    motion_series: list[float] = []
    for frame_index, frame_bgr in zip(frame_indices, frames_bgr):
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        frame_rgb = np.asarray(Image.fromarray(frame_rgb).resize((input_rgb.shape[1], input_rgb.shape[0])))
        frame_gray = cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2GRAY)
        diff_to_input = np.mean(np.abs(frame_rgb.astype(np.float32) - input_rgb.astype(np.float32))) / 255.0
        diff_series.append(float(diff_to_input))
        motion = 0.0
        if prev_gray is not None:
            motion = float(np.mean(np.abs(frame_gray.astype(np.float32) - prev_gray.astype(np.float32))) / 255.0)
            motion_series.append(motion)
        edges = cv2.Canny(frame_gray, 100, 200)
        band_profile = band_orientation_profile(frame_gray)
        line_profile = line_structure_profile(frame_gray)
        motion_profile = directional_motion_profile(input_gray, frame_gray)
        blur_profile = directional_blur_profile(input_gray, frame_gray)
        frame_stats.append(
            {
                "frame_index": frame_index,
                "mean_rgb": [round(float(x), 4) for x in np.mean(frame_rgb, axis=(0, 1)) / 255.0],
                "brightness_mean": round(float(np.mean(frame_gray) / 255.0), 4),
                "brightness_std": round(float(np.std(frame_gray) / 255.0), 4),
                "edge_density": round(float(np.mean(edges > 0)), 4),
                "diff_to_input": round(float(diff_to_input), 4),
                "diff_to_prev": round(float(motion), 4),
                "horizontal_band_strength": round(band_profile["horizontal_band_strength"], 4),
                "vertical_band_strength": round(band_profile["vertical_band_strength"], 4),
                "grid_tiling_strength": round(grid_tiling_score(frame_gray), 4),
                "horizontal_line_strength": round(line_profile["horizontal_line_strength"], 4),
                "vertical_line_strength": round(line_profile["vertical_line_strength"], 4),
                "dominant_line_axis_ratio": round(line_profile["dominant_line_axis_ratio"], 4),
                "line_elongation_strength": round(line_profile["line_elongation_strength"], 4),
                "jitter_x": round(motion_profile["jitter_x"], 4),
                "jitter_y": round(motion_profile["jitter_y"], 4),
                "sampling_blur_x": round(blur_profile["sampling_blur_x"], 4),
                "sampling_blur_y": round(blur_profile["sampling_blur_y"], 4),
            }
        )
        prev_gray = frame_gray

    monotonic_increase = all(b >= a for a, b in zip(diff_series, diff_series[1:])) if len(diff_series) > 1 else True
    monotonic_decrease = all(b <= a for a, b in zip(diff_series, diff_series[1:])) if len(diff_series) > 1 else True
    shape_bias_hint = "ambiguous"
    if (
        visual_profile["dominant_line_axis_ratio"] >= 0.28
        and max(visual_profile["horizontal_line_strength"], visual_profile["vertical_line_strength"]) >= 0.45
    ):
        shape_bias_hint = "line_band_likely"
    elif (
        visual_profile["grid_tiling_strength"] >= 0.75
        and visual_profile["dominant_line_axis_ratio"] < 0.2
    ):
        shape_bias_hint = "grid_tile_likely"

    motion_bias_hint = "ambiguous"
    if visual_profile["dominant_motion_axis_ratio"] >= 0.25 and max(visual_profile["jitter_x"], visual_profile["jitter_y"]) >= 0.04:
        motion_bias_hint = "directional_jitter_likely"
    elif visual_profile["motion_intensity"] >= 0.08 and visual_profile["dominant_motion_axis_ratio"] < 0.15:
        motion_bias_hint = "non_directional_motion_likely"

    transform_bias_hint = "ambiguous"
    if visual_profile.get("final_horizontal_flip_match", 0.0) >= 0.08 or visual_profile.get("horizontal_flip_match", 0.0) >= 0.14:
        transform_bias_hint = "horizontal_flip_likely"
    elif visual_profile.get("final_vertical_flip_match", 0.0) >= 0.08 or visual_profile.get("vertical_flip_match", 0.0) >= 0.14:
        transform_bias_hint = "vertical_flip_likely"

    sampling_axis_hint = "ambiguous"
    if visual_profile["sampling_axis_confidence"] >= 0.20 and max(
        visual_profile["sampling_blur_x"], visual_profile["sampling_blur_y"]
    ) >= 0.08:
        sampling_axis_hint = "x" if visual_profile["sampling_blur_x"] > visual_profile["sampling_blur_y"] else "y"

    return {
        "sample_id": sample["sample_id"],
        "effect_name_hidden": "unknown",
        "input_variant": sample.get("input_variant", ""),
        "input_image_path": sample.get("input_image_path", ""),
        "frame_indices": frame_indices,
        "reference_frame_stats": {
            "mean_rgb": [round(float(x), 4) for x in np.mean(input_rgb, axis=(0, 1)) / 255.0],
            "brightness_mean": round(float(np.mean(input_gray) / 255.0), 4),
            "brightness_std": round(float(np.std(input_gray) / 255.0), 4),
        },
        "frame_stats": frame_stats,
        "aggregate": {
            "mean_diff_to_reference": round(float(np.mean(diff_series)) if diff_series else 0.0, 4),
            "max_diff_to_reference": round(float(np.max(diff_series)) if diff_series else 0.0, 4),
            "mean_motion_between_frames": round(float(np.mean(motion_series)) if motion_series else 0.0, 4),
            "monotonic_increase_in_difference": monotonic_increase,
            "monotonic_decrease_in_difference": monotonic_decrease,
            "shape_bias_hint": shape_bias_hint,
            "motion_bias_hint": motion_bias_hint,
            "transform_bias_hint": transform_bias_hint,
            "sampling_axis_hint": sampling_axis_hint,
        },
        "estimated_effect_profile": {key: round(value, 4) for key, value in visual_profile.items()},
    }


def build_visual_observation_prompt(
    sample: dict[str, Any],
    *,
    repo_root: Path,
    frame_indices: list[int],
    image_size: int,
) -> str:
    observation = build_visual_observation_data(sample, repo_root=repo_root, frame_indices=frame_indices, image_size=image_size)
    proxy_mode = sample.get("input_variant") == "estimated_proxy_image_and_video"
    reference_description = (
        "estimated proxy image" if proxy_mode else "provided input image" if sample.get("input_image_path") else "reference first frame"
    )
    proxy_instruction = (
        "This proxy is not a ground-truth source image: frame-to-proxy differences can include source reconstruction error. "
        "Prioritize frame-to-frame temporal evidence and report transferable transformation behavior rather than scene content.\n"
        if proxy_mode
        else ""
    )
    return (
        f"Infer the visual effect by comparing video frames against the {reference_description}.\n"
        f"{proxy_instruction}"
        "The vision endpoint is unavailable, so you must infer the effect from structured visual observations extracted "
        f"from the {reference_description} and rendered video frames. Treat these observations as evidence of blur, distortion, "
        "pixelation, color change, edge emphasis, masking, compositing, geometry change, particles, and temporal pattern.\n"
        "Prioritize the estimated_effect_profile and frame-to-reference deltas over any guess about scene semantics.\n"
        f"observations:\n{json.dumps(observation, ensure_ascii=False, indent=2)}\n"
        "Return only plain text, 3-6 short lines, with no JSON and no markdown table.\n"
    )
