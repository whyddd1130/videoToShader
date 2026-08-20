"""Typed multi-pass baseline: plan first, generate layers serially, repair one layer."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any
from urllib import request
from urllib.parse import quote

import cv2

from .direct_shader_baseline import _encode_jpeg_data_url, build_target_contact_sheet_data_url
from .manifest import resolve_repo_path
from .model_client import generate_messages


def _wait_for_url(url: str, timeout: float = 25.0) -> None:
    """Wait until the local Studio endpoint is ready."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with request.urlopen(url, timeout=2) as response:
                if response.status < 500:
                    return
        except Exception:
            time.sleep(0.4)
    raise RuntimeError(f"MultiPass Studio did not start at {url}")


def _free_local_port() -> int:
    """Reserve an available localhost port for the render receiver."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])

PLANNER = """You receive two images: SOURCE_IMAGE, then TARGET_VIDEO_SAMPLES. Both are upright in normal human-view orientation. TARGET_VIDEO_SAMPLES is a chronological contact sheet: its labelled frames progress left to right from p=0 to p=1.
Infer the changing effect only from this visual evidence. Do not assume a known effect, implementation, shader, pass count, parameter name, or rendering technique.
Preserve SOURCE_IMAGE orientation by default. Plan a flip or rotation only when TARGET_VIDEO_SAMPLES visibly perform it; WebGL coordinate conventions are already handled by the renderer.
Return ONE executable render graph with the smallest positive number of passes genuinely required by the observed effect. There is no fixed upper limit. This step plans resources; it must not write GLSL.
Never output fragment_shader, vertex_shader, shader code, markdown fences, or explanatory text.

A pass may read source and any earlier named output. Decide the number of passes, their order, resource branches, FBO scales, and parameter names only from the provided image and video. Name its primary sampler inputImageTexture; use inputImageTexture1 only when a pass needs a second texture. Every pass must include id, name, role, inputs, output, scale, dynamic, progress_behavior, must_preserve, must_not_do. inputs maps sampler uniform names to source or an earlier output. scale is 0.25, 0.5, or 1.0. parameters is an object of named external uniforms with keyframes [[progress,value],...]; include it only for an animation controlled outside GLSL. Only one pass may own visible time variation.

