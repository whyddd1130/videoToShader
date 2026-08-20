from __future__ import annotations

import json
import os
import random
import subprocess
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib import error
from urllib import request


DEFAULT_WANQING_ENDPOINT = "https://wanqing-api.corp.kuaishou.com/api/gateway/v1/endpoints/chat/completions"


def _load_project_dotenv() -> None:
    """Load the repository's local model configuration without overriding shell env.

    The command-line workflows are launched directly with ``python -m``.  They
    previously did not read the project's `.env`, so a valid HTTPS endpoint and
    API key in that file were silently ignored and the code fell back to the
    inaccessible `wanqing.internal` address.
    """
    dotenv = Path(__file__).resolve().parents[2] / ".env"
    if not dotenv.is_file():
        return
    for raw_line in dotenv.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        if key:
            os.environ.setdefault(key, value)


_load_project_dotenv()


def generate_text(prompt: str, *, model: str, temperature: float = 0.0) -> str:
    return generate_messages(
        [{"role": "user", "content": prompt}],
        model=model,
        temperature=temperature,
    )


def generate_messages(messages: list[dict[str, Any]], *, model: str, temperature: float = 0.0) -> str:
    """Single interface for connecting any LLM provider.

    Supported modes:
    - http_json: POST to an HTTP endpoint that accepts a JSON prompt payload.
    - command: call a local command and pass the prompt through stdin.

    Edit this function if your provider has a different SDK or request format.
    """
    provider = os.environ.get("EFFECT_IR_LLM_PROVIDER", "http_json")
    if provider == "http_json":
        return _generate_http_json(messages, model=model, temperature=temperature)
    if provider == "command":
        prompt = _messages_to_prompt(messages)
        return _generate_command(prompt, model=model)
    raise ValueError(f"Unsupported EFFECT_IR_LLM_PROVIDER: {provider}")


def _generate_http_json(messages: list[dict[str, Any]], *, model: str, temperature: float) -> str:
    base_url = os.environ.get("EFFECT_IR_LLM_BASE_URL")
    endpoint = os.environ.get("EFFECT_IR_LLM_ENDPOINT")
    if endpoint is None:
        if base_url is not None:
            endpoint = base_url.rstrip("/") + "/chat/completions"
        else:
            endpoint = DEFAULT_WANQING_ENDPOINT
    api_key = os.environ.get("EFFECT_IR_LLM_API_KEY") or os.environ.get("WQ_API_KEY", "EMPTY")
    payload: dict[str, Any] = {
        "model": model,
        "messages": _normalize_messages(messages),
    }
    max_tokens = os.environ.get("EFFECT_IR_LLM_MAX_TOKENS", "").strip()
    if max_tokens:
        try:
            payload["max_tokens"] = max(1, int(max_tokens))
        except ValueError as exc:
            raise ValueError("EFFECT_IR_LLM_MAX_TOKENS must be a positive integer") from exc
    if temperature not in (None, 0, 0.0, 1, 1.0):
        payload["temperature"] = temperature
    if os.environ.get("EFFECT_IR_LLM_JSON_MODE", "0") == "1":
        payload["response_format"] = {"type": "json_object"}
    stream = os.environ.get("EFFECT_IR_LLM_STREAM", "0").strip().lower() in {"1", "true", "yes"}
    if stream:
        payload["stream"] = True
    data = json.dumps(payload).encode("utf-8")
    req = request.Request(
        endpoint,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "Accept": "text/event-stream" if stream else "application/json",
        },
        method="POST",
    )
    retries = max(1, int(os.environ.get("EFFECT_IR_LLM_RETRIES", "3")))
    rate_limit_retries = max(retries, int(os.environ.get("EFFECT_IR_LLM_RATE_LIMIT_RETRIES", "6")))
    base_sleep = float(os.environ.get("EFFECT_IR_LLM_RETRY_SLEEP", "2"))
    rate_limit_sleep = float(os.environ.get("EFFECT_IR_LLM_RATE_LIMIT_SLEEP", "30"))
    rate_limit_sleep_cap = float(os.environ.get("EFFECT_IR_LLM_RATE_LIMIT_MAX_SLEEP", "240"))
    timeout = float(os.environ.get("EFFECT_IR_LLM_TIMEOUT", "300"))
    last_error: Exception | None = None
    for attempt in range(1, rate_limit_retries + 1):
        is_rate_limit = False
        retry_after: float | None = None
        try:
            with request.urlopen(req, timeout=timeout) as resp:
                if stream:
                    return _extract_streaming_text(resp)
                body = json.loads(resp.read().decode("utf-8"))
            return _extract_text(body)
        except error.HTTPError as exc:
            details = exc.read().decode("utf-8", errors="replace")
            last_error = RuntimeError(f"HTTP {exc.code} from model endpoint: {details}")
            is_rate_limit = exc.code == 429
            retry_after = _retry_after_seconds(exc) if is_rate_limit else None
            if not is_rate_limit and attempt >= retries:
                break
        except error.URLError as exc:
            last_error = RuntimeError(f"URL error from model endpoint: {exc.reason}")
            if attempt >= retries:
                break
        except (TimeoutError, ConnectionError, OSError) as exc:
            last_error = RuntimeError(f"Timeout from model endpoint: {exc}")
            if attempt >= retries:
                break
        if is_rate_limit and attempt < rate_limit_retries:
            exponential = min(rate_limit_sleep_cap, rate_limit_sleep * (2 ** (attempt - 1)))
            delay = max(exponential, retry_after or 0.0)
            delay += random.uniform(0.0, min(5.0, delay * 0.1))
            print(f"Model rate-limited (429); retry {attempt + 1}/{rate_limit_retries} in {delay:.1f}s", flush=True)
            time.sleep(delay)
        elif attempt < retries:
            time.sleep(base_sleep * attempt)
    assert last_error is not None
    raise last_error


