#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TMPDIR:-}" ]]; then
  tmpdir="${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TMPDIR}"
  mkdir -p "${tmpdir}"
  cleanup_tmpdir=0
else
  tmpdir="$(mktemp -d)"
  cleanup_tmpdir=1
fi
if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_KEEP_TMP:-0}" == "1" ]]; then
  cleanup_tmpdir=0
fi
if [[ "${cleanup_tmpdir}" == "1" ]]; then
  trap 'rm -rf "${tmpdir}"' EXIT
fi

cd "${repo_root}"

swift build --product OpenComputerUse >/dev/null

messages_file="${tmpdir}/messages.jsonl"
cat >"${messages_file}" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"event-stream-smoke","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"event_stream_status","arguments":{}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"event_stream_stop","arguments":{}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"event_stream_stop","arguments":{}}}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"event_stream_status","arguments":{}}}
JSONL

screenshot_policy="never"
if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_SCREENSHOTS:-0}" == "1" ]]; then
  screenshot_policy="always"
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS:-0}" == "1" ]]; then
  python3 - "${tmpdir}" "${screenshot_policy}" <<'PY'
import json
import os
import pathlib
import socket
import subprocess
import sys
import time

root = pathlib.Path(sys.argv[1])
screenshot_policy = sys.argv[2]
recordings = root / "recordings"
socket_path = root / "open-computer-use-agent.sock"
mcp_transcript_path = root / "action-mcp-transcript.json"
action_scenario = os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO", "mixed-action-stop")
supported_action_scenarios = {
    "mixed-action-stop",
    "simple-action-stop",
    "drag-stop",
}
assert action_scenario in supported_action_scenarios, action_scenario


def start_process(command, env=None):
    return subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


agent = start_process([".build/debug/OpenComputerUse", "__open-computer-use-app-agent", str(socket_path)])


def request(payload, persistent_socket=None):
    data = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
    if persistent_socket is not None:
        persistent_socket.sendall(data)
        chunks = []
        while True:
            chunk = persistent_socket.recv(65536)
            assert chunk, "app-agent closed persistent connection before newline response"
            if b"\n" in chunk:
                before, _sep, _after = chunk.partition(b"\n")
                chunks.append(before)
                break
            chunks.append(chunk)
        response = json.loads(b"".join(chunks).decode())
        if "error" in response:
            raise AssertionError(response["error"])
        return response

    deadline = time.time() + 10
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        while True:
            try:
                client.connect(str(socket_path))
                break
            except OSError as error:
                if time.time() >= deadline:
                    raise AssertionError(f"failed to connect to app-agent socket: {error}")
                time.sleep(0.05)
        client.sendall(data)
        chunks = []
        while True:
            chunk = client.recv(65536)
            assert chunk, "app-agent closed connection before newline response"
            if b"\n" in chunk:
                before, _sep, _after = chunk.partition(b"\n")
                chunks.append(before)
                break
            chunks.append(chunk)
    response = json.loads(b"".join(chunks).decode())
    if "error" in response:
        raise AssertionError(response["error"])
    return response


def cli(arguments, environment=None):
    response = request({
        "kind": "cli",
        "arguments": arguments,
        "environment": environment or {},
    })
    assert response["exitCode"] == 0, response
    stdout = response["stdout"].strip()
    assert stdout, response
    return json.loads(stdout)


mcp_next_id = 1
mcp_transcript = []
mcp_response_shapes = {}


def mcp_exchange(message, environment=None, expect_response=True):
    line = json.dumps(message, separators=(",", ":"))
    mcp_transcript.append({"direction": "send", "message": message})
    response = request({
        "kind": "eventStreamMCP",
        "line": line,
        "environment": environment or {},
    }).get("response")
    if response is None:
        assert not expect_response, message
        return None
    parsed = json.loads(response)
    mcp_transcript.append({"direction": "receive", "message": parsed})
    return parsed


def mcp_request(method, params=None, environment=None, expect_response=True):
    global mcp_next_id
    message = {
        "jsonrpc": "2.0",
        "id": mcp_next_id,
        "method": method,
    }
    mcp_next_id += 1
    if params is not None:
        message["params"] = params
    return mcp_exchange(message, environment=environment, expect_response=expect_response)


def mcp_notify(method, params=None, environment=None):
    message = {
        "jsonrpc": "2.0",
        "method": method,
    }
    if params is not None:
        message["params"] = params
    return mcp_exchange(message, environment=environment, expect_response=False)


def decode_mcp_tool_text(response):
    assert isinstance(response, dict), response
    assert "result" in response, response
    content = response["result"].get("content", [])
    assert content, response
    text = content[0].get("text")
    assert isinstance(text, str) and text.strip(), response
    return json.loads(text)


def mcp_tool_call(tool_name, shape_key, environment=None):
    response = mcp_request(
        "tools/call",
        {"name": tool_name, "arguments": {}},
        environment=environment,
    )
    mcp_response_shapes[shape_key] = response
    return decode_mcp_tool_text(response)


def write_mcp_transcript():
    payload = {
        "target": "local-open-computer-use-action-smoke",
        "transcript": mcp_transcript,
        **mcp_response_shapes,
    }
    mcp_transcript_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


