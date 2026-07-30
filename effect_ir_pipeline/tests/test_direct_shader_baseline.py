from __future__ import annotations

import base64
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.direct_shader_baseline import build_direct_shader_baseline_content


def _write_video(path: Path, frames: list[np.ndarray]) -> None:
    height, width = frames[0].shape[:2]
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), 10.0, (width, height))
    if not writer.isOpened():
        raise RuntimeError("OpenCV could not open the test video writer")
    try:
        for frame in frames:
            writer.write(frame)
    finally:
        writer.release()


class DirectShaderBaselineTest(unittest.TestCase):
    def test_prompt_contains_only_source_and_target_visual_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            image_path = root / "input.png"
            video_path = root / "target.avi"
            source = np.full((32, 48, 3), (40, 120, 220), dtype=np.uint8)
            cv2.imwrite(str(image_path), source)
            _write_video(video_path, [np.roll(source, index * 2, axis=1) for index in range(5)])

            content, indices = build_direct_shader_baseline_content(
                input_image=image_path,
                target_video=video_path,
                image_size=48,
            )

            self.assertEqual(len(content), 3)
            self.assertEqual(content[0]["type"], "text")
            self.assertIn("Do not use library references, IR, edit plans", content[0]["text"])
            self.assertEqual(len(indices), 5)
            for item in content[1:]:
                self.assertTrue(item["image_url"]["url"].startswith("data:image/jpeg;base64,"))
                base64.b64decode(item["image_url"]["url"].split(",", 1)[1])


if __name__ == "__main__":
    unittest.main()
