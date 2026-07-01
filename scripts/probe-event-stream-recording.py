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
import time
from typing import Any


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OFFICIAL_PLUGIN_DIR = (
    pathlib.Path.home()
    / ".codex/plugins/cache/openai-bundled/record-and-replay/1.0.857"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Probe a Record & Replay event-stream MCP server and optionally run a "
            "short start/stop recording cycle."
        )
    )
    parser.add_argument(
        "--target",
        choices=["local", "official"],
        default="official",
        help="Which event-stream MCP server to probe.",
    )
    parser.add_argument(
        "--client",
        help="Executable to launch. Defaults to local .build/debug/OpenComputerUse or the official bundled client.",
    )
    parser.add_argument(
        "--plugin-dir",
        default=os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_PLUGIN_DIR"),
        help="Official record-and-replay plugin directory.",
    )
    parser.add_argument(
        "--recordings-dir",
        help="Recording output directory to pass through OPEN_COMPUTER_USE_EVENT_STREAM_DIR.",
    )
    parser.add_argument(
        "--start-stop",
        action="store_true",
        help="Call event_stream_start and then event_stream_stop. Without this flag only initialize/tools-list are probed.",
    )
    parser.add_argument(
        "--decline-elicitation",
        action="store_true",
        help="Deprecated alias for --elicitation-action decline.",
    )
    parser.add_argument(
        "--elicitation-action",
        choices=["accept", "decline", "cancel"],
        default="accept",
        help="Action to return when the server sends elicitation/create.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_TIMEOUT", "10")),
        help="Seconds to wait for each MCP response.",
    )
    parser.add_argument(
        "--output",
        help="Optional path to write the full JSON probe result.",
    )
    parser.add_argument(
        "--fixture-output",
        help="Optional path to write a sanitized, repo-stable probe fixture.",
    )
    parser.add_argument(
        "--official-plugin-version",
        default="1.0.857",
        help="Official Record & Replay plugin version to record in fixture output.",
    )
    parser.add_argument(
        "--allow-start-timeout",
        action="store_true",
        help="Return success when initialize/tools-list work but event_stream_start times out. Useful for documenting official raw-client host constraints.",
    )
    args = parser.parse_args()
    if args.decline_elicitation:
        if args.elicitation_action != "accept":
            parser.error("--decline-elicitation cannot be combined with --elicitation-action")
        args.elicitation_action = "decline"
    return args


def official_client(plugin_dir: pathlib.Path) -> pathlib.Path:
    return (
        plugin_dir
        / "Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
    )


def launch_config(args: argparse.Namespace) -> tuple[list[str], pathlib.Path, dict[str, str], pathlib.Path]:
    env = os.environ.copy()
    recordings_dir = pathlib.Path(args.recordings_dir) if args.recordings_dir else pathlib.Path(
        tempfile.mkdtemp(prefix="event-stream-probe-")
    ) / "recordings"
    env["OPEN_COMPUTER_USE_EVENT_STREAM_DIR"] = str(recordings_dir)

    if args.target == "local":
        client = pathlib.Path(args.client) if args.client else REPO_ROOT / ".build/debug/OpenComputerUse"
        env.setdefault("OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY", "1")
        env.setdefault("OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL", "approve")
        env.setdefault("OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS", "0")
        env.setdefault("OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS", "never")
        return [str(client), "event-stream", "mcp"], REPO_ROOT, env, recordings_dir

    plugin_dir = pathlib.Path(args.plugin_dir) if args.plugin_dir else DEFAULT_OFFICIAL_PLUGIN_DIR
    client = pathlib.Path(args.client) if args.client else official_client(plugin_dir)
    return [str(client), "event-stream", "mcp"], plugin_dir, env, recordings_dir


