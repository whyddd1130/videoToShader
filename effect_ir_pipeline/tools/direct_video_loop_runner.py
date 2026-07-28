from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.closed_loop_shader_iter import (
    _build_comparison_contact_sheet_data_url,
    call_llm_content,
    extract_feedback_overall_score,
    extract_glsl_blocks,
    generate_llm_visual_feedback,
    generate_video_ir,
    repair_shader_text,
    run_shader_lab_render,
    validate_rendered_video,
    validate_shader_text,
    write_shader_files,
)
from effect_ir_pipeline.effect_ir.manifest import resolve_repo_path


def _image_data_url(path: Path) -> str:
    suffix = path.suffix.lower()
    mime = "image/png" if suffix == ".png" else "image/jpeg"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"


def _sample_video_frames_at_progress(video_path: Path, *, progress_values: list[float], image_size: int) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if frame_count <= 0:
        cap.release()
        raise RuntimeError(f"Video has no readable frames: {video_path}")
    frames: list[np.ndarray] = []
    try:
        for progress in progress_values:
            frame_index = min(frame_count - 1, max(0, int(round(progress * (frame_count - 1)))))
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame_bgr = cap.read()
            if not ok:
                raise RuntimeError(f"Cannot read frame {frame_index} from {video_path}")
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            frames.append(cv2.resize(frame_rgb, (image_size, image_size), interpolation=cv2.INTER_AREA))
    finally:
        cap.release()
    return frames


def _target_contact_sheet_data_url(target_video: Path, *, progress_values: list[float], image_size: int) -> str:
    frames = _sample_video_frames_at_progress(target_video, progress_values=progress_values, image_size=image_size)
    label_h = 28
    sheet = np.full((image_size + label_h, len(frames) * image_size, 3), 255, dtype=np.uint8)
    for col, (progress, frame) in enumerate(zip(progress_values, frames)):
        x0 = col * image_size
        sheet[label_h : label_h + image_size, x0 : x0 + image_size] = frame
        cv2.putText(
            sheet,
            f"target p={progress:.2f}",
            (x0 + 6, 19),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )
    ok, encoded = cv2.imencode(".jpg", cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR), [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise RuntimeError("Cannot encode target contact sheet")
    return f"data:image/jpeg;base64,{base64.b64encode(encoded.tobytes()).decode('ascii')}"


def _initial_direct_content(*, input_image: Path, target_video: Path, image_size: int) -> list[dict[str, Any]]:
    progress_values = [0.0, 0.25, 0.5, 0.75, 1.0]
    text = (
        "第一张图是原图，第二张是 target 在 p=0/0.25/0.5/0.75/1 的采样。直接生成 shader，不解释，不参考库。\n"
        "只输出两段 GLSL：Vertex、Fragment。Fragment 只允许 inputImageTexture/uProgress/uTime；不用额外 uniform/外部纹理/resolution/uTexelSize；不要假设 p=0 是原图。\n"
    )
    return [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": _image_data_url(input_image)}},
        {"type": "image_url", "image_url": {"url": _target_contact_sheet_data_url(target_video, progress_values=progress_values, image_size=image_size)}},
    ]


def _iteration_content(
    *,
    iteration: int,
    input_image: Path,
    target_video: Path,
    candidate_video: Path,
    current_shader: str,
    image_size: int,
) -> list[dict[str, Any]]:
    text = (
        "根据原图、TARGET/CANDIDATE/DIFF 对比图和当前 shader，直接生成下一版 shader。不解释，不参考库。\n"
        f"iteration:{iteration}\n"
        f"当前 shader:\n{current_shader[:14000]}\n\n"
        "只输出两段 GLSL：Vertex、Fragment。Fragment 只允许 inputImageTexture/uProgress/uTime；不用额外 uniform/外部纹理/resolution/uTexelSize；不要假设 p=0 是原图。\n"
    )
    return [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": _image_data_url(input_image)}},
        {
            "type": "image_url",
            "image_url": {
                "url": _build_comparison_contact_sheet_data_url(
                    target_video,
                    candidate_video,
                    progress_values=[0.0, 0.25, 0.5, 0.75, 1.0],
                    image_size=image_size,
                )
            },
        },
    ]


def _generate_valid_shader(
    *,
    content: list[dict[str, Any]],
    model: str,
    temperature: float,
    max_attempts: int,
) -> str:
    last_reason = ""
    for attempt in range(1, max_attempts + 1):
        response = call_llm_content(
            content,
            model=model,
            temperature=temperature,
            max_tokens=3200,
            timeout=float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "360")),
        )
        valid, reason = validate_shader_text(response)
        if valid:
            return response
        repaired = repair_shader_text(response, model=model, temperature=temperature)
        valid, repair_reason = validate_shader_text(repaired)
        if valid:
            return repaired
        last_reason = f"attempt={attempt}, reason={reason}, repair_reason={repair_reason}"
    raise RuntimeError(f"Could not generate valid shader after {max_attempts} attempts: {last_reason}")


