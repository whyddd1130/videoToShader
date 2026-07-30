from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.llm_adapter import generate_video_structured_ir_prompt
from effect_ir_pipeline.effect_ir.video_only_input import estimate_proxy_input_from_video


def _write_video(path: Path, frames: list[np.ndarray]) -> None:
    height, width = frames[0].shape[:2]
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), 12.0, (width, height))
    if not writer.isOpened():
        raise RuntimeError("OpenCV could not open the test video writer")
    try:
        for frame in frames:
            writer.write(frame)
    finally:
        writer.release()


class VideoOnlyInputTest(unittest.TestCase):
    def test_estimates_proxy_and_uncertainty_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            video = root / "target.avi"
            base = np.zeros((48, 64, 3), dtype=np.uint8)
            base[:, :32] = (30, 120, 210)
            base[:, 32:] = (180, 60, 40)
            frames = [np.zeros_like(base), base, base.copy(), cv2.GaussianBlur(base, (9, 9), 0), base.copy()]
            _write_video(video, frames)

            result = estimate_proxy_input_from_video(video, output_dir=root / "proxy", sample_count=5)

            proxy = cv2.imread(result["proxy_image_path"])
            uncertainty = cv2.imread(result["uncertainty_mask_path"], cv2.IMREAD_GRAYSCALE)
            self.assertIsNotNone(proxy)
            self.assertIsNotNone(uncertainty)
            self.assertGreater(float(proxy.mean()), 20.0)
            self.assertEqual(proxy.shape[:2], uncertainty.shape[:2])
            self.assertEqual(len(result["selection"]), 5)
            self.assertTrue(Path(result["metadata_path"]).exists())

    def test_proxy_mode_prompt_does_not_claim_ground_truth_source(self) -> None:
        prompt = generate_video_structured_ir_prompt({
            "sample_id": "blind-video",
            "input_variant": "estimated_proxy_image_and_video",
        })
        self.assertIn("estimated proxy", prompt)
        self.assertIn("not ground truth", prompt)


if __name__ == "__main__":
    unittest.main()