Return exactly this complete shape; the passes array must contain the number of pass objects you inferred:
{"summary":"...","parameters":{"parameterName":{"type":"float","keyframes":[[0,0],[0.5,1],[1,0]]}},"passes":[{"id":"pass_01","name":"...","role":"...","inputs":{"inputImageTexture":"source"},"output":"pass_01","scale":1.0,"dynamic":false,"progress_behavior":"static","must_preserve":["..."],"must_not_do":["..."]}]}"""

def _visual_evidence(input_image: Path, target_video: Path, *, image_size: int, frame_count: int, work_dir: Path) -> tuple[list[dict[str, Any]], list[int]]:
    """Provide exactly the source image and chronological target-video slices.

    This deliberately does not reuse the direct-baseline content helper: that
    helper prepends a legacy fixed-three-pass prompt, which would be an unwanted
    structural prior for graph inference.
    """
    source = cv2.imread(str(input_image), cv2.IMREAD_COLOR)
    if source is None:
        raise FileNotFoundError(f"Cannot read input image: {input_image}")
    target_sheet, indices = build_target_contact_sheet_data_url(
        target_video, image_size=image_size, frame_count=frame_count, work_dir=work_dir,
    )
    return [
        {"type": "image_url", "image_url": {"url": _encode_jpeg_data_url(source)}},
        {"type": "image_url", "image_url": {"url": target_sheet}},
    ], indices

def _json(text: str, label: str) -> dict[str, Any]:
    text = text.strip()
    if not text.startswith("{"):
        start, end = text.find("{"), text.rfind("}")
        text = text[start:end + 1] if start >= 0 and end > start else text
    try: value = json.loads(text)
    except json.JSONDecodeError as exc: raise ValueError(f"{label} returned invalid JSON: {exc}") from exc
    if not isinstance(value, dict): raise ValueError(f"{label} must be an object")
    return value

def _validate_plan(plan: dict[str, Any]) -> list[dict[str, Any]]:
    candidates = plan.get("candidates")
    if not isinstance(candidates, list) or not 1 <= len(candidates) <= 3: raise ValueError("Planner needs one to three candidates")
    for candidate in candidates:
        passes = candidate.get("passes") if isinstance(candidate, dict) else None
        if not isinstance(passes, list) or len(passes) < 1: raise ValueError("Every graph needs at least one pass")
        candidate.setdefault("parameters",{})
        if sum(bool(p.get("dynamic")) for p in passes if isinstance(p, dict)) > 1: raise ValueError("A graph has more than one dynamic owner")
        outputs={"source"}
        for index,p in enumerate(passes,1):
            if not isinstance(p, dict) or any(key not in p for key in ("name","role","dynamic","progress_behavior","must_preserve","must_not_do")):
                raise ValueError("Pass type contract is incomplete")
            p.setdefault("id",f"pass_{index:02d}")
            p.setdefault("output",str(p["id"]))
            p.setdefault("scale",1.0)
            p.setdefault("inputs",{"inputImageTexture": "source" if index == 1 else str(passes[index-2].get("output",passes[index-2].get("id",f"pass_{index-1:02d}")))})
            if not isinstance(p["inputs"],dict) or not p["inputs"] or any(value not in outputs for value in p["inputs"].values()): raise ValueError("Pass inputs must reference source or an earlier output")
            if not isinstance(p["scale"],(float,int)) or not 0.05 <= float(p["scale"]) <= 1.0: raise ValueError("Pass scale must be within 0.05..1.0")
            outputs.add(str(p["output"]))
        if not isinstance(candidate.get("parameters",{}),dict): raise ValueError("Graph parameters must be an object")
    return candidates

def _validated_graph(payload: dict[str, Any]) -> dict[str, Any]:
    if "candidates" in payload or "fragment_shader" in json.dumps(payload,ensure_ascii=False):
        raise ValueError("Planner returned candidates or GLSL instead of one render graph")
    candidate={"id":"A",**payload}
    return _validate_plan({"candidates":[candidate]})[0]

def _fragment(text: str) -> str:
    blocks = re.findall(r"```(?:glsl)?\s*\n(.*?)```", text, re.I | re.S)
    source = (blocks[0] if blocks else text).strip()
    for token in ("precision", "varying vec2 textureCoord", "inputImageTexture", "gl_FragColor"):
        if token not in source: raise ValueError("Code model did not return a complete WebGL 1 fragment pass")
    if any(x in source for x in ("#version", "texture(", "layout(", "texelFetch")): raise ValueError("Pass contains non-WebGL-1 syntax")
    return source

def _write_graph(job_dir: Path, job_id: str, image: Path, selected: dict[str, Any], shaders: list[str]) -> Path:
    job_dir.mkdir(parents=True, exist_ok=True)
    copied = job_dir / "input.png"
    if not copied.exists(): shutil.copy2(image, copied)
    passes=[]
    for n, shader in enumerate(shaders, 1):
        path=job_dir/f"pass_{n:02d}.frag.glsl"; path.write_text(shader+"\n", encoding="utf-8")
        item=selected["passes"][n-1]
        passes.append({"id":item["id"],"name":item["name"],"role":item["role"],"inputs":item["inputs"],"output":item["output"],"scale":item["scale"],"dynamic":item["dynamic"],"progress_behavior":item["progress_behavior"],"fragment_shader":path.name})
    graph=job_dir/"pass_graph.json"
    graph.write_text(json.dumps({"id":job_id,"effect_summary":selected.get("summary",""),"input_image":copied.name,"parameters":selected.get("parameters",{}),"pass_count":len(passes),"passes":passes},ensure_ascii=False,indent=2),encoding="utf-8")
    return graph

def _studio_task(repo: Path, studio: Path, studio_url: str, graph: Path, job_id: str, out: Path, prefix: int | None = None, feedback_job: str = "", keep_receiver: bool = False, reveal_after_render: bool = False, feedback_allow_finish: bool = False, existing_video: Path | None = None) -> Path | tuple[Path, subprocess.Popen[Any]]:
    out.mkdir(parents=True, exist_ok=True); port=_free_local_port(); env=os.environ.copy()
    reveal_enabled = reveal_after_render and env.get("MULTIPASS_RENDER_REVEAL", "1").strip().lower() not in {"0", "false", "no"}
    env["MULTIPASS_OUTPUT_DIR"]=str(out); env["MULTIPASS_RECEIVER_PORT"]=str(port)
    receiver=subprocess.Popen(["node","tools/multipass_render_receiver.mjs"],cwd=repo,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    receiver_handed_off=False
    backups: list[tuple[Path, Path]] = []
    started=None
    broker_request: Path | None = None
    broker_request_id = ""
    browser_worker: subprocess.Popen[Any] | None = None
    browser_log_handle: Any = None
    browser_log = out / "headless_render.log"
    try:
        backend = env.get("MULTIPASS_RENDER_BACKEND", "local").strip().lower()
        # Automated renders must not depend on a visible Studio tab polling in
        # the foreground. The local GPU worker consumes the graph directly;
        # Studio remains responsible only for displaying results and collecting
        # human feedback. Set MULTIPASS_RENDER_BACKEND=browser explicitly to
        # retain the legacy browser adapter for diagnostics.
        use_local = backend == "local" and existing_video is None and not keep_receiver
        if use_local:
            expected = out / (f"{job_id}_prefix_{prefix}.jpg" if prefix is not None else f"{job_id}.mp4")
            backup = expected.with_name(f".{expected.name}.{uuid.uuid4().hex}.previous")
            if expected.exists(): expected.replace(backup)
            local_log = out / "local_render.log"
            command = [
                sys.executable, str(repo / "tools" / "local_multipass_renderer.py"),
                "--graph", str(graph), "--output", str(expected),
            ]
            if prefix is not None: command += ["--prefix", str(prefix)]
            try:
                completed = subprocess.run(command, cwd=repo, env=env, capture_output=True, text=True, timeout=180)
                local_log.write_text(
                    f"command: {' '.join(command)}\nexit_code: {completed.returncode}\n\nstdout:\n{completed.stdout}\n\nstderr:\n{completed.stderr}\n",
                    encoding="utf-8",
                )
                if completed.returncode != 0:
                    raise RuntimeError(f"Independent local renderer failed (code {completed.returncode}). See {local_log}.\n{completed.stderr[-3000:]}")
                if not expected.exists() or expected.stat().st_size <= 1024:
                    raise RuntimeError(f"Independent local renderer produced no valid output. See {local_log}")
                backup.unlink(missing_ok=True)
                return expected
            except BaseException:
                expected.unlink(missing_ok=True)
                if backup.exists(): backup.replace(expected)
                raise
        try: _wait_for_url(studio_url, timeout=3)
        except RuntimeError:
            started=subprocess.Popen(["npm","run","dev","--","--host","localhost","--port","3002"],cwd=studio,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); studio_url="http://localhost:3002"; _wait_for_url(studio_url)
        relative=graph.relative_to(studio/"public").as_posix(); output=f"http://localhost:{port}/videos"
        feedback_query = f"&feedbackJob={quote(feedback_job)}&feedbackOutput={quote(output,safe=':/')}&feedbackFinish={1 if feedback_allow_finish else 0}" if feedback_job else ""
        if existing_video is not None:
            existing_video = existing_video.resolve()
            if existing_video.parent != out.resolve() or not existing_video.exists():
                raise FileNotFoundError("Existing feedback video must be a completed file in the output directory")
            query=(
                f"inspectGraph=/{quote(relative)}"
                f"&existingVideo={quote(f'http://localhost:{port}/videos/{existing_video.name}', safe=':/')}"
                f"{feedback_query}"
            )
            expected=[]
        elif prefix is None: query=f"renderJob=/{quote(relative)}{feedback_query}"; expected=[out/f"{job_id}.mp4",out/f"{job_id}.webm"]
        else: query=f"renderPrefix=/{quote(relative)}&prefixCount={prefix}"; expected=[out/f"{job_id}_prefix_{prefix}.jpg"]
        # A full render always has the same public name (``<job_id>.mp4``).
        # Never discard the last playable candidate before the replacement has
        # actually arrived from the browser: an invalid shader or a browser
        # timeout used to make the final round appear to have no video at all.
        for item in expected:
            if item.exists():
                backup = item.with_name(f".{item.name}.{uuid.uuid4().hex}.previous")
                item.replace(backup)
                backups.append((item, backup))
        run_id=uuid.uuid4().hex
        url=f"{studio_url}/?{query}&renderOutput={quote(output,safe=':/')}&run={run_id}"
        backend = env.get("MULTIPASS_RENDER_BACKEND", "browser").strip().lower()
        # Interactive feedback still belongs to the visible page. All ordinary
        # Agent renders use an isolated browser so a hidden/background Safari
        # tab cannot throttle the renderer or stop consuming requests.
        use_headless = backend == "headless" and existing_video is None and not keep_receiver
        if use_headless:
            browser_log_handle = browser_log.open("ab")
            browser_log_handle.write(f"\n--- render {run_id} {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n".encode())
            browser_log_handle.flush()
            browser_worker = subprocess.Popen(
                ["node", "scripts/headless-renderer.mjs", url],
                cwd=studio, env=env, stdout=browser_log_handle, stderr=subprocess.STDOUT,
            )
        elif env.get("MULTIPASS_RENDER_BROKER", "0").strip().lower() in {"1", "true", "yes"}:
            broker_request_id = uuid.uuid4().hex
            broker_request = out / "render_request.json"
            temporary_request = out / f".render_request.{broker_request_id}.tmp"
            temporary_request.write_text(json.dumps({
                "request_id": broker_request_id,
                "run": run_id,
                "kind": "existing" if existing_video is not None else "full" if prefix is None else "prefix",
                "graph_url": f"/{relative}",
                "upload_base": output,
                "prefix_count": prefix,
                "existing_video_url": f"http://localhost:{port}/videos/{existing_video.name}" if existing_video is not None else None,
            }, ensure_ascii=False), encoding="utf-8")
            temporary_request.replace(broker_request)
        else:
            # CLI runs retain the Safari adapter. Web-launched Agent jobs use the
            # render broker above, keeping the visible Studio page stable.
            open_args=["open", "-a", "Safari", url] if reveal_enabled else ["open", "-g", "-a", "Safari", url]
            subprocess.run(open_args,check=True)
        until=time.monotonic()+120
        while time.monotonic()<until:
            if browser_worker is not None and browser_worker.poll() is not None:
                detail = browser_log.read_text(encoding="utf-8", errors="replace")[-4000:] if browser_log.exists() else ""
                raise RuntimeError(f"Independent browser renderer exited before producing output (code {browser_worker.returncode}).\n{detail}")
            render_log=out/"render_log.jsonl"
            if render_log.exists():
                for line in render_log.read_text(encoding="utf-8",errors="replace").splitlines():
                    try: event=json.loads(line)
                    except json.JSONDecodeError: continue
                    if event.get("run") == run_id and event.get("event") == "job_failed":
                        raise RuntimeError(f"Website render failed: {event.get('error','unknown browser error')}")
                    if existing_video is not None and event.get("run") == run_id and event.get("event") == "feedback_failed":
                        raise RuntimeError(f"Website could not load the completed video: {event.get('error','unknown browser error')}")
                    if existing_video is not None and event.get("run") == run_id and event.get("event") == "feedback_ready":
                        if keep_receiver:
                            receiver_handed_off=True
                            return existing_video, receiver
                        return existing_video
            for item in expected:
                if item.exists() and item.stat().st_size>1024:
                    if reveal_enabled: subprocess.run(["open","-a","Safari"],check=True)
                    for _, backup in backups:
                        backup.unlink(missing_ok=True)
                    if keep_receiver:
                        receiver_handed_off=True
                        return item, receiver
                    return item
            time.sleep(.4)
        detail = browser_log.read_text(encoding="utf-8", errors="replace")[-4000:] if browser_log.exists() else ""
        raise TimeoutError(f"Independent renderer timed out after 120 seconds.\n{detail}" if use_headless else "Website render timed out")
    except BaseException:
        # Restore the last known-good output if this attempt did not finish.
        for item, backup in backups:
            item.unlink(missing_ok=True)
            if backup.exists():
                backup.replace(item)
        raise
    finally:
        if broker_request is not None and broker_request.exists():
            try:
                current_request=json.loads(broker_request.read_text(encoding="utf-8"))
            except (OSError,json.JSONDecodeError):
                current_request={}
            if current_request.get("request_id") == broker_request_id:
                broker_request.unlink(missing_ok=True)
        if browser_worker is not None and browser_worker.poll() is None:
            browser_worker.terminate()
            try: browser_worker.wait(timeout=5)
            except subprocess.TimeoutExpired: browser_worker.kill()
        if browser_log_handle is not None: browser_log_handle.close()
        if not receiver_handed_off: receiver.terminate()
        if started: started.terminate()

def _archive_round_video(video: Path, out: Path, job_id: str, round_number: int) -> Path:
    """Keep every successful full render, independently of the public final name."""
    suffix = video.suffix or ".mp4"
    archived = out / f"{job_id}_round_{round_number:02d}{suffix}"
    shutil.copy2(video, archived)
    return archived

def _wait_for_web_feedback_event(path: Path, timeout_seconds: int) -> dict[str, str]:
    deadline=time.monotonic()+timeout_seconds
    while time.monotonic()<deadline:
        if path.exists():
            payload=_json(path.read_text(encoding="utf-8"),"web feedback")
            action="finish" if payload.get("action") == "finish" else "revise"
            feedback=str(payload.get("feedback","")).strip()
            if action == "finish" or feedback: return {"action":action,"feedback":feedback}
        time.sleep(.5)
    raise TimeoutError(f"Timed out waiting for web feedback: {path}")

def _wait_for_web_feedback(path: Path, timeout_seconds: int) -> str:
    event=_wait_for_web_feedback_event(path,timeout_seconds)
    if event["action"] == "finish":
        raise ValueError("This workflow requires revision feedback and does not support a finish action")
    return event["feedback"]

def _execution_contract(review: dict[str, Any], responsible_pass: int) -> dict[str, Any]:
    """Normalize the small, current-turn-only contract used to gate a repair."""
    proposed = review.get("execution_contract")
    if not isinstance(proposed, dict):
        proposed = {}
    preserve = proposed.get("preserve", review.get("preserve", []))
    return {
        "pass": responsible_pass,
        "control": str(proposed.get("control", review.get("required_edit", "visible correction"))).strip(),
        "observable": str(proposed.get("observable", review.get("assessment", "the requested visible change"))).strip(),
        "trajectory": str(proposed.get("trajectory", "apply the requested change visibly throughout the intended process")).strip(),
        "preserve": [str(item) for item in preserve] if isinstance(preserve, list) else [],
    }

def _pass_prompt(selected: dict[str, Any], index: int, repair: str="", downstream_shaders: list[str] | None = None, execution_contract: dict[str, Any] | None = None) -> str:
    item=selected["passes"][index-1]; earlier=selected["passes"][:index-1]; later=selected["passes"][index:]
    upstream="SOURCE_IMAGE is input." if not earlier else "PREFIX_CONTACT_SHEET shows the fixed output of upstream passes: "+json.dumps([{ "name":p["name"],"role":p["role"]} for p in earlier],ensure_ascii=False)
    downstream_contract="No later pass exists." if not later else "Later pass contracts that must preserve this pass's output: "+json.dumps([{ "name":p["name"],"role":p["role"],"must_preserve":p["must_preserve"],"must_not_do":p["must_not_do"]} for p in later],ensure_ascii=False)
    downstream_code="" if not downstream_shaders else "\nCURRENT DOWNSTREAM SHADERS (your correction must remain visible after these run):\n"+"\n\n".join(f"PASS {n}:\n{s}" for n,s in enumerate(downstream_shaders,index+1))
    contract_text="" if execution_contract is None else "\nEXECUTION CONTRACT (mandatory, compact): "+json.dumps(execution_contract,ensure_ascii=False)+". The named control must directly produce the named observable and trajectory. Do not replace it with an opacity toggle, endpoint switch, or unrelated intermediary."
    return f"""Implement only pass {index} of this typed WebGL 1 graph. SOURCE_IMAGE and TARGET_VIDEO_SAMPLES show the final target. {upstream}
