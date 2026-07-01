#!/usr/bin/env python3

import json
import pathlib
import re
import subprocess
import sys
import tempfile


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PROBE = REPO_ROOT / "scripts/probe-event-stream-recording.py"
VALIDATOR = REPO_ROOT / "scripts/validate-event-stream-recording.py"
LOCAL_CLIENT = REPO_ROOT / ".build/debug/OpenComputerUse"
ABSOLUTE_PATH_PATTERN = re.compile(r"(/Users/|/var/folders/|/private/var/|/tmp/)")
EXPECTED_TOOL_NAMES = [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
]


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **kwargs,
    )


def content_text_json(shape: dict) -> dict:
    content = shape["result"]["content"]
    assert len(content) == 1
    item = content[0]
    assert item["type"] == "text"
    assert "text" not in item
    decoded = item["textJSON"]
    assert isinstance(decoded, dict)
    return decoded


def assert_redacted_path(payload: dict, key: str) -> None:
    assert payload[key] == f"<redacted-{key}>", payload


def assert_active_payload(payload: dict) -> None:
    assert payload["state"] == "recording"
    assert payload["active"] is True
    assert payload["isRecording"] is True
    assert payload["maxDurationSeconds"] == 1800
    assert payload["eventCount"] >= 3
    assert payload["suppressedEventCount"] == 0
    for key in (
        "eventsPath",
        "metadataPath",
        "sessionPath",
        "suppressedEventsPath",
        "currentSegmentEventsPath",
        "currentSegmentMetadataPath",
    ):
        assert_redacted_path(payload, key)


def assert_stopped_payload(payload: dict) -> None:
    assert payload["state"] == "stopped"
    assert payload["active"] is False
    assert payload["isRecording"] is False
    assert payload["maxDurationSeconds"] == 1800
    assert payload["endReason"] == "recording_controls_stopped"
    assert payload["eventCount"] >= 4
    assert "currentSegmentEventsPath" not in payload
    assert "currentSegmentMetadataPath" not in payload
    for key in ("eventsPath", "metadataPath", "sessionPath", "suppressedEventsPath"):
        assert_redacted_path(payload, key)


def main() -> int:
    run(["swift", "build", "--product", "OpenComputerUse"])

    with tempfile.TemporaryDirectory(prefix="event-stream-local-probe-") as tmp:
        tmpdir = pathlib.Path(tmp)
        output_path = tmpdir / "probe-output.json"
        fixture_path = tmpdir / "probe-fixture.json"
        recordings_dir = tmpdir / "recordings"

        run(
            [
                sys.executable,
                str(PROBE),
                "--target",
                "local",
                "--client",
                str(LOCAL_CLIENT),
                "--recordings-dir",
                str(recordings_dir),
                "--start-stop",
                "--timeout",
                "5",
                "--output",
                str(output_path),
                "--fixture-output",
                str(fixture_path),
            ]
        )

        output = json.loads(output_path.read_text(encoding="utf-8"))
        fixture_text = fixture_path.read_text(encoding="utf-8")
        if ABSOLUTE_PATH_PATTERN.search(fixture_text):
            raise AssertionError("local probe fixture contains a local absolute path")
        fixture = json.loads(fixture_text)

        assert output["ok"] is True
        assert output["startStopRequested"] is True
        assert output["startStopCompleted"] is True
        assert output["startTimedOut"] is False
        assert output["process"]["returncode"] == 0
        assert fixture["fixtureFormatVersion"] == 1
        assert fixture["kind"] == "record-and-replay-event-stream-probe"
        assert fixture["source"] == "local"
        assert fixture["officialPluginVersion"] is None
        assert fixture["protocolVersion"] == "2025-11-25"
        assert fixture["serverInfo"]["name"] == "Record & Replay"
        assert fixture["toolNames"] == EXPECTED_TOOL_NAMES
        assert fixture["elicitationRequests"] == []

        start_payload = content_text_json(fixture["startResponseShape"])
        repeat_start_payload = content_text_json(fixture["repeatStartResponseShape"])
        status_payload = content_text_json(fixture["statusResponseShape"])
        stop_payload = content_text_json(fixture["stopResponseShape"])
        repeat_stop_payload = content_text_json(fixture["repeatStopResponseShape"])
        final_status_payload = content_text_json(fixture["finalStatusResponseShape"])
        assert_active_payload(start_payload)
        assert_active_payload(repeat_start_payload)
        assert_active_payload(status_payload)
        assert_stopped_payload(stop_payload)
        assert_stopped_payload(repeat_stop_payload)
        assert_stopped_payload(final_status_payload)

        assert output["startStatus"]["sessionId"] == output["repeatStartStatus"]["sessionId"]
        assert output["startStatus"]["eventsPath"] == output["repeatStartStatus"]["eventsPath"]
        assert output["repeatStartStatus"]["state"] == "recording"
        assert output["repeatStartStatus"]["active"] is True
        assert output["stopStatus"]["sessionId"] == output["repeatStopStatus"]["sessionId"]
        assert output["stopStatus"]["eventsPath"] == output["repeatStopStatus"]["eventsPath"]
        assert output["stopStatus"]["sessionId"] == output["finalStatusStatus"]["sessionId"]
        assert output["repeatStopStatus"]["state"] == "stopped"
        assert output["repeatStopStatus"]["active"] is False
        assert output["finalStatusStatus"]["state"] == "stopped"
        assert output["finalStatusStatus"]["active"] is False

        metadata_path = pathlib.Path(output["stopStatus"]["metadataPath"])
        session_path = pathlib.Path(output["stopStatus"]["sessionPath"])
        events_path = pathlib.Path(output["stopStatus"]["eventsPath"])
        assert metadata_path.exists()
        assert session_path.exists()
        assert events_path.exists()

        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        assert "currentSegmentEventsPath" not in metadata
        assert "currentSegmentMetadataPath" not in metadata

        run(
            [
                sys.executable,
                str(VALIDATOR),
                str(metadata_path),
                "--strict-ocu",
                "--require-event-type",
                "session.started",
                "--require-event-type",
                "session.ended",
            ]
        )
        runtime_validation = run(
            [
                str(LOCAL_CLIENT),
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                str(session_path),
            ]
        )
        runtime_payload = json.loads(runtime_validation.stdout)
        assert runtime_payload["ok"] is True, runtime_payload

    print(json.dumps({"ok": True, "probe": "event-stream-local"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
