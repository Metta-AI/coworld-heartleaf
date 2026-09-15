import argparse
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "claude_subscription_bridge.py"
SPEC = importlib.util.spec_from_file_location("claude_subscription_bridge", MODULE_PATH)
bridge_module = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(bridge_module)


def args(trace: str) -> argparse.Namespace:
    return argparse.Namespace(
        claude="claude", model="", effort="low", max_parallel=1,
        timeout=10, trace=trace, cwd=str(MODULE_PATH.parent.parent),
    )


class ClaudeSubscriptionBridgeTests(unittest.TestCase):
    def body(self):
        return {
            "max_tokens": 192,
            "system": [{"type": "text", "text": "Return JSON only."}],
            "messages": [{"role": "user", "content": [{"text": "Choose wait."}]}],
        }

    def test_prompt_conversion(self):
        system, prompt = bridge_module.request_prompt(self.body())
        self.assertEqual(system, "Return JSON only.")
        self.assertIn("USER:\nChoose wait.", prompt)

    def test_invoke_strips_provider_overrides_and_returns_bedrock_shape(self):
        envelope = {
            "is_error": False,
            "result": '{"action":"wait"}',
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 12, "output_tokens": 4},
            "modelUsage": {"claude-haiku-4-5-20251001": {"provider": "firstParty"}},
        }
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {
            "ANTHROPIC_API_KEY": "hidden", "ANTHROPIC_AUTH_TOKEN": "hidden",
            "ANTHROPIC_BASE_URL": "https://invalid", "CLAUDE_CODE_USE_BEDROCK": "1",
            "MAX_THINKING_TOKENS": "32000",
        }), patch.object(subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps(envelope), "")
            result = bridge_module.Bridge(args(str(Path(temp) / "trace.jsonl"))).invoke(
                "/model/anthropic.claude-haiku/invoke", {"X-Coworld-Player-Slot": "2"}, self.body()
            )
            child_env = run.call_args.kwargs["env"]
            for name in bridge_module.SECRET_ENV_NAMES:
                self.assertNotIn(name, child_env)
            self.assertEqual(child_env["MAX_THINKING_TOKENS"], "0")
            record = json.loads((Path(temp) / "trace.jsonl").read_text())
            self.assertEqual(record["thinking_requested"], "disabled")
            self.assertEqual(result["content"][0]["text"], '{"action":"wait"}')
            self.assertEqual(result["model"], "claude-haiku-4-5-20251001")

    def test_exit_zero_error_envelope_is_rejected_and_traced(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(subprocess, "run") as run:
            trace = Path(temp) / "trace.jsonl"
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps({
                "is_error": True, "result": "quota exhausted", "subtype": "error"
            }), "")
            with self.assertRaisesRegex(RuntimeError, "quota exhausted"):
                bridge_module.Bridge(args(str(trace))).invoke(
                    "/model/anthropic.claude-haiku/invoke", {}, self.body()
                )
            record = json.loads(trace.read_text().splitlines()[0])
            self.assertEqual(record["error_kind"], "envelope")

    def test_auth_check_requires_first_party_subscription(self):
        valid = {"loggedIn": True, "authMethod": "claude.ai", "apiProvider": "firstParty"}
        with patch.object(subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps(valid), "")
            bridge_module.require_subscription_auth("claude")
        invalid = {"loggedIn": True, "authMethod": "apiKey", "apiProvider": "firstParty"}
        with patch.object(subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps(invalid), "")
            with self.assertRaises(SystemExit):
                bridge_module.require_subscription_auth("claude")

    def test_queue_wait_is_bounded_and_traced(self):
        with tempfile.TemporaryDirectory() as temp:
            trace = Path(temp) / "trace.jsonl"
            bridge = bridge_module.Bridge(args(str(trace)))
            bridge.slots = MagicMock()
            bridge.slots.acquire.return_value = False
            with self.assertRaises(subprocess.TimeoutExpired), patch.object(subprocess, "run") as run:
                bridge.invoke("/model/anthropic.claude-haiku/invoke", {}, self.body())
            run.assert_not_called()
            record = json.loads(trace.read_text().splitlines()[0])
            self.assertEqual(record["error_kind"], "queue_timeout")


if __name__ == "__main__":
    unittest.main()