Current pass contract: {json.dumps(item,ensure_ascii=False)}
Graph parameters: {json.dumps(selected.get("parameters",{}),ensure_ascii=False)}
{downstream_contract}{downstream_code}{contract_text}
Return exactly one fenced WebGL 1 GLSL fragment shader. It must declare precision highp float, varying vec2 textureCoord, every sampler named by inputs, any graph parameter it uses, and assign gl_FragColor. It may consume only the named input samplers. Implement this role only: do not redo upstream roles, do not alter protected features, and do not animate a static pass. Preserve the visible output required by earlier passes; a downstream palette/threshold must not erase a required texture, line, dot, blur, or motion. No external texture, #version, WebGL 2 syntax, explanation, or second block. {repair}"""

def _verify_execution_contract(video: Path, contract: dict[str, Any], *, model: str, frame_count: int, work_dir: Path) -> dict[str, Any]:
    """Use rendered evidence, not source-text/regex heuristics, to accept a repair."""
    # Eleven uniform samples include p=0.20, 0.40, 0.50, 0.60 and 0.80.
    # The smaller six-frame sheet skipped p=0.50, which made a valid midpoint
    # contract impossible to verify from rendered evidence.
    sheet,_=build_target_contact_sheet_data_url(video,frame_count=11,work_dir=work_dir)
    prompt=("CANDIDATE_VIDEO_SAMPLES is chronological from p=0 to p=1. Verify only this execution contract using visible output, not guessed shader text. "
            "Return JSON only: {\"fulfilled\":true,\"reason\":\"brief visual evidence\",\"retry_instruction\":\"one precise correction if false\"}. "
            "fulfilled is true only when the stated observable visibly follows the stated trajectory while preserve items remain intact. "
            "Do not introduce a new optimization goal. CONTRACT: "+json.dumps(contract,ensure_ascii=False))
    result=_json(generate_messages([{"role":"user","content":[{"type":"text","text":prompt},{"type":"image_url","image_url":{"url":sheet}}]}],model=model,temperature=0.0),"execution-contract verification")
    if not isinstance(result.get("fulfilled"),bool):
        raise ValueError("Execution-contract verifier must return boolean fulfilled")
    result.setdefault("reason","")
    result.setdefault("retry_instruction","")
    return result