def _retry_after_seconds(exc: error.HTTPError) -> float | None:
    """Read either numeric seconds or an HTTP date from Retry-After."""
    value = exc.headers.get("Retry-After") if exc.headers else None
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except ValueError:
        try:
            parsed = parsedate_to_datetime(value)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return max(0.0, (parsed - datetime.now(timezone.utc)).total_seconds())
        except (TypeError, ValueError, OverflowError):
            return None


def _extract_streaming_text(response: Any) -> str:
    """Collect OpenAI-compatible SSE deltas, retaining only final answer content.

    Reasoning deltas are intentionally not fed back into the shader loop. They do
    keep the HTTP stream active, which is useful for providers that otherwise
    reset a long non-streaming visual-reasoning request before final content.
    """
    content_parts: list[str] = []
    event_count = 0
    reasoning_char_count = 0
    for raw_line in response:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line.startswith("data:"):
            continue
        event_data = line[5:].strip()
        if not event_data or event_data == "[DONE]":
            continue
        try:
            event = json.loads(event_data)
        except json.JSONDecodeError:
            continue
        event_count += 1
        choices = event.get("choices") or []
        if not choices:
            continue
        delta = choices[0].get("delta") or {}
        content = delta.get("content", "")
        if isinstance(content, list):
            content = "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))
        if content:
            content_parts.append(str(content))
        reasoning = delta.get("reasoning_content", delta.get("reasoning", ""))
        if isinstance(reasoning, list):
            reasoning = "".join(str(part.get("text", "")) for part in reasoning if isinstance(part, dict))
        reasoning_char_count += len(str(reasoning or ""))
    text = "".join(content_parts).strip()
    if text:
        return text
    raise ValueError(
        "Streaming model returned no final content "
        f"(events={event_count}, reasoning_chars={reasoning_char_count})"
    )


def _extract_text(body: dict[str, Any]) -> str:
    if "choices" in body:
        content = body["choices"][0]["message"]["content"]
        if isinstance(content, list):
            text = "".join(str(item.get("text", "")) for item in content if isinstance(item, dict))
        else:
            text = str(content or "")
        if text.strip():
            return text
        finish_reason = body["choices"][0].get("finish_reason")
        usage = body.get("usage")
        raise ValueError(f"Model returned empty text; finish_reason={finish_reason}; usage={usage}")
    if "text" in body:
        return str(body["text"])
    if "output" in body:
        return str(body["output"])
    if "response" in body:
        return str(body["response"])
    raise ValueError(f"Cannot extract model text from response keys: {sorted(body)}")


def _generate_command(prompt: str, *, model: str) -> str:
    command_template = os.environ.get("EFFECT_IR_LLM_COMMAND")
    if not command_template:
        raise RuntimeError("EFFECT_IR_LLM_COMMAND is required when EFFECT_IR_LLM_PROVIDER=command")
    command = command_template.format(model=model)
    result = subprocess.run(
        command,
        input=prompt,
        text=True,
        shell=True,
        capture_output=True,
        check=True,
    )
    return result.stdout


def _normalize_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    content_mode = os.environ.get("EFFECT_IR_LLM_CONTENT_MODE", "text")
    normalized: list[dict[str, Any]] = []
    for message in messages:
        content = message.get("content", "")
        if content_mode == "parts":
            normalized_content: Any = content if isinstance(content, list) else [{"type": "text", "text": str(content)}]
        else:
            normalized_content = _messages_to_prompt([message]) if isinstance(content, list) else str(content)
        normalized.append({"role": message.get("role", "user"), "content": normalized_content})
    return normalized


def _messages_to_prompt(messages: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for message in messages:
        role = str(message.get("role", "user")).upper()
        content = message.get("content", "")
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                item_type = item.get("type")
                if item_type == "text":
                    parts.append(str(item.get("text", "")))
                elif item_type == "image_url":
                    image_url = item.get("image_url", {})
                    if isinstance(image_url, dict):
                        parts.append(f"[image: {image_url.get('url', '')[:64]}...]")
                    else:
                        parts.append(f"[image: {str(image_url)[:64]}...]")
            text = "\n".join(part for part in parts if part)
        else:
            text = str(content)
        lines.append(f"{role}:\n{text}")
    return "\n\n".join(lines)
