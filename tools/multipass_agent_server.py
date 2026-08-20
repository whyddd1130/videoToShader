#!/usr/bin/env python3
"""Local job API for the single-page multi-pass Agent experience."""
from __future__ import annotations

import json
import mimetypes
import os
import signal
import subprocess
import sys
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse


REPO = Path(__file__).resolve().parents[1]
JOB_ROOT = Path(os.environ.get("MULTIPASS_AGENT_JOB_ROOT", REPO / "runs" / "multi_pass" / "agent_jobs")).resolve()
HOST = os.environ.get("MULTIPASS_AGENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("MULTIPASS_AGENT_PORT", "8792"))
MAX_UPLOAD_BYTES = int(os.environ.get("MULTIPASS_AGENT_MAX_UPLOAD_BYTES", str(512 * 1024 * 1024)))
PROCESS_LOCK = threading.Lock()
PROCESSES: dict[str, subprocess.Popen[bytes]] = {}


def _safe_job_id(value: str) -> str:
    cleaned = "".join(character for character in value if character.isalnum() or character in "_-").strip("_-")
    if not cleaned or cleaned != value:
        raise ValueError("Invalid job id")
    return cleaned


def _job_dir(job_id: str) -> Path:
    path = (JOB_ROOT / _safe_job_id(job_id)).resolve()
    if path.parent != JOB_ROOT:
        raise ValueError("Invalid job path")
    return path


def _read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def _write_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def _metadata(job_id: str) -> dict[str, Any]:
    return _read_json(_job_dir(job_id) / "job.json", {}) or {}


def _workflow_id(requested_job_id: str, metadata: dict[str, Any]) -> str:
    """Return the immutable workflow id persisted when the job was created."""
    value = str(metadata.get("job_id") or requested_job_id)
    return _safe_job_id(value)


def _state_path(directory: Path, requested_job_id: str, metadata: dict[str, Any]) -> Path:
    workflow_id = _workflow_id(requested_job_id, metadata)
    preferred = directory / "results" / f"{workflow_id}_agent_state.json"
    if preferred.is_file():
        return preferred
    legacy = directory / "results" / f"{requested_job_id}_agent_state.json"
    if legacy.is_file():
        return legacy
    candidates = sorted((directory / "results").glob("*_agent_state.json")) if (directory / "results").is_dir() else []
    return candidates[-1] if len(candidates) == 1 else preferred


def _upload_path(directory: Path, metadata: dict[str, Any], kind: str) -> Path:
    original = str(metadata.get("source_name" if kind == "source" else "video_name", ""))
    suffix = Path(original).suffix.lower()
    allowed = {".png", ".jpg", ".jpeg", ".webp", ".bmp"} if kind == "source" else {".mp4", ".mov", ".webm", ".m4v"}
    if suffix not in allowed:
        suffix = ".png" if kind == "source" else ".mp4"
    return directory / f"{kind}_{'image' if kind == 'source' else 'video'}{suffix}"


def _save_metadata(job_id: str, **changes: Any) -> dict[str, Any]:
    directory = _job_dir(job_id)
    metadata = _metadata(job_id)
    metadata.update(changes)
    metadata["updated_at"] = time.time()
    _write_json(directory / "job.json", metadata)
    return metadata


def _process_status(job_id: str, metadata: dict[str, Any]) -> tuple[bool, int | None]:
    process = PROCESSES.get(job_id)
    if process is not None:
        code = process.poll()
        return code is None, code
    pid = metadata.get("pid")
    if isinstance(pid, int):
        try:
            os.kill(pid, 0)
            command = subprocess.run(
                ["ps", "-p", str(pid), "-o", "command="],
                capture_output=True, text=True, timeout=2, check=False,
            ).stdout.strip()
            if "agentic_multipass_translation" in command and job_id in command:
                return True, None
        except OSError:
            pass
        except subprocess.SubprocessError:
            pass
    return False, metadata.get("exit_code") if isinstance(metadata.get("exit_code"), int) else None


def _watch_process(job_id: str, process: subprocess.Popen[bytes], log_handle: Any) -> None:
    code = process.wait()
    log_handle.close()
    with PROCESS_LOCK:
        PROCESSES.pop(job_id, None)
    metadata = _metadata(job_id)
    status = "cancelled" if metadata.get("status") == "cancelled" else "complete" if code == 0 else "failed"
    _save_metadata(job_id, exit_code=code, process_finished_at=time.time(), status=status)


def _active_job_ids() -> list[str]:
    active: list[str] = []
    if not JOB_ROOT.is_dir():
        return active
    for directory in JOB_ROOT.iterdir():
        if not directory.is_dir():
            continue
        metadata = _read_json(directory / "job.json", {}) or {}
        if metadata.get("status") not in {"running"}:
            continue
        running, _ = _process_status(directory.name, metadata)
        if running:
            active.append(directory.name)
    return active


def _agent_command(
    *,
    job_id: str,
    source: Path,
    target: Path,
    result_dir: Path,
    metadata: dict[str, Any],
    resume: bool = False,
) -> list[str]:
    """Build the exact workflow command from persisted launch settings."""
    command = [
        sys.executable, "-m", "effect_ir_pipeline.effect_ir.agentic_multipass_translation",
        str(target), "--input-image", str(source), "--repo-root", str(REPO),
        "--work-dir", str(result_dir), "--job-id", job_id,
        "--wait-for-feedback", "--feedback-timeout", "86400", "--max-feedback-rounds", "0",
        "--human-transaction-attempts", "1",
    ]
    pass_count = metadata.get("pass_count")
    pass_description = str(metadata.get("pass_description", "")).strip()
    effect_description = str(metadata.get("effect_description", "")).strip()
    if pass_count not in (None, ""):
        command += ["--pass-count", str(int(pass_count))]
    if pass_description:
        command += ["--pass-description", pass_description]
    if effect_description:
        command += ["--effect-description", effect_description]
    if metadata.get("dense_timeline"):
        command += ["--dense-timeline", "--timeline-interval", "0.2", "--timeline-max-frames", "60"]
    if resume:
        command.append("--resume")
    return command


def _reconcile_jobs() -> None:
    if not JOB_ROOT.is_dir():
        return
    for directory in JOB_ROOT.iterdir():
        metadata = _read_json(directory / "job.json", {}) if directory.is_dir() else {}
        if not metadata or metadata.get("status") != "running":
            continue
        running, _ = _process_status(directory.name, metadata)
        if not running:
            _save_metadata(directory.name, status="interrupted", process_finished_at=time.time())


def _current_video(state: dict[str, Any]) -> Path | None:
    rounds = state.get("round_videos")
    if isinstance(rounds, list) and rounds:
        value = rounds[-1].get("video") if isinstance(rounds[-1], dict) else None
        if value:
            path = Path(str(value)).resolve()
            if path.is_file():
                return path
    value = state.get("rendered_video")
    if value:
        path = Path(str(value)).resolve()
        if path.is_file():
            return path
    return None


def _display_video(state: dict[str, Any]) -> tuple[Path | None, str]:
    accepted = _current_video(state)
    accepted_status = "accepted"
    rounds = state.get("round_videos")
    if (
        isinstance(rounds, list) and rounds and isinstance(rounds[-1], dict)
        and rounds[-1].get("verifier_accepted") is False
        and not rounds[-1].get("human_accepted")
    ):
        accepted_status = "candidate"
    candidates: list[Path] = []
    transactions = state.get("repair_transactions")
    if isinstance(transactions, list):
        for transaction in reversed(transactions):
            if not isinstance(transaction, dict):
                continue
            if "human_transaction" not in str(transaction.get("label", "")) and not transaction.get("staged_for_human_review"):
                continue
            for attempt in reversed(transaction.get("attempts", [])):
                value = attempt.get("candidate_video") if isinstance(attempt, dict) else None
                if value:
                    path = Path(str(value)).resolve()
                    if path.is_file():
                        candidates.append(path)
                        break
            if candidates:
                break
    candidate = candidates[0] if candidates else None
    if candidate is not None and (accepted is None or candidate.stat().st_mtime_ns > accepted.stat().st_mtime_ns):
        return candidate, "candidate"
    return accepted, accepted_status


def _tail(path: Path, limit: int = 6000) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return text[-limit:]


class AgentHandler(BaseHTTPRequestHandler):
    server_version = "MultiPassAgent/1.0"

    def log_message(self, format_string: str, *args: Any) -> None:
        sys.stderr.write(f"[{self.log_date_time_string()}] {format_string % args}\n")

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-File-Name")
        self.send_header("Cache-Control", "no-store")

    def _json_response(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str) -> None:
        self._json_response(status, {"error": message})

    def _body(self, maximum: int = 1024 * 1024) -> bytes:
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > maximum:
            raise ValueError("Request body is too large")
        return self.rfile.read(length)

    def _json_body(self) -> dict[str, Any]:
        value = json.loads(self._body().decode("utf-8") or "{}")
        if not isinstance(value, dict):
            raise ValueError("JSON body must be an object")
        return value

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cors()
        self.end_headers()

    def do_POST(self) -> None:
        try:
            self._post()
        except (ValueError, json.JSONDecodeError) as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
        except Exception as exc:
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def _post(self) -> None:
        parsed = urlparse(self.path)
        parts = [unquote(part) for part in parsed.path.strip("/").split("/") if part]
        if parts == ["api", "agent", "jobs"]:
            payload = self._json_body()
            requested = str(payload.get("name", "")).strip()
            prefix = "".join(character for character in requested if character.isalnum() or character in "_-").strip("_-")[:40]
            job_id = f"{prefix + '_' if prefix else ''}{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
            directory = _job_dir(job_id)
            directory.mkdir(parents=True)
            metadata = {
                "job_id": job_id,
                "status": "uploading",
                "created_at": time.time(),
                "pass_count": payload.get("pass_count"),
                "pass_description": str(payload.get("pass_description", "")).strip(),
                "effect_description": str(payload.get("effect_description", "")).strip(),
                "dense_timeline": bool(payload.get("dense_timeline", False)),
                "source_name": str(payload.get("source_name", "source.png")),
                "video_name": str(payload.get("video_name", "target.mp4")),
            }
            _write_json(directory / "job.json", metadata)
            self._json_response(HTTPStatus.CREATED, metadata)
            return
        if len(parts) == 5 and parts[:3] == ["api", "agent", "jobs"] and parts[4] == "start":
            self._start_job(_safe_job_id(parts[3]))
            return
        if len(parts) == 5 and parts[:3] == ["api", "agent", "jobs"] and parts[4] == "resume":
            self._resume_job(_safe_job_id(parts[3]))
            return
        if len(parts) == 5 and parts[:3] == ["api", "agent", "jobs"] and parts[4] == "feedback":
            self._submit_feedback(_safe_job_id(parts[3]))
            return
        if len(parts) == 5 and parts[:3] == ["api", "agent", "jobs"] and parts[4] == "cancel":
            self._cancel_job(_safe_job_id(parts[3]))
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown endpoint")

    def _start_job(self, job_id: str) -> None:
        directory = _job_dir(job_id)
        metadata = _metadata(job_id)
        source = _upload_path(directory, metadata, "source")
        target = _upload_path(directory, metadata, "target")
        if not source.is_file() or not target.is_file():
            raise ValueError("Upload both source image and target video before starting")
        pass_description = str(metadata.get("pass_description", "")).strip()
        effect_description = str(metadata.get("effect_description", "")).strip()
        pass_count = metadata.get("pass_count")
        if pass_count not in (None, "") and int(pass_count) < 1:
            raise ValueError("Pass count must be a positive integer")
        with PROCESS_LOCK:
            active = _active_job_ids()
            if active:
                self._error(HTTPStatus.CONFLICT, f"Another Agent job is running: {active[0]}")
                return
            result_dir = directory / "results"
            result_dir.mkdir(exist_ok=True)
            command = _agent_command(
                job_id=job_id,
                source=source,
                target=target,
                result_dir=result_dir,
                metadata=metadata,
            )
            log_handle = (directory / "agent.log").open("ab")
            environment = os.environ.copy()
            environment["MULTIPASS_RENDER_REVEAL"] = "0"
            # Automated pass/prefix renders run in the independent local GPU
            # worker. The visible Studio page only displays completed videos
            # and collects human feedback, so a hidden Safari tab cannot stall
            # the Agent.
            environment["MULTIPASS_RENDER_BACKEND"] = "local"
            # A long-running Agent may wait hours for human feedback. Keep it
            # independent from the HTTP API process so a server hot-restart
            # does not terminate or orphan the active feedback workflow.
            process = subprocess.Popen(
                command,
                cwd=REPO,
                env=environment,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            PROCESSES[job_id] = process
            _save_metadata(job_id, status="running", pid=process.pid, started_at=time.time(), command=command)
            threading.Thread(target=_watch_process, args=(job_id, process, log_handle), daemon=True).start()
        self._json_response(HTTPStatus.ACCEPTED, {"job_id": job_id, "status": "running"})

    def _resume_job(self, job_id: str) -> None:
        directory = _job_dir(job_id)
        metadata = _metadata(job_id)
        if not metadata:
            self._error(HTTPStatus.NOT_FOUND, "Job not found")
            return
        running, _ = _process_status(job_id, metadata)
        if running:
            self._error(HTTPStatus.CONFLICT, "Job is already running")
            return
        state_path = _state_path(directory, job_id, metadata)
        state = _read_json(state_path, {}) or {}
        if not state.get("compiled_pass_graph"):
            self._error(HTTPStatus.CONFLICT, "No completed planning checkpoint is available")
            return
        source = _upload_path(directory, metadata, "source")
        target = _upload_path(directory, metadata, "target")
        with PROCESS_LOCK:
            active = [value for value in _active_job_ids() if value != job_id]
            if active:
                self._error(HTTPStatus.CONFLICT, f"Another Agent job is running: {active[0]}")
                return
            result_dir = directory / "results"
            command = _agent_command(
                job_id=job_id, source=source, target=target, result_dir=result_dir,
                metadata=metadata, resume=True,
            )
            (result_dir / "render_request.json").unlink(missing_ok=True)
            log_path = directory / "agent.log"
            with log_path.open("ab") as marker:
                marker.write(f"\n--- RESUME {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n".encode())
            log_handle = log_path.open("ab")
            environment = os.environ.copy()
            environment["MULTIPASS_RENDER_REVEAL"] = "0"
            environment["MULTIPASS_RENDER_BACKEND"] = "local"
            process = subprocess.Popen(
                command, cwd=REPO, env=environment, stdout=log_handle,
                stderr=subprocess.STDOUT, start_new_session=True,
            )
            PROCESSES[job_id] = process
            _save_metadata(
                job_id, status="running", pid=process.pid, started_at=time.time(),
                resumed_at=time.time(), command=command, exit_code=None,
            )
            threading.Thread(target=_watch_process, args=(job_id, process, log_handle), daemon=True).start()
        self._json_response(HTTPStatus.ACCEPTED, {"job_id": job_id, "status": "running", "resumed": True})

    def _cancel_job(self, job_id: str) -> None:
        metadata = _metadata(job_id)
        if not metadata:
            self._error(HTTPStatus.NOT_FOUND, "Job not found")
            return
        running, _ = _process_status(job_id, metadata)
        if not running:
            self._error(HTTPStatus.CONFLICT, "Job is not running")
            return
        _save_metadata(job_id, status="cancelled", cancelled_at=time.time())
        process = PROCESSES.get(job_id)
        if process is not None:
            process.terminate()
        else:
            os.kill(int(metadata["pid"]), signal.SIGTERM)
        (_job_dir(job_id) / "results" / "render_request.json").unlink(missing_ok=True)
        self._json_response(HTTPStatus.ACCEPTED, {"job_id": job_id, "status": "cancelled"})

    def _submit_feedback(self, job_id: str) -> None:
        payload = self._json_body()
        action = "finish" if payload.get("action") == "finish" else "revise"
        feedback = str(payload.get("feedback", "")).strip()
        if action == "revise" and not feedback:
            raise ValueError("Revision feedback cannot be empty")
        directory = _job_dir(job_id)
        metadata = _metadata(job_id)
        workflow_id = _workflow_id(job_id, metadata)
        state = _read_json(_state_path(directory, job_id, metadata), {}) or {}
        if state.get("phase") != "waiting_for_human_feedback":
            self._error(HTTPStatus.CONFLICT, "The Agent is not waiting for feedback")
            return
        feedback_round = int(state.get("feedback_round", 0))
        path = directory / "results" / f"{workflow_id}_feedback_{feedback_round:02d}_web_feedback.json"
        if path.exists():
            self._error(HTTPStatus.CONFLICT, "Feedback for this round was already submitted")
            return
        _write_json(path, {"action": action, "feedback": feedback, "job_id": workflow_id, "received_at": time.time()})
        self._json_response(HTTPStatus.ACCEPTED, {"job_id": workflow_id, "action": action, "round": feedback_round})

    def do_PUT(self) -> None:
        try:
            parsed = urlparse(self.path)
            parts = [unquote(part) for part in parsed.path.strip("/").split("/") if part]
            if len(parts) != 5 or parts[:3] != ["api", "agent", "jobs"] or parts[4] not in {"source-image", "target-video"}:
                self._error(HTTPStatus.NOT_FOUND, "Unknown upload endpoint")
                return
            job_id = _safe_job_id(parts[3])
            directory = _job_dir(job_id)
            if not directory.is_dir():
                self._error(HTTPStatus.NOT_FOUND, "Job not found")
                return
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_UPLOAD_BYTES:
                raise ValueError("Invalid upload size")
            metadata = _metadata(job_id)
            destination = _upload_path(directory, metadata, "source" if parts[4] == "source-image" else "target")
            remaining = length
            with destination.open("wb") as output:
                while remaining:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError("Upload ended before Content-Length")
                    output.write(chunk)
                    remaining -= len(chunk)
            self._json_response(HTTPStatus.CREATED, {"job_id": job_id, "kind": parts[4], "bytes": length})
        except ValueError as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
        except Exception as exc:
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def do_GET(self) -> None:
        try:
            self._get()
        except ValueError as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
        except Exception as exc:
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def _get(self) -> None:
        parsed = urlparse(self.path)
        parts = [unquote(part) for part in parsed.path.strip("/").split("/") if part]
        if parts == ["api", "agent", "health"]:
            self._json_response(HTTPStatus.OK, {"ok": True, "job_root": str(JOB_ROOT)})
            return
        if len(parts) == 4 and parts[:3] == ["api", "agent", "jobs"]:
            self._job_status(_safe_job_id(parts[3]))
            return
        if len(parts) == 5 and parts[:3] == ["api", "agent", "jobs"] and parts[4] in {"video", "source", "target"}:
            self._serve_artifact(_safe_job_id(parts[3]), parts[4])
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown endpoint")

    def _job_status(self, job_id: str) -> None:
        directory = _job_dir(job_id)
        metadata = _metadata(job_id)
        if not metadata:
            self._error(HTTPStatus.NOT_FOUND, "Job not found")
            return
        state_path = _state_path(directory, job_id, metadata)
        state = _read_json(state_path, {}) or {}
        running, exit_code = _process_status(job_id, metadata)
        metadata_status = str(metadata.get("status", "uploading"))
        phase = metadata_status if metadata_status in {"cancelled", "interrupted", "failed"} else str(state.get("phase") or ("running" if running else metadata_status))
        current_video, video_status = _display_video(state)
        rounds = state.get("round_videos", []) if isinstance(state.get("round_videos"), list) else []
        archived_video = _current_video(state)
        visible_round_count = len(rounds) + (1 if current_video is not None and archived_video is not None and current_video != archived_video else 0)
        graph = REPO / "muti_pass" / "multipass-studio" / "public" / "generated" / job_id / "pass_graph.json"
        payload = {
            "job_id": job_id,
            "status": "running" if running else metadata.get("status", "unknown"),
            "phase": phase,
            "planning_mode": state.get("planning_mode", "dense_timeline" if metadata.get("dense_timeline") else "constrained" if (metadata.get("pass_count") or metadata.get("pass_description") or metadata.get("effect_description")) else "model"),
            "resolved_pass_count": state.get("resolved_pass_count"),
            "completed_passes": len(state.get("pass_agents", [])) if isinstance(state.get("pass_agents"), list) else 0,
            "feedback_round": state.get("feedback_round"),
            "round_count": visible_round_count,
            "passes": (state.get("compiled_pass_graph") or {}).get("passes", []),
            "video_url": f"http://{HOST}:{PORT}/api/agent/jobs/{job_id}/video" if current_video else None,
            "video_version": f"{current_video.name}:{current_video.stat().st_mtime_ns}:{current_video.stat().st_size}" if current_video else None,
            "video_status": video_status if current_video else None,
            "source_url": f"http://{HOST}:{PORT}/api/agent/jobs/{job_id}/source",
            "target_url": f"http://{HOST}:{PORT}/api/agent/jobs/{job_id}/target",
            "graph_url": f"/generated/{job_id}/pass_graph.json" if graph.is_file() else None,
            "exit_code": exit_code,
            "error_log": _tail(directory / "agent.log") if not running and metadata.get("status") == "failed" else "",
            "render_request": _read_json(directory / "results" / "render_request.json"),
            "current_obligation": state.get("current_obligation"),
            "last_transaction": state.get("repair_transactions", [])[-1] if state.get("repair_transactions") else None,
        }
        self._json_response(HTTPStatus.OK, payload)

    def _serve_artifact(self, job_id: str, kind: str) -> None:
        directory = _job_dir(job_id)
        metadata = _metadata(job_id)
        if kind == "source":
            path = _upload_path(directory, metadata, "source")
            content_type = "image/*"
        elif kind == "target":
            path = _upload_path(directory, metadata, "target")
            content_type = "video/mp4"
        else:
            state = _read_json(_state_path(directory, job_id, metadata), {}) or {}
            path, _ = _display_video(state)
            content_type = "video/mp4"
        if path is None or not path.is_file():
            self._error(HTTPStatus.NOT_FOUND, "Artifact not available")
            return
        guessed = mimetypes.guess_type(str(path))[0]
        size = path.stat().st_size
        self.send_response(HTTPStatus.OK)
        self._cors()
        self.send_header("Content-Type", guessed or content_type)
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with path.open("rb") as source:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)


def main() -> None:
    JOB_ROOT.mkdir(parents=True, exist_ok=True)
    _reconcile_jobs()
    server = ThreadingHTTPServer((HOST, PORT), AgentHandler)
    print(f"Multi-pass Agent API: http://{HOST}:{PORT}/api/agent/health", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
