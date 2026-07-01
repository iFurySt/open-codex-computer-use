#!/usr/bin/env python3

import json
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

from record_and_replay_scenarios import DEFAULT_REQUIRED_SCENARIOS


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n")


def action_event(event_type: str, session_id: str) -> dict:
    if event_type == "mouse.click":
        return {
            "type": "mouse.click",
            "sessionId": session_id,
            "button": "left",
            "location": {"x": 10, "y": 20},
            "targetAccessibilityElement": {
                "role": "AXButton",
                "title": "Private OCU Button",
                "value": "private-ocu-value",
                "actions": ["AXPress"],
            },
        }
    if event_type == "keyboard.text_input":
        return {
            "type": "keyboard.text_input",
            "sessionId": session_id,
            "textLength": 11,
            "focusedAccessibilityElement": {
                "role": "AXTextField",
                "title": "Private OCU Text Field",
                "value": "private-ocu-keyboard-value",
            },
        }
    if event_type == "mouse.drag":
        return {
            "type": "mouse.drag",
            "sessionId": session_id,
            "startLocation": {"x": 10, "y": 20},
            "endLocation": {"x": 80, "y": 120},
            "distance": 122.1,
            "durationSeconds": 0.42,
            "targetAccessibilityElement": {
                "role": "AXSlider",
                "title": "Private OCU Drag Target",
                "value": "private-ocu-drag-value",
            },
        }
    raise ValueError(f"unsupported action event type: {event_type}")


def make_recording(
    root: pathlib.Path,
    session_id: str = "ocu-secret-session",
    event_type: str = "mouse.click",
) -> dict[str, pathlib.Path]:
    recording = root / "recordings" / session_id
    recording.mkdir(parents=True)
    metadata_path = recording / "metadata.json"
    session_path = recording / "session.json"
    events_path = recording / "events.jsonl"
    suppressed_path = recording / "suppressed.jsonl"
    events = [
        {"type": "session.started", "sessionId": session_id},
        {
            "type": "AX.focusedWindowChanged",
            "sessionId": session_id,
            "accessibilityInspectorPayload": {
                "kind": "full",
                "diffFromPrevious": False,
                "renderedText": "Private OCU app content",
                "treeLines": ["AXWindow Private OCU Title", "+ AXButton Private OCU Button"],
                "screenshotNeededForContext": False,
                "screenshotAvailable": False,
            },
        },
        action_event(event_type, session_id),
        {
            "type": "session.ended",
            "sessionId": session_id,
            "endReason": "recording_controls_stopped",
        },
    ]
    write_jsonl(events_path, events)
    write_jsonl(suppressed_path, [])
    metadata = {
        "sessionId": session_id,
        "state": "stopped",
        "active": False,
        "endReason": "recording_controls_stopped",
        "eventCount": len(events),
        "suppressedEventCount": 0,
        "metadataPath": str(metadata_path),
        "sessionPath": str(session_path),
        "eventsPath": str(events_path),
        "suppressedEventsPath": str(suppressed_path),
    }
    write_json(metadata_path, metadata)
    write_json(session_path, metadata)
    return {
        "recording": recording,
        "metadata": metadata_path,
        "session": session_path,
        "events": events_path,
        "suppressed": suppressed_path,
        "recordingsRoot": recording.parent,
        "sessionId": session_id,
    }


def response_shape(session_id: str, paths: dict[str, pathlib.Path]):
    return {
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        {
                            "sessionId": session_id,
                            "metadataPath": str(paths["metadata"]),
                            "sessionPath": str(paths["session"]),
                            "eventsPath": str(paths["events"]),
                            "suppressedEventsPath": str(paths["suppressed"]),
                        }
                    ),
                }
            ]
        }
    }


