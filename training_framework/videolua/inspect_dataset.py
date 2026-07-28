from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from .config import load_config
from .manifest import load_manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("config.yaml"))
    args = parser.parse_args()

    cfg = load_config(args.config)
    base_dir = args.config.parent
    dataset_root = (base_dir / cfg["dataset_root"]).resolve()
    manifest_path = (base_dir / cfg["manifest_path"]).resolve()
    records = load_manifest(dataset_root, manifest_path)

    effect_counts = Counter(record.effect_name for record in records)
    variant_counts = Counter(record.input_variant for record in records)
    lua_file_counts = Counter(len(list(record.code_dir.glob("*.lua"))) for record in records)

    report = {
        "dataset_root": str(dataset_root),
        "records": len(records),
        "effects": len(effect_counts),
        "input_variants": dict(sorted(variant_counts.items())),
        "lua_file_count_distribution": dict(sorted(lua_file_counts.items())),
        "first_records": [
            {
                "sample_id": record.sample_id,
                "effect_name": record.effect_name,
                "video_path": str(record.video_path),
                "param_path": str(record.param_path),
                "code_dir": str(record.code_dir),
            }
            for record in records[:5]
        ],
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
