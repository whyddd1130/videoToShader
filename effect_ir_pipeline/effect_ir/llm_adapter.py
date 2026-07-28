from __future__ import annotations

import json

from .schema_ir import STRUCTURED_IR_SCHEMA


CODE_TO_STRUCTURED_IR_PROMPT = """You are given Lua shader plugin source files and filter.json metadata.
Convert the shader behavior into a structured JSON intermediate representation.
Use only the allowed enum values.
Do not output markdown or explanation.
If an effect has multiple important operations, include more than one item in the list fields.
Prefer content-invariant visual semantics over implementation details.
"""

VIDEO_TO_STRUCTURED_IR_PROMPT = """You are given one source image and a rendered/effected video.
Infer the visual effect or transformation that maps the source image to the video frames.
Return a structured JSON intermediate representation using only the allowed enum values.
Do not guess the effect name. Do not output markdown or explanation.
Use the observations to decide: region_scope, geometry_ops, appearance_ops, temporal_pattern, mask_dependency, strength, motion_hint, color_hint, edge_hint, shape_hint, subject_hint, geometry_pattern, mask_shape_source.
Prefer discriminative visual semantics over scene content.
"""


def generate_library_structured_ir_prompt(effect_name: str, filter_json: str, lua_sources: str) -> str:
    schema_json = json.dumps(STRUCTURED_IR_SCHEMA, ensure_ascii=False, indent=2)
    return (
        f"{CODE_TO_STRUCTURED_IR_PROMPT}\n"
        f"effect_name: {effect_name}\n\n"
        "Return a JSON object with exactly these keys:\n"
        "{\n"
        '  "region_scope": string,\n'
        '  "geometry_ops": [string, ...],\n'
        '  "appearance_ops": [string, ...],\n'
        '  "temporal_pattern": string,\n'
        '  "mask_dependency": string,\n'
        '  "strength": string,\n'
        '  "motion_hint": string,\n'
        '  "color_hint": string,\n'
        '  "edge_hint": string,\n'
        '  "shape_hint": string,\n'
        '  "subject_hint": string,\n'
        '  "geometry_pattern": string,\n'
        '  "mask_shape_source": string,\n'
        '  "summary": string\n'
        "}\n\n"
        "Allowed enum values:\n"
        f"{schema_json}\n\n"
        "Guidelines:\n"
        "- region_scope describes where the effect acts.\n"
        "- geometry_ops describes geometric transforms.\n"
        "- geometry_pattern distinguishes radial / swirl / directional / localized / global warp structure.\n"
        "- appearance_ops describes blur, color, light, compositing, or edge style.\n"
        "- subject_hint identifies whether the effect follows face / eyes / hair / foreground / background.\n"
        "- mask_shape_source identifies whether the affected region is driven by an analytic shape, segmentation mask, edges, luminance/alpha, or a texture pattern.\n"
        "- temporal_pattern describes time behavior.\n"
        "- summary should be one short sentence in English, no effect name.\n\n"
        f"filter_json:\n{filter_json}\n\n"
        f"lua_sources:\n{lua_sources[:24000]}\n\n"
        "Return only JSON.\n"
    )


def generate_video_structured_ir_prompt(sample: dict[str, object]) -> str:
    schema_json = json.dumps(STRUCTURED_IR_SCHEMA, ensure_ascii=False, indent=2)
    return (
        f"{VIDEO_TO_STRUCTURED_IR_PROMPT}\n"
        f"sample_id: {sample.get('sample_id', '')}\n"
        f"input_image_path: {sample.get('input_image_path', '')}\n"
        f"video_path: {sample.get('video_path', '')}\n"
        "You will receive a provided source image and video frames represented through structured visual observations.\n"
        "Return a JSON object with exactly these keys:\n"
        "{\n"
        '  "region_scope": string,\n'
        '  "geometry_ops": [string, ...],\n'
        '  "appearance_ops": [string, ...],\n'
        '  "temporal_pattern": string,\n'
        '  "mask_dependency": string,\n'
        '  "strength": string,\n'
        '  "motion_hint": string,\n'
        '  "color_hint": string,\n'
        '  "edge_hint": string,\n'
        '  "shape_hint": string,\n'
        '  "subject_hint": string,\n'
        '  "geometry_pattern": string,\n'
        '  "mask_shape_source": string,\n'
        '  "summary": string\n'
        "}\n\n"
        "Allowed enum values:\n"
        f"{schema_json}\n\n"
        "Guidelines:\n"
        "- region_scope describes where the effect acts.\n"
        "- geometry_ops describes geometric transforms.\n"
        "- geometry_pattern distinguishes radial / swirl / directional / localized / global warp structure.\n"
        "- appearance_ops describes blur, color, light, compositing, or edge style.\n"
        "- subject_hint identifies whether the effect follows face / eyes / hair / foreground / background.\n"
        "- mask_shape_source identifies whether the affected region is driven by an analytic shape, segmentation mask, edges, luminance/alpha, or a texture pattern.\n"
        "- temporal_pattern describes time behavior.\n"
        "- summary should be one short sentence in English, no effect name.\n"
        "Return only JSON.\n"
    )
