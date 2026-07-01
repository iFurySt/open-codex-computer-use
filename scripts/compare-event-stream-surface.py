#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import select
import subprocess
import sys
from typing import Any


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = (
    REPO_ROOT
    / "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-event-stream-surface-1.0.857.json"
)
DEFAULT_OFFICIAL_PLUGIN_DIR = (
    pathlib.Path.home()
    / ".codex/plugins/cache/openai-bundled/record-and-replay/1.0.857"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Record & Replay event-stream MCP initialize/tools-list surface."
    )
    parser.add_argument(
        "--fixture",
        default=str(DEFAULT_FIXTURE),
        help="Normalized official surface fixture JSON.",
    )
    parser.add_argument(
        "--local-command",
        default=str(REPO_ROOT / ".build/debug/OpenComputerUse"),
        help="Local OpenComputerUse binary to launch with 'event-stream mcp'.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Do not run 'swift build --product OpenComputerUse' before local comparison.",
    )
    parser.add_argument(
        "--official-plugin-dir",
        default=os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_PLUGIN_DIR"),
        help="Official record-and-replay plugin directory. If omitted, official comparison is skipped unless --use-default-official is set.",
    )
    parser.add_argument(
        "--use-default-official",
        action="store_true",
        help=f"Probe the default official plugin path: {DEFAULT_OFFICIAL_PLUGIN_DIR}",
    )
    parser.add_argument(
        "--require-official",
        action="store_true",
        help="Fail if the official plugin/client is unavailable.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_TIMEOUT", "10")),
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


def client_for_official_plugin(plugin_dir: pathlib.Path) -> pathlib.Path:
    return (
        plugin_dir
        / "Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
    )


def capture_surface(
    command: list[str],
    cwd: pathlib.Path | None,
    timeout: float,
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    proc = subprocess.Popen(
        command,
        cwd=str(cwd) if cwd else None,
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
        initialize_response = request(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "event-stream-surface-compare",
                        "version": "0",
                    },
                },
            }
        )
        request(
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            expect_response=False,
        )
        tools_response = request(
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        )
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

    assert initialize_response is not None
    assert tools_response is not None
    initialize = initialize_response["result"]
    tools = tools_response["result"]["tools"]
    return {"initialize": initialize, "tools": tools}


def comparable_surface(surface: dict[str, Any], ignore_server_version: bool) -> dict[str, Any]:
    initialize = dict(surface["initialize"])
    server_info = dict(initialize["serverInfo"])
    if ignore_server_version:
        server_info.pop("version", None)
    initialize["serverInfo"] = server_info
    return {
        "initialize": initialize,
        "tools": surface["tools"],
    }


def compare_surface(
    label: str,
    actual: dict[str, Any],
    fixture: dict[str, Any],
    ignore_server_version: bool,
) -> dict[str, Any]:
    comparable_actual = comparable_surface(actual, ignore_server_version=ignore_server_version)
    comparable_fixture = comparable_surface(fixture, ignore_server_version=ignore_server_version)
    ok = canonical(comparable_actual) == canonical(comparable_fixture)
    result: dict[str, Any] = {
        "label": label,
        "ok": ok,
        "ignoreServerVersion": ignore_server_version,
        "protocolVersion": actual["initialize"].get("protocolVersion"),
        "serverName": actual["initialize"].get("serverInfo", {}).get("name"),
        "toolNames": [tool.get("name") for tool in actual.get("tools", [])],
    }
    if not ok:
        result["expected"] = comparable_fixture
        result["actual"] = comparable_actual
    return result


def main() -> int:
    args = parse_args()
    fixture_path = pathlib.Path(args.fixture)
    fixture = load_json(fixture_path)

    if not args.skip_build:
        subprocess.run(
            ["swift", "build", "--product", "OpenComputerUse"],
            cwd=str(REPO_ROOT),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    results: list[dict[str, Any]] = []
    local_surface = capture_surface(
        [args.local_command, "event-stream", "mcp"],
        cwd=REPO_ROOT,
        timeout=args.timeout,
        env={**os.environ, "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1"},
    )
    results.append(
        compare_surface(
            "local-open-computer-use",
            local_surface,
            fixture,
            ignore_server_version=True,
        )
    )

    official_plugin_dir = args.official_plugin_dir
    if args.use_default_official and not official_plugin_dir:
        official_plugin_dir = str(DEFAULT_OFFICIAL_PLUGIN_DIR)

    official_result: dict[str, Any] | None = None
    if official_plugin_dir:
        plugin_dir = pathlib.Path(official_plugin_dir)
        official_client = client_for_official_plugin(plugin_dir)
        if official_client.exists():
            official_surface = capture_surface(
                [str(official_client), "event-stream", "mcp"],
                cwd=plugin_dir,
                timeout=args.timeout,
            )
            official_result = compare_surface(
                "official-record-and-replay",
                official_surface,
                fixture,
                ignore_server_version=False,
            )
            official_result["pluginDir"] = str(plugin_dir)
            official_result["client"] = str(official_client)
            results.append(official_result)
        else:
            official_result = {
                "label": "official-record-and-replay",
                "ok": not args.require_official,
                "skipped": True,
                "reason": "officialClientNotFound",
                "pluginDir": str(plugin_dir),
                "client": str(official_client),
            }
            results.append(official_result)
    elif args.require_official:
        official_result = {
            "label": "official-record-and-replay",
            "ok": False,
            "skipped": True,
            "reason": "officialPluginDirNotProvided",
        }
        results.append(official_result)

    payload = {
        "ok": all(result.get("ok") is True for result in results),
        "fixture": str(fixture_path),
        "results": results,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
