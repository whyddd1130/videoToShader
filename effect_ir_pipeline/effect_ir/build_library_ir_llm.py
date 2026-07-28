from __future__ import annotations

import argparse
import json
import os
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from .llm_adapter import generate_library_structured_ir_prompt
from .manifest import load_rendered_rows, write_jsonl
from .model_client import generate_text
from .schema_ir import build_structured_ir_summary, parse_structured_ir_response


def read_code_inputs(code_dir: Path) -> tuple[str, str]:
    filter_path = code_dir / "filter.json"
    filter_json = filter_path.read_text(encoding="utf-8", errors="replace") if filter_path.exists() else "{}"
    source_chunks: list[str] = []
    for lua_path in sorted(code_dir.rglob("*.lua")):
        source_chunks.append(
            f"-- FILE: {lua_path.relative_to(code_dir)}\n"
            f"{lua_path.read_text(encoding='utf-8', errors='replace')}"
        )
    for shader_path in sorted([*code_dir.rglob("*.glsl"), *code_dir.rglob("*.frag"), *code_dir.rglob("*.vert")]):
        source_chunks.append(
            f"// FILE: {shader_path.relative_to(code_dir)}\n"
            f"{shader_path.read_text(encoding='utf-8', errors='replace')}"
        )
    return filter_json, "\n\n".join(source_chunks)


def library_id_from_row(row: dict[str, Any]) -> str:
    if row.get("source_dataset") == "jianying_single_pass":
        return str(row.get("sample_id") or row["effect_name"])
    return str(row.get("library_id") or row["effect_name"])


def code_dir_from_manifest_row(row: dict[str, Any], *, code_root: Path) -> Path:
    copied = str(row.get("copied_code_dir", "")).strip()
    if copied:
        return Path(copied)
    return code_root / str(row["effect_name"])


def load_existing(output: Path) -> dict[str, dict[str, Any]]:
    if not output.exists():
        return {}
    existing: dict[str, dict[str, Any]] = {}
    with output.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            existing[str(row.get("library_id") or row["effect_name"])] = row
    return existing


def call_llm_effect_structured_ir(prompt: str, *, model: str, temperature: float, retries: int) -> dict[str, Any]:
    last_error: Exception | None = None
    repair_suffix = ""
    for attempt in range(retries + 1):
        try:
            response_text = generate_text(
                prompt + repair_suffix,
                model=model,
                temperature=temperature,
            )
            return parse_structured_ir_response(response_text)
        except Exception as exc:
            last_error = exc
            repair_suffix = (
                "\n\nYour previous response was not valid JSON structured IR. "
                f"Parser error: {exc}. Return only one valid JSON object using the requested enum values."
            )
            if attempt < retries:
                wait_seconds = min(60.0, 5.0 * (attempt + 1) ** 2)
                time.sleep(wait_seconds)
    raise RuntimeError(f"LLM failed to return structured IR after {retries + 1} attempts") from last_error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("manifest_train.jsonl"))
    parser.add_argument("--code-root", type=Path, default=Path("code"))
    parser.add_argument("--output", type=Path, default=Path("effect_ir_pipeline/library_structured_ir_llm.jsonl"))
    parser.add_argument("--request-model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--model-name", default=os.environ.get("EFFECT_IR_LLM_MODEL_NAME", "qwen3.7-plus"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--effect", help="Only process one library_id or effect_name, useful for debugging.")
    parser.add_argument("--limit", type=int, help="Only process the first N effects.")
    parser.add_argument("--sleep", type=float, default=0.2)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--num-workers", type=int, default=1)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    rows = load_rendered_rows(args.manifest)
    targets_by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        library_id = library_id_from_row(row)
        if library_id not in targets_by_id:
            targets_by_id[library_id] = row
    effects = sorted(targets_by_id)
    if args.effect:
        effects = [
            effect
            for effect in effects
            if effect == args.effect or targets_by_id[effect].get("effect_name") == args.effect
        ]
    if args.limit is not None:
        effects = effects[: args.limit]

    existing = {} if args.overwrite else load_existing(args.output)
    output_rows = [existing[effect] for effect in sorted(existing) if effect not in effects]

    pending_effects = []
    for index, effect_name in enumerate(effects, start=1):
        if effect_name in existing and not args.overwrite:
            output_rows.append(existing[effect_name])
            print(f"[skip] {effect_name}")
            continue
        pending_effects.append((index, effect_name))

    write_lock = threading.Lock()

    def build_one(index: int, library_id: str) -> dict[str, Any]:
        source_row = targets_by_id[library_id]
        effect_name = str(source_row["effect_name"])
        code_dir = code_dir_from_manifest_row(source_row, code_root=args.code_root)
        filter_json, lua_sources = read_code_inputs(code_dir)
        prompt_name = library_id if library_id != effect_name else effect_name
        prompt = generate_library_structured_ir_prompt(prompt_name, filter_json, lua_sources)
        print(f"[{index}/{len(effects)}] calling LLM for {library_id}", flush=True)
        structured_ir = call_llm_effect_structured_ir(
            prompt,
            model=args.request_model,
            temperature=args.temperature,
            retries=args.retries,
        )
        return {
            "library_id": library_id,
            "sample_id": source_row.get("sample_id"),
            "effect_name": effect_name,
            "input_variant": source_row.get("input_variant"),
            "source_dataset": source_row.get("source_dataset", "single_shader_multi"),
            "code_dir": str(code_dir),
            "model": args.model_name,
            "request_model": args.request_model,
            "provider": os.environ.get("EFFECT_IR_LLM_PROVIDER", "http_json"),
            "structured_ir": structured_ir,
            "summary": build_structured_ir_summary(structured_ir),
        }

    if args.num_workers <= 1:
        for index, effect_name in pending_effects:
            output_rows.append(build_one(index, effect_name))
            write_jsonl(args.output, sorted(output_rows, key=lambda row: str(row.get("library_id") or row["effect_name"])))
            time.sleep(args.sleep)
    else:
        print(f"Using {args.num_workers} worker threads", flush=True)
        with ThreadPoolExecutor(max_workers=args.num_workers) as executor:
            futures = {
                executor.submit(build_one, index, effect_name): (index, effect_name)
                for index, effect_name in pending_effects
            }
            completed_rows: list[dict[str, Any]] = []
            for future in as_completed(futures):
                row = future.result()
                with write_lock:
                    output_rows.append(row)
                    completed_rows.append(row)
                    write_jsonl(args.output, sorted(output_rows, key=lambda item: str(item.get("library_id") or item["effect_name"])))
                if args.sleep > 0:
                    time.sleep(args.sleep)

    write_jsonl(args.output, sorted(output_rows, key=lambda row: str(row.get("library_id") or row["effect_name"])))
    print(json.dumps({"effects": len(output_rows), "output": str(args.output)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
