#!/usr/bin/env python3
"""Render a MultiPass Studio graph without depending on a visible browser page."""
from __future__ import annotations

import argparse
import json
import re
import site
import sys
from pathlib import Path
from typing import Any

# The project virtualenv owns OpenCV/numpy while the workstation may already
# provide moderngl as a user package. Make that package visible without making
# the renderer depend on an online Playwright browser download.
site.ENABLE_USER_SITE = True
user_site = site.getusersitepackages()
if user_site not in sys.path:
    sys.path.append(user_site)

import cv2
import moderngl
import numpy as np


DEFAULT_VERTEX = """
attribute vec2 position;
varying vec2 textureCoord;
void main() {
  textureCoord = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}
"""


def _desktop_glsl(source: str, *, fragment: bool) -> str:
    """Translate the small WebGL-1 dialect accepted by Studio to GLSL 330."""
    source = re.sub(r"^\s*#version[^\n]*\n", "", source, flags=re.MULTILINE)
    source = re.sub(r"\bprecision\s+(?:lowp|mediump|highp)\s+float\s*;", "", source)
    source = re.sub(r"\b(lowp|mediump|highp)\b", "", source)
    source = source.replace("texture2D(", "texture(")
    if fragment:
        source = re.sub(r"\bvarying\b", "in", source)
        source = re.sub(r"\bgl_FragColor\b", "fragColor", source)
        declaration = "out vec4 fragColor;\n"
    else:
        source = re.sub(r"\battribute\b", "in", source)
        source = re.sub(r"\bvarying\b", "out", source)
        declaration = ""
    return "#version 330\n" + declaration + source.strip() + "\n"


def _evaluate(spec: Any, progress: float) -> Any:
    if isinstance(spec, (int, float, list)):
        return spec
    if not isinstance(spec, dict):
        return 0.0
    keyframes = spec.get("keyframes") or []
    if not keyframes:
        return spec.get("value", 0.0)
    points = []
    for item in keyframes:
        if isinstance(item, list):
            points.append((float(item[0]), item[1]))
        else:
            points.append((float(item["progress"]), item["value"]))
    points.sort(key=lambda item: item[0])
    left = next((item for item in reversed(points) if item[0] <= progress), points[0])
    right = next((item for item in points if item[0] >= progress), points[-1])
    if left[0] == right[0]:
        return left[1]
    amount = (progress - left[0]) / (right[0] - left[0])
    a = left[1] if isinstance(left[1], list) else [left[1]]
    b = right[1] if isinstance(right[1], list) else [right[1]]
    result = [float(value) + (float(b[min(i, len(b) - 1)]) - float(value)) * amount for i, value in enumerate(a)]
    return result if isinstance(left[1], list) or isinstance(right[1], list) else result[0]


