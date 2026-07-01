#!/usr/bin/env python3

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ABSOLUTE_PATH_PATTERN = re.compile(r"(/Users/|/var/folders/|/private/var/|/tmp/)")


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def assert_generated_skill(
    output_dir: pathlib.Path,
    expected_quote: str,
    expect_metadata_path: bool = True,
) -> None:
    skill_text = (output_dir / "SKILL.md").read_text(encoding="utf-8")
    summary_text = (output_dir / "references/recording-summary.json").read_text(encoding="utf-8")
    if ABSOLUTE_PATH_PATTERN.search(skill_text + summary_text):
        raise AssertionError("generated skill scaffold contains local absolute paths")
    assert "name: recorded-example-workflow" in skill_text
    assert f"Click role={expected_quote}AXButton{expected_quote}, title={expected_quote}New Item{expected_quote}" in skill_text
    assert "Scroll in Example using the recorded wheel direction" in skill_text
    assert "Enter user-provided text" in skill_text
    assert "## Runtime Inputs" in skill_text
    assert "Runtime text for role=" in skill_text
    assert "use a fresh runtime value" in skill_text
    assert "Runtime selection or selected-content meaning" in skill_text
    assert "## Workflow Readiness" in skill_text
    assert "Status: needsReview" in skill_text
    assert "Can create skill draft: true" in skill_text
    assert "Requires human review: true" in skill_text
    assert "recording includes actions that may require explicit user confirmation" in skill_text
    assert "## Summary Limits" in skill_text
    assert "No high-volume summary fields were truncated." in skill_text
    assert "## Agent Replay Procedure" in skill_text
    assert "connector, API, or dedicated tool" in skill_text
    assert "visually dependent verification" in skill_text
    assert "get_app_state" in skill_text
    assert "`element_index` actions" in skill_text
    assert "## Verification" in skill_text
    assert "### Confirmation Signals" in skill_text
    assert "`keyboard.submit` matched submitAction" in skill_text
    assert "ask for explicit confirmation before replaying this step" in skill_text
    assert "open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadata-or-session>" in skill_text
    assert "## Finalizing The Skill" in skill_text
    assert "skill-creator" in skill_text
    assert "Read and follow the `skill-creator` skill" in skill_text
    assert "Complete the `skill-creator` workflow, including validation" in skill_text
    assert "actual discoverable skill directory" in skill_text
    assert "not a standalone runbook or replay plan" in skill_text
    summary = json.loads(summary_text)
    assert summary["eventsPath"] == "<recording-eventsPath>"
    if expect_metadata_path:
        assert summary["metadataPath"] == "<recording-metadataPath>"
    else:
        assert "metadataPath" not in summary
    assert summary["sessionDir"] == "<recording-sessionDir>"
    assert summary["runtimeInputs"][0]["kind"] == "text"
    assert summary["runtimeInputs"][0]["sourceEventType"] == "keyboard.text_input"
    assert summary["runtimeInputs"][0]["textLength"] == 12
    assert summary["runtimeInputs"][1]["kind"] == "selection"
    assert summary["runtimeInputs"][1]["sourceEventType"] == "selection.changed"
    assert summary["safetySignals"][0]["sourceEventType"] == "keyboard.submit"
    assert summary["safetySignals"][0]["reason"] == "submitAction"
    assert summary["safetySignals"][0]["confirmationRequired"] is True
    assert summary["skillEvidence"]["hasSafetySignals"] is True
    assert summary["summaryLimits"]["hasTruncatedSummary"] is False
    assert summary["summaryLimits"]["omittedCounts"]["actionSequence"] == 0
    assert summary["skillReadiness"]["status"] == "needsReview"
    assert summary["skillReadiness"]["canCreateSkillDraft"] is True


def run_source_scaffold(
    metadata_path: pathlib.Path,
    output_dir: pathlib.Path,
    expect_metadata_path: bool = True,
) -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/scaffold-event-stream-skill.py"),
            str(metadata_path),
            "--skill-name",
            "recorded-example-workflow",
            "--description",
            "Replay the recorded Example app workflow.",
            "--output-dir",
            str(output_dir),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr or completed.stdout)
    assert_generated_skill(output_dir, expected_quote="'", expect_metadata_path=expect_metadata_path)