try:
    deadline = time.time() + 10
    while not socket_path.exists():
        if time.time() >= deadline:
            raise AssertionError("timed out waiting for app-agent socket")
        time.sleep(0.05)

    start_env = {
        "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
        "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": screenshot_policy,
        "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
    }
    if action_scenario != "mixed-action-stop":
        start_env["OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS"] = "0"
    initialized = mcp_request(
        "initialize",
        {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "event-stream-action-smoke", "version": "0"},
        },
        environment=start_env,
    )
    assert initialized["result"]["serverInfo"]["name"] == "Record & Replay", initialized
    mcp_notify("notifications/initialized", {}, environment=start_env)
    listed = mcp_request("tools/list", {}, environment=start_env)
    assert [tool["name"] for tool in listed["result"]["tools"]] == [
        "event_stream_start",
        "event_stream_status",
        "event_stream_stop",
    ], listed

    started = mcp_tool_call("event_stream_start", "startResponseShape", environment=start_env)
    session_id = started["sessionId"]
    assert started["state"] == "recording"
    repeated_start = mcp_tool_call("event_stream_start", "repeatStartResponseShape", environment=start_env)
    assert repeated_start["sessionId"] == session_id
    status = mcp_tool_call("event_stream_status", "statusResponseShape", environment=start_env)
    assert status["sessionId"] == session_id
    assert status["state"] == "recording"

    subprocess.run([
        "swift",
        "-e",
        """
import CoreGraphics
import Darwin
import Foundation
let point = CGEvent(source: nil)?.location ?? CGPoint(x: 240, y: 240)
guard let source = CGEventSource(stateID: .hidSystemState) else {
    exit(2)
}
let scenario = ProcessInfo.processInfo.environment["OCU_ACTION_SCENARIO"] ?? "mixed-action-stop"

func postClick() {
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        exit(2)
    }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cghidEventTap)
    usleep(50_000)
    up.post(tap: .cghidEventTap)
    usleep(50_000)
}

func postScroll() {
    guard let scroll = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: -4, wheel2: 0, wheel3: 0) else {
        exit(2)
    }
    scroll.post(tap: .cghidEventTap)
    usleep(50_000)
}

func postShortcut() {
    for _ in 0..<2 {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 79, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 79, keyDown: false) else {
            exit(2)
        }
        keyDown.flags = [.maskShift]
        keyUp.flags = [.maskShift]
        keyDown.post(tap: .cgSessionEventTap)
        usleep(100_000)
        keyUp.post(tap: .cgSessionEventTap)
        usleep(150_000)
    }
}

func postTextInput() {
    for _ in 0..<3 {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            exit(2)
        }
        keyDown.flags = []
        keyUp.flags = []
        var text = Array("a".utf16)
        text.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                exit(2)
            }
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        }
        keyDown.post(tap: .cghidEventTap)
        usleep(100_000)
        keyUp.post(tap: .cghidEventTap)
        usleep(150_000)
    }
}

func postDrag() {
    let end = CGPoint(x: point.x + 48, y: point.y + 36)
    let mid = CGPoint(x: point.x + 24, y: point.y + 18)
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let dragged = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: mid, mouseButton: .left),
          let draggedEnd = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) else {
        exit(2)
    }
    down.post(tap: .cghidEventTap)
    usleep(50_000)
    dragged.post(tap: .cghidEventTap)
    usleep(50_000)
    draggedEnd.post(tap: .cghidEventTap)
    usleep(50_000)
    up.post(tap: .cghidEventTap)
    usleep(50_000)
}

switch scenario {
case "mixed-action-stop":
    postClick()
    postScroll()
case "simple-action-stop":
    postClick()
case "drag-stop":
    postDrag()
default:
    exit(3)
}
""",
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OCU_ACTION_SCENARIO": action_scenario,
    })

    time.sleep(0.5)
    stopped = mcp_tool_call("event_stream_stop", "stopResponseShape", environment=start_env)
    assert stopped["sessionId"] == session_id
    assert stopped["state"] == "stopped"
    repeated_stop = mcp_tool_call("event_stream_stop", "repeatStopResponseShape", environment=start_env)
    assert repeated_stop["sessionId"] == session_id
    final_status = mcp_tool_call("event_stream_status", "finalStatusResponseShape", environment=start_env)
    assert final_status["sessionId"] == session_id
    assert final_status["state"] == "stopped"
    required_mcp_response_shape_keys = {
        "startResponseShape",
        "repeatStartResponseShape",
        "statusResponseShape",
        "stopResponseShape",
        "repeatStopResponseShape",
        "finalStatusResponseShape",
    }
    missing_response_shape_keys = sorted(required_mcp_response_shape_keys - set(mcp_response_shapes))
    assert not missing_response_shape_keys, {
        "missingResponseShapes": missing_response_shape_keys,
        "mcpResponseShapes": sorted(mcp_response_shapes),
    }
    checked_mcp_response_shapes_captured = True
    write_mcp_transcript()
    events_path = pathlib.Path(stopped["eventsPath"])
    handoff_metadata_path = pathlib.Path(stopped["metadataPath"])
    session_dir = pathlib.Path(stopped.get("sessionDirectoryPath") or handoff_metadata_path.parent)
    metadata_path = session_dir / "metadata.json"
    events = [
        json.loads(line)
        for line in events_path.read_text().splitlines()
        if line.strip()
    ]
    event_types = [event.get("type") for event in events]
    required_event_types = {
        "mixed-action-stop": {"mouse.click"},
        "simple-action-stop": {"mouse.click"},
        "drag-stop": {"mouse.drag"},
    }[action_scenario]
    for required_event_type in required_event_types:
        assert required_event_type in event_types, event_types
    assert "AX.focusedWindowChanged" in event_types, event_types
    validation_required_event_types = [
        "AX.focusedWindowChanged",
        "session.ended",
        *sorted(required_event_types),
    ]

    validate_command = [
        sys.executable,
        "scripts/validate-event-stream-recording.py",
        str(metadata_path),
        "--strict-ocu",
        "--require-skill-draft",
    ]
    for required_event_type in validation_required_event_types:
        validate_command.extend(["--require-event-type", required_event_type])
    subprocess.run(validate_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    runtime_validate_command = [
        ".build/debug/OpenComputerUse",
        "event-stream",
        "validate",
        "--json",
        "--strict-ocu",
        "--require-skill-draft",
        str(metadata_path),
    ]
    for required_event_type in validation_required_event_types:
        runtime_validate_command[-1:-1] = ["--require-event-type", required_event_type]
    subprocess.run(runtime_validate_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    })
    subprocess.run([
        ".build/debug/OpenComputerUse",
        "event-stream",
        "summarize",
        "--json",
        "--require-action",
        str(metadata_path),
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    })
    skill_dir = root / "generated-action-skill"
    scaffold = subprocess.run([
        ".build/debug/OpenComputerUse",
        "event-stream",
        "scaffold-skill",
        "--json",
        str(metadata_path),
        "--skill-name",
        "recorded-action-smoke",
        "--description",
        "Replay the action smoke workflow captured by Open Computer Use Record & Replay.",
        "--output-dir",
        str(skill_dir),
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    })
    scaffold_payload = json.loads(scaffold.stdout)
    assert scaffold_payload["ok"] is True, scaffold_payload
    skill_path = pathlib.Path(scaffold_payload["skillPath"])
    summary_path = pathlib.Path(scaffold_payload["summaryPath"])
    assert skill_path.exists(), scaffold_payload
    assert summary_path.exists(), scaffold_payload
    skill_text = skill_path.read_text()
    summary_text = summary_path.read_text()
    summary_json = json.loads(summary_text)
    skill_creator_handoff_snippets = [
        "connector, API, or dedicated tool",
        "skill-creator",
        "Complete the `skill-creator` workflow, including validation",
        "not a standalone runbook or replay plan",
    ]
    for snippet in skill_creator_handoff_snippets:
        assert snippet in skill_text, skill_text
    checked_skill_creator_finalization_handoff = True
    assert "Replay Steps" in skill_text, skill_text
    expected_replay_text = {
        "mixed-action-stop": ("Click", "Scroll in"),
        "simple-action-stop": ("Click",),
        "drag-stop": ("Drag",),
    }[action_scenario]
    for expected_text in expected_replay_text:
        assert expected_text in skill_text, skill_text
    readiness = summary_json.get("skillReadiness", {})
    assert readiness.get("status") in ("ready", "needsReview"), readiness
    assert readiness.get("canCreateSkillDraft") is True, readiness
    checked_skill_readiness_can_create_draft = True
    combined_scaffold_text = skill_text + "\n" + summary_text
    forbidden_path_fragments = [
        "/Users/",
        "/var/folders/",
        "/private/var/",
        "/tmp/",
        str(metadata_path),
        str(events_path),
        str(session_dir),
    ]
    for fragment in forbidden_path_fragments:
        assert fragment not in combined_scaffold_text, fragment
    assert summary_json.get("metadataPath") == "<recording-metadataPath>", summary_json
    assert summary_json.get("eventsPath") == "<recording-eventsPath>", summary_json
    assert summary_json.get("sessionDir") == "<recording-sessionDir>", summary_json
    checked_generated_skill_path_redaction = True

    request({"kind": "terminate"})