class MCPProbe:
    def __init__(self, command: list[str], cwd: pathlib.Path, env: dict[str, str], timeout: float):
        self.command = command
        self.cwd = cwd
        self.timeout = timeout
        self.next_id = 1
        self.transcript: list[dict[str, Any]] = []
        self.proc = subprocess.Popen(
            command,
            cwd=str(cwd),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )

    def send(self, message: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        self.transcript.append({"direction": "send", "message": message})
        self.proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def request(self, method: str, params: dict[str, Any] | None = None) -> int:
        message_id = self.next_id
        self.next_id += 1
        self.send(
            {
                "jsonrpc": "2.0",
                "id": message_id,
                "method": method,
                "params": params or {},
            }
        )
        return message_id

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def read(self) -> dict[str, Any]:
        assert self.proc.stdout is not None
        ready, _, _ = select.select([self.proc.stdout], [], [], self.timeout)
        if not ready:
            message = {"timeout": self.timeout}
            self.transcript.append({"direction": "receive", "message": message})
            return message
        line = self.proc.stdout.readline()
        if not line:
            message = {"eof": True}
            self.transcript.append({"direction": "receive", "message": message})
            return message
        try:
            message = json.loads(line)
        except json.JSONDecodeError as error:
            message = {"raw": line, "parseError": str(error)}
        self.transcript.append({"direction": "receive", "message": message})
        return message

    def close(self) -> dict[str, Any]:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=3)
        stderr = self.proc.stderr.read() if self.proc.stderr else ""
        return {"returncode": self.proc.returncode, "stderr": stderr}


