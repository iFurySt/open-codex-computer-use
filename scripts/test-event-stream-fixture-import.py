#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    path.write_text(
        "\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n"
    )


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        recording = root / "recording"
        recording.mkdir()
        events_path = recording / "events.jsonl"
        metadata_path = recording / "metadata.json"
        session_path = recording / "session.json"
        suppressed_path = recording / "suppressed.jsonl"

        events = [
            {
                "type": "session.started",
                "timestamp": "2026-06-26T00:00:00.000Z",
                "sessionId": "secret-session-id",
                "appName": "Secret App",
                "bundleIdentifier": "com.example.secret",
            },
            {
                "type": "mouse.click",
                "timestamp": "2026-06-26T00:00:01.000Z",
                "sessionId": "secret-session-id",
                "windowTitle": "Private Window Title",
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": "Sensitive Button",
                    "value": "secret-value",
                    "selectedText": "selected-secret",
                    "actions": ["AXPress"],
                },
                "accessibilityInspectorPayload": {
                    "renderedText": "Visible private content",
                    "fullTree": [
                        "0 Private full tree root",
                        "1 Private full tree child",
                    ],
                    "treeLines": [
                        "+ Visible private tree line",
                        "~ Old private value -> New private value",
                    ],
                    "cumulativeTreeLines": [
                        "- Removed private tree line",
                    ],
                    "screenshotPath": str(recording / "screenshots" / "private.png"),
                },
            },
            {
                "type": "session.ended",
                "timestamp": "2026-06-26T00:00:02.000Z",
                "sessionId": "secret-session-id",
                "endReason": "recording_controls_stopped",
            },
        ]
        write_jsonl(events_path, events)
        suppressed = [
            {
                "type": "AX.snapshot.suppressed",
                "timestamp": "2026-06-26T00:00:01.500Z",
                "sessionId": "secret-session-id",
                "reason": "snapshotTooLarge",
                "windowTitle": "Suppressed Private Window",
                "value": "suppressed-secret-value",
                "path": str(recording / "screenshots" / "suppressed-sensitive.png"),
            }
        ]
        write_jsonl(suppressed_path, suppressed)

        metadata = {
            "sessionId": "secret-session-id",
            "state": "stopped",
            "active": False,
            "endReason": "recording_controls_stopped",
            "eventCount": len(events),
            "suppressedEventCount": len(suppressed),
            "eventsPath": str(events_path),
            "metadataPath": str(metadata_path),
            "sessionPath": str(session_path),
            "suppressedEventsPath": str(suppressed_path),
        }
        write_json(metadata_path, metadata)
        write_json(session_path, metadata)
        transcript_path = recording / "probe.json"
        transcript = {
            "target": "official",
            "command": ["/private/path/SkyComputerUseClient", "event-stream", "mcp"],
            "cwd": "/private/path/plugin",
            "recordingsDir": str(recording),
            "repeatStartResponseShape": {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "sessionId": "secret-session-id",
                                    "currentSegmentEventsPath": str(events_path),
                                    "currentSegmentMetadataPath": str(metadata_path),
                                }
                            ),
                        }
                    ]
                }
            },
            "repeatStopResponseShape": {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "sessionId": "secret-session-id",
                                    "eventsPath": str(events_path),
                                    "metadataPath": str(metadata_path),
                                    "state": "stopped",
                                }
                            ),
                        }
                    ]
                }
            },
            "finalStatusResponseShape": {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "sessionId": "secret-session-id",
                                    "eventsPath": str(events_path),
                                    "metadataPath": str(metadata_path),
                                    "state": "stopped",
                                }
                            ),
                        }
                    ]
                }
            },
            "transcript": [
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "tools/call",
                        "params": {"name": "event_stream_start", "arguments": {}},
                    },
                },
                {
                    "direction": "receive",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "result": {
                            "content": [
                                {
                                    "type": "text",
                                    "text": json.dumps(
                                        {
                                            "sessionId": "secret-session-id",
                                            "eventsPath": str(events_path),
                                            "metadataPath": str(metadata_path),
                                            "windowTitle": "Private Window Title",
                                        }
                                    ),
                                }
                            ]
                        },
                    },
                },
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 2,
                        "method": "tools/call",
                        "params": {"name": "event_stream_status", "arguments": {}},
                    },
                },
                {"direction": "receive", "message": {"jsonrpc": "2.0", "id": 2, "result": {"content": []}}},
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {"name": "event_stream_stop", "arguments": {}},
                    },
                },
                {"direction": "receive", "message": {"jsonrpc": "2.0", "id": 3, "result": {"content": []}}},
            ],
        }
        write_json(transcript_path, transcript)

        output_dir = root / "fixtures"
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/import-event-stream-fixture.py"),
                str(recording),
                "--name",
                "sample-official-recording",
                "--output-dir",
                str(output_dir),
                "--source",
                "official",
                "--scenario",
                "simple-action-stop",
                "--official-plugin-version",
                "record-and-replay 1.0.857",
                "--captured-at",
                "2026-06-26",
                "--mcp-transcript",
                str(transcript_path),
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        fixture = output_dir / "sample-official-recording"
        combined = "\n".join(path.read_text() for path in fixture.glob("*") if path.is_file())
        for secret in [
            "secret-session-id",
            "Secret App",
            "com.example.secret",
            "Private Window Title",
            "Sensitive Button",
            "secret-value",
            "selected-secret",
            "Visible private content",
            "Private full tree root",
            "Private full tree child",
            "Visible private tree line",
            "Old private value",
            "New private value",
            "Removed private tree line",
            "private.png",
            "Suppressed Private Window",
            "suppressed-secret-value",
            "suppressed-sensitive.png",
            "/private/path",
        ]:
            assert secret not in combined, secret
        assert "+ <redacted-treeLines:" in combined
        assert "~ <redacted-treeLines:" in combined
        assert "- <redacted-cumulativeTreeLines:" in combined
        assert "<redacted-fullTree:" in combined

        imported_metadata = json.loads((fixture / "metadata.json").read_text())
        assert imported_metadata["eventsPath"] == "events.jsonl"
        assert imported_metadata["metadataPath"] == "metadata.json"
        assert imported_metadata["sessionPath"] == "session.json"
        assert imported_metadata["suppressedEventsPath"] == "suppressed.jsonl"

        manifest = json.loads((fixture / "fixture-manifest.json").read_text())
        assert manifest["eventCount"] == len(events)
        assert manifest["scenario"] == "simple-action-stop"
        assert manifest["scenarioRecipe"]["scenario"] == "simple-action-stop"
        assert manifest["scenarioRecipe"]["expectedActionEvents"] == ["mouse.click"]
        assert manifest["suppressedEventCount"] == len(suppressed)
        assert manifest["eventTypes"]["mouse.click"] == 1
        assert manifest["files"]["mcpTranscript"] == "mcp-transcript.json"
        assert manifest["redaction"]["screenshotsCopied"] is False
        assert manifest["redaction"]["mcpTranscriptSanitized"] is True

        imported_transcript = json.loads((fixture / "mcp-transcript.json").read_text())
        decoded = imported_transcript["transcript"][1]["message"]["result"]["content"][0]["decodedText"]
        assert decoded["sessionId"] == "fixture-session"
        assert decoded["eventsPath"] == "events.jsonl"
        assert decoded["metadataPath"] == "metadata.json"
        assert decoded["windowTitle"].startswith("<redacted-windowTitle")
        repeat_start_shape = imported_transcript["repeatStartResponseShape"]["result"]["content"][0]
        assert "text" not in repeat_start_shape
        assert repeat_start_shape["decodedText"]["sessionId"] == "fixture-session"
        assert repeat_start_shape["decodedText"]["currentSegmentEventsPath"] == "events.jsonl"
        repeat_stop_shape = imported_transcript["repeatStopResponseShape"]["result"]["content"][0]
        assert repeat_stop_shape["decodedText"]["state"] == "stopped"
        assert repeat_stop_shape["decodedText"]["metadataPath"] == "metadata.json"
        final_status_shape = imported_transcript["finalStatusResponseShape"]["result"]["content"][0]
        assert final_status_shape["decodedText"]["state"] == "stopped"
        assert final_status_shape["decodedText"]["eventsPath"] == "events.jsonl"

        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/validate-event-stream-recording.py"),
                str(fixture),
                "--strict-ocu",
                "--require-event-type",
                "mouse.click",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/summarize-event-stream-recording.py"),
                str(fixture),
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/check-event-stream-golden-readiness.py"),
                str(fixture),
                "--require-fixture-manifest",
                "--require-source",
                "official",
                "--require-official-plugin-version",
                "record-and-replay 1.0.857",
                "--require-mcp-transcript",
                "--require-event-type",
                "mouse.click",
                "--require-suppressed-events",
                "--require-suppressed-event-type",
                "AX.snapshot.suppressed",
                "--require-mcp-response-shape",
                "repeatStartResponseShape",
                "--require-mcp-response-shape",
                "repeatStopResponseShape",
                "--require-mcp-response-shape",
                "finalStatusResponseShape",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(fixture),
                str(fixture),
                "--require-mcp-response-shapes",
                "--require-same-mcp-response-schema",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        minimal_recording = root / "official-minimal-recording"
        minimal_recording.mkdir()
        minimal_events_path = minimal_recording / "events.jsonl"
        minimal_session_path = minimal_recording / "session.json"
        minimal_events = [
            {
                "kind": "session.started",
                "timestamp": "2026-06-29T00:00:00.000Z",
                "sessionId": "official-minimal-secret",
            },
            {
                "kind": "AX.focusedWindowChanged",
                "timestamp": "2026-06-29T00:00:01.000Z",
                "sessionId": "official-minimal-secret",
                "accessibilityInspectorPayload": {
                    "diffFromPrevious": False,
                    "fullTree": ["0 Official Minimal Private Window"],
                    "treeLines": ["0 Official Minimal Private Window"],
                },
            },
            {
                "kind": "mouse.click",
                "timestamp": "2026-06-29T00:00:02.000Z",
                "sessionId": "official-minimal-secret",
                "button": "left",
                "location": {"x": 4, "y": 8},
            },
            {
                "kind": "session.ended",
                "timestamp": "2026-06-29T00:00:03.000Z",
                "sessionId": "official-minimal-secret",
                "endReason": "recording_controls_stopped",
            },
        ]
        write_jsonl(minimal_events_path, minimal_events)
        write_json(
            minimal_session_path,
            {
                "id": "official-minimal-secret",
                "startedAt": "2026-06-29T00:00:00.000Z",
                "endedAt": "2026-06-29T00:00:03.000Z",
                "endReason": "recording_controls_stopped",
                "eventsPath": str(minimal_events_path),
            },
        )
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/import-event-stream-fixture.py"),
                str(minimal_recording),
                "--name",
                "official-minimal-recording",
                "--output-dir",
                str(output_dir),
                "--source",
                "official",
                "--scenario",
                "simple-action-stop",
                "--official-plugin-version",
                "record-and-replay 1.0.857",
                "--captured-at",
                "2026-06-29",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        minimal_fixture = output_dir / "official-minimal-recording"
        minimal_combined = "\n".join(path.read_text() for path in minimal_fixture.glob("*") if path.is_file())
        assert "official-minimal-secret" not in minimal_combined
        assert "Official Minimal Private Window" not in minimal_combined
        assert (minimal_fixture / "suppressed.jsonl").exists()
        assert (minimal_fixture / "suppressed.jsonl").read_text() == ""
        minimal_metadata = json.loads((minimal_fixture / "metadata.json").read_text())
        assert minimal_metadata["sessionId"] == "fixture-session"
        assert minimal_metadata["state"] == "stopped"
        assert minimal_metadata["active"] is False
        assert minimal_metadata["eventCount"] == len(minimal_events)
        assert minimal_metadata["suppressedEventCount"] == 0
        assert minimal_metadata["eventsPath"] == "events.jsonl"
        assert minimal_metadata["metadataPath"] == "metadata.json"
        assert minimal_metadata["sessionPath"] == "session.json"
        assert minimal_metadata["suppressedEventsPath"] == "suppressed.jsonl"
        minimal_session = json.loads((minimal_fixture / "session.json").read_text())
        assert minimal_session["id"] == "fixture-session"
        assert minimal_session["eventsPath"] == "events.jsonl"
        minimal_manifest = json.loads((minimal_fixture / "fixture-manifest.json").read_text())
        assert minimal_manifest["files"]["suppressed"] == "suppressed.jsonl"
        subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/check-event-stream-golden-readiness.py"),
                str(minimal_fixture),
                "--require-fixture-manifest",
                "--require-source",
                "official",
                "--require-official-plugin-version",
                "record-and-replay 1.0.857",
                "--require-session-alias",
                "--require-metadata-counts",
                "--require-handoff-paths",
                "--require-event-type",
                "mouse.click",
                "--require-end-reason",
                "recording_controls_stopped",
                "--require-full-ax-payload",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    print(json.dumps({"ok": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