def run(command, cwd):
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    default_required_scenario = DEFAULT_REQUIRED_SCENARIOS[0]
    ingest_script = repo / "scripts/ingest-ocu-record-and-replay-candidate.py"
    import_script = repo / "scripts/import-event-stream-fixture.py"
    spec = importlib.util.spec_from_file_location("ocu_candidate_ingest", ingest_script)
    assert spec and spec.loader
    ingest_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ingest_module)

    assert ingest_module.action_smoke_scenario_for_fixture_scenario("simple-action-stop") == "simple-action-stop"
    assert ingest_module.action_smoke_scenario_for_fixture_scenario("drag-stop") == "drag-stop"
    assert ingest_module.action_smoke_scenario_for_fixture_scenario("cancel") == "mixed-action-stop"
    try:
        ingest_module.action_smoke_scenario_for_fixture_scenario("keyboard-input-stop")
    except ValueError as error:
        assert "does not support --run-action-smoke yet" in str(error)
    else:
        raise AssertionError("keyboard-input-stop should not map to --run-action-smoke")

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        paths = make_recording(root)
        transcript = root / "candidate-transcript.json"
        shape = response_shape(paths["sessionId"], paths)
        write_json(
            transcript,
            {
                "startResponseShape": shape,
                "repeatStartResponseShape": shape,
                "statusResponseShape": shape,
                "stopResponseShape": shape,
                "repeatStopResponseShape": shape,
                "finalStatusResponseShape": shape,
            },
        )

        official_root = root / "official-fixtures"
        official_import = run(
            [
                sys.executable,
                str(import_script),
                str(paths["recording"]),
                "--name",
                "official-simple-action",
                "--output-dir",
                str(official_root),
                "--source",
                "official",
                "--scenario",
                "simple-action-stop",
                "--official-plugin-version",
                "record-and-replay 1.0.857",
                "--mcp-transcript",
                str(transcript),
            ],
            repo,
        )
        assert official_import.returncode == 0, official_import.stderr

        candidate_root = root / "candidate-fixtures"
        direct = run(
            [
                sys.executable,
                str(ingest_script),
                "--recording",
                str(paths["recording"]),
                "--name",
                "ocu-simple-action",
                "--output-dir",
                str(candidate_root),
                "--mcp-transcript",
                str(transcript),
                "--require-mcp-transcript-evidence",
                "--official-root",
                str(official_root),
                "--check-fixture-set",
            ],
            repo,
        )
        assert direct.returncode == 0, direct.stderr
        direct_json = json.loads(direct.stdout)
        assert direct_json["ok"] is True
        assert direct_json["validation"]["ok"] is True
        assert direct_json["readiness"]["ok"] is True
        assert direct_json["fixtureSetGate"]["ok"] is True
        assert direct_json["usedMcpTranscript"] == str(transcript)
        commands = direct_json["commands"]
        assert commands["pairingPreflightShell"].startswith(
            "python3 scripts/prepare-record-and-replay-ocu-candidate-pairing.py"
        )
        assert "--require-candidate-ready" in commands["pairingPreflight"]
        assert str(official_root) in commands["pairingPreflight"]
        assert str(candidate_root) in commands["pairingPreflight"]
        assert commands["fixtureSetGateShell"].startswith(
            "python3 scripts/check-event-stream-official-fixture-set.py"
        )
        assert "--require-scenario" in commands["fixtureSetGate"]
        assert "simple-action-stop" in commands["fixtureSetGate"]

        fixture = candidate_root / "ocu-simple-action"
        manifest = json.loads((fixture / "fixture-manifest.json").read_text())
        assert manifest["source"] == "ocu"
        assert manifest["scenario"] == default_required_scenario
        assert manifest["files"]["mcpTranscript"] == "mcp-transcript.json"
        combined = "\n".join(path.read_text() for path in fixture.glob("*") if path.is_file())
        for secret in [
            paths["sessionId"],
            "Private OCU app content",
            "Private OCU Title",
            "Private OCU Button",
            "Private OCU Text Field",
            "Private OCU Drag Target",
            "private-ocu-value",
            "private-ocu-keyboard-value",
            "private-ocu-drag-value",
            str(root),
        ]:
            assert secret not in combined, secret

        scenario_cases = [
            ("keyboard-input-stop", "keyboard.text_input", "ocu-keyboard-input"),
            ("drag-stop", "mouse.drag", "ocu-drag"),
        ]
        for scenario, event_type, name in scenario_cases:
            scenario_paths = make_recording(
                root,
                session_id=f"{name}-secret-session",
                event_type=event_type,
            )
            scenario_transcript = root / f"{name}-transcript.json"
            scenario_shape = response_shape(scenario_paths["sessionId"], scenario_paths)
            write_json(
                scenario_transcript,
                {
                    "startResponseShape": scenario_shape,
                    "repeatStartResponseShape": scenario_shape,
                    "statusResponseShape": scenario_shape,
                    "stopResponseShape": scenario_shape,
                    "repeatStopResponseShape": scenario_shape,
                    "finalStatusResponseShape": scenario_shape,
                },
            )
            scenario_result = run(
                [
                    sys.executable,
                    str(ingest_script),
                    "--recording",
                    str(scenario_paths["recording"]),
                    "--name",
                    name,
                    "--scenario",
                    scenario,
                    "--output-dir",
                    str(candidate_root),
                    "--mcp-transcript",
                    str(scenario_transcript),
                    "--require-mcp-transcript-evidence",
                ],
                repo,
            )
            assert scenario_result.returncode == 0, scenario_result.stderr
            scenario_json = json.loads(scenario_result.stdout)
            assert scenario_json["ok"] is True
            assert scenario_json["validation"]["ok"] is True
            assert scenario_json["readiness"]["ok"] is True
            assert scenario_json["scenario"] == scenario
            event_counts = scenario_json["readiness"]["recordings"][0]["eventTypes"]
            assert event_counts[event_type] == 1

        smoke_json = root / "action-smoke.jsonl"
        write_jsonl(
            smoke_json,
            [
                {"mode": "ignored", "ok": True},
                {
                    "mode": "actions",
                    "ok": True,
                    "sessionId": paths["sessionId"],
                    "recordingsRoot": str(paths["recordingsRoot"]),
                    "mcpTranscriptPath": str(transcript),
                    "eventTypes": ["session.started", "AX.focusedWindowChanged", "mouse.click", "session.ended"],
                },
            ],
        )
        from_smoke = run(
            [
                sys.executable,
                str(ingest_script),
                "--smoke-json",
                str(smoke_json),
                "--name",
                "ocu-simple-action-from-smoke",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(candidate_root),
                "--require-mcp-transcript-evidence",
            ],
            repo,
        )
        assert from_smoke.returncode == 0, from_smoke.stderr
        from_smoke_json = json.loads(from_smoke.stdout)
        assert from_smoke_json["ok"] is True
        assert from_smoke_json["smokeRecord"]["mode"] == "actions"
        assert from_smoke_json["recordingInput"] == str(paths["recording"])
        assert from_smoke_json["usedMcpTranscript"] == str(transcript)

        missing_mode = run(
            [
                sys.executable,
                str(ingest_script),
                "--smoke-json",
                str(smoke_json),
                "--smoke-mode",
                "missing",
                "--name",
                "missing-mode",
                "--output-dir",
                str(candidate_root),
            ],
            repo,
        )
        assert missing_mode.returncode == 1
        missing_mode_json = json.loads(missing_mode.stderr)
        assert "smoke JSONL has no record with mode='missing'" in missing_mode_json["errors"][0]

    print(
        json.dumps(
            {
                "ok": True,
                "checkedOcuCandidateIngest": True,
                "checkedCandidateIngestHandoffCommands": True,
                "checkedSmokeJsonImport": True,
                "checkedOfficialCandidatePairing": True,
                "checkedCandidateRedaction": True,
                "checkedKeyboardInputScenarioReadiness": True,
                "checkedDragScenarioReadiness": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
