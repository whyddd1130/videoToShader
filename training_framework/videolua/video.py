from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image


def _resize_rgb(image: np.ndarray, image_size: int) -> torch.Tensor:
    image = cv2.resize(image, (image_size, image_size), interpolation=cv2.INTER_AREA)
    image = image.astype("float32") / 255.0
    image = np.transpose(image, (2, 0, 1))
    return torch.from_numpy(image)


def load_video_frames(video_path: Path, frame_indices: list[int], image_size: int) -> torch.Tensor:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")

    frames: list[torch.Tensor] = []
    last_frame: torch.Tensor | None = None
    for frame_index in frame_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok:
            if last_frame is None:
                raise RuntimeError(f"Cannot read frame {frame_index} from {video_path}")
            frames.append(last_frame.clone())
            continue
        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        tensor = _resize_rgb(frame, image_size)
        frames.append(tensor)
        last_frame = tensor
    cap.release()
    return torch.stack(frames, dim=0)


def load_input_image(image_path: Path | None, image_size: int) -> torch.Tensor:
    if image_path is None or not image_path.exists():
        return torch.zeros(3, image_size, image_size)
    image = Image.open(image_path).convert("RGB")
    image = image.resize((image_size, image_size), Image.Resampling.BICUBIC)
    arr = np.asarray(image).astype("float32") / 255.0
    arr = np.transpose(arr, (2, 0, 1))
    return torch.from_numpy(arr)