def _contact_part(path: Path) -> dict[str, Any]:
    image=cv2.imread(str(path),cv2.IMREAD_COLOR)
    if image is None: raise RuntimeError("Cannot read website prefix output")
    return {"type":"image_url","image_url":{"url":_encode_jpeg_data_url(image)}}

def _apply_graph_repair(selected: dict[str, Any], index: int, category: str, raw: str) -> None:
    change=_json(raw,"graph repair"); item=selected["passes"][index-1]
    if category == "input_connection":
        inputs=change.get("inputs"); allowed={"source",*(str(p["output"]) for p in selected["passes"][:index-1])}
        if not isinstance(inputs,dict) or not inputs or any(value not in allowed for value in inputs.values()): raise ValueError("Graph repair returned invalid inputs")
        item["inputs"]=inputs
    elif category == "fbo_scale":
        scale=change.get("scale")
        if not isinstance(scale,(float,int)) or not 0.05 <= float(scale) <= 1.0: raise ValueError("Graph repair returned invalid scale")
        item["scale"]=float(scale)
    elif category == "parameter_curve":
        parameters=change.get("parameters")
        if not isinstance(parameters,dict): raise ValueError("Graph repair returned invalid parameters")
        selected["parameters"]=parameters
    else: raise ValueError("Unsupported graph repair category")