class GraphRenderer:
    def __init__(self, graph_path: Path, prefix: int | None = None, max_dimension: int = 720):
        self.graph_path = graph_path.resolve()
        self.root = self.graph_path.parent
        self.graph = json.loads(self.graph_path.read_text(encoding="utf-8"))
        self.passes = self.graph["passes"][:prefix]
        image = cv2.imread(str((self.root / self.graph["input_image"]).resolve()), cv2.IMREAD_COLOR)
        if image is None:
            raise FileNotFoundError(f"Cannot read graph input image: {self.graph['input_image']}")
        scale = min(1.0, max_dimension / max(image.shape[:2]))
        self.width = max(1, round(image.shape[1] * scale))
        self.height = max(1, round(image.shape[0] * scale))
        image = cv2.resize(image, (self.width, self.height), interpolation=cv2.INTER_AREA)
        rgba = cv2.cvtColor(image, cv2.COLOR_BGR2RGBA)
        self.context = moderngl.create_standalone_context()
        self.source = self.context.texture((self.width, self.height), 4, np.flipud(rgba).tobytes())
        self.source.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.source.repeat_x = self.source.repeat_y = False
        self.programs: list[Any] = []
        for index, item in enumerate(self.passes, 1):
            fragment = (self.root / item["fragment_shader"]).read_text(encoding="utf-8")
            vertex = (self.root / item["vertex_shader"]).read_text(encoding="utf-8") if item.get("vertex_shader") else DEFAULT_VERTEX
            try:
                program = self.context.program(
                    vertex_shader=_desktop_glsl(vertex, fragment=False),
                    fragment_shader=_desktop_glsl(fragment, fragment=True),
                )
            except Exception as exc:
                raise RuntimeError(f"Pass {index} shader compilation failed: {exc}") from exc
            vertices = np.array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1], dtype="f4")
            buffer = self.context.buffer(vertices.tobytes())
            attributes = [name for name in ("position", "vPosition") if name in program]
            if not attributes:
                raise RuntimeError(f"Pass {index} vertex shader has no position or vPosition attribute")
            vao = self.context.simple_vertex_array(program, buffer, attributes[0])
            self.programs.append((item, program, vao, buffer))

    def _uniform(self, program: Any, name: str, value: Any) -> None:
        if name not in program:
            return
        if isinstance(value, list):
            program[name].value = tuple(value)
        else:
            program[name].value = value

    def frame(self, progress: float) -> np.ndarray:
        resources: dict[str, Any] = {"source": self.source, "input": self.source}
        previous = "source"
        allocated: list[Any] = []
        graph_parameters = self.graph.get("parameters") or {}
        try:
            for index, (item, program, vao, _) in enumerate(self.programs, 1):
                scale = max(0.05, min(1.0, float(item.get("scale", 1.0))))
                width, height = max(1, round(self.width * scale)), max(1, round(self.height * scale))
                output_texture = self.context.texture((width, height), 4)
                output_texture.filter = (moderngl.LINEAR, moderngl.LINEAR)
                output_texture.repeat_x = output_texture.repeat_y = False
                framebuffer = self.context.framebuffer(color_attachments=[output_texture])
                allocated.extend([framebuffer, output_texture])
                framebuffer.use()
                inputs = item.get("inputs") or {"inputImageTexture": previous}
                for unit, (uniform, resource_name) in enumerate(inputs.items()):
                    resource_name = previous if resource_name == "previous" else resource_name
                    texture = resources.get(resource_name)
                    if texture is None:
                        raise RuntimeError(f"Pass {index} input '{resource_name}' is unavailable")
                    texture.use(location=unit)
                    self._uniform(program, uniform, unit)
                self._uniform(program, "uProgress", float(progress))
                self._uniform(program, "uTime", float(progress * 5.0))
                self._uniform(program, "uResolution", [width, height])
                self._uniform(program, "uOutputResolution", [width, height])
                self._uniform(program, "uTexelSize", [1.0 / width, 1.0 / height])
                self._uniform(program, "uSourceResolution", [self.width, self.height])
                for name, spec in {**graph_parameters, **(item.get("uniforms") or {})}.items():
                    value = _evaluate(spec, progress)
                    if isinstance(spec, dict) and spec.get("type") == "int":
                        value = int(round(float(value)))
                    self._uniform(program, name, value)
                vao.render(moderngl.TRIANGLES)
                output = str(item.get("output") or item.get("id") or f"pass_{index:02d}")
                resources[output] = output_texture
                previous = output
            final = resources[previous]
            raw = final.read(alignment=1)
            rgba = np.frombuffer(raw, dtype=np.uint8).reshape(final.height, final.width, 4)
            rgba = np.flipud(rgba)
            if (final.width, final.height) != (self.width, self.height):
                rgba = cv2.resize(rgba, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
            return cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGR)
        finally:
            for resource in reversed(allocated):
                resource.release()

    def close(self) -> None:
        for _, program, vao, buffer in self.programs:
            vao.release(); buffer.release(); program.release()
        self.source.release(); self.context.release()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--graph", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prefix", type=int)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--duration", type=float, default=5.0)
    args = parser.parse_args()
    renderer = GraphRenderer(args.graph, prefix=args.prefix)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        if args.prefix is not None:
            frames = [renderer.frame(value) for value in (0.0, 0.5, 1.0)]
            labels = ("p=0.00", "p=0.50", "p=1.00")
            for frame, label in zip(frames, labels):
                cv2.rectangle(frame, (0, 0), (118, 28), (0, 0, 0), -1)
                cv2.putText(frame, label, (8, 20), cv2.FONT_HERSHEY_SIMPLEX, .55, (255, 255, 255), 1, cv2.LINE_AA)
            if not cv2.imwrite(str(args.output), np.hstack(frames)):
                raise RuntimeError("OpenCV could not save prefix contact sheet")
        else:
            frame_count = max(2, round(args.duration * args.fps))
            writer = cv2.VideoWriter(str(args.output), cv2.VideoWriter_fourcc(*"avc1"), args.fps, (renderer.width, renderer.height))
            if not writer.isOpened():
                writer = cv2.VideoWriter(str(args.output), cv2.VideoWriter_fourcc(*"mp4v"), args.fps, (renderer.width, renderer.height))
            if not writer.isOpened():
                raise RuntimeError("OpenCV could not initialize an MP4 encoder")
            try:
                for index in range(frame_count):
                    writer.write(renderer.frame(index / (frame_count - 1)))
            finally:
                writer.release()
        if not args.output.is_file() or args.output.stat().st_size <= 1024:
            raise RuntimeError("Renderer did not create a valid output file")
        print(json.dumps({"output": str(args.output), "bytes": args.output.stat().st_size}))
    finally:
        renderer.close()


if __name__ == "__main__":
    main()
