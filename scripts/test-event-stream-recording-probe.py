#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile
import textwrap


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PROBE = REPO_ROOT / "scripts/probe-event-stream-recording.py"


FAKE_SERVER = r'''
#!/usr/bin/env python3
import json
import os
import pathlib
import sys

record_file = pathlib.Path(os.environ["FAKE_ELICITATION_RESPONSE_FILE"])
active_started = False
completed = False

def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()

pending_start_id = None
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "protocolVersion": "2025-11-25",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "Record & Replay", "version": "fake"},
            },
        })
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "tools": [
                    {"name": "event_stream_start", "inputSchema": {"type": "object", "properties": {}}},
                    {"name": "event_stream_status", "inputSchema": {"type": "object", "properties": {}}},
                    {"name": "event_stream_stop", "inputSchema": {"type": "object", "properties": {}}},
                ]
            },
        })
    elif method == "tools/call":
        params = message.get("params", {})
        name = params.get("name")
        if name == "event_stream_start":
            if active_started:
                send({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                        "content": [{"type": "text", "text": json.dumps({
                            "state": "recording",
                            "active": True,
                            "sessionId": "fake-session",
                            "eventsPath": "/tmp/fake-session/events.jsonl",
                            "metadataPath": "/tmp/fake-session/metadata.json",
                            "currentSegmentEventsPath": "/tmp/fake-session/events.jsonl",
                            "currentSegmentMetadataPath": "/tmp/fake-session/metadata.json",
                        })}],
                        "isError": False,
                    },
                })
                continue
            pending_start_id = message["id"]
            send({
                "jsonrpc": "2.0",
                "id": "fake-approval-1",
                "method": "elicitation/create",
                "params": {
                    "mode": "form",
                    "message": "Fake approval request",
                    "requestedSchema": {
                        "type": "object",
                        "properties": {"note": {"type": "string"}},
                        "required": [],
                        "additionalProperties": False,
                    },
                },
            })
        elif name == "event_stream_status":
            state_payload = {
                "state": "stopped" if completed else "recording",
                "active": False if completed else True,
                "sessionId": "fake-session",
                "eventsPath": "/tmp/fake-session/events.jsonl",
                "metadataPath": "/tmp/fake-session/metadata.json",
            }
            if completed:
                state_payload["endReason"] = "recording_controls_stopped"
            else:
                state_payload["currentSegmentEventsPath"] = "/tmp/fake-session/events.jsonl"
                state_payload["currentSegmentMetadataPath"] = "/tmp/fake-session/metadata.json"
            send({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {
                    "content": [{"type": "text", "text": json.dumps(state_payload)}],
                    "isError": False,
                },
            })
        elif name == "event_stream_stop":
            completed = True
            send({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {
                    "content": [{"type": "text", "text": json.dumps({
                        "state": "stopped",
                        "active": False,
                        "sessionId": "fake-session",
                        "eventsPath": "/tmp/fake-session/events.jsonl",
                        "metadataPath": "/tmp/fake-session/metadata.json",
                        "endReason": "recording_controls_stopped",
                    })}],
                    "isError": False,
                },
            })
    elif message.get("id") == "fake-approval-1" and "result" in message:
        active_started = True
        record_file.write_text(json.dumps(message["result"], sort_keys=True) + "\n", encoding="utf-8")
        send({
            "jsonrpc": "2.0",
            "id": pending_start_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps({"state": "recording", "active": True, "sessionId": "fake-session"})}],
                "isError": False,
            },
        })
'''


def write_fake_server(directory: pathlib.Path) -> pathlib.Path:
    path = directory / "fake-event-stream-server.py"
    path.write_text(textwrap.dedent(FAKE_SERVER).lstrip(), encoding="utf-8")
    path.chmod(0o755)
    return path


def run_probe(
    fake_server: pathlib.Path,
    tmpdir: pathlib.Path,
    action: str = "accept",
    legacy_decline: bool = False,
) -> tuple[dict, dict, dict]:
    label = "legacy-decline" if legacy_decline else action
    response_file = tmpdir / f"{label}-response.json"
    output_file = tmpdir / f"{label}-output.json"
    fixture_file = tmpdir / f"{label}-fixture.json"
    command = [
        sys.executable,
        str(PROBE),
        "--target",
        "local",
        "--client",
        str(fake_server),
        "--start-stop",
        "--timeout",
        "2",
        "--output",
        str(output_file),
        "--fixture-output",
        str(fixture_file),
    ]
    if legacy_decline:
        command.append("--decline-elicitation")
    else:
        command.extend(["--elicitation-action", action])
    env = dict(**os_environ(), FAKE_ELICITATION_RESPONSE_FILE=str(response_file))
    subprocess.run(command, cwd=REPO_ROOT, env=env, check=True, stdout=subprocess.PIPE, text=True)
    return (
        json.loads(output_file.read_text(encoding="utf-8")),
        json.loads(fixture_file.read_text(encoding="utf-8")),
        json.loads(response_file.read_text(encoding="utf-8")),
    )


