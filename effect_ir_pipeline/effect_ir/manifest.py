from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_rendered_rows(manifest_path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with manifest_path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get("status") == "rendered":
                rows.append(row)
    return rows


def resolve_repo_path(repo_root: Path, path_value: str) -> Path:
    path = Path(path_value)
    if path.is_absolute():
        return path
    marker = Path("datasets/effect_training/single_shader_multi")
    text = path.as_posix()
    marker_text = marker.as_posix()
    if text.startswith(marker_text + "/"):
        suffix = text[len(marker_text) + 1 :]
        direct = repo_root / suffix
        if direct.exists():
            return direct
    return repo_root / path


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows
