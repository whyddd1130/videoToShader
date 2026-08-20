from __future__ import annotations

import io
import json
import unittest
from email.message import Message
from unittest.mock import patch
from urllib.error import HTTPError

from effect_ir_pipeline.effect_ir import model_client


class _Response:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def read(self) -> bytes:
        return json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode()


class ModelClientBackoffTest(unittest.TestCase):
    def test_429_uses_long_backoff_and_then_recovers(self) -> None:
        headers = Message()
        headers["Retry-After"] = "45"
        limited = HTTPError("https://example.invalid", 429, "limited", headers, io.BytesIO(b"limited"))
        with patch.dict("os.environ", {
            "EFFECT_IR_LLM_ENDPOINT": "https://example.invalid",
            "EFFECT_IR_LLM_RATE_LIMIT_RETRIES": "2",
            "EFFECT_IR_LLM_RATE_LIMIT_SLEEP": "30",
        }, clear=False), patch.object(model_client.request, "urlopen", side_effect=[limited, _Response()]), patch.object(model_client.random, "uniform", return_value=0), patch.object(model_client.time, "sleep") as sleep:
            result = model_client._generate_http_json([{"role": "user", "content": "hello"}], model="model", temperature=0)
        self.assertEqual(result, "ok")
        sleep.assert_called_once_with(45.0)


if __name__ == "__main__":
    unittest.main()