def os_environ() -> dict[str, str]:
    import os

    return os.environ.copy()


def assert_probe_result(output: dict, fixture: dict) -> None:
    assert output["ok"] is True
    assert output["startStopCompleted"] is True
    assert output["startTimedOut"] is False
    assert fixture["kind"] == "record-and-replay-event-stream-probe"
    assert fixture["source"] == "local"
    assert fixture["toolNames"] == [
        "event_stream_start",
        "event_stream_status",
        "event_stream_stop",
    ]
    assert fixture["elicitationRequests"] == [
        {
            "message": "Fake approval request",
            "mode": "form",
            "requestedSchemaHasAdditionalProperties": True,
            "requestedSchemaPropertyNames": ["note"],
            "requestedSchemaRequired": [],
            "requestedSchemaType": "object",
        }
    ]
    fixture_text = json.dumps(fixture, sort_keys=True)
    assert "/tmp/fake-session" not in fixture_text
    status_text = fixture["statusResponseShape"]["result"]["content"][0]
    assert status_text["type"] == "text"
    assert "text" not in status_text
    assert status_text["textJSON"]["eventsPath"] == "<redacted-eventsPath>"
    assert status_text["textJSON"]["metadataPath"] == "<redacted-metadataPath>"
    assert (
        status_text["textJSON"]["currentSegmentEventsPath"]
        == "<redacted-currentSegmentEventsPath>"
    )
    repeat_start_text = fixture["repeatStartResponseShape"]["result"]["content"][0]
    assert repeat_start_text["type"] == "text"
    assert "text" not in repeat_start_text
    assert repeat_start_text["textJSON"]["sessionId"] == "<redacted-session-id>"
    assert (
        repeat_start_text["textJSON"]["currentSegmentMetadataPath"]
        == "<redacted-currentSegmentMetadataPath>"
    )
    stop_text = fixture["stopResponseShape"]["result"]["content"][0]
    assert "text" not in stop_text
    assert "currentSegmentEventsPath" not in stop_text["textJSON"]
    assert stop_text["textJSON"]["endReason"] == "recording_controls_stopped"
    repeat_stop_text = fixture["repeatStopResponseShape"]["result"]["content"][0]
    assert "text" not in repeat_stop_text
    assert repeat_stop_text["textJSON"]["state"] == "stopped"
    assert repeat_stop_text["textJSON"]["sessionId"] == "<redacted-session-id>"
    final_status_text = fixture["finalStatusResponseShape"]["result"]["content"][0]
    assert "text" not in final_status_text
    assert final_status_text["textJSON"]["state"] == "stopped"
    assert "currentSegmentEventsPath" not in final_status_text["textJSON"]


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="event-stream-probe-test-") as tmp:
        tmpdir = pathlib.Path(tmp)
        fake_server = write_fake_server(tmpdir)

        accept_output, accept_fixture, accept_response = run_probe(fake_server, tmpdir)
        assert_probe_result(accept_output, accept_fixture)
        assert accept_response == {"action": "accept", "content": {}}

        decline_output, decline_fixture, decline_response = run_probe(fake_server, tmpdir, "decline")
        assert_probe_result(decline_output, decline_fixture)
        assert decline_response == {"action": "decline", "content": None}

        cancel_output, cancel_fixture, cancel_response = run_probe(fake_server, tmpdir, "cancel")
        assert_probe_result(cancel_output, cancel_fixture)
        assert cancel_response == {"action": "cancel", "content": None}

        legacy_decline_output, legacy_decline_fixture, legacy_decline_response = run_probe(
            fake_server,
            tmpdir,
            legacy_decline=True,
        )
        assert_probe_result(legacy_decline_output, legacy_decline_fixture)
        assert legacy_decline_response == {"action": "decline", "content": None}

    print(json.dumps({"ok": True, "probe": "event-stream-recording"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
