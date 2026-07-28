from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class SampleRecord:
    sample_id: str
    effect_name: str
    input_variant: str
    video_path: Path
    param_path: Path
    code_dir: Path
    input_image_path: Path | None


def resolve_dataset_path(dataset_root: Path, path_value: str) -> Path:
    path = Path(path_value)
    if path.is_absolute():
        return path
    parts = path.parts
    root_name = dataset_root.name
    if root_name in parts:
        idx = parts.index(root_name)
        suffix = Path(*parts[idx + 1 :])
        return dataset_root / suffix
    return dataset_root / path


def load_manifest(dataset_root: Path, manifest_path: Path) -> list[SampleRecord]:
    records: list[SampleRecord] = []
    with manifest_path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            row: dict[str, Any] = json.loads(line)
            if row.get("status") != "rendered":
                continue
            input_image_raw = row.get("input_image_path", "")
            input_image_path = resolve_dataset_path(dataset_root, input_image_raw) if input_image_raw else None
            records.append(
                SampleRecord(
                    sample_id=row["sample_id"],
                    effect_name=row["effect_name"],
                    input_variant=row["input_variant"],
                    video_path=resolve_dataset_path(dataset_root, row["video_path"]),
                    param_path=resolve_dataset_path(dataset_root, row["param_metadata_path"]),
                    code_dir=resolve_dataset_path(dataset_root, row["copied_code_dir"]),
                    input_image_path=input_image_path,
                )
            )
    return records


def split_records(
    records: list[SampleRecord],
    train_ratio: float,
    val_ratio: float,
    seed: int,
) -> tuple[list[SampleRecord], list[SampleRecord], list[SampleRecord]]:
    shuffled = list(records)
    random.Random(seed).shuffle(shuffled)
    n = len(shuffled)
    train_end = int(n * train_ratio)
    val_end = train_end + int(n * val_ratio)
    return shuffled[:train_end], shuffled[train_end:val_end], shuffled[val_end:]