def _write_md(path: Path, selected: dict[str, Any], shaders: list[str], review: dict[str, Any], intermediate_outputs: list[dict[str, Any]], human_feedback_events: list[dict[str, Any]] | None = None) -> None:
    lines=["# Typed Pass Graph Baseline","",f"**Graph:** {selected.get('summary','')}","","## Parameters","","```json",json.dumps(selected.get("parameters",{}),ensure_ascii=False,indent=2),"```",""]
    for n,(item,shader) in enumerate(zip(selected["passes"],shaders),1):
        lines += [f"## Pass {n}: {item['name']}","",f"- Role: {item['role']}",f"- Inputs: `{json.dumps(item['inputs'],ensure_ascii=False)}`",f"- Output: `{item['output']}` · FBO scale: `{item['scale']}`",f"- Dynamic: {item['dynamic']} — {item['progress_behavior']}","","```glsl",shader,"```",""]
    lines += ["## Intermediate outputs",""]
    for item in intermediate_outputs:
        lines.append(f"- Round {item['round']}: "+", ".join(item["passes"]))
    if human_feedback_events:
        lines += ["", "## Human feedback", ""]
        for event in human_feedback_events:
            lines += [f"### Repair round {event['round']}", "", f"- Feedback: {event['feedback']}", "- Effective instruction:", "", "```json", json.dumps(event["effective_instruction"],ensure_ascii=False,indent=2), "```", ""]
    lines += ["## Final review","","```json",json.dumps(review,ensure_ascii=False,indent=2),"```",""]
    path.write_text("\n".join(lines),encoding="utf-8")

def _human_feedback_prompt(feedback: str, automatic_review: dict[str, Any]) -> str:
    return f"""TARGET_VIDEO_SAMPLES, CANDIDATE_VIDEO_SAMPLES, and INTERMEDIATE_PASS_SHEETS show a target effect, the current result, and intermediate pass outputs. A human reviewer supplied this high-priority visual feedback:
{feedback!r}

Translate that feedback into exactly one executable repair instruction for the current generated graph. The human request takes priority over the automatic review, but do not invent an effect that is not visible in the target. Prefer a local correction to one responsible pass. Choose repair_target=graph only if the request can be satisfied solely by changing existing texture inputs, FBO scale, or a graph parameter curve; otherwise choose shader. Preserve explicitly correct visual properties.

The automatic review, included only as secondary context, was:
{json.dumps(automatic_review, ensure_ascii=False)}

Return JSON only:
{{"assessment":"how the human-visible mismatch appears in the current result","error_category":"shader_code|input_connection|fbo_scale|parameter_curve","repair_target":"shader|graph","responsible_pass":1,"required_edit":"one concrete, visually testable change","execution_contract":{{"control":"direct parameter or mechanism","observable":"one visible feature","trajectory":"required change over time","preserve":["..."]}},"required_change_fulfilled":false,"preserve":["visible properties that must remain"]}}"""