finally:
    for process in [agent]:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
    agent_stderr = agent.stderr.read() if agent.stderr else ""
    if agent.returncode not in (0, -15, None):
        raise AssertionError(f"app-agent exited with {agent.returncode}: {agent_stderr}")

print(json.dumps({
    "ok": True,
    "mode": "actions",
    "actionScenario": action_scenario,
    "sessionId": session_id,
    "eventCount": stopped["eventCount"],
    "eventTypes": sorted(set(event_types)),
    "recordingsRoot": str(recordings),
    "screenshotPolicy": screenshot_policy,
    "skillPath": str(skill_path),
    "mcpTranscriptPath": str(mcp_transcript_path),
    "checkedGeneratedSkillPathRedaction": checked_generated_skill_path_redaction,
    "checkedMcpResponseShapesCaptured": checked_mcp_response_shapes_captured,
    "checkedSkillCreatorFinalizationHandoff": checked_skill_creator_finalization_handoff,
    "checkedSkillReadinessCanCreateDraft": checked_skill_readiness_can_create_draft,
}, sort_keys=True))
PY
  exit 0
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_MCP_ELICITATION:-0}" == "1" ]]; then
  python3 - "${tmpdir}" <<'PY'
import json
import os
import pathlib
import select
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
recordings = root / "recordings"

env = os.environ.copy()
env.update({
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "mcp",
    "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
    "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
})

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "event-stream", "mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

def read_response(timeout=5):
    ready, _, _ = select.select([proc.stdout], [], [], timeout)
    assert ready, f"MCP server did not respond within {timeout}s"
    line = proc.stdout.readline()
    assert line, "MCP server exited before responding"
    return json.loads(line)

def send(message):
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()

def request(message, timeout=5):
    send(message)
    return read_response(timeout=timeout)

