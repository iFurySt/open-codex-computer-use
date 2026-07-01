#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import select
import subprocess
import sys
import tempfile
from typing import Any


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = (
    REPO_ROOT
    / "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-no-active-status-stop-1.0.857.json"
)
EXPECTED_TOOLS = ["event_stream_status", "event_stream_stop"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Record & Replay no-active status/stop MCP responses against the official fixture."
    )
    parser.add_argument(
        "--fixture",
        default=str(DEFAULT_FIXTURE),
        help="Official Codex-hosted no-active status/stop fixture JSON.",
    )
    parser.add_argument(
        "--local-command",
        default=str(REPO_ROOT / ".build/debug/OpenComputerUse"),
        help="Local OpenComputerUse binary to launch with 'event-stream mcp'.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Do not run 'swift build --product OpenComputerUse' before comparison.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10,
        help="Seconds to wait for each MCP response.",
    )
    return parser.parse_args()


def load_json(path: pathlib.Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object at {path}")
    return value


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def expected_responses(fixture: dict[str, Any]) -> dict[str, dict[str, Any]]:
    tool_responses = fixture.get("toolResponses")
    if not isinstance(tool_responses, dict):
        raise AssertionError("fixture missing toolResponses object")

    expected: dict[str, dict[str, Any]] = {}
    for tool_name in EXPECTED_TOOLS:
        response = tool_responses.get(tool_name)
        if not isinstance(response, dict):
            raise AssertionError(f"fixture missing {tool_name} response")
        content = response.get("content")
        if not isinstance(content, list) or len(content) != 1:
            raise AssertionError(f"fixture {tool_name} response must contain one content item")
        item = content[0]
        if not isinstance(item, dict) or item.get("type") != "text":
            raise AssertionError(f"fixture {tool_name} response must be text content")
        text_json = item.get("textJSON")
        if not isinstance(text_json, dict):
            raise AssertionError(f"fixture {tool_name} response missing textJSON object")
        expected[tool_name] = text_json
    return expected


def text_json_from_tool_result(response: dict[str, Any], tool_name: str) -> dict[str, Any]:
    result = response.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"{tool_name} response missing result")
    content = result.get("content")
    if not isinstance(content, list) or len(content) != 1:
        raise AssertionError(f"{tool_name} response must contain one content item")
    item = content[0]
    if not isinstance(item, dict) or item.get("type") != "text":
        raise AssertionError(f"{tool_name} response must be text content")
    text = item.get("text")
    if not isinstance(text, str):
        raise AssertionError(f"{tool_name} text content missing text field")
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise AssertionError(f"{tool_name} text JSON must parse to an object")
    return parsed


def capture_no_active(
    command: list[str],
    timeout: float,
    recordings_dir: pathlib.Path,
) -> dict[str, dict[str, Any]]:
    env = {
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings_dir),
        "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
        "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
    }
    proc = subprocess.Popen(
        command,
        cwd=str(REPO_ROOT),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    def request(message: dict[str, Any], expect_response: bool = True) -> dict[str, Any] | None:
        assert proc.stdin is not None
        assert proc.stdout is not None
        proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        proc.stdin.flush()
        if not expect_response:
            return None
        ready, _, _ = select.select([proc.stdout], [], [], timeout)
        if not ready:
            raise TimeoutError(f"MCP server did not respond within {timeout}s: {command}")
        line = proc.stdout.readline()
        if not line:
            raise AssertionError(f"MCP server exited before responding: {command}")
        response = json.loads(line)
        if "error" in response:
            raise AssertionError(response["error"])
        return response

    try:
        request(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "event-stream-no-active-compare",
                        "version": "0",
                    },
                },
            }
        )
        request(
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            expect_response=False,
        )
        actual: dict[str, dict[str, Any]] = {}
        for index, tool_name in enumerate(EXPECTED_TOOLS, start=2):
            response = request(
                {
                    "jsonrpc": "2.0",
                    "id": index,
                    "method": "tools/call",
                    "params": {"name": tool_name, "arguments": {}},
                }
            )
            assert response is not None
            actual[tool_name] = text_json_from_tool_result(response, tool_name)
    finally:
        if proc.stdin:
            proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        stderr = proc.stderr.read() if proc.stderr else ""
        if proc.returncode != 0:
            raise AssertionError(stderr)

    forbidden_files = [
        recordings_dir / "latest-session.json",
        recordings_dir / "active-session.json",
    ]
    session_dirs = [path for path in recordings_dir.iterdir() if path.is_dir()]
    created_files = [path for path in forbidden_files if path.exists()] + session_dirs
    if created_files:
        relative = [str(path.relative_to(recordings_dir)) for path in created_files]
        raise AssertionError(f"no-active status/stop created session files: {relative}")

    return actual


def main() -> int:
    args = parse_args()
    fixture_path = pathlib.Path(args.fixture)
    fixture = load_json(fixture_path)
    expected = expected_responses(fixture)

    if not args.skip_build:
        subprocess.run(
            ["swift", "build", "--product", "OpenComputerUse"],
            cwd=str(REPO_ROOT),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    with tempfile.TemporaryDirectory(prefix="event-stream-no-active-") as tmp:
        recordings_dir = pathlib.Path(tmp)
        actual = capture_no_active(
            [args.local_command, "event-stream", "mcp"],
            timeout=args.timeout,
            recordings_dir=recordings_dir,
        )
        ok = canonical(actual) == canonical(expected)
        payload: dict[str, Any] = {
            "ok": ok,
            "fixture": str(fixture_path),
            "recordingsDir": str(recordings_dir),
            "checkedTools": EXPECTED_TOOLS,
            "expected": expected,
            "actual": actual,
            "createdSessionFiles": False,
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