def main() -> None:
    p=argparse.ArgumentParser(description="Plan/select/generate/render/review/repair typed multi-pass baseline")
    p.add_argument("video_path",type=Path);p.add_argument("--input-image",type=Path,required=True);p.add_argument("--repo-root",type=Path,default=Path("."));p.add_argument("--work-dir",type=Path,default=Path("runs/multi_pass/typed_multipass_baselines"));p.add_argument("--studio-root",type=Path,default=Path("muti_pass/multipass-studio"));p.add_argument("--studio-url",default="http://localhost:3001");p.add_argument("--model",default=os.environ.get("EFFECT_IR_LLM_MODEL","ep-fipdyi-1784171757952297366"));p.add_argument("--frame-count",type=int,default=10);p.add_argument("--temperature",type=float,default=0.0);p.add_argument("--job-id",default="");p.add_argument("--plan-attempts",type=int,default=3,help="Maximum graph-only planning attempts before failing.");p.add_argument("--force-pass-count",type=int,default=0,help="Require exactly this positive number of passes; 0 lets the planner decide.");p.add_argument("--max-repairs",type=int,default=0,help="Maximum responsible-pass repairs after the initial render; default 0 outputs the first render directly.");p.add_argument("--contract-retries",type=int,default=1,help="Extra rewrites of the same pass when rendered evidence does not fulfill its execution contract.");p.add_argument("--human-feedback",default="",help="One high-priority human visual correction, applied before the selected repair round.");p.add_argument("--human-feedback-round",type=int,default=0,help="Zero-based repair round where human feedback is applied.");p.add_argument("--wait-for-feedback",action="store_true",help="After the initial video is shown in the website, wait for feedback submitted from its web form.");p.add_argument("--feedback-timeout",type=int,default=1800,help="Seconds to wait for website feedback (default: 1800).");p.add_argument("--skip-repair",action="store_true")
    a=p.parse_args(); repo=a.repo_root.resolve(); image=resolve_repo_path(repo,str(a.input_image)); video=resolve_repo_path(repo,str(a.video_path)); studio=resolve_repo_path(repo,str(a.studio_root)); out=resolve_repo_path(repo,str(a.work_dir));out.mkdir(parents=True,exist_ok=True)
    if not image.exists() or not video.exists() or not (studio/"public").is_dir(): raise FileNotFoundError("Input, video, or studio directory missing")
    if a.max_repairs < 0 or a.plan_attempts < 1 or a.contract_retries < 0: raise ValueError("--max-repairs and --contract-retries must be non-negative and --plan-attempts must be positive")
    if a.force_pass_count < 0: raise ValueError("--force-pass-count must be 0 or a positive integer")
    if a.human_feedback_round < 0: raise ValueError("--human-feedback-round must be non-negative")
    if a.human_feedback.strip() and (a.max_repairs == 0 or a.human_feedback_round >= a.max_repairs): raise ValueError("Human feedback must target a repair round before --max-repairs")
    if a.wait_for_feedback and (a.max_repairs == 0 or a.human_feedback_round != 0): raise ValueError("--wait-for-feedback currently pauses after the initial render, so --human-feedback-round must be 0 and --max-repairs must be positive")
    if a.wait_for_feedback and a.human_feedback.strip(): raise ValueError("Use either --human-feedback or --wait-for-feedback, not both")
    if a.feedback_timeout < 1: raise ValueError("--feedback-timeout must be positive")
    job_id=re.sub(r"[^A-Za-z0-9_-]+","_",a.job_id or f"typed_{video.stem}_{uuid.uuid4().hex[:8]}").strip("_")
    visual,indices=_visual_evidence(input_image=image,target_video=video,image_size=256,frame_count=a.frame_count,work_dir=out)
    selected=None; planner_error=""
    forced_pass_instruction="" if not a.force_pass_count else f"\nHard requirement: return exactly {a.force_pass_count} passes. Decompose the visible process into distinct serial responsibilities; do not use a placeholder or identity pass."
    for attempt in range(1,a.plan_attempts+1):
        correction="" if attempt == 1 else f"\nYour previous response was invalid: {planner_error}. Return the required graph JSON only; do not write GLSL."
        planner_raw=generate_messages([{ "role":"user","content":[{"type":"text","text":PLANNER+forced_pass_instruction+correction},*visual]}],model=a.model,temperature=a.temperature)
        (out/f"{job_id}_planner_response_{attempt:02d}.txt").write_text(planner_raw,encoding="utf-8")
        try:
            selected=_validated_graph(_json(planner_raw,"planner"))
            if a.force_pass_count and len(selected["passes"]) != a.force_pass_count: raise ValueError(f"Planner returned {len(selected['passes'])} passes; exactly {a.force_pass_count} required")
            break
        except ValueError as exc:
            planner_error=str(exc)
    if selected is None: raise ValueError(f"Planner failed to return a valid render graph after {a.plan_attempts} attempts: {planner_error}")
    (out/f"{job_id}_planner_response.txt").write_text(planner_raw,encoding="utf-8")
    planner_mode="strict_graph"; selection={"selected_id":"A","reason":"Single validated render graph."}
    (out/f"{job_id}_typed_plan.json").write_text(json.dumps({"planner_mode":planner_mode,"selected":selected,"selection":selection},ensure_ascii=False,indent=2),encoding="utf-8")
    job=studio/"public"/"generated"/job_id; shaders=[]; prefixes=[]
    # The graph author, not this runner, determines how many layers are needed.
    for index in range(1, len(selected["passes"]) + 1):
        previous=[]
        if shaders:
            graph=_write_graph(job,job_id,image,selected,shaders); prefix=_studio_task(repo,studio,a.studio_url,graph,job_id,out,len(shaders)); prefixes.append(str(prefix)); previous=[_contact_part(prefix)]
        raw=generate_messages([{ "role":"user","content":[{"type":"text","text":_pass_prompt(selected,index)},*visual,*previous]}],model=a.model,temperature=a.temperature)
        shaders.append(_fragment(raw));(out/f"{job_id}_pass_{index:02d}_response.txt").write_text(raw,encoding="utf-8")
    graph=_write_graph(job,job_id,image,selected,shaders)
    initial_receiver=None
    initial_render=_studio_task(repo,studio,a.studio_url,graph,job_id,out,feedback_job=job_id if a.wait_for_feedback else "",keep_receiver=a.wait_for_feedback,reveal_after_render=True)
    if isinstance(initial_render,tuple): final,initial_receiver=initial_render
    else: final=initial_render
    round_videos=[{"round":0,"video":str(_archive_round_video(final,out,job_id,0))}]
    pending_human_feedback=a.human_feedback.strip()
    if a.wait_for_feedback:
        feedback_path=out/f"{job_id}_web_feedback.json"
        print(f"Waiting for website feedback: {feedback_path}",flush=True)
        try: pending_human_feedback=_wait_for_web_feedback(feedback_path,a.feedback_timeout)
        finally:
            if initial_receiver: initial_receiver.terminate(); initial_receiver=None
    if a.skip_repair or a.max_repairs == 0:
        review={"assessment":"Initial render output directly; review and repair are disabled.","error_category":None,"repair_target":None,"responsible_pass":None,"required_edit":"","required_change_fulfilled":None,"preserve":[]}
        (out/f"{job_id}_final_review.json").write_text(json.dumps(review,ensure_ascii=False,indent=2),encoding="utf-8")
        md=out/f"{job_id}_model_output.md";_write_md(md,selected,shaders,review,[{"round":0,"passes":prefixes}])
        result={"baseline":"typed_pass_graph_generation","planner_mode":planner_mode,"model_calls":1 + len(shaders),"job_id":job_id,"target_frame_indices":indices,"selected_graph":selected,"selection":selection,"prefix_contact_sheets":prefixes,"intermediate_outputs":[{"round":0,"passes":prefixes}],"round_videos":round_videos,"render_failures":[],"reviews":[],"repairs":[],"review":review,"website_graph":str(graph),"rendered_video":str(final),"model_output_markdown":str(md)};result_path=out/f"{job_id}_result.json";result_path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8");print(json.dumps({"result":str(result_path),"rendered_video":str(final)},ensure_ascii=False));return
    from .direct_shader_baseline import build_target_contact_sheet_data_url
    reviews=[]; repairs=[]; intermediate_outputs=[]; previous_required=""; human_feedback_events=[]; render_failures=[]; contract_verifications=[]
    # These snapshots are the only graph/code pair known to correspond to
    # ``final``.  If a later browser render fails, report the failure but hand
    # back this coherent, playable state instead of an unrendered shader.
    last_successful_selected=json.loads(json.dumps(selected))
    last_successful_shaders=list(shaders)
    total_repairs=0 if a.skip_repair else a.max_repairs
    for repair_round in range(total_repairs + 1):
        candidate_sheet,_=build_target_contact_sheet_data_url(final,frame_count=a.frame_count,work_dir=out)
        intermediate=[]
        for pass_count in range(1,len(shaders)):
            prefix=_studio_task(repo,studio,a.studio_url,graph,job_id,out,pass_count)
            archived=out/f"{job_id}_round_{repair_round:02d}_pass_{pass_count:02d}.jpg"
            shutil.copy2(prefix,archived)
            intermediate.append(str(archived))
        intermediate_outputs.append({"round":repair_round,"passes":intermediate})
        verification=("" if not previous_required else " The prior required change was: "+previous_required+". State required_change_fulfilled true only if it is visibly present.")
        review_prompt="""TARGET_VIDEO_SAMPLES and CANDIDATE_VIDEO_SAMPLES show the same effect. INTERMEDIATE_PASS_SHEETS show each non-final pass at p=0,0.5,1. Compare the visible process and diagnose one category: shader code, input connection, FBO scale, or parameter curve. Return only JSON: {\"assessment\":\"specific mismatch\",\"error_category\":\"shader_code|input_connection|fbo_scale|parameter_curve\",\"repair_target\":\"shader|graph\",\"responsible_pass\":1,\"required_edit\":\"one concrete code or graph change\",\"execution_contract\":{\"control\":\"parameter or mechanism directly changed\",\"observable\":\"one visible feature\",\"trajectory\":\"its required change over the process\",\"preserve\":[\"...\"]},\"required_change_fulfilled\":false,\"preserve\":[\"...\"]}. The execution_contract must be short and testable from rendered frames; do not include history. Use repair_target=graph only when the correction can be made solely by changing existing graph inputs, FBO scale, or a named graph parameter keyframe. If the correction requires changing GLSL (including adding or using uProgress), set repair_target=shader even when its category is parameter_curve. Choose exactly one pass; never ask to rewrite all passes. Inspect the full current shader chain before choosing: if an earlier pass creates the missing feature but a later pass thresholds, recolors, composites, or otherwise erases it, choose that later destructive pass as responsible. The required edit must make the final output visibly retain the feature."""+verification
        chain="\n\n".join(f"PASS {n} ({selected['passes'][n-1]['name']}):\n{shader}" for n,shader in enumerate(shaders,1))
        review_content=[
            {"type":"text","text":review_prompt+"\nGRAPH:\n"+json.dumps({"parameters":selected.get("parameters",{}),"passes":selected["passes"]},ensure_ascii=False)+"\nCURRENT_SHADER_CHAIN:\n"+chain},
            *visual,
            {"type":"image_url","image_url":{"url":candidate_sheet}},
            *[_contact_part(Path(path)) for path in intermediate],
        ]
        review_raw=generate_messages([{ "role":"user","content":review_content}],model=a.model,temperature=a.temperature)
        automatic_review=_json(review_raw,"review"); review=automatic_review; feedback_event=None
        if pending_human_feedback and repair_round == a.human_feedback_round:
            feedback_content=[
                {"type":"text","text":_human_feedback_prompt(pending_human_feedback, automatic_review)+"\nGRAPH:\n"+json.dumps({"parameters":selected.get("parameters",{}),"passes":selected["passes"]},ensure_ascii=False)+"\nCURRENT_SHADER_CHAIN:\n"+chain},
                *visual,
                {"type":"image_url","image_url":{"url":candidate_sheet}},
                *[_contact_part(Path(path)) for path in intermediate],
            ]
            feedback_raw=generate_messages([{ "role":"user","content":feedback_content}],model=a.model,temperature=a.temperature)
            review=_json(feedback_raw,"human feedback interpretation")
            feedback_event={"round":repair_round,"feedback":pending_human_feedback,"automatic_review":automatic_review,"effective_instruction":review,"raw_response":feedback_raw}
            human_feedback_events.append(feedback_event)
            (out/f"{job_id}_human_feedback_{repair_round:02d}.json").write_text(json.dumps(feedback_event,ensure_ascii=False,indent=2),encoding="utf-8")
        responsible=int(review.get("responsible_pass",0))
        if responsible not in range(1, len(shaders) + 1): raise ValueError("Review must name one responsible pass")
        reviews.append({"round":repair_round,"automatic_review":automatic_review,"review":review,"human_feedback_applied":feedback_event is not None,"video":str(final)})
        review_artifact={"automatic_review":automatic_review,"human_feedback":pending_human_feedback if feedback_event else None,"effective_repair_instruction":review}
        (out/f"{job_id}_review_{repair_round:02d}.json").write_text(json.dumps(review_artifact,ensure_ascii=False,indent=2),encoding="utf-8")
        if repair_round == total_repairs: break
        previous=[]
        if responsible>1:
            prefix=_studio_task(repo,studio,a.studio_url,graph,job_id,out,responsible-1); previous=[_contact_part(prefix)]
        required=str(review.get("required_edit", "")); category=str(review.get("error_category", "shader_code")); repair_target=str(review.get("repair_target", "shader")); contract=_execution_contract(review,responsible)
        if repair_target == "graph" and category in {"input_connection","fbo_scale","parameter_curve"}:
            graph_prompt=f"""Repair only graph metadata for pass {responsible}. TARGET_VIDEO_SAMPLES and CANDIDATE_VIDEO_SAMPLES show the desired and current effect. Current graph: {json.dumps({"parameters":selected.get("parameters",{}),"passes":selected["passes"]},ensure_ascii=False)}. Required correction: {required}. Return JSON only. For input_connection return {{\"inputs\":{{\"samplerUniform\":\"source_or_earlier_output\"}}}}. For fbo_scale return {{\"scale\":0.25}}. For parameter_curve return {{\"parameters\":{{\"uniformName\":{{\"type\":\"float\",\"keyframes\":[[0,0],[0.5,1],[1,0]]}}}}}}. Do not change shader code."""
            raw=generate_messages([{ "role":"user","content":[{"type":"text","text":graph_prompt},*visual,*previous]}],model=a.model,temperature=a.temperature)
            _apply_graph_repair(selected,responsible,category,raw)
            (out/f"{job_id}_pass_{responsible:02d}_graph_repair_{repair_round+1:02d}.json").write_text(raw,encoding="utf-8")
        else:
            raw=generate_messages([{ "role":"user","content":[{"type":"text","text":_pass_prompt(selected,responsible,"Required correction that must be visibly implemented: "+required,shaders[responsible:],contract)},*visual,*previous]}],model=a.model,temperature=a.temperature)
            shaders[responsible-1]=_fragment(raw);(out/f"{job_id}_pass_{responsible:02d}_repair_{repair_round+1:02d}_response.txt").write_text(raw,encoding="utf-8")
        repairs.append({"round":repair_round+1,"responsible_pass":responsible,"error_category":category,"repair_target":repair_target,"required_edit":required,"execution_contract":contract})
        repair_aborted=False
        for contract_attempt in range(a.contract_retries + 1):
            if contract_attempt:
                retry_note=f"The prior rendered attempt failed this mandatory contract: {json.dumps(contract,ensure_ascii=False)}. Visual verifier evidence: {verification.get('reason','')}. Rewrite only this pass to fulfill it. {verification.get('retry_instruction','')}"
                raw=generate_messages([{ "role":"user","content":[{"type":"text","text":_pass_prompt(selected,responsible,retry_note,shaders[responsible:],contract)},*visual,*previous]}],model=a.model,temperature=a.temperature)
                shaders[responsible-1]=_fragment(raw)
                (out/f"{job_id}_pass_{responsible:02d}_contract_retry_{repair_round+1:02d}_{contract_attempt:02d}.txt").write_text(raw,encoding="utf-8")
            graph=_write_graph(job,job_id,image,selected,shaders)
            try:
                final=_studio_task(repo,studio,a.studio_url,graph,job_id,out,reveal_after_render=True)
            except Exception as exc:
                failure={"round":repair_round+1,"error":str(exc),"required_edit":required,"responsible_pass":responsible,"stage":"render"}
                render_failures.append(failure)
                (out/f"{job_id}_render_failure_{repair_round+1:02d}.json").write_text(json.dumps(failure,ensure_ascii=False,indent=2),encoding="utf-8")
                repair_aborted=True
                break
            attempt_video=out/f"{job_id}_round_{repair_round+1:02d}_attempt_{contract_attempt:02d}{final.suffix or '.mp4'}"
            shutil.copy2(final,attempt_video)
            verification=_verify_execution_contract(final,contract,model=a.model,frame_count=a.frame_count,work_dir=out)
            verification_event={"round":repair_round+1,"attempt":contract_attempt,"contract":contract,"verification":verification,"video":str(attempt_video)}
            contract_verifications.append(verification_event)
            (out/f"{job_id}_contract_verification_{repair_round+1:02d}_{contract_attempt:02d}.json").write_text(json.dumps(verification_event,ensure_ascii=False,indent=2),encoding="utf-8")
            if verification["fulfilled"]:
                round_videos.append({"round":repair_round+1,"video":str(_archive_round_video(final,out,job_id,repair_round+1))})
                break
            if contract_attempt == a.contract_retries:
                failure={"round":repair_round+1,"required_edit":required,"responsible_pass":responsible,"stage":"execution_contract","contract":contract,"verification":verification}
                render_failures.append(failure)
                (out/f"{job_id}_execution_contract_failure_{repair_round+1:02d}.json").write_text(json.dumps(failure,ensure_ascii=False,indent=2),encoding="utf-8")
                shutil.copy2(Path(round_videos[-1]["video"]),final)
                repair_aborted=True
        if repair_aborted:
            selected=last_successful_selected; shaders=last_successful_shaders
            graph=_write_graph(job,job_id,image,selected,shaders)
            break
        last_successful_selected=json.loads(json.dumps(selected)); last_successful_shaders=list(shaders)
        previous_required=required
    review=reviews[-1]["review"]; (out/f"{job_id}_final_review.json").write_text(json.dumps(review,ensure_ascii=False,indent=2),encoding="utf-8")
    md=out/f"{job_id}_model_output.md";_write_md(md,selected,shaders,review,intermediate_outputs,human_feedback_events)
    result={"baseline":"typed_pass_graph_generation","planner_mode":planner_mode,"model_calls":len(shaders) + 2 + total_repairs * 3 + len(human_feedback_events),"job_id":job_id,"target_frame_indices":indices,"selected_graph":selected,"selection":selection,"prefix_contact_sheets":prefixes,"intermediate_outputs":intermediate_outputs,"round_videos":round_videos,"render_failures":render_failures,"contract_verifications":contract_verifications,"reviews":reviews,"human_feedback":human_feedback_events,"repairs":repairs,"review":review,"website_graph":str(graph),"rendered_video":str(final),"model_output_markdown":str(md)};result_path=out/f"{job_id}_result.json";result_path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8");print(json.dumps({"result":str(result_path),"rendered_video":str(final)},ensure_ascii=False))

if __name__ == "__main__": main()