def tool_text(response):
    content = response["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])

try:
    initialize_response = request({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {"elicitation": {}},
            "clientInfo": {"name": "event-stream-mcp-elicitation-smoke", "version": "0"},
        },
    })
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    send({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "event_stream_start", "arguments": {}},
    })
    elicitation_request = read_response()
    assert elicitation_request["method"] == "elicitation/create"
    assert elicitation_request["params"]["mode"] == "form"
    assert "Record & Replay" in elicitation_request["params"]["message"]
    assert elicitation_request["params"]["requestedSchema"]["type"] == "object"
    assert "additionalProperties" not in elicitation_request["params"]["requestedSchema"]
    send({
        "jsonrpc": "2.0",
        "id": elicitation_request["id"],
        "result": {
            "action": "accept",
            "content": {},
        },
    })
    start_response = read_response()
    stop_response = request({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "event_stream_stop", "arguments": {}},
    })
finally:
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

initialize = initialize_response["result"]
assert initialize["protocolVersion"] == "2025-11-25"
assert initialize["serverInfo"]["name"] == "Record & Replay"
assert "instructions" not in initialize

started = tool_text(start_response)
stopped = tool_text(stop_response)
session_id = started["sessionId"]
assert started["state"] == "recording"
assert stopped["state"] == "stopped"
assert stopped["sessionId"] == session_id
assert stopped["endReason"] == "recording_controls_stopped"
session_path = pathlib.Path(stopped["sessionPath"])
metadata_path = session_path.parent / "metadata.json"
assert metadata_path.exists()
subprocess.run([
    sys.executable,
    "scripts/validate-event-stream-recording.py",
    str(metadata_path),
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "session.ended",
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "session.ended",
    str(metadata_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})

print(json.dumps({
    "ok": True,
    "mode": "mcp-elicitation",
    "sessionId": session_id,
    "eventCount": stopped["eventCount"],
    "recordingsRoot": str(recordings),
}, sort_keys=True))
PY
  exit 0
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APP_AGENT_WAIT:-0}" == "1" ]]; then
  python3 - "${tmpdir}" "${screenshot_policy}" <<'PY'
import json
import os
import pathlib
import socket
import subprocess
import sys
import threading
import time

root = pathlib.Path(sys.argv[1])
screenshot_policy = sys.argv[2]
recordings = root / "recordings"
socket_path = root / "open-computer-use-agent.sock"

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "__open-computer-use-app-agent", str(socket_path)],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

def connect_with_retry():
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            return socket.socket(socket.AF_UNIX, socket.SOCK_STREAM).connect(str(socket_path))
        except OSError as error:
            last_error = error
            time.sleep(0.05)
    raise AssertionError(f"timed out waiting for app-agent socket: {last_error}")

def request(payload):
    deadline = time.time() + 10
    data = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        while True:
            try:
                client.connect(str(socket_path))
                break
            except OSError as error:
                if time.time() >= deadline:
                    raise AssertionError(f"failed to connect to app-agent socket: {error}")
                time.sleep(0.05)
        client.sendall(data)
        chunks = []
        while True:
            chunk = client.recv(4096)
            assert chunk, "app-agent closed connection before newline response"
            if b"\n" in chunk:
                before, _sep, _after = chunk.partition(b"\n")
                chunks.append(before)
                break
            chunks.append(chunk)
    response = json.loads(b"".join(chunks).decode())
    if "error" in response:
        raise AssertionError(response["error"])
    return response

def cli(arguments, environment=None):
    response = request({
        "kind": "cli",
        "arguments": arguments,
        "environment": environment or {},
    })
    assert response["exitCode"] == 0, response
    stdout = response["stdout"].strip()
    assert stdout, response
    return json.loads(stdout)

def event_stream_mcp(message, environment=None):
    response = request({
        "kind": "eventStreamMCP",
        "line": json.dumps(message, separators=(",", ":")),
        "environment": environment or {},
    })
    if response["response"] is None:
        return None
    return json.loads(response["response"])

