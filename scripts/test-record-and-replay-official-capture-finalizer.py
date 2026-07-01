#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile


def write_json(path: pathlib.Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path: pathlib.Path, values) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(value, sort_keys=True) + "\n" for value in values))


def run(command, cwd):
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def hosted_tool_json(payload):
    return {
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(payload, sort_keys=True),
                }
            ]
        }
    }


def make_recording(root: pathlib.Path) -> dict[str, pathlib.Path]:
    recording = root / "official-recording"
    metadata = recording / "metadata.json"
    session = recording / "session.json"
    events = recording / "events.jsonl"
    suppressed = recording / "suppressed.jsonl"
    event_records = [
        {"type": "session.started", "sessionId": "official-secret-session"},
        {
            "type": "mouse.click",
            "sessionId": "official-secret-session",
            "button": "left",
            "location": {"x": 10, "y": 20},
            "targetAccessibilityElement": {
                "role": "AXButton",
                "title": "Safe Button",
            },
        },
        {
            "type": "AX.focusedWindowChanged",
            "sessionId": "official-secret-session",
            "accessibilityInspectorPayload": {
                "kind": "full",
                "diffFromPrevious": False,
                "treeLines": ["AXWindow Safe"],
                "renderedText": "AXWindow Safe",
            },
        },
        {
            "type": "session.ended",
            "sessionId": "official-secret-session",
            "endReason": "recording_controls_stopped",
        },
    ]
    suppressed_records = [
        {
            "type": "AX.snapshot.suppressed",
            "reason": "snapshotTooLarge",
            "subsystem": "accessibility",
        }
    ]
    metadata_payload = {
        "sessionId": "official-secret-session",
        "state": "stopped",
        "endReason": "recording_controls_stopped",
        "eventCount": len(event_records),
        "suppressedEventCount": len(suppressed_records),
        "metadataPath": str(metadata),
        "sessionPath": str(session),
        "eventsPath": str(events),
        "suppressedEventsPath": str(suppressed),
    }
    write_json(metadata, metadata_payload)
    write_json(session, metadata_payload)
    write_jsonl(events, event_records)
    write_jsonl(suppressed, suppressed_records)
    return {
        "recording": recording,
        "metadata": metadata,
        "session": session,
        "events": events,
        "suppressed": suppressed,
    }


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parents[1]
    prepare = repo / "scripts/prepare-record-and-replay-official-golden-capture.py"
    finalizer = repo / "scripts/finalize-record-and-replay-official-capture-packet.py"
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = pathlib.Path(tmp)
        fixture_root = tmp_path / "fixtures"
        plugin_root = tmp_path / "record-and-replay"
        (plugin_root / "1.0.857/skills/record-and-replay").mkdir(parents=True)
        (plugin_root / "1.0.857/skills/record-and-replay/SKILL.md").write_text(
            "---\nname: record-and-replay\n---\n"
        )
        packet_dir = tmp_path / "packet"
        prepared = run(
            [
                sys.executable,
                str(prepare),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--capture-packet-dir",
                str(packet_dir),
            ],
            repo,
        )
        assert prepared.returncode == 0, prepared.stderr
        paths = make_recording(tmp_path)
        start_json = tmp_path / "start.json"
        status_json = tmp_path / "status.json"
        stop_json = tmp_path / "stop.json"
        final_status_json = tmp_path / "final-status.json"
        start_payload = {
            "isRecording": True,
            "sessionId": "official-secret-session",
            "metadataPath": str(paths["metadata"]),
            "eventsPath": str(paths["events"]),
        }
        status_payload = {
            "isRecording": True,
            "sessionId": "official-secret-session",
            "metadataPath": str(paths["metadata"]),
            "eventsPath": str(paths["events"]),
        }
        stop_payload = {
            "isRecording": False,
            "sessionId": "official-secret-session",
            "metadataPath": str(paths["metadata"]),
            "sessionPath": str(paths["session"]),
            "eventsPath": str(paths["events"]),
        }
        write_json(start_json, hosted_tool_json(start_payload))
        write_json(status_json, hosted_tool_json(status_payload))
        write_json(stop_json, hosted_tool_json(stop_payload))
        write_json(final_status_json, hosted_tool_json(stop_payload))

        finalized = run(
            [
                sys.executable,
                str(finalizer),
                "--packet-dir",
                str(packet_dir),
                "--start-json",
                str(start_json),
                "--status-json",
                str(status_json),
                "--stop-json",
                str(stop_json),
                "--final-status-json",
                str(final_status_json),
            ],
            repo,
        )
        assert finalized.returncode == 0, finalized.stderr
        finalized_payload = json.loads(finalized.stdout)
        assert finalized_payload["ok"] is True
        assert finalized_payload["checkedHostedResponseShapes"] == [
            "startResponseShape",
            "statusResponseShape",
            "stopResponseShape",
            "finalStatusResponseShape",
        ]
        assert finalized_payload["verifyWorkflow"]["ok"] is True
        assert finalized_payload["verifyInputs"]["ok"] is True
        transcript = json.loads((packet_dir / "inputs/mcp-transcript.json").read_text())
        assert transcript["kind"] == "record-and-replay-hosted-capture-transcript"
        assert transcript["startResponseShape"]["result"]["content"][0]["type"] == "text"
        assert transcript["statusResponseShape"]["result"]["content"][0]["type"] == "text"
        assert transcript["stopResponseShape"]["result"]["content"][0]["type"] == "text"
        assert transcript["finalStatusResponseShape"]["result"]["content"][0]["type"] == "text"
        status_input = json.loads((packet_dir / "inputs/event_stream_stop-response.json").read_text())
        status_input_text = status_input["result"]["content"][0]["text"]
        assert "eventsPath" in status_input_text
        assert "metadataPath" in status_input_text
        assert "suppressedEventsPath" not in status_input_text

        missing_final = run(
            [
                sys.executable,
                str(finalizer),
                "--packet-dir",
                str(packet_dir),
                "--start-json",
                str(start_json),
                "--status-json",
                str(status_json),
                "--stop-json",
                str(stop_json),
            ],
            repo,
        )
        assert missing_final.returncode == 1
        assert "finalStatusResponseShape" in missing_final.stderr

        no_handoff = tmp_path / "no-handoff.json"
        write_json(no_handoff, hosted_tool_json({"isRecording": False}))
        no_handoff_result = run(
            [
                sys.executable,
                str(finalizer),
                "--packet-dir",
                str(packet_dir),
                "--start-json",
                str(start_json),
                "--status-json",
                str(status_json),
                "--stop-json",
                str(no_handoff),
                "--final-status-json",
                str(final_status_json),
            ],
            repo,
        )
        assert no_handoff_result.returncode == 1
        assert "handoff paths" in no_handoff_result.stderr

    print(json.dumps({"ok": True, "checkedHostedCaptureFinalizer": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