def _ensure_precision_preamble(shader_text: str) -> str:
    vertex, fragment = extract_glsl_blocks(shader_text)
    preamble = (
        "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
        "precision highp float;\n"
        "#else\n"
        "precision mediump float;\n"
        "#endif\n\n"
    )
    if "precision highp float" not in vertex and "precision mediump float" not in vertex:
        vertex = preamble + vertex
    if "precision highp float" not in fragment and "precision mediump float" not in fragment:
        fragment = preamble + fragment
    return f"```glsl\n{vertex.strip()}\n```\n\n```glsl\n{fragment.strip()}\n```"


def _with_retry_feedback(content: list[dict[str, Any]], *, reason: str, failed_shader: str | None) -> list[dict[str, Any]]:
    updated: list[dict[str, Any]] = []
    retry_note = (
        "\n\n上一次生成没有计入迭代轮次，因为它没有通过平台渲染/视频有效性检查。\n"
        f"失败原因：{reason}\n"
        "请重新生成完整 shader。为提高平台兼容性：不要在 main() 中使用提前 return；"
        "不要依赖额外 uniform；任何 UV 采样都必须 clamp 到 0..1；始终给 gl_FragColor 赋有效颜色。\n"
    )
    if failed_shader:
        retry_note += f"\n失败 shader:\n{failed_shader[:7000]}\n"
    inserted = False
    for part in content:
        if not inserted and part.get("type") == "text":
            new_part = dict(part)
            new_part["text"] = str(new_part.get("text", "")) + retry_note
            updated.append(new_part)
            inserted = True
        else:
            updated.append(part)
    if not inserted:
        updated.insert(0, {"type": "text", "text": retry_note})
    return updated


def _cleanup_intermediates(work_dir: Path, *, keep_iterations: set[int]) -> None:
    keep_names = {"closed_loop_result.json"}
    for iteration in keep_iterations:
        keep_names.update(
            {
                f"iter_{iteration:02d}.vert.glsl",
                f"iter_{iteration:02d}.frag.glsl",
                f"iter_{iteration:02d}_shader.md",
                f"iter_{iteration:02d}_rendered.mp4",
            }
        )
    for path in work_dir.iterdir():
        if path.name not in keep_names and path.is_file():
            path.unlink()


