from __future__ import annotations

from typing import Any

import torch
from torch.utils.data import Dataset

from .manifest import SampleRecord, load_manifest, split_records
from .text import format_param_description, load_json, read_lua_target
from .video import load_input_image, load_video_frames


class VideoLuaDataset(Dataset):
    def __init__(
        self,
        records: list[SampleRecord],
        label_to_id: dict[str, int],
        frame_indices: list[int],
        image_size: int,
        max_param_text_chars: int,
        max_lua_chars: int,
        load_pixels: bool = True,
    ) -> None:
        self.records = records
        self.label_to_id = label_to_id
        self.frame_indices = frame_indices
        self.image_size = image_size
        self.max_param_text_chars = max_param_text_chars
        self.max_lua_chars = max_lua_chars
        self.load_pixels = load_pixels

    def __len__(self) -> int:
        return len(self.records)

    def __getitem__(self, index: int) -> dict[str, Any]:
        record = self.records[index]
        param_json = load_json(record.param_path)
        item: dict[str, Any] = {
            "sample_id": record.sample_id,
            "effect_name": record.effect_name,
            "label": self.label_to_id[record.effect_name],
            "input_variant": record.input_variant,
            "video_path": str(record.video_path),
            "input_image_path": str(record.input_image_path) if record.input_image_path else "",
            "param_text": format_param_description(param_json, self.max_param_text_chars),
            "lua_target": read_lua_target(record.code_dir, self.max_lua_chars),
        }
        if self.load_pixels:
            item["video_frames"] = load_video_frames(record.video_path, self.frame_indices, self.image_size)
            item["input_image"] = load_input_image(record.input_image_path, self.image_size)
        return item


def collate_classification(batch: list[dict[str, Any]]) -> dict[str, Any]:
    labels = torch.tensor([item["label"] for item in batch], dtype=torch.long)
    result = {
        "labels": labels,
        "sample_id": [item["sample_id"] for item in batch],
        "effect_name": [item["effect_name"] for item in batch],
        "param_text": [item["param_text"] for item in batch],
    }
    if "video_frames" in batch[0]:
        result["video_frames"] = torch.stack([item["video_frames"] for item in batch], dim=0)
        result["input_image"] = torch.stack([item["input_image"] for item in batch], dim=0)
    return result