def tool_text(response):
    content = response["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])

try:
    connect_with_retry()
    start_env = {
        "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
        "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": screenshot_policy,
        "OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
    }
    initialize_response = event_stream_mcp({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "event-stream-app-agent-wait-smoke", "version": "0"},
        },
    }, start_env)
    event_stream_mcp({
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": {},
    }, start_env)
    start_response = event_stream_mcp({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "event_stream_start", "arguments": {}},
    }, start_env)

    initialize = initialize_response["result"]
    assert initialize["protocolVersion"] == "2025-11-25"
    assert initialize["serverInfo"]["name"] == "Record & Replay"
    assert "instructions" not in initialize

    started = tool_text(start_response)
    session_id = started["sessionId"]
    assert started["state"] == "recording"
    assert started["active"] is True
    assert pathlib.Path(started["eventsPath"]).is_relative_to(recordings)

    notify_script = root / "notify.sh"
    notify_status_path = root / "notify-status.json"
    notify_session_path = root / "notify-session.txt"
    notify_state_path = root / "notify-state.txt"
    notify_script.write_text(
        "#!/bin/sh\n"
        "cat > \"$1\"\n"
        "printf '%s' \"$OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID\" > \"$2\"\n"
        "printf '%s' \"$OPEN_COMPUTER_USE_EVENT_STREAM_STATE\" > \"$3\"\n"
        "test -n \"$OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH\"\n"
        "test -n \"$OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH\"\n",
        encoding="utf-8",
    )
    notify_script.chmod(0o755)

    waited = {}
    wait_error = {}

    def wait_for_stop():
        try:
            waited["status"] = cli([
                "event-stream",
                "wait",
                "--json",
                "--session-id",
                session_id,
                "--timeout",
                "5",
                "--notify-command",
                json.dumps([
                    str(notify_script),
                    str(notify_status_path),
                    str(notify_session_path),
                    str(notify_state_path),
                ]),
            ])
        except BaseException as error:
            wait_error["error"] = error

    waiter = threading.Thread(target=wait_for_stop)
    waiter.start()
    time.sleep(0.3)
    stopped = cli(["event-stream", "stop", "--json"])
    waiter.join(timeout=8)

    assert not waiter.is_alive(), "wait command did not return after stop"
    if "error" in wait_error:
        raise wait_error["error"]
    waited_status = waited["status"]

    assert stopped["state"] == "stopped"
    assert stopped["sessionId"] == session_id
    assert stopped["endReason"] == "recording_controls_stopped"
    assert waited_status["state"] == "stopped"
    assert waited_status["sessionId"] == session_id
    assert waited_status["endReason"] == stopped["endReason"]
    assert waited_status["waitTimedOut"] is False
    assert waited_status["waitSessionMatched"] is True
    notification = waited_status["notification"]
    assert notification["attempted"] is True
    assert notification["skipped"] is False
    assert notification["ok"] is True
    assert notification["exitCode"] == 0

    notify_status = json.loads(notify_status_path.read_text())
    assert notify_status["sessionId"] == session_id
    assert notify_status["state"] == "stopped"
    assert notify_status["waitTimedOut"] is False
    assert notify_status["waitSessionMatched"] is True
    assert notify_session_path.read_text() == session_id
    assert notify_state_path.read_text() == "stopped"

    completed_wait = cli([
        "event-stream",
        "wait",
        "--json",
        "--session-id",
        session_id,
        "--timeout",
        "5",
    ])
    assert completed_wait["state"] == "stopped"
    assert completed_wait["sessionId"] == session_id
    assert completed_wait["endReason"] == stopped["endReason"]
    assert completed_wait["waitTimedOut"] is False
    assert completed_wait["waitSessionMatched"] is True

    events_path = pathlib.Path(stopped["eventsPath"])
    session_path = pathlib.Path(stopped["sessionPath"])
    metadata_path = session_path.parent / "metadata.json"
    session_alias_path = metadata_path.parent / "session.json"
    assert events_path.exists()
    assert metadata_path.exists()
    metadata = json.loads(metadata_path.read_text())
    session_alias = json.loads(session_alias_path.read_text())
    assert session_alias.get("id") == metadata.get("sessionId")
    assert session_alias.get("eventsPath") == metadata.get("eventsPath")
    assert session_alias.get("startedAt") == metadata.get("startedAt")
    assert session_alias.get("endReason") == metadata.get("endReason")
    assert not (recordings / "active-session.json").exists()
    subprocess.run([
        sys.executable,
        "scripts/validate-event-stream-recording.py",
        str(metadata_path),
        "--strict-ocu",
        "--require-event-type",
        "session.started",
        "--require-event-type",
        "session.ended",
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    subprocess.run([
        ".build/debug/OpenComputerUse",
        "event-stream",
        "validate",
        "--json",
        "--strict-ocu",
        "--require-event-type",
        "session.started",
        "--require-event-type",
        "session.ended",
        str(metadata_path),
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    })

    request({"kind": "terminate"})
finally:
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

print(json.dumps({
    "ok": True,
    "mode": "app-agent-wait",
    "sessionId": session_id,
    "eventCount": stopped["eventCount"],
    "recordingsRoot": str(recordings),
    "screenshotPolicy": screenshot_policy,
}, sort_keys=True))
PY
  exit 0
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_WAIT_TIMEOUT:-0}" == "1" ]]; then
  python3 - "${tmpdir}" "${screenshot_policy}" <<'PY'
import json
import os
import pathlib
import socket
import subprocess
import sys
import time

root = pathlib.Path(sys.argv[1])
screenshot_policy = sys.argv[2]
recordings = root / "recordings"
socket_path = root / "open-computer-use-agent.sock"

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "__open-computer-use-app-agent", str(socket_path)],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

def request(payload):
    deadline = time.time() + 10
    data = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        while True:
            try:
                client.connect(str(socket_path))
                break
            except OSError as error:
                if time.time() >= deadline:
                    raise AssertionError(f"failed to connect to app-agent socket: {error}")
                time.sleep(0.05)
        client.sendall(data)
        chunks = []
        while True:
            chunk = client.recv(4096)
            assert chunk, "app-agent closed connection before newline response"
            if b"\n" in chunk:
                before, _sep, _after = chunk.partition(b"\n")
                chunks.append(before)
                break
            chunks.append(chunk)
    response = json.loads(b"".join(chunks).decode())
    if "error" in response:
        raise AssertionError(response["error"])
    return response

def cli(arguments, environment=None):
    response = request({
        "kind": "cli",
        "arguments": arguments,
        "environment": environment or {},
    })
    assert response["exitCode"] == 0, response
    stdout = response["stdout"].strip()
    assert stdout, response
    return json.loads(stdout)

