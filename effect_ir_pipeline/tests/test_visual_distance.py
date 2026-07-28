from __future__ import annotations

import math
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.visual_distance import compare_video_visual_distance


def _write_video(path: Path, frames: list[np.ndarray], *, fps: float = 12.0) -> None:
    height, width = frames[0].shape[:2]
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), fps, (width, height))
    if not writer.isOpened():
        raise RuntimeError("OpenCV could not open MJPG VideoWriter")
    try:
        for frame_rgb in frames:
            writer.write(cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2BGR))
    finally:
        writer.release()


def _base_frames(count: int = 12, size: int = 64) -> list[np.ndarray]:
    x = np.linspace(0, 255, size, dtype=np.uint8)
    y = np.linspace(0, 255, size, dtype=np.uint8)
    grid_x, grid_y = np.meshgrid(x, y)
    frames: list[np.ndarray] = []
    for index in range(count):
        frame = np.stack(
            [
                (grid_x + index * 7).astype(np.uint8),
                grid_y,
                ((grid_x // 2 + grid_y // 2 + index * 11) % 256).astype(np.uint8),
            ],
            axis=2,
        )
        center = (12 + index * 3, 32)
        cv2.circle(frame, center, 8, (255, 40, 30), -1)
        frames.append(frame)
    return frames


def _brightness(frames: list[np.ndarray], amount: int) -> list[np.ndarray]:
    return [np.clip(frame.astype(np.int16) + amount, 0, 255).astype(np.uint8) for frame in frames]


def _blur(frames: list[np.ndarray], kernel_size: int) -> list[np.ndarray]:
    return [cv2.GaussianBlur(frame, (kernel_size, kernel_size), 0) for frame in frames]


def _shift(frames: list[np.ndarray], pixels: int) -> list[np.ndarray]:
    return [np.roll(frame, shift=pixels, axis=1) for frame in frames]


class VisualDistanceTest(unittest.TestCase):
    def test_same_video_has_zero_distance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "base.avi"
            _write_video(video, _base_frames())

            result = compare_video_visual_distance(video, video, sample_fps=2.0, image_size=64, max_frames=8)

        self.assertLessEqual(result["overall"], 1e-8)
        self.assertEqual(result["distance_mode"], "direct_visual")
        self.assertGreater(result["sample_count"], 0)
        self._assert_bounded_numbers(result)

    def test_common_visual_perturbations_are_detected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base_frames = _base_frames()
            base = Path(tmp) / "base.avi"
            bright_small = Path(tmp) / "bright_small.avi"
            bright_large = Path(tmp) / "bright_large.avi"
            blur_large = Path(tmp) / "blur_large.avi"
            shift_large = Path(tmp) / "shift_large.avi"
            _write_video(base, base_frames)
            _write_video(bright_small, _brightness(base_frames, 5))
            _write_video(bright_large, _brightness(base_frames, 20))
            _write_video(blur_large, _blur(base_frames, 11))
            _write_video(shift_large, _shift(base_frames, 5))

            small_brightness = compare_video_visual_distance(base, bright_small, image_size=64, max_frames=8)["overall"]
            large_brightness = compare_video_visual_distance(base, bright_large, image_size=64, max_frames=8)["overall"]
            large_blur = compare_video_visual_distance(base, blur_large, image_size=64, max_frames=8)["overall"]
            large_shift = compare_video_visual_distance(base, shift_large, image_size=64, max_frames=8)["overall"]

        self.assertLess(small_brightness, large_brightness)
        self.assertGreater(large_brightness, 0.04)
        self.assertGreater(large_blur, 0.04)
        self.assertGreater(large_shift, 0.04)

    def test_repository_sample_videos_are_farther_than_threshold_when_present(self) -> None:
        test1 = Path("test_videos/test1.mp4")
        test2 = Path("test_videos/test2.mp4")
        if not test1.exists() or not test2.exists():
            self.skipTest("repository sample videos are not present")

        result = compare_video_visual_distance(test2, test1, sample_fps=2.0, image_size=128, max_frames=8)

        self.assertGreater(result["overall"], 0.2)
        self._assert_bounded_numbers(result)

    def _assert_bounded_numbers(self, value: object) -> None:
        if isinstance(value, dict):
            for item in value.values():
                self._assert_bounded_numbers(item)
        elif isinstance(value, list):
            for item in value:
                self._assert_bounded_numbers(item)
        elif isinstance(value, float):
            self.assertTrue(math.isfinite(value))
            if value != int(value):
                self.assertGreaterEqual(value, 0.0)
                self.assertLessEqual(value, 1.0)


if __name__ == "__main__":
    unittest.main()
