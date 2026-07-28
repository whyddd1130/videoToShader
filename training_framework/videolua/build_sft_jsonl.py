from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from tqdm import tqdm
except ModuleNotFoundError:
    def tqdm(iterable, **kwargs):
        return iterable

from .config import load_config
from .manifest import load_manifest
from .text import build_generation_prompt, format_param_description, load_json, read_lua_target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("config.yaml"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-target-code-context", action="store_true")
    args = parser.parse_args()

    cfg = load_config(args.config)
    base_dir = args.config.parent
    dataset_root = (base_dir / cfg["dataset_root"]).resolve()
    manifest_path = (base_dir / cfg["manifest_path"]).resolve()
    output_path = (base_dir / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    records = load_manifest(dataset_root, manifest_path)
    with output_path.open("w", encoding="utf-8") as f:
        for record in tqdm(records, desc="build-sft"):
            param_json = load_json(record.param_path)
            param_text = format_param_description(param_json, cfg["data"]["max_param_text_chars"])
            target = read_lua_target(record.code_dir, cfg["data"]["max_lua_chars"])
            retrieved_context = ""
            if args.include_target_code_context:
                retrieved_context = target[: cfg["generation"]["max_source_length"]]
            prompt = build_generation_prompt(
                sample_id=record.sample_id,
                video_path=str(record.video_path),
                input_image_path=str(record.input_image_path) if record.input_image_path else "",
                param_text=param_text,
                retrieved_code_summary=retrieved_context,
            )
            row = {
                "sample_id": record.sample_id,
                "effect_name": record.effect_name,
                "input_variant": record.input_variant,
                "video_path": str(record.video_path),
                "input_image_path": str(record.input_image_path) if record.input_image_path else "",
                "prompt": prompt,
                "target": target,
            }
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