def run_direct_loop(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = args.repo_root.resolve()
    work_dir = args.work_dir
    work_dir.mkdir(parents=True, exist_ok=True)
    target_video = resolve_repo_path(repo_root, str(args.video_path))
    input_image = resolve_repo_path(repo_root, str(args.input_image))

    print("[1] generate target IR from provided image + target video", flush=True)
    target_ir_generation = generate_video_ir(
        args.video_path,
        input_image=input_image,
        repo_root=repo_root,
        sample_id=target_video.stem,
        model=args.request_model,
        temperature=args.temperature,
        sample_fps=args.sample_fps,
        image_size=args.image_size,
    )
    target_ir = target_ir_generation["structured_ir"]

    iterations: list[dict[str, Any]] = []
    feedback_history: list[dict[str, Any]] = []
    current_shader: str | None = None
    candidate_ir: dict[str, Any] | None = None
    previous_candidate_video: Path | None = None

    for iteration in range(1, args.max_iters + 1):
        print(f"[2] direct iteration {iteration}/{args.max_iters}", flush=True)
        if iteration == 1:
            content = _initial_direct_content(
                input_image=input_image,
                target_video=target_video,
                image_size=args.image_size,
            )
        else:
            if previous_candidate_video is None:
                raise RuntimeError("Previous candidate video is missing for direct iteration prompt")
            content = _iteration_content(
                iteration=iteration,
                input_image=input_image,
                target_video=target_video,
                candidate_video=previous_candidate_video,
                current_shader=current_shader or "",
                image_size=args.image_size,
            )
        last_failure = ""
        shader_text = ""
        render_job: dict[str, Any] | None = None
        rendered_video = work_dir / f"iter_{iteration:02d}_rendered.mp4"
        shader_md = work_dir / f"iter_{iteration:02d}_shader.md"
        vertex_path = work_dir / f"iter_{iteration:02d}.vert.glsl"
        fragment_path = work_dir / f"iter_{iteration:02d}.frag.glsl"
        for generation_attempt in range(1, args.max_generation_attempts + 1):
            shader_text = _generate_valid_shader(
                content=content,
                model=args.request_model,
                temperature=args.temperature,
                max_attempts=1,
            )
            shader_text = _ensure_precision_preamble(shader_text)
            valid, reason = validate_shader_text(shader_text)
            if not valid:
                last_failure = f"shader became invalid after precision preamble normalization: {reason}"
                content = _with_retry_feedback(content, reason=last_failure, failed_shader=shader_text)
                continue
            vertex_path, fragment_path = write_shader_files(shader_text, work_dir, iteration)
            shader_md.write_text(shader_text, encoding="utf-8")
            try:
                render_job = run_shader_lab_render(
                    base_url=args.shader_lab_url,
                    token=args.shader_lab_token,
                    vertex_shader=vertex_path,
                    fragment_shader=fragment_path,
                    input_image=input_image,
                    output_video=rendered_video,
                    timeout=args.shader_lab_timeout,
                    poll_interval=args.shader_lab_poll_interval,
                )
                ok, reason = validate_rendered_video(rendered_video)
                if ok:
                    break
                last_failure = reason
            except Exception as exc:
                last_failure = str(exc)
            print(
                f"[retry] iteration {iteration} generation_attempt={generation_attempt} not counted: {last_failure}",
                flush=True,
            )
            if rendered_video.exists():
                rendered_video.unlink()
            content = _with_retry_feedback(content, reason=last_failure, failed_shader=shader_text)
        else:
            raise RuntimeError(
                f"Rendered video validation failed at iteration {iteration} after "
                f"{args.max_generation_attempts} generation attempts: {last_failure}"
            )

        candidate_ir_generation = generate_video_ir(
            rendered_video,
            input_image=input_image,
            repo_root=repo_root,
            sample_id=f"direct_iter_{iteration:02d}",
            model=args.request_model,
            temperature=args.temperature,
            sample_fps=args.sample_fps,
            image_size=args.image_size,
        )
        candidate_ir = candidate_ir_generation["structured_ir"]
        feedback = generate_llm_visual_feedback(
            target_video=args.video_path,
            candidate_video=rendered_video,
            repo_root=repo_root,
            target_ir=target_ir,
            candidate_ir=candidate_ir,
            current_shader=shader_text,
            model=args.request_model,
            temperature=args.temperature,
            image_size=args.image_size,
        )
        score = extract_feedback_overall_score(feedback)
        feedback_history.append(feedback)
        current_shader = shader_text
        previous_candidate_video = rendered_video
        iterations.append(
            {
                "iteration": iteration,
                "shader_markdown": str(shader_md),
                "vertex_shader": str(vertex_path),
                "fragment_shader": str(fragment_path),
                "rendered_video": str(rendered_video),
                "render_job": render_job,
                "candidate_ir": candidate_ir_generation,
                "llm_visual_feedback": feedback,
                "overall_score": score,
            }
        )
        print(f"[3] iteration {iteration} score={score}", flush=True)

    scored = [item for item in iterations if item.get("overall_score") is not None]
    best = max(scored, key=lambda item: float(item["overall_score"])) if scored else iterations[-1]
    result = {
        "mode": "direct_video_no_library_reference",
        "input_image": str(input_image),
        "target_video": str(target_video),
        "max_iters": args.max_iters,
        "target_ir_generation": target_ir_generation,
        "iterations": iterations,
        "best_iteration": best["iteration"],
        "best_score": best.get("overall_score"),
        "best_video": best["rendered_video"],
        "best_shader_markdown": best["shader_markdown"],
        "final_iteration": iterations[-1]["iteration"],
        "final_video": iterations[-1]["rendered_video"],
        "final_shader_markdown": iterations[-1]["shader_markdown"],
        "score_ranking": sorted(
            [
                {
                    "iteration": item["iteration"],
                    "overall_score": item.get("overall_score"),
                    "rendered_video": item["rendered_video"],
                    "shader_markdown": item["shader_markdown"],
                }
                for item in iterations
            ],
            key=lambda item: (-1 if item["overall_score"] is None else -float(item["overall_score"]), item["iteration"]),
        ),
    }
    result_path = work_dir / "closed_loop_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    keep_iterations = {int(item["iteration"]) for item in iterations}
    if args.cleanup_intermediate:
        keep_iterations = {int(best["iteration"]), int(iterations[-1]["iteration"])}
        _cleanup_intermediates(work_dir, keep_iterations=keep_iterations)
    print(f"[4] result saved: {result_path}", flush=True)
    print(f"[5] kept iterations: {sorted(keep_iterations)}", flush=True)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Direct video+image to shader closed-loop runner without library reference.")
    parser.add_argument("video_path", type=Path)
    parser.add_argument("--input-image", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--request-model", default=os.environ.get("EFFECT_IR_LLM_MODEL", "ep-fipdyi-1784171757952297366"))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--sample-fps", type=float, default=2.0)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--max-iters", type=int, default=5)
    parser.add_argument("--max-generation-attempts", type=int, default=3)
    parser.add_argument("--shader-lab-url", default=os.environ.get("SHADER_LAB_URL", "http://172.22.112.93:8788"))
    parser.add_argument("--shader-lab-token", default=os.environ.get("SHADER_LAB_TOKEN", "Zaz_tjklcxhqjfo6Sy7HsA"))
    parser.add_argument("--shader-lab-timeout", type=float, default=float(os.environ.get("SHADER_LAB_TIMEOUT", "900")))
    parser.add_argument("--shader-lab-poll-interval", type=float, default=1.6)
    parser.add_argument(
        "--cleanup-intermediate",
        action="store_true",
        help="Delete non-best/non-final iteration files after the run. By default all iteration videos and shaders are kept.",
    )
    args = parser.parse_args()
    run_direct_loop(args)


if __name__ == "__main__":
    main()