def decode_tool_text(result: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(result, dict):
        return None
    content = result.get("content")
    if not isinstance(content, list):
        return None
    for item in content:
        if not isinstance(item, dict) or item.get("type") != "text":
            continue
        text = item.get("text")
        if not isinstance(text, str):
            continue
        try:
            decoded = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(decoded, dict):
            return decoded
    return None


def sanitize_probe_value(value: Any) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, child in value.items():
            if key in {"command", "cwd", "recordingsDir"}:
                continue
            if key == "text" and isinstance(child, str):
                try:
                    decoded_text = json.loads(child)
                except json.JSONDecodeError:
                    result[key] = child
                else:
                    result["textJSON"] = sanitize_probe_value(decoded_text)
                continue
            if key in {
                "eventsPath",
                "metadataPath",
                "sessionPath",
                "suppressedEventsPath",
                "currentSegmentEventsPath",
                "currentSegmentMetadataPath",
            }:
                result[key] = f"<redacted-{key}>"
                continue
            if key in {"sessionId", "sessionID"} and isinstance(child, str):
                result[key] = "<redacted-session-id>"
                continue
            if key.endswith("At") and isinstance(child, str):
                result[key] = "<redacted-timestamp>"
                continue
            result[key] = sanitize_probe_value(child)
        return result
    if isinstance(value, list):
        return [sanitize_probe_value(child) for child in value]
    return value


def summarize_probe(result: dict[str, Any], official_plugin_version: str) -> dict[str, Any]:
    initialize = result.get("initializeResponse", {})
    initialize_result = initialize.get("result", {}) if isinstance(initialize, dict) else {}
    tools_response = result.get("toolsResponse", {})
    tools_result = tools_response.get("result", {}) if isinstance(tools_response, dict) else {}
    tools = tools_result.get("tools", []) if isinstance(tools_result, dict) else []
    transcript = []
    elicitation_requests = []
    for entry in result.get("transcript", []):
        if not isinstance(entry, dict):
            continue
        message = entry.get("message", {})
        if not isinstance(message, dict):
            continue
        if entry.get("direction") == "receive" and message.get("method") == "elicitation/create":
            params = message.get("params")
            if isinstance(params, dict):
                requested_schema = params.get("requestedSchema")
                schema_properties = (
                    requested_schema.get("properties")
                    if isinstance(requested_schema, dict)
                    else None
                )
                elicitation_requests.append(
                    {
                        "mode": params.get("mode"),
                        "message": params.get("message"),
                        "requestedSchemaType": requested_schema.get("type")
                        if isinstance(requested_schema, dict)
                        else None,
                        "requestedSchemaPropertyNames": sorted(schema_properties.keys())
                        if isinstance(schema_properties, dict)
                        else None,
                        "requestedSchemaRequired": requested_schema.get("required")
                        if isinstance(requested_schema, dict)
                        else None,
                        "requestedSchemaHasAdditionalProperties": "additionalProperties"
                        in requested_schema
                        if isinstance(requested_schema, dict)
                        else None,
                    }
                )
        transcript.append(
            {
                "direction": entry.get("direction"),
                "id": message.get("id"),
                "method": message.get("method"),
                "hasResult": "result" in message,
                "hasError": "error" in message,
                "timeout": message.get("timeout"),
                "eof": message.get("eof"),
            }
        )
    return {
        "fixtureFormatVersion": 1,
        "kind": "record-and-replay-event-stream-probe",
        "source": result.get("target"),
        "officialPluginVersion": official_plugin_version if result.get("target") == "official" else None,
        "ok": result.get("ok"),
        "startStopRequested": result.get("startStopRequested"),
        "startStopCompleted": result.get("startStopCompleted"),
        "startTimedOut": result.get("startTimedOut"),
        "serverInfo": sanitize_probe_value(initialize_result.get("serverInfo")),
        "protocolVersion": initialize_result.get("protocolVersion"),
        "toolNames": [tool.get("name") for tool in tools if isinstance(tool, dict)],
        "startResponseShape": sanitize_probe_value(result.get("startResponse")),
        "repeatStartResponseShape": sanitize_probe_value(result.get("repeatStartResponse")),
        "statusResponseShape": sanitize_probe_value(result.get("statusResponse")),
        "stopResponseShape": sanitize_probe_value(result.get("stopResponse")),
        "repeatStopResponseShape": sanitize_probe_value(result.get("repeatStopResponse")),
        "finalStatusResponseShape": sanitize_probe_value(result.get("finalStatusResponse")),
        "elicitationRequests": sanitize_probe_value(elicitation_requests),
        "process": sanitize_probe_value(result.get("process")),
        "transcriptShape": transcript,
    }


def wait_for_response(
    probe: MCPProbe,
    response_id: int,
    elicitation_action: str,
) -> dict[str, Any]:
    while True:
        message = probe.read()
        if message.get("method") == "elicitation/create":
            content = {} if elicitation_action == "accept" else None
            probe.send(
                {
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {"action": elicitation_action, "content": content},
                }
            )
            continue
        if message.get("id") == response_id:
            return message
        if "timeout" in message or "eof" in message or "parseError" in message:
            return message


def probe_server(args: argparse.Namespace) -> dict[str, Any]:
    command, cwd, env, recordings_dir = launch_config(args)
    result: dict[str, Any] = {
        "ok": False,
        "target": args.target,
        "command": command,
        "cwd": str(cwd),
        "recordingsDir": str(recordings_dir),
        "startStopRequested": args.start_stop,
    }
    client_path = pathlib.Path(command[0])
    if not client_path.exists():
        result.update({"error": "clientNotFound", "client": str(client_path)})
        return result

    probe = MCPProbe(command, cwd, env, args.timeout)
    elicitation_action = args.elicitation_action
    try:
        initialize_id = probe.request(
            "initialize",
            {
                "protocolVersion": "2025-11-25",
                "capabilities": {"elicitation": {}},
                "clientInfo": {"name": "event-stream-recording-probe", "version": "0"},
            },
        )
        initialize = wait_for_response(probe, initialize_id, elicitation_action)
        result["initializeResponse"] = initialize
        if "result" not in initialize:
            return result

        probe.notify("notifications/initialized")
        tools_id = probe.request("tools/list")
        tools = wait_for_response(probe, tools_id, elicitation_action)
        result["toolsResponse"] = tools

        if args.start_stop:
            start_id = probe.request(
                "tools/call",
                {"name": "event_stream_start", "arguments": {}},
            )
            start = wait_for_response(probe, start_id, elicitation_action)
            result["startResponse"] = start
            decoded_start = decode_tool_text(start.get("result") if isinstance(start, dict) else None)
            if decoded_start:
                result["startStatus"] = decoded_start

            if "result" in start:
                repeat_start_id = probe.request(
                    "tools/call",
                    {"name": "event_stream_start", "arguments": {}},
                )
                repeat_start = wait_for_response(
                    probe,
                    repeat_start_id,
                    elicitation_action,
                )
                result["repeatStartResponse"] = repeat_start
                decoded_repeat_start = decode_tool_text(
                    repeat_start.get("result") if isinstance(repeat_start, dict) else None
                )
                if decoded_repeat_start:
                    result["repeatStartStatus"] = decoded_repeat_start

            should_try_stop = "result" in start or "timeout" in start
            if should_try_stop:
                # Give the recorder a moment to flush session.started before the stop request.
                time.sleep(0.2)
                status_id = probe.request(
                    "tools/call",
                    {"name": "event_stream_status", "arguments": {}},
                )
                status = wait_for_response(probe, status_id, elicitation_action)
                result["statusResponse"] = status
                decoded_status = decode_tool_text(status.get("result") if isinstance(status, dict) else None)
                if decoded_status:
                    result["statusStatus"] = decoded_status

                stop_id = probe.request(
                    "tools/call",
                    {"name": "event_stream_stop", "arguments": {}},
                )
                stop = wait_for_response(probe, stop_id, elicitation_action)
                result["stopResponse"] = stop
                decoded_stop = decode_tool_text(stop.get("result") if isinstance(stop, dict) else None)
                if decoded_stop:
                    result["stopStatus"] = decoded_stop

                if "result" in stop:
                    repeat_stop_id = probe.request(
                        "tools/call",
                        {"name": "event_stream_stop", "arguments": {}},
                    )
                    repeat_stop = wait_for_response(
                        probe,
                        repeat_stop_id,
                        elicitation_action,
                    )
                    result["repeatStopResponse"] = repeat_stop
                    decoded_repeat_stop = decode_tool_text(
                        repeat_stop.get("result")
                        if isinstance(repeat_stop, dict)
                        else None
                    )
                    if decoded_repeat_stop:
                        result["repeatStopStatus"] = decoded_repeat_stop

                    final_status_id = probe.request(
                        "tools/call",
                        {"name": "event_stream_status", "arguments": {}},
                    )
                    final_status = wait_for_response(
                        probe,
                        final_status_id,
                        elicitation_action,
                    )
                    result["finalStatusResponse"] = final_status
                    decoded_final_status = decode_tool_text(
                        final_status.get("result")
                        if isinstance(final_status, dict)
                        else None
                    )
                    if decoded_final_status:
                        result["finalStatusStatus"] = decoded_final_status

        surface_ok = "result" in result.get("initializeResponse", {}) and "result" in result.get(
            "toolsResponse", {}
        )
        result["startStopCompleted"] = False
        result["startTimedOut"] = False
        if args.start_stop:
            start_response = result.get("startResponse", {})
            stop_response = result.get("stopResponse", {})
            result["startStopCompleted"] = "result" in start_response and "result" in stop_response
            result["startTimedOut"] = "timeout" in start_response
            result["ok"] = surface_ok and (
                result["startStopCompleted"]
                or (args.allow_start_timeout and result["startTimedOut"])
            )
        else:
            result["ok"] = surface_ok
    finally:
        result["process"] = probe.close()
        result["transcript"] = probe.transcript
    return result


def main() -> int:
    args = parse_args()
    result = probe_server(args)
    output = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False)
    if args.output:
        pathlib.Path(args.output).write_text(output + "\n")
    if args.fixture_output:
        fixture = summarize_probe(result, args.official_plugin_version)
        fixture_path = pathlib.Path(args.fixture_output)
        fixture_path.parent.mkdir(parents=True, exist_ok=True)
        fixture_path.write_text(
            json.dumps(fixture, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        )
    print(output)
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
