#!/usr/bin/env python3
"""Local Bedrock-shaped HTTP bridge to an authenticated Claude subscription.

This is an opt-in development tool. It invokes the installed Claude CLI in
print mode, with tools and customizations disabled, and returns the model text
in the Anthropic Bedrock response shape Heartleaf already understands.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


SECRET_ENV_NAMES = {
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_BASE_URL",
    "AWS_BEARER_TOKEN_BEDROCK",
    "BEDROCK_KEY",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "CLAUDE_CODE_USE_BEDROCK",
    "CLAUDE_CODE_USE_VERTEX",
    "CLAUDE_CODE_USE_FOUNDRY",
    "CLAUDE_CODE_USE_FABRIC",
}


def clean_environment() -> dict[str, str]:
    return {key: value for key, value in os.environ.items() if key not in SECRET_ENV_NAMES}


def require_subscription_auth(claude: str) -> None:
    completed = subprocess.run(
        [claude, "auth", "status", "--json"], text=True, capture_output=True,
        timeout=30, env=clean_environment(), check=False,
    )
    try:
        status = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit("bridge: could not verify Claude subscription auth") from error
    if completed.returncode != 0 or not status.get("loggedIn") or \
        status.get("authMethod") != "claude.ai" or status.get("apiProvider") != "firstParty":
        raise SystemExit("bridge: Claude must use logged-in claude.ai first-party subscription auth")


def text_parts(value: Any) -> str:
    if isinstance(value, str):
        return value
    if not isinstance(value, list):
        return ""
    return "".join(
        part.get("text", "")
        for part in value
        if isinstance(part, dict) and isinstance(part.get("text"), str)
    )


def request_prompt(body: dict[str, Any]) -> tuple[str, str]:
    system = text_parts(body.get("system", []))
    turns: list[str] = []
    for message in body.get("messages", []):
        if not isinstance(message, dict):
            continue
        role = str(message.get("role", "user")).upper()
        content = text_parts(message.get("content", []))
        turns.append(f"{role}:\n{content}")
    turns.append("ASSISTANT:\nReturn only the response requested by the game.")
    return system, "\n\n".join(turns)


def model_alias(path: str, override: str) -> str:
    if override:
        return override
    lowered = path.lower()
    if "opus" in lowered:
        return "opus"
    if "sonnet" in lowered:
        return "sonnet"
    return "haiku"


class Bridge:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.started = time.time()
        self.sequence = 0
        self.lock = threading.Lock()
        self.slots = threading.BoundedSemaphore(args.max_parallel)
        self.trace_path = Path(args.trace)
        self.trace_path.parent.mkdir(parents=True, exist_ok=True)

    def trace(self, record: dict[str, Any]) -> None:
        with self.lock:
            self.sequence += 1
            record["sequence"] = self.sequence
            with self.trace_path.open("a", encoding="utf-8") as output:
                output.write(json.dumps(record, ensure_ascii=False) + "\n")

    def invoke(self, path: str, headers: Any, body: dict[str, Any]) -> dict[str, Any]:
        system, prompt = request_prompt(body)
        alias = model_alias(path, self.args.model)
        command = [
            self.args.claude,
            "-p",
            "--safe-mode",
            "--tools",
            "",
            "--disable-slash-commands",
            "--strict-mcp-config",
            "--no-session-persistence",
            "--permission-prompts",
            "none",
            "--model",
            alias,
            "--effort",
            self.args.effort,
            "--output-format",
            "json",
        ]
        if system:
            command.extend(["--system-prompt", system])
        clean_env = clean_environment()
        # Heartleaf sends ordinary action/interview requests without extended
        # thinking. Do not inherit the coding CLI's much larger thinking budget.
        clean_env["MAX_THINKING_TOKENS"] = "0"
        started = time.time()
        slot = headers.get("X-Coworld-Player-Slot", "")
        acquired = self.slots.acquire(timeout=self.args.timeout)
        if not acquired:
            self.trace({
                "kind": "claude_subscription_call", "ok": False,
                "slot": slot, "requested_model": alias,
                "requested_max_tokens": body.get("max_tokens", 0),
                "error_kind": "queue_timeout",
                "duration_ms": round((time.time() - started) * 1000),
            })
            raise subprocess.TimeoutExpired(command, self.args.timeout)
        try:
            remaining = max(0.001, self.args.timeout - (time.time() - started))
            completed = subprocess.run(
                command,
                input=prompt,
                text=True,
                capture_output=True,
                timeout=remaining,
                env=clean_env,
                cwd=self.args.cwd,
                check=False,
            )
        except subprocess.TimeoutExpired:
            self.trace({
                "kind": "claude_subscription_call",
                "ok": False,
                "slot": slot,
                "requested_model": alias,
                "requested_max_tokens": body.get("max_tokens", 0),
                "error_kind": "timeout",
                "duration_ms": round((time.time() - started) * 1000),
            })
            raise
        finally:
            self.slots.release()
        duration_ms = round((time.time() - started) * 1000)
        if completed.returncode != 0:
            error = completed.stderr.strip() or completed.stdout.strip() or "Claude CLI failed"
            self.trace({
                "kind": "claude_subscription_call",
                "ok": False,
                "slot": slot,
                "requested_model": alias,
                "requested_max_tokens": body.get("max_tokens", 0),
                "duration_ms": duration_ms,
                "error_kind": "exit",
                "error": error[:2000],
            })
            raise RuntimeError(error)
        try:
            envelope = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            self.trace({
                "kind": "claude_subscription_call",
                "ok": False,
                "slot": slot,
                "requested_model": alias,
                "requested_max_tokens": body.get("max_tokens", 0),
                "duration_ms": duration_ms,
                "error_kind": "decode",
                "error": str(error),
            })
            raise RuntimeError("Claude CLI returned invalid JSON") from error
        if envelope.get("is_error"):
            error = str(envelope.get("result") or envelope.get("subtype") or "Claude CLI error")
            self.trace({
                "kind": "claude_subscription_call",
                "ok": False,
                "slot": slot,
                "requested_model": alias,
                "requested_max_tokens": body.get("max_tokens", 0),
                "duration_ms": duration_ms,
                "error_kind": "envelope",
                "error": error[:2000],
            })
            raise RuntimeError(error)
        result = envelope.get("result", "")
        usage = envelope.get("usage", {})
        actual_models = sorted((envelope.get("modelUsage") or {}).keys())
        self.trace({
            "kind": "claude_subscription_call",
            "ok": True,
            "slot": slot,
            "requested_model": alias,
            "requested_max_tokens": body.get("max_tokens", 0),
            "max_tokens_enforced": False,
            "thinking_requested": "disabled",
            "actual_models": actual_models,
            "provider": sorted({
                item.get("provider", "")
                for item in (envelope.get("modelUsage") or {}).values()
                if isinstance(item, dict)
            }),
            "duration_ms": duration_ms,
            "input_tokens": usage.get("input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
            "result": result,
        })
        return {
            "id": f"claude-subscription-{self.sequence + 1}",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": result}],
            "model": actual_models[0] if actual_models else alias,
            "stop_reason": envelope.get("stop_reason", "end_turn"),
            "usage": {
                "input_tokens": usage.get("input_tokens", 0),
                "output_tokens": usage.get("output_tokens", 0),
            },
        }


def handler_for(bridge: Bridge) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "HeartleafClaudeSubscriptionBridge/1"

        def send_json(self, code: int, value: dict[str, Any]) -> None:
            encoded = json.dumps(value).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/healthz":
                self.send_json(200, {"status": "healthy", "uptime_seconds": round(time.time() - bridge.started, 1)})
            else:
                self.send_json(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                self.send_json(200, bridge.invoke(self.path, self.headers, body))
            except subprocess.TimeoutExpired:
                self.send_json(504, {"message": "Claude subscription call timed out"})
            except Exception as error:  # Return an endpoint-shaped failure to Heartleaf.
                self.send_json(500, {"message": str(error)[:2000]})

        def log_message(self, fmt: str, *args: Any) -> None:
            sys.stderr.write("bridge: " + (fmt % args) + "\n")

    return Handler


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--claude", default=shutil.which("claude") or "claude")
    parser.add_argument("--model", default=os.environ.get("HEARTLEAF_CLAUDE_MODEL", ""))
    parser.add_argument("--effort", default="low", choices=["low", "medium", "high"])
    parser.add_argument("--max-parallel", type=int, default=9)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--trace", default="out/claude-subscription/bridge-trace.jsonl")
    parser.add_argument("--cwd", default=str(Path(__file__).resolve().parent.parent))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.host not in {"127.0.0.1", "localhost"}:
        raise SystemExit("bridge: --host must be a loopback address")
    require_subscription_auth(args.claude)
    print("bridge: verified claude.ai first-party subscription auth", flush=True)
    bridge = Bridge(args)
    server = ThreadingHTTPServer((args.host, args.port), handler_for(bridge))
    print(f"bridge: listening on http://{args.host}:{args.port}; trace={args.trace}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
