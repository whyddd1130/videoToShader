from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def format_param_description(param_json: dict[str, Any], max_chars: int | None = None) -> str:
    lines: list[str] = []
    lines.append(f"sample_id: {param_json.get('sample_id', '')}")
    lines.append(f"effect_name: {param_json.get('effect_name', '')}")
    lines.append(f"match_name: {param_json.get('match_name', '')}")

    input_info = param_json.get("input", {})
    lines.append(f"input.variant: {input_info.get('variant', '')}")
    lines.append(f"input.image_path: {input_info.get('image_path', '')}")

    video = param_json.get("video", {})
    lines.append(
        "video: "
        f"{video.get('width', '')}x{video.get('height', '')}, "
        f"fps={video.get('fps', '')}, "
        f"duration_ms={video.get('duration_ms', '')}, "
        f"total_frames={video.get('total_frames', '')}"
    )
    lines.append(f"primary_strength_param: {param_json.get('primary_strength_param', '')}")
    lines.append("parameters:")

    for param in param_json.get("params", []):
        keyframes = []
        for keyframe in param.get("keyframes", []):
            keyframes.append(
                f"frame {keyframe.get('frame')} time {keyframe.get('time_sec')}: "
                f"{keyframe.get('value')}"
            )
        lines.append(
            "- "
            f"index={param.get('index')} "
            f"key={param.get('key')} "
            f"type={param.get('type')} "
            f"default={param.get('source_default')} "
            f"range=[{param.get('source_min')}, {param.get('source_max')}] "
            f"animated={param.get('animated')} "
            f"strength_like={param.get('strength_like')} "
            f"keyframes={' | '.join(keyframes)}"
        )

    text = "\n".join(lines)
    if max_chars is not None:
        text = text[:max_chars]
    return text


def read_lua_target(code_dir: Path, max_chars: int | None = None) -> str:
    lua_files = sorted(code_dir.glob("*.lua"))
    chunks: list[str] = []
    for lua_file in lua_files:
        body = lua_file.read_text(encoding="utf-8", errors="replace")
        chunks.append(f"-- FILE: {lua_file.name}\n{body.rstrip()}\n")
    text = "\n".join(chunks)
    if max_chars is not None:
        text = text[:max_chars]
    return text


def build_generation_prompt(
    sample_id: str,
    video_path: str,
    input_image_path: str,
    param_text: str,
    retrieved_code_summary: str = "",
) -> str:
    return (
        "You are generating Lua shader plugin code for the CGE/FM runtime.\n"
        "Use the video path as the visual reference, the input image as the source image, "
        "and the parameter description as the animation/control contract.\n\n"
        f"sample_id:\n{sample_id}\n\n"
        f"video_path:\n{video_path}\n\n"
        f"input_image_path:\n{input_image_path}\n\n"
        f"parameter_description:\n{param_text}\n\n"
        f"retrieved_code_context:\n{retrieved_code_summary}\n\n"
        "Return the complete Lua source code."
    )

