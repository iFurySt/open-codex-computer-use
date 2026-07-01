#!/usr/bin/env python3

import json
import pathlib
import re
import sys


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = (
    REPO_ROOT
    / "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json"
)
NO_ACTIVE_FIXTURE = (
    REPO_ROOT
    / "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-no-active-status-stop-1.0.857.json"
)
ABSOLUTE_PATH_PATTERN = re.compile(r"(/Users/|/var/folders/|/private/var/|/tmp/)")
EXPECTED_NO_ACTIVE_RESPONSE = {"isRecording": False, "maxDurationSeconds": 1800}
RECORDING_PATH_KEYS = {
    "currentSegmentEventsPath",
    "currentSegmentMetadataPath",
    "eventsPath",
    "metadataPath",
    "sessionPath",
    "suppressedEventsPath",
}


def contains_recording_path(value) -> bool:
    if isinstance(value, dict):
        if any(key in RECORDING_PATH_KEYS for key in value):
            return True
        return any(contains_recording_path(item) for item in value.values())
    if isinstance(value, list):
        return any(contains_recording_path(item) for item in value)
    return False


def main() -> int:
    text = FIXTURE.read_text(encoding="utf-8")
    if ABSOLUTE_PATH_PATTERN.search(text):
        raise AssertionError(f"probe fixture contains a local absolute path: {FIXTURE}")
    data = json.loads(text)
    assert data["fixtureFormatVersion"] == 1
    assert data["kind"] == "record-and-replay-event-stream-probe"
    assert data["source"] == "official"
    assert data["officialPluginVersion"] == "1.0.857"
    assert data["ok"] is True
    assert data["startStopRequested"] is True
    assert data["startStopCompleted"] is False
    assert data["startTimedOut"] is True
    assert data["startResponseShape"] == {"timeout": 10.0}
    assert data["statusResponseShape"] == {"timeout": 10.0}
    assert data["stopResponseShape"] == {"timeout": 10.0}
    assert data["protocolVersion"] == "2025-11-25"
    assert data["serverInfo"]["name"] == "Record & Replay"
    assert data["toolNames"] == [
        "event_stream_start",
        "event_stream_status",
        "event_stream_stop",
    ]
    assert data.get("elicitationRequests") == []
    transcript = data["transcriptShape"]
    has_tool_call = any(
        item.get("direction") == "send"
        and item.get("method") == "tools/call"
        for item in transcript
    )
    assert has_tool_call
    tool_call_count = sum(
        1
        for item in transcript
        if item.get("direction") == "send" and item.get("method") == "tools/call"
    )
    timeout_count = sum(1 for item in transcript if item.get("timeout") is not None)
    assert tool_call_count == 3
    assert timeout_count == 3
    assert not contains_recording_path(data)

    no_active_text = NO_ACTIVE_FIXTURE.read_text(encoding="utf-8")
    if ABSOLUTE_PATH_PATTERN.search(no_active_text):
        raise AssertionError(
            f"no-active fixture contains a local absolute path: {NO_ACTIVE_FIXTURE}"
        )
    no_active = json.loads(no_active_text)
    assert no_active["officialPluginVersion"] == "record-and-replay 1.0.857"
    assert "no active recording" in no_active["captureScope"]
    responses = no_active["toolResponses"]
    for tool_name in ("event_stream_status", "event_stream_stop"):
        content = responses[tool_name]["content"]
        assert content == [{"type": "text", "textJSON": EXPECTED_NO_ACTIVE_RESPONSE}]

    print(
        json.dumps(
            {
                "ok": True,
                "checkedOfficialRawStartTimeoutBoundary": True,
                "checkedOfficialRawStartStatusStopTimeout": True,
                "checkedOfficialRawStartDoesNotReturnRecordingPaths": True,
                "checkedOfficialRawSurface": True,
                "checkedRawProbeFixtureRedaction": True,
                "checkedNoActiveFixtureRedaction": True,
                "officialRawToolCallCount": tool_call_count,
                "officialRawTimeoutCount": timeout_count,
                "fixtures": [
                    str(FIXTURE.relative_to(REPO_ROOT)),
                    str(NO_ACTIVE_FIXTURE.relative_to(REPO_ROOT)),
                ],
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