def run_source_summary_reports_truncation(metadata_path: pathlib.Path) -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr or completed.stdout)
    summary = json.loads(completed.stdout)
    assert summary["summaryLimits"]["hasTruncatedSummary"] is True
    assert summary["summaryLimits"]["omittedCounts"]["actionSequence"] == 5
    assert summary["summaryLimits"]["omittedCounts"]["targetElements"] == 30
    assert len(summary["actionSequence"]) == 50
    assert len(summary["targetElements"]) == 25
    assert "recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill" in summary["warnings"]
    assert summary["skillEvidence"]["hasTruncatedSummary"] is True
    assert (
        "recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill"
        in summary["skillReadiness"]["reasons"]
    )


def runtime_cli_path() -> pathlib.Path:
    override = os.environ.get("OPEN_COMPUTER_USE_CLI")
    if override:
        return pathlib.Path(override)

    subprocess.run(
        ["swift", "build", "--product", "OpenComputerUse"],
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    return REPO_ROOT / ".build/debug/OpenComputerUse"


def run_runtime_scaffold(
    metadata_path: pathlib.Path,
    output_dir: pathlib.Path,
    expect_metadata_path: bool = True,
) -> None:
    cli = runtime_cli_path()
    completed = subprocess.run(
        [
            str(cli),
            "event-stream",
            "scaffold-skill",
            "--json",
            str(metadata_path),
            "--skill-name",
            "recorded-example-workflow",
            "--description",
            "Replay the recorded Example app workflow.",
            "--output-dir",
            str(output_dir),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        },
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr or completed.stdout)
    payload = json.loads(completed.stdout)
    assert payload["ok"] is True
    assert payload["skillName"] == "recorded-example-workflow"
    assert pathlib.Path(payload["skillPath"]).exists()
    assert pathlib.Path(payload["summaryPath"]).exists()
    assert_generated_skill(output_dir, expected_quote='"', expect_metadata_path=expect_metadata_path)


def run_validator_skill_draft_gate(metadata_path: pathlib.Path) -> None:
    source_completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
            str(metadata_path),
            "--require-skill-draft",
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if source_completed.returncode != 0:
        raise AssertionError(source_completed.stderr or source_completed.stdout)
    source_payload = json.loads(source_completed.stdout)
    assert source_payload["skillDraftReady"] is True

    cli = runtime_cli_path()
    runtime_completed = subprocess.run(
        [
            str(cli),
            "event-stream",
            "validate",
            "--json",
            "--require-skill-draft",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        },
    )
    if runtime_completed.returncode != 0:
        raise AssertionError(runtime_completed.stderr or runtime_completed.stdout)
    runtime_payload = json.loads(runtime_completed.stdout)
    assert runtime_payload["skillDraftReady"] is True


def run_external_screenshot_path_validation_gate(root: pathlib.Path) -> None:
    metadata_path = write_recording(root / "external-screenshot-session")
    external_screenshot = root / "outside-session-screenshot.png"
    external_screenshot.write_bytes(b"\x89PNG")

    events_path = metadata_path.parent / "events.jsonl"
    events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    events[2]["accessibilityInspectorPayload"] = {"screenshotPath": str(external_screenshot)}
    events_path.write_text(
        "".join(json.dumps(event, separators=(",", ":")) + "\n" for event in events),
        encoding="utf-8",
    )

    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
            str(metadata_path),
            "--strict-ocu",
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source validator accepted an external screenshotPath")
    payload = json.loads(completed.stderr or completed.stdout)
    expected = f"screenshotPath from event line 3 must stay inside session directory: {external_screenshot}"
    assert expected in payload["errors"]
    assert f"screenshotPath from event line 3 does not exist: {external_screenshot}" not in payload["errors"]


def run_events_jsonl_input_gate(metadata_path: pathlib.Path, root: pathlib.Path) -> None:
    events_path = metadata_path.parent / "events.jsonl"
    source_completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
            str(events_path),
            "--require-skill-draft",
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if source_completed.returncode != 0:
        raise AssertionError(source_completed.stderr or source_completed.stdout)
    source_payload = json.loads(source_completed.stdout)
    assert source_payload["skillDraftReady"] is True
    assert source_payload["metadataPath"] is None
    assert "metadata/session files not available; validating events.jsonl only" in source_payload["warnings"]

    source_output_dir = root / "events-jsonl-source-skill"
    run_source_scaffold(events_path, source_output_dir, expect_metadata_path=False)

    cli = runtime_cli_path()
    runtime_completed = subprocess.run(
        [
            str(cli),
            "event-stream",
            "validate",
            "--json",
            "--require-skill-draft",
            "--events-path",
            str(events_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        },
    )
    if runtime_completed.returncode != 0:
        raise AssertionError(runtime_completed.stderr or runtime_completed.stdout)
    runtime_payload = json.loads(runtime_completed.stdout)
    assert runtime_payload["skillDraftReady"] is True
    assert "metadataPath" not in runtime_payload
    assert "metadata/session files not available; validating events.jsonl only" in runtime_payload["warnings"]

    runtime_output_dir = root / "events-jsonl-runtime-skill"
    run_runtime_scaffold(events_path, runtime_output_dir, expect_metadata_path=False)


def write_recording(
    session_dir: pathlib.Path,
    state: str = "stopped",
    end_reason: str = "recording_controls_stopped",
    include_blocking_diagnostic: bool = False,
    include_session_ended: bool = True,
) -> pathlib.Path:
    session_dir.mkdir()
    events_path = session_dir / "events.jsonl"
    metadata_path = session_dir / "metadata.json"
    session_path = session_dir / "session.json"
    suppressed_path = session_dir / "suppressed.jsonl"
    events = [
        {
            "type": "session.started",
            "timestamp": "2026-06-26T00:00:00.000Z",
        },
        {
            "type": "window.changed",
            "timestamp": "2026-06-26T00:00:01.000Z",
            "appName": "Example",
            "bundleIdentifier": "com.example.app",
            "windowTitle": "Example Window",
        },
        {
            "type": "AX.focusedWindowChanged",
            "timestamp": "2026-06-26T00:00:02.000Z",
            "appName": "Example",
            "windowTitle": "Example Window",
        },
        {
            "type": "mouse.click",
            "timestamp": "2026-06-26T00:00:03.000Z",
            "appName": "Example",
            "windowTitle": "Example Window",
            "targetAccessibilityElement": {
                "role": "AXButton",
                "title": "New Item",
                "actions": ["AXPress"],
            },
        },
        {
            "type": "experimentalRawEvents",
            "timestamp": "2026-06-26T00:00:03.500Z",
            "appName": "Example",
            "windowTitle": "Example Window",
            "reason": "scrollWheel",
            "experimentalRawEvents": [
                {
                    "eventType": "scrollWheel",
                    "scrollingDeltaX": 0,
                    "scrollingDeltaY": -4,
                    "hasPreciseScrollingDeltas": False,
                },
            ],
        },
        {
            "type": "keyboard.text_input",
            "timestamp": "2026-06-26T00:00:04.000Z",
            "appName": "Example",
            "windowTitle": "Example Window",
            "textLength": 12,
            "focusedAccessibilityElement": {
                "role": "AXTextField",
                "title": "Name",
            },
        },
        {
            "type": "keyboard.submit",
            "timestamp": "2026-06-26T00:00:04.250Z",
            "appName": "Example",
            "windowTitle": "Example Window",
            "focusedAccessibilityElement": {
                "role": "AXButton",
                "title": "Submit",
            },
        },
        {
            "type": "selection.changed",
            "timestamp": "2026-06-26T00:00:04.500Z",
            "appName": "Example",
            "windowTitle": "Example Window",
            "selectedText": "example selected value",
            "focusedAccessibilityElement": {
                "role": "AXTextArea",
                "title": "Body",
            },
        },
    ]
    if include_blocking_diagnostic:
        events.append(
            {
                "type": "debug.error",
                "timestamp": "2026-06-26T00:00:04.750Z",
                "subsystem": "inputMonitoring",
                "reason": "inputMonitorsUnavailable",
                "errorType": "permission",
            }
        )
    if include_session_ended:
        events.append(
            {
                "type": "session.ended",
                "timestamp": "2026-06-26T00:00:05.000Z",
                "endReason": end_reason,
            }
        )
    events_path.write_text(
        "".join(json.dumps(event, separators=(",", ":")) + "\n" for event in events),
        encoding="utf-8",
    )
    suppressed_path.write_text("", encoding="utf-8")
    metadata = {
        "sessionId": f"session-test-{state}",
        "state": state,
        "active": state == "recording",
        "endReason": end_reason,
        "eventsPath": str(events_path),
        "metadataPath": str(metadata_path),
        "sessionPath": str(session_path),
        "suppressedEventsPath": str(suppressed_path),
        "eventCount": len(events),
        "suppressedEventCount": 0,
    }
    if state == "recording":
        metadata["currentSegmentEventsPath"] = str(events_path)
        metadata["currentSegmentMetadataPath"] = str(metadata_path)
    write_json(metadata_path, metadata)
    write_json(session_path, metadata)
    return metadata_path


def write_invalid_event_count_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["eventCount"] = 999
    write_json(metadata_path, metadata)
    write_json(metadata_path.parent / "session.json", metadata)
    return metadata_path


def write_events(metadata_path: pathlib.Path, events: list[dict]) -> None:
    events_path = metadata_path.parent / "events.jsonl"
    events_path.write_text(
        "".join(json.dumps(event, separators=(",", ":")) + "\n" for event in events),
        encoding="utf-8",
    )
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["eventCount"] = len(events)
    write_json(metadata_path, metadata)
    write_json(metadata_path.parent / "session.json", metadata)


def read_events(metadata_path: pathlib.Path) -> list[dict]:
    events_path = metadata_path.parent / "events.jsonl"
    return [
        json.loads(line)
        for line in events_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_missing_session_started_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    events = [event for event in read_events(metadata_path) if event.get("type") != "session.started"]
    write_events(metadata_path, events)
    return metadata_path


def write_duplicate_session_started_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    events = read_events(metadata_path)
    events.insert(
        1,
        {
            "type": "session.started",
            "timestamp": "2026-06-26T00:00:00.500Z",
        },
    )
    write_events(metadata_path, events)
    return metadata_path


def write_session_started_not_first_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    events = read_events(metadata_path)
    first = events.pop(0)
    events.insert(1, first)
    write_events(metadata_path, events)
    return metadata_path


def write_session_ended_not_final_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    events = read_events(metadata_path)
    events.append(
        {
            "type": "window.changed",
            "timestamp": "2026-06-26T00:00:06.000Z",
            "appName": "Example",
            "windowTitle": "Late Window",
        }
    )
    write_events(metadata_path, events)
    return metadata_path


def write_duplicate_session_ended_recording(session_dir: pathlib.Path) -> pathlib.Path:
    metadata_path = write_recording(session_dir)
    events = read_events(metadata_path)
    events.append(
        {
            "type": "session.ended",
            "timestamp": "2026-06-26T00:00:06.000Z",
            "endReason": "recording_controls_stopped",
        }
    )
    write_events(metadata_path, events)
    return metadata_path


def write_long_recording(session_dir: pathlib.Path) -> pathlib.Path:
    session_dir.mkdir()
    events_path = session_dir / "events.jsonl"
    metadata_path = session_dir / "metadata.json"
    session_path = session_dir / "session.json"
    suppressed_path = session_dir / "suppressed.jsonl"
    events = [
        {
            "type": "session.started",
            "timestamp": "2026-06-26T00:00:00.000Z",
        },
        {
            "type": "window.changed",
            "timestamp": "2026-06-26T00:00:01.000Z",
            "appName": "Example",
            "windowTitle": "Long Example Window",
        },
    ]
    for index in range(55):
        events.append(
            {
                "type": "mouse.click",
                "timestamp": f"2026-06-26T00:00:{index + 2:02d}.000Z",
                "appName": "Example",
                "windowTitle": "Long Example Window",
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": f"Step {index}",
                },
            }
        )
    events.append(
        {
            "type": "session.ended",
            "timestamp": "2026-06-26T00:01:00.000Z",
            "endReason": "recording_controls_stopped",
        }
    )
    events_path.write_text(
        "".join(json.dumps(event, separators=(",", ":")) + "\n" for event in events),
        encoding="utf-8",
    )
    suppressed_path.write_text("", encoding="utf-8")
    metadata = {
        "sessionId": "long-session-test",
        "state": "stopped",
        "endReason": "recording_controls_stopped",
        "eventsPath": str(events_path),
        "metadataPath": str(metadata_path),
        "sessionPath": str(session_path),
        "suppressedEventsPath": str(suppressed_path),
        "eventCount": len(events),
        "suppressedEventCount": 0,
    }
    write_json(metadata_path, metadata)
    write_json(session_path, metadata)
    return metadata_path


def run_source_scaffold_rejected(metadata_path: pathlib.Path, output_dir: pathlib.Path, expected_reason: str) -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/scaffold-event-stream-skill.py"),
            str(metadata_path),
            "--skill-name",
            "cancelled-recording-workflow",
            "--description",
            "Replay the cancelled recording.",
            "--output-dir",
            str(output_dir),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    combined = completed.stdout + completed.stderr
    if completed.returncode == 0:
        raise AssertionError("source scaffold accepted a recording that should be rejected")
    assert expected_reason in combined
    assert not output_dir.exists()


def run_runtime_scaffold_rejected(metadata_path: pathlib.Path, output_dir: pathlib.Path, expected_reason: str) -> None:
    cli = runtime_cli_path()
    completed = subprocess.run(
        [
            str(cli),
            "event-stream",
            "scaffold-skill",
            "--json",
            str(metadata_path),
            "--skill-name",
            "cancelled-recording-workflow",
            "--description",
            "Replay the cancelled recording.",
            "--output-dir",
            str(output_dir),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        },
    )
    combined = completed.stdout + completed.stderr
    if completed.returncode == 0:
        payload = json.loads(completed.stdout)
        assert payload["ok"] is False
    assert expected_reason in combined
    assert not output_dir.exists()


def run_validator_skill_draft_gate_rejected(metadata_path: pathlib.Path, expected_reason: str) -> None:
    source_completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
            str(metadata_path),
            "--require-skill-draft",
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    source_combined = source_completed.stdout + source_completed.stderr
    if source_completed.returncode == 0:
        raise AssertionError("source validator accepted a skill draft recording that should be rejected")
    assert expected_reason in source_combined
    source_payload = json.loads(source_completed.stderr or source_completed.stdout)
    assert source_payload["skillDraftReady"] is False
    assert expected_reason in source_payload["skillDraftReasons"]

    cli = runtime_cli_path()
    runtime_completed = subprocess.run(
        [
            str(cli),
            "event-stream",
            "validate",
            "--json",
            "--require-skill-draft",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
        },
    )
    runtime_combined = runtime_completed.stdout + runtime_completed.stderr
    if runtime_completed.returncode == 0:
        payload = json.loads(runtime_completed.stdout)
        assert payload["ok"] is False
        assert payload["skillDraftReady"] is False
    assert expected_reason in runtime_combined
    runtime_payload = json.loads(runtime_completed.stderr or runtime_completed.stdout)
    assert runtime_payload["skillDraftReady"] is False
    assert expected_reason in runtime_payload["skillDraftReasons"]


def run_current_segment_strict_validation_gate(root: pathlib.Path) -> None:
    cli = runtime_cli_path()

    active_metadata_path = write_recording(
        root / "strict-current-segment-active",
        state="recording",
        end_reason="",
        include_session_ended=False,
    )
    active_metadata = json.loads(active_metadata_path.read_text(encoding="utf-8"))
    active_metadata.pop("currentSegmentEventsPath")
    active_metadata.pop("currentSegmentMetadataPath")
    write_json(active_metadata_path, active_metadata)
    write_json(active_metadata_path.parent / "session.json", active_metadata)

    final_metadata_path = write_recording(root / "strict-current-segment-final")
    final_metadata = json.loads(final_metadata_path.read_text(encoding="utf-8"))
    final_metadata["currentSegmentEventsPath"] = final_metadata["eventsPath"]
    final_metadata["currentSegmentMetadataPath"] = final_metadata["metadataPath"]
    write_json(final_metadata_path, final_metadata)
    write_json(final_metadata_path.parent / "session.json", final_metadata)

    cases = [
        (
            active_metadata_path,
            [
                "recording state requires currentSegmentEventsPath",
                "recording state requires currentSegmentMetadataPath",
            ],
        ),
        (
            final_metadata_path,
            [
                "final state must not include currentSegmentEventsPath",
                "final state must not include currentSegmentMetadataPath",
            ],
        ),
    ]
    for metadata_path, expected_errors in cases:
        source = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
                str(metadata_path),
                "--strict-ocu",
            ],
            cwd=str(REPO_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert source.returncode != 0, source.stdout
        source_payload = json.loads(source.stderr or source.stdout)
        for expected_error in expected_errors:
            assert expected_error in source_payload["errors"], source_payload

        runtime = subprocess.run(
            [
                str(cli),
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                str(metadata_path),
            ],
            cwd=str(REPO_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        runtime_payload = json.loads(runtime.stdout or runtime.stderr)
        assert runtime_payload["ok"] is False, runtime_payload
        for expected_error in expected_errors:
            assert expected_error in runtime_payload["errors"], runtime_payload


def run_declared_handoff_path_strict_validation_gate(root: pathlib.Path) -> None:
    cli = runtime_cli_path()

    missing_metadata_path = write_recording(root / "strict-declared-paths-missing")
    missing_metadata = json.loads(missing_metadata_path.read_text(encoding="utf-8"))
    for key in ["metadataPath", "sessionPath", "eventsPath", "suppressedEventsPath"]:
        missing_metadata.pop(key)
    write_json(missing_metadata_path, missing_metadata)
    write_json(missing_metadata_path.parent / "session.json", missing_metadata)

    bad_metadata_path = write_recording(root / "strict-declared-paths-bad-session")
    bad_metadata = json.loads(bad_metadata_path.read_text(encoding="utf-8"))
    bad_metadata["sessionPath"] = "missing-session.json"
    write_json(bad_metadata_path, bad_metadata)
    write_json(bad_metadata_path.parent / "session.json", bad_metadata)

    cases = [
        (
            missing_metadata_path,
            [
                "strict OCU validation requires metadataPath",
                "strict OCU validation requires sessionPath",
                "strict OCU validation requires eventsPath",
                "strict OCU validation requires suppressedEventsPath",
            ],
        ),
        (
            bad_metadata_path,
            [
                "sessionPath does not exist: missing-session.json",
            ],
        ),
    ]
    for metadata_path, expected_errors in cases:
        source = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "scripts/validate-event-stream-recording.py"),
                str(metadata_path),
                "--strict-ocu",
            ],
            cwd=str(REPO_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert source.returncode != 0, source.stdout
        source_payload = json.loads(source.stderr or source.stdout)
        assert set(source_payload["declaredPaths"].keys()) == {
            "metadataPath",
            "sessionPath",
            "eventsPath",
            "suppressedEventsPath",
        }
        for expected_error in expected_errors:
            assert expected_error in source_payload["errors"], source_payload

        runtime = subprocess.run(
            [
                str(cli),
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                str(metadata_path),
            ],
            cwd=str(REPO_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        runtime_payload = json.loads(runtime.stdout or runtime.stderr)
        assert runtime_payload["ok"] is False, runtime_payload
        assert set(runtime_payload["declaredPaths"].keys()) == {
            "metadataPath",
            "sessionPath",
            "eventsPath",
            "suppressedEventsPath",
        }
        for expected_error in expected_errors:
            assert expected_error in runtime_payload["errors"], runtime_payload


def run_source_summary_rejects_blocking_diagnostics(metadata_path: pathlib.Path) -> None:
    expected_reason = "recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a blocking diagnostic recording")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["skillEvidence"]["hasBlockingDiagnostics"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert payload["blockingDiagnostics"][0]["reason"] == "inputMonitorsUnavailable"
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_incomplete_recording(metadata_path: pathlib.Path) -> None:
    expected_reason = "recording is not complete; stop the recording before creating a skill"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted an incomplete recording")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["state"] == "recording"
    assert payload["skillEvidence"]["recordingIncomplete"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_session_started_count(metadata_path: pathlib.Path, expected_count: int) -> None:
    expected_reason = "recording must contain exactly one session.started event before creating a skill"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a recording with invalid session.started count")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["sessionStartedCount"] == expected_count
    assert payload["skillEvidence"]["sessionStartedCountInvalid"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_session_started_not_first(metadata_path: pathlib.Path) -> None:
    expected_reason = "recording has events before session.started; start must be the first event before creating a skill"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a recording with events before session.started")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["firstEventType"] == "window.changed"
    assert payload["sessionStartedCount"] == 1
    assert payload["sessionStartedIsFirst"] is False
    assert payload["skillEvidence"]["sessionStartedNotFirst"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_session_ended_not_final(metadata_path: pathlib.Path) -> None:
    expected_reason = "recording has events after session.ended; stop or cancel must be the final event before creating a skill"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a recording with events after session.ended")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["finalEventType"] == "window.changed"
    assert payload["sessionEndedIsFinal"] is False
    assert payload["skillEvidence"]["sessionEndedNotFinal"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_duplicate_session_ended(metadata_path: pathlib.Path) -> None:
    expected_reason = "recording has multiple session.ended events; stop or cancel must close the event stream exactly once"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(metadata_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a recording with duplicate session.ended events")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["sessionEndedCount"] == 2
    assert payload["sessionEndedIsFinal"] is True
    assert payload["skillEvidence"]["sessionEndedCountInvalid"] is True
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def run_source_summary_rejects_cancelled_events_jsonl(events_path: pathlib.Path) -> None:
    expected_reason = "recording was cancelled; do not create or update a skill from this event stream"
    completed = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts/summarize-event-stream-recording.py"),
            "--require-action",
            str(events_path),
        ],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode == 0:
        raise AssertionError("source summary accepted a cancelled events.jsonl recording")
    payload = json.loads(completed.stderr or completed.stdout)
    assert payload["ok"] is False
    assert payload["endReason"] == "recording_controls_cancelled"
    assert payload["skillReadiness"]["status"] == "insufficient"
    assert payload["skillReadiness"]["canCreateSkillDraft"] is False
    assert expected_reason in payload["errors"]
    assert expected_reason in payload["warnings"]
    assert expected_reason in payload["skillReadiness"]["reasons"]


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="event-stream-skill-scaffold-") as raw_root:
        root = pathlib.Path(raw_root)
        session_dir = root / "session"
        source_output_dir = root / "generated-source-skill"
        runtime_output_dir = root / "generated-runtime-skill"

        metadata_path = write_recording(session_dir)
        long_metadata_path = write_long_recording(root / "long-session")

        run_source_summary_reports_truncation(long_metadata_path)
        run_validator_skill_draft_gate(metadata_path)
        run_external_screenshot_path_validation_gate(root)
        run_current_segment_strict_validation_gate(root)
        run_declared_handoff_path_strict_validation_gate(root)
        run_events_jsonl_input_gate(metadata_path, root)
        run_source_scaffold(metadata_path, source_output_dir)
        run_runtime_scaffold(metadata_path, runtime_output_dir)

        cancelled_metadata_path = write_recording(
            root / "cancelled-session",
            state="cancelled",
            end_reason="recording_controls_cancelled",
        )
        cancelled_reason = "recording was cancelled; do not create or update a skill from this event stream"
        run_validator_skill_draft_gate_rejected(cancelled_metadata_path, cancelled_reason)
        run_source_scaffold_rejected(cancelled_metadata_path, root / "cancelled-source-skill", cancelled_reason)
        run_runtime_scaffold_rejected(cancelled_metadata_path, root / "cancelled-runtime-skill", cancelled_reason)
        cancelled_events_path = cancelled_metadata_path.parent / "events.jsonl"
        run_source_summary_rejects_cancelled_events_jsonl(cancelled_events_path)
        run_validator_skill_draft_gate_rejected(cancelled_events_path, cancelled_reason)
        run_source_scaffold_rejected(cancelled_events_path, root / "cancelled-events-source-skill", cancelled_reason)
        run_runtime_scaffold_rejected(cancelled_events_path, root / "cancelled-events-runtime-skill", cancelled_reason)

        blocking_metadata_path = write_recording(
            root / "blocking-diagnostic-session",
            include_blocking_diagnostic=True,
        )
        blocking_reason = "recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"
        run_source_summary_rejects_blocking_diagnostics(blocking_metadata_path)
        run_validator_skill_draft_gate_rejected(blocking_metadata_path, blocking_reason)
        run_source_scaffold_rejected(blocking_metadata_path, root / "blocking-source-skill", blocking_reason)
        run_runtime_scaffold_rejected(blocking_metadata_path, root / "blocking-runtime-skill", blocking_reason)

        incomplete_metadata_path = write_recording(
            root / "incomplete-session",
            state="recording",
            end_reason="",
            include_session_ended=False,
        )
        incomplete_reason = "recording is not complete; stop the recording before creating a skill"
        run_source_summary_rejects_incomplete_recording(incomplete_metadata_path)
        run_validator_skill_draft_gate_rejected(incomplete_metadata_path, incomplete_reason)
        run_source_scaffold_rejected(incomplete_metadata_path, root / "incomplete-source-skill", incomplete_reason)
        run_runtime_scaffold_rejected(incomplete_metadata_path, root / "incomplete-runtime-skill", incomplete_reason)

        missing_start_metadata_path = write_missing_session_started_recording(root / "missing-session-started")
        invalid_start_count_reason = "recording must contain exactly one session.started event before creating a skill"
        run_source_summary_rejects_session_started_count(missing_start_metadata_path, 0)
        run_validator_skill_draft_gate_rejected(missing_start_metadata_path, invalid_start_count_reason)
        run_source_scaffold_rejected(missing_start_metadata_path, root / "missing-start-source-skill", invalid_start_count_reason)
        run_runtime_scaffold_rejected(missing_start_metadata_path, root / "missing-start-runtime-skill", invalid_start_count_reason)

        duplicate_start_metadata_path = write_duplicate_session_started_recording(root / "duplicate-session-started")
        run_source_summary_rejects_session_started_count(duplicate_start_metadata_path, 2)
        run_validator_skill_draft_gate_rejected(duplicate_start_metadata_path, invalid_start_count_reason)
        run_source_scaffold_rejected(duplicate_start_metadata_path, root / "duplicate-start-source-skill", invalid_start_count_reason)
        run_runtime_scaffold_rejected(duplicate_start_metadata_path, root / "duplicate-start-runtime-skill", invalid_start_count_reason)

        start_not_first_metadata_path = write_session_started_not_first_recording(root / "session-started-not-first")
        start_not_first_reason = "recording has events before session.started; start must be the first event before creating a skill"
        run_source_summary_rejects_session_started_not_first(start_not_first_metadata_path)
        run_validator_skill_draft_gate_rejected(start_not_first_metadata_path, start_not_first_reason)
        run_source_scaffold_rejected(start_not_first_metadata_path, root / "start-not-first-source-skill", start_not_first_reason)
        run_runtime_scaffold_rejected(start_not_first_metadata_path, root / "start-not-first-runtime-skill", start_not_first_reason)

        not_final_metadata_path = write_session_ended_not_final_recording(root / "session-ended-not-final")
        not_final_reason = "recording has events after session.ended; stop or cancel must be the final event before creating a skill"
        run_source_summary_rejects_session_ended_not_final(not_final_metadata_path)
        run_validator_skill_draft_gate_rejected(not_final_metadata_path, not_final_reason)
        run_source_scaffold_rejected(not_final_metadata_path, root / "not-final-source-skill", not_final_reason)
        run_runtime_scaffold_rejected(not_final_metadata_path, root / "not-final-runtime-skill", not_final_reason)

        duplicate_end_metadata_path = write_duplicate_session_ended_recording(root / "duplicate-session-ended")
        duplicate_end_reason = "recording has multiple session.ended events; stop or cancel must close the event stream exactly once"
        run_source_summary_rejects_duplicate_session_ended(duplicate_end_metadata_path)
        run_validator_skill_draft_gate_rejected(duplicate_end_metadata_path, duplicate_end_reason)
        run_source_scaffold_rejected(duplicate_end_metadata_path, root / "duplicate-end-source-skill", duplicate_end_reason)
        run_runtime_scaffold_rejected(duplicate_end_metadata_path, root / "duplicate-end-runtime-skill", duplicate_end_reason)

        invalid_count_metadata_path = write_invalid_event_count_recording(root / "invalid-count-session")
        invalid_count_reason = "eventCount=999 does not match events.jsonl lines=9"
        run_source_scaffold_rejected(
            invalid_count_metadata_path,
            root / "invalid-count-source-skill",
            invalid_count_reason,
        )
        run_runtime_scaffold_rejected(
            invalid_count_metadata_path,
            root / "invalid-count-runtime-skill",
            invalid_count_reason,
        )

    print(
        json.dumps(
            {
                "checkedExternalScreenshotPathBoundary": True,
                "ok": True,
                "scaffold": "event-stream-skill",
                "runtimeCli": True,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