try:
    start_env = {
        "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
        "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": screenshot_policy,
        "OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "0",
        "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
    }
    started = cli(["event-stream", "start", "--json"], start_env)
    session_id = started["sessionId"]
    assert started["state"] == "recording"
    assert pathlib.Path(started["eventsPath"]).is_relative_to(recordings)

    waited = cli([
        "event-stream",
        "wait",
        "--json",
        "--session-id",
        session_id,
        "--timeout",
        "0.2",
    ])
    assert waited["sessionId"] == session_id
    assert waited["state"] == "recording"
    assert waited["active"] is True
    assert waited["waitTimedOut"] is True
    assert waited["waitSessionMatched"] is True

    cancelled = cli(["event-stream", "cancel", "--json"])
    assert cancelled["sessionId"] == session_id
    assert cancelled["state"] == "cancelled"
    assert cancelled["endReason"] == "recording_controls_cancelled"
    assert not (recordings / "active-session.json").exists()
    subprocess.run([
        sys.executable,
        "scripts/validate-event-stream-recording.py",
        str(cancelled["metadataPath"]),
        "--strict-ocu",
        "--require-event-type",
        "session.started",
        "--require-event-type",
        "session.ended",
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    subprocess.run([
        ".build/debug/OpenComputerUse",
        "event-stream",
        "validate",
        "--json",
        "--strict-ocu",
        "--require-event-type",
        "session.started",
        "--require-event-type",
        "session.ended",
        str(cancelled["metadataPath"]),
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
        **os.environ,
        "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    })

    request({"kind": "terminate"})
finally:
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

print(json.dumps({
    "ok": True,
    "mode": "wait-timeout",
    "sessionId": session_id,
    "waitTimedOut": waited["waitTimedOut"],
    "recordingsRoot": str(recordings),
    "screenshotPolicy": screenshot_policy,
}, sort_keys=True))
PY
  exit 0
fi

if [[ -n "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL:-}" ]]; then
  approval_policy="${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL}"
  if [[ "${approval_policy}" != "deny" && "${approval_policy}" != "cancel" ]]; then
    echo "OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL must be 'deny' or 'cancel'" >&2
    exit 2
  fi
python3 - "${tmpdir}" "${approval_policy}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
approval_policy = sys.argv[2]
recordings = root / "recordings"

env = os.environ.copy()
env.update({
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": approval_policy,
    "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
    "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
})

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "event-stream", "mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

def request(message, expect_response=True):
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    if not expect_response:
        return None
    line = proc.stdout.readline()
    assert line, "MCP server exited before responding"
    return json.loads(line)

try:
    initialize_response = request({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "event-stream-approval-smoke", "version": "0"},
        },
    })
    request({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, expect_response=False)
    start_response = request({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "event_stream_start", "arguments": {}},
    })
finally:
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

initialize = initialize_response["result"]
assert initialize["protocolVersion"] == "2025-11-25"
assert initialize["serverInfo"]["name"] == "Record & Replay"
assert "instructions" not in initialize

result = start_response["result"]
assert result["isError"] is True
content = result["content"]
assert content and content[0]["type"] == "text"
text = content[0]["text"]
if approval_policy == "deny":
    expected = "Record & Replay approval denied via MCP elicitation."
else:
    expected = "Record & Replay approval cancelled via MCP elicitation."
assert text == expected
assert not (recordings / "latest-session.json").exists()
assert not (recordings / "active-session.json").exists()

print(json.dumps({
    "ok": True,
    "mode": "approval",
    "approvalPolicy": approval_policy,
    "message": text,
    "recordingsRoot": str(recordings),
}, sort_keys=True))
PY
  exit 0
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_NO_ACTIVE:-0}" == "1" ]]; then
  python3 - "${tmpdir}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
recordings = root / "recordings"

env = os.environ.copy()
env.update({
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
    "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
    "OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
})

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "event-stream", "mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

def request(message, expect_response=True):
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    if not expect_response:
        return None
    line = proc.stdout.readline()
    assert line, "MCP server exited before responding"
    return json.loads(line)

def tool_text(response):
    content = response["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])

try:
    initialize_response = request({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "event-stream-no-active-smoke", "version": "0"},
        },
    })
    request({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, expect_response=False)
    tools_response = request({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    status_response = request({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "event_stream_status", "arguments": {}},
    })
    stop_response = request({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {"name": "event_stream_stop", "arguments": {}},
    })
finally:
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

initialize = initialize_response["result"]
assert initialize["protocolVersion"] == "2025-11-25"
assert initialize["serverInfo"]["name"] == "Record & Replay"
assert "instructions" not in initialize

tools = tools_response["result"]["tools"]
assert [tool["name"] for tool in tools] == [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
]

status = tool_text(status_response)
stopped = tool_text(stop_response)

for payload in [status, stopped]:
    assert payload == {
        "isRecording": False,
        "maxDurationSeconds": 1800,
    }, payload
    assert "sessionId" not in payload
    assert "eventsPath" not in payload
    assert "metadataPath" not in payload

assert not (recordings / "latest-session.json").exists()
assert not (recordings / "active-session.json").exists()

print(json.dumps({
    "ok": True,
    "mode": "no-active",
    "isRecording": stopped["isRecording"],
    "maxDurationSeconds": stopped["maxDurationSeconds"],
    "recordingsRoot": str(recordings),
}, sort_keys=True))
PY
  exit 0
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TIMEOUT:-0}" == "1" ]]; then
  timeout_seconds="${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TIMEOUT_SECONDS:-1.5}"
  python3 - "${tmpdir}" "${screenshot_policy}" "${timeout_seconds}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(sys.argv[1])
screenshot_policy = sys.argv[2]
timeout_seconds = float(sys.argv[3])
recordings = root / "recordings"
responses = []

env = os.environ.copy()
env.update({
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
    "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
    "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": screenshot_policy,
    "OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "0",
    "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
    "OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS": str(timeout_seconds),
})

proc = subprocess.Popen(
    [".build/debug/OpenComputerUse", "event-stream", "mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

def request(message, expect_response=True):
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    if not expect_response:
        return None
    line = proc.stdout.readline()
    assert line, "MCP server exited before responding"
    response = json.loads(line)
    responses.append(response)
    return response

def tool_text(response):
    content = response["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])

try:
    initialize_response = request({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "event-stream-timeout-smoke", "version": "0"},
        },
    })
    request({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, expect_response=False)
    tools_response = request({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    start_response = request({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "event_stream_start", "arguments": {}},
    })

    time.sleep(timeout_seconds + 0.8)

    status_response = request({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {"name": "event_stream_status", "arguments": {}},
    })
    stop_after_timeout_response = request({
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {"name": "event_stream_stop", "arguments": {}},
    })
finally:
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise
    stderr = proc.stderr.read() if proc.stderr else ""
    assert proc.returncode == 0, stderr

initialize = initialize_response["result"]
assert initialize["protocolVersion"] == "2025-11-25"
assert initialize["serverInfo"]["name"] == "Record & Replay"
assert "instructions" not in initialize

tools = tools_response["result"]["tools"]
assert [tool["name"] for tool in tools] == [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
]

started = tool_text(start_response)
stopped = tool_text(status_response)
stop_after_timeout = tool_text(stop_after_timeout_response)

assert started["state"] == "recording"
assert started["active"] is True
assert stopped["state"] == "stopped"
assert stopped["active"] is False
assert stopped["endReason"] == "recording_time_limit_reached"
assert stop_after_timeout["state"] == "stopped"
assert stop_after_timeout["sessionId"] == stopped["sessionId"]
assert stop_after_timeout["endReason"] == stopped["endReason"]

events_path = pathlib.Path(stopped["eventsPath"])
session_path = pathlib.Path(stopped["sessionPath"])
metadata_path = session_path.parent / "metadata.json"
suppressed_path = pathlib.Path(stopped["suppressedEventsPath"])
session_alias_path = metadata_path.parent / "session.json"

assert events_path.exists()
assert metadata_path.exists()
assert session_path.exists()
assert suppressed_path.exists()
assert session_alias_path.exists()
assert session_path == session_alias_path
metadata = json.loads(metadata_path.read_text())
session_alias = json.loads(session_alias_path.read_text())
assert session_alias.get("id") == metadata.get("sessionId")
assert session_alias.get("eventsPath") == metadata.get("eventsPath")
assert session_alias.get("startedAt") == metadata.get("startedAt")
assert session_alias.get("endReason") == metadata.get("endReason")

events = [
    json.loads(line)
    for line in events_path.read_text().splitlines()
    if line.strip()
]
event_types = [event["type"] for event in events]
assert "session.started" in event_types
assert "window.changed" in event_types
assert "AX.focusedWindowChanged" in event_types
assert "session.ended" in event_types
assert any(
    event.get("type") == "session.ended"
    and event.get("endReason") == "recording_time_limit_reached"
    for event in events
)
subprocess.run([
    sys.executable,
    "scripts/validate-event-stream-recording.py",
    str(metadata_path),
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "AX.focusedWindowChanged",
    "--require-event-type",
    "session.ended",
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "AX.focusedWindowChanged",
    "--require-event-type",
    "session.ended",
    str(metadata_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})

print(json.dumps({
    "ok": True,
    "mode": "timeout",
    "sessionId": stopped["sessionId"],
    "eventCount": stopped["eventCount"],
    "recordingsRoot": str(recordings),
    "screenshotPolicy": screenshot_policy,
    "timeoutSeconds": timeout_seconds,
}, sort_keys=True))
PY
  exit 0
fi

OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 \
OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS=0 \
OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=approve \
OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS="${screenshot_policy}" \
OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS=0 \
OPEN_COMPUTER_USE_EVENT_STREAM_DIR="${tmpdir}/recordings" \
  ".build/debug/OpenComputerUse" event-stream mcp \
  <"${messages_file}" >"${tmpdir}/responses.jsonl"

python3 - "${tmpdir}" "${screenshot_policy}" <<'PY'
import json
import os
import pathlib
import select
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
screenshot_policy = sys.argv[2]
recordings = root / "recordings"
responses_path = root / "responses.jsonl"

responses = [
    json.loads(line)
    for line in responses_path.read_text().splitlines()
    if line.strip()
]
by_id = {response.get("id"): response for response in responses if "id" in response}

initialize = by_id[1]["result"]
assert initialize["protocolVersion"] == "2025-11-25"
assert initialize["serverInfo"]["name"] == "Record & Replay"
assert "instructions" not in initialize

tools = by_id[2]["result"]["tools"]
assert [tool["name"] for tool in tools] == [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
]

def tool_text(response_id):
    content = by_id[response_id]["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])

started = tool_text(3)
repeated_start = tool_text(4)
status = tool_text(5)
stopped = tool_text(6)
repeated_stop = tool_text(7)
status_after_stop = tool_text(8)

assert started["state"] == "recording"
assert started["active"] is True
assert repeated_start["state"] == "recording"
assert repeated_start["sessionId"] == started["sessionId"]
assert status["state"] == "recording"
assert status["sessionId"] == started["sessionId"]
assert stopped["state"] == "stopped"
assert stopped["active"] is False
assert stopped["endReason"] == "recording_controls_stopped"
assert repeated_stop["state"] == "stopped"
assert repeated_stop["sessionId"] == stopped["sessionId"]
assert repeated_stop["endReason"] == stopped["endReason"]
assert status_after_stop["state"] == "stopped"
assert status_after_stop["sessionId"] == stopped["sessionId"]

events_path = pathlib.Path(stopped["eventsPath"])
session_path = pathlib.Path(stopped["sessionPath"])
metadata_path = session_path.parent / "metadata.json"
suppressed_path = pathlib.Path(stopped["suppressedEventsPath"])
session_alias_path = metadata_path.parent / "session.json"

assert events_path.exists()
assert metadata_path.exists()
assert session_path.exists()
assert suppressed_path.exists()
assert session_alias_path.exists()
assert session_path == session_alias_path
metadata = json.loads(metadata_path.read_text())
session_alias = json.loads(session_alias_path.read_text())
assert session_alias.get("id") == metadata.get("sessionId")
assert session_alias.get("eventsPath") == metadata.get("eventsPath")
assert session_alias.get("startedAt") == metadata.get("startedAt")
assert session_alias.get("endReason") == metadata.get("endReason")

events = [
    json.loads(line)
    for line in events_path.read_text().splitlines()
    if line.strip()
]
event_types = [event["type"] for event in events]
assert "session.started" in event_types
assert "window.changed" in event_types
assert "AX.focusedWindowChanged" in event_types
assert "session.ended" in event_types
subprocess.run([
    sys.executable,
    "scripts/validate-event-stream-recording.py",
    str(metadata_path),
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "AX.focusedWindowChanged",
    "--require-event-type",
    "session.ended",
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    "--require-event-type",
    "session.started",
    "--require-event-type",
    "AX.focusedWindowChanged",
    "--require-event-type",
    "session.ended",
    str(metadata_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    str(session_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})
subprocess.run([
    sys.executable,
    "scripts/summarize-event-stream-recording.py",
    str(metadata_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "summarize",
    "--json",
    str(metadata_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})
subprocess.run([
    ".build/debug/OpenComputerUse",
    "event-stream",
    "summarize",
    "--json",
    str(session_path),
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={
    **os.environ,
    "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
})

ax_payloads = [
    event.get("accessibilityInspectorPayload")
    for event in events
    if event.get("type") == "AX.focusedWindowChanged"
]
ax_payloads = [payload for payload in ax_payloads if payload]
assert ax_payloads, "expected at least one AX payload"
screenshot_needed_count = sum(
    1 for payload in ax_payloads if payload.get("screenshotNeededForContext")
)
screenshot_available_payloads = [
    payload for payload in ax_payloads if payload.get("screenshotAvailable")
]
screenshot_available_count = len(screenshot_available_payloads)
screenshot_paths = [
    pathlib.Path(payload["screenshotPath"])
    for payload in screenshot_available_payloads
    if payload.get("screenshotPath")
]
screenshot_path_count = len(screenshot_paths)

if screenshot_policy == "always":
    assert screenshot_needed_count > 0, "expected screenshotNeededForContext with always policy"
    if screenshot_available_payloads:
        assert screenshot_paths, "expected screenshotPath when screenshot is available"
        assert all(path.exists() for path in screenshot_paths)

if os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL") == "1":
    official_timeout = float(os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_TIMEOUT", "10"))
    plugin_dir = pathlib.Path(os.environ.get(
        "OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_PLUGIN_DIR",
        str(pathlib.Path.home() / ".codex/plugins/cache/openai-bundled/record-and-replay/1.0.857"),
    ))
    official_client = plugin_dir / "Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
    assert official_client.exists(), f"official Record & Replay client not found: {official_client}"

    proc = subprocess.Popen(
        [str(official_client), "event-stream", "mcp"],
        cwd=str(plugin_dir),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    def official_request(message, expect_response=True):
        proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        proc.stdin.flush()
        if not expect_response:
            return None
        ready, _, _ = select.select([proc.stdout], [], [], official_timeout)
        assert ready, f"official MCP server did not respond within {official_timeout}s"
        line = proc.stdout.readline()
        assert line, "official MCP server exited before responding"
        return json.loads(line)

    try:
        official_initialize_response = official_request({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "event-stream-smoke-official-compare", "version": "0"},
            },
        })
        official_request({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, expect_response=False)
        official_tools_response = official_request({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    finally:
        if proc.stdin:
            proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise
        stderr = proc.stderr.read() if proc.stderr else ""
        assert proc.returncode == 0, stderr

    official_initialize = official_initialize_response["result"]
    assert official_initialize["protocolVersion"] == initialize["protocolVersion"]
    assert official_initialize["serverInfo"]["name"] == initialize["serverInfo"]["name"]
    assert "instructions" not in official_initialize

    official_tools = official_tools_response["result"]["tools"]
    comparable_local_tools = [
        {key: tool[key] for key in ["name", "description", "inputSchema", "annotations"]}
        for tool in tools
    ]
    comparable_official_tools = [
        {key: tool[key] for key in ["name", "description", "inputSchema", "annotations"]}
        for tool in official_tools
    ]
    assert comparable_local_tools == comparable_official_tools

print(json.dumps({
    "ok": True,
    "sessionId": stopped["sessionId"],
    "eventCount": stopped["eventCount"],
    "recordingsRoot": str(recordings),
    "screenshotPolicy": screenshot_policy,
    "screenshotContextChecked": screenshot_policy == "always",
    "screenshotNeededForContextCount": screenshot_needed_count,
    "screenshotAvailableCount": screenshot_available_count,
    "screenshotPathCount": screenshot_path_count,
    "handoffChecked": True,
    "officialCompared": os.environ.get("OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL") == "1",
}, sort_keys=True))
PY
