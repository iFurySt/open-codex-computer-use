#!/usr/bin/env python3

import json
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
                "title": "Private Button",
                "value": "private-value",
            },
        }
    if event_type == "keyboard.text_input":
        return {
            "type": "keyboard.text_input",
            "sessionId": session_id,
            "textLength": 4,
            "focusedAccessibilityElement": {
                "role": "AXTextField",
                "title": "Private Field",
                "value": "private-keyboard-value",
            },
        }
    if event_type == "mouse.drag":
        return {
            "type": "mouse.drag",
            "sessionId": session_id,
            "button": "left",
            "startLocation": {"x": 10, "y": 20},
            "endLocation": {"x": 80, "y": 120},
            "distance": 122.07,
            "durationMs": 400,
            "targetAccessibilityElement": {
                "role": "AXSlider",
                "title": "Private Drag Target",
                "value": "private-drag-value",
            },
        }
    raise ValueError(f"unsupported action event type: {event_type}")


def make_recording(root: pathlib.Path, event_type: str = "mouse.click") -> dict[str, pathlib.Path]:
    recording = root / "official-recording"
    recording.mkdir(parents=True)
    metadata_path = recording / "metadata.json"
    session_path = recording / "session.json"
    events_path = recording / "events.jsonl"
    suppressed_path = recording / "suppressed.jsonl"
    events = [
        {"type": "session.started", "sessionId": "official-secret-session"},
        {
            "type": "AX.focusedWindowChanged",
            "sessionId": "official-secret-session",
            "accessibilityInspectorPayload": {
                "kind": "full",
                "diffFromPrevious": False,
                "renderedText": "Private app content",
                "treeLines": ["AXWindow Private Title", "+ AXButton Private Button"],
                "screenshotNeededForContext": False,
                "screenshotAvailable": False,
            },
        },
        action_event(event_type, "official-secret-session"),
        {
            "type": "session.ended",
            "sessionId": "official-secret-session",
            "endReason": "recording_controls_stopped",
        },
    ]
    write_jsonl(events_path, events)
    write_jsonl(suppressed_path, [])
    metadata = {
        "sessionId": "official-secret-session",
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


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    default_required_scenario = DEFAULT_REQUIRED_SCENARIOS[0]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        paths = make_recording(root)
        status_json = root / "official-stop-response.json"
        write_json(
            status_json,
            {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "metadataPath": str(paths["metadata"]),
                                    "eventsPath": str(paths["events"]),
                                }
                            ),
                        }
                    ]
                }
            },
        )
        transcript = root / "official-transcript.json"
        shape = response_shape("official-secret-session", paths)
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
        inspect_output_dir = root / "inspect-only-fixtures"
        inspect_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(status_json),
                "--name",
                "official-simple-action-inspect",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(inspect_output_dir),
                "--mcp-transcript",
                str(transcript),
                "--require-mcp-transcript-evidence",
                "--inspect-only",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert inspect_completed.returncode == 0, inspect_completed.stderr
        inspect_payload = json.loads(inspect_completed.stdout)
        assert inspect_payload["ok"] is True
        assert inspect_payload["stage"] == "inspect"
        assert inspect_payload["wouldImport"] is False
        assert inspect_payload["recordingInput"] == str(paths["metadata"])
        assert inspect_payload["recordingInputInspection"]["metadataPath"]["exists"] is True
        assert inspect_payload["recordingInputInspection"]["sessionPath"]["exists"] is True
        assert inspect_payload["recordingInputInspection"]["eventsPath"]["exists"] is True
        assert inspect_payload["mcpTranscriptInspection"]["looksLikeMcpTranscript"] is True
        assert not inspect_output_dir.exists()

        inspect_missing_transcript = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(status_json),
                "--name",
                "official-simple-action-inspect-missing-transcript",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(root / "inspect-missing-transcript-fixtures"),
                "--require-mcp-transcript-evidence",
                "--inspect-only",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert inspect_missing_transcript.returncode == 1
        inspect_missing_transcript_payload = json.loads(inspect_missing_transcript.stderr)
        assert inspect_missing_transcript_payload["stage"] == "inspect"
        assert inspect_missing_transcript_payload["recordingInputInspection"]["exists"] is True
        assert inspect_missing_transcript_payload["mcpTranscriptInspection"][
            "looksLikeMcpTranscript"
        ] is False

        output_dir = root / "fixtures"
        completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(status_json),
                "--name",
                "official-simple-action",
                "--output-dir",
                str(output_dir),
                "--mcp-transcript",
                str(transcript),
                "--require-mcp-transcript-evidence",
                "--check-fixture-set",
                "--check-coverage",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert completed.returncode == 0, completed.stderr
        payload = json.loads(completed.stdout)
        assert payload["ok"] is True
        assert payload["scenario"] == default_required_scenario
        assert payload["readiness"]["ok"] is True
        assert payload["fixtureSetGate"]["ok"] is True
        assert payload["coverage"]["coverageOk"] is True
        assert payload["coverage"]["scenarioCoverageOk"] is True
        assert payload["coverage"]["hasRequiredOfficialSuccessfulFixture"] is True
        assert payload["coverage"]["requiredOfficialReadinessChecked"] is True
        assert payload["coverage"]["requiredOfficialReadinessOk"] is True
        assert payload["coverage"]["officialFixtureSetReadiness"]["ok"] is True
        assert payload["coverage"]["missingOfficialScenarios"] == []
        assert payload["extractedPaths"]["metadataPath"] == str(paths["metadata"])
        assert payload["extractedPaths"]["eventsPath"] == str(paths["events"])

        scenario_cases = [
            ("keyboard-input-stop", "keyboard.text_input", "official-keyboard-input"),
            ("drag-stop", "mouse.drag", "official-drag"),
        ]
        for scenario, event_type, name in scenario_cases:
            scenario_paths = make_recording(root / f"{name}-recording", event_type=event_type)
            scenario_status = root / f"{name}-response.json"
            write_json(
                scenario_status,
                {
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(
                                    {
                                        "metadataPath": str(scenario_paths["metadata"]),
                                        "eventsPath": str(scenario_paths["events"]),
                                    }
                                ),
                            }
                        ]
                    }
                },
            )
            scenario_transcript = root / f"{name}-transcript.json"
            scenario_shape = response_shape("official-secret-session", scenario_paths)
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
            scenario_output_dir = root / f"{name}-fixtures"
            scenario_result = subprocess.run(
                [
                    sys.executable,
                    str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                    "--status-json",
                    str(scenario_status),
                    "--name",
                    name,
                    "--scenario",
                    scenario,
                    "--output-dir",
                    str(scenario_output_dir),
                    "--mcp-transcript",
                    str(scenario_transcript),
                    "--require-mcp-transcript-evidence",
                ],
                cwd=repo,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert scenario_result.returncode == 0, scenario_result.stderr
            scenario_payload = json.loads(scenario_result.stdout)
            assert scenario_payload["ok"] is True
            assert scenario_payload["scenario"] == scenario
            assert scenario_payload["readiness"]["ok"] is True
            event_counts = scenario_payload["readiness"]["recordings"][0]["eventTypes"]
            assert event_counts[event_type] == 1
            response_shapes = scenario_payload["readiness"]["recordings"][0]["mcpResponseShapes"]
            assert response_shapes["startResponseShape"]["hasResult"] is True
            assert response_shapes["statusResponseShape"]["hasResult"] is True
            assert response_shapes["stopResponseShape"]["hasResult"] is True
            assert response_shapes["finalStatusResponseShape"]["hasResult"] is True

        stdin_status_json = {
            **response_shape("official-secret-session", paths),
            "startResponseShape": shape,
            "repeatStartResponseShape": shape,
            "statusResponseShape": shape,
            "stopResponseShape": shape,
            "repeatStopResponseShape": shape,
            "finalStatusResponseShape": shape,
        }
        inspect_stdin_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                "-",
                "--name",
                "official-simple-action-inspect-stdin",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(root / "inspect-stdin-fixtures"),
                "--use-status-json-as-transcript",
                "--require-mcp-transcript-evidence",
                "--inspect-only",
            ],
            cwd=repo,
            input=json.dumps(stdin_status_json),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert inspect_stdin_completed.returncode == 0, inspect_stdin_completed.stderr
        inspect_stdin_payload = json.loads(inspect_stdin_completed.stdout)
        assert inspect_stdin_payload["ok"] is True
        assert inspect_stdin_payload["usedMcpTranscript"] == "<stdin>"
        assert inspect_stdin_payload["mcpTranscriptInspection"]["looksLikeMcpTranscript"] is True
        assert inspect_stdin_payload["mcpTranscriptInspection"][
            "statusJsonLooksLikeMcpTranscript"
        ] is True

        stdin_output_dir = root / "stdin-fixtures"
        stdin_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                "-",
                "--name",
                "official-simple-action-stdin",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(stdin_output_dir),
                "--use-status-json-as-transcript",
                "--require-mcp-transcript-evidence",
                "--check-fixture-set",
            ],
            cwd=repo,
            input=json.dumps(stdin_status_json),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert stdin_completed.returncode == 0, stdin_completed.stderr
        stdin_payload = json.loads(stdin_completed.stdout)
        assert stdin_payload["ok"] is True
        assert stdin_payload["usedMcpTranscript"] == "<stdin>"
        assert stdin_payload["readiness"]["ok"] is True
        assert stdin_payload["fixtureSetGate"]["ok"] is True
        assert stdin_payload["extractedPaths"]["metadataPath"] == str(paths["metadata"])
        assert stdin_payload["extractedPaths"]["sessionPath"] == str(paths["session"])

        relative_status_json = {
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(
                            {
                                "metadataPath": "official-recording/metadata.json",
                                "eventsPath": "official-recording/events.jsonl",
                            }
                        ),
                    }
                ]
            }
        }
        relative_output_dir = root / "relative-fixtures"
        relative_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                "-",
                "--status-json-base-dir",
                str(root),
                "--name",
                "official-simple-action-relative",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(relative_output_dir),
            ],
            cwd=repo,
            input=json.dumps(relative_status_json),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert relative_completed.returncode == 0, relative_completed.stderr
        relative_payload = json.loads(relative_completed.stdout)
        assert relative_payload["ok"] is True
        assert relative_payload["statusJsonBaseDir"] == str(root)
        assert relative_payload["recordingInput"] == str(paths["metadata"])
        assert relative_payload["extractedPaths"]["metadataPath"] == "official-recording/metadata.json"

        minimal_recording = root / "official-minimal-recording"
        minimal_recording.mkdir()
        minimal_events = minimal_recording / "events.jsonl"
        minimal_session = minimal_recording / "session.json"
        minimal_session_id = "official-minimal-secret-session"
        write_jsonl(
            minimal_events,
            [
                {"kind": "session.started", "sessionId": minimal_session_id},
                {
                    "kind": "AX.focusedWindowChanged",
                    "sessionId": minimal_session_id,
                    "accessibilityInspectorPayload": {
                        "kind": "full",
                        "diffFromPrevious": False,
                        "fullTree": ["AXWindow Private Minimal Title"],
                    },
                },
                {
                    "kind": "mouse.click",
                    "sessionId": minimal_session_id,
                    "button": "left",
                    "location": {"x": 12, "y": 34},
                    "targetAccessibilityElement": {
                        "role": "AXButton",
                        "title": "Private Minimal Button",
                    },
                },
                {
                    "kind": "session.ended",
                    "sessionId": minimal_session_id,
                    "endReason": "recording_controls_stopped",
                },
            ],
        )
        write_json(
            minimal_session,
            {
                "id": minimal_session_id,
                "startedAt": "2026-06-29T00:00:00Z",
                "endedAt": "2026-06-29T00:00:03Z",
                "endReason": "recording_controls_stopped",
                "eventsPath": str(minimal_events),
            },
        )
        minimal_status = root / "official-minimal-session-dir-response.json"
        write_json(
            minimal_status,
            {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "sessionDirectoryPath": str(minimal_recording),
                                }
                            ),
                        }
                    ]
                }
            },
        )
        minimal_output_dir = root / "minimal-session-dir-fixtures"
        minimal_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(minimal_status),
                "--name",
                "official-minimal-session-dir",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(minimal_output_dir),
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert minimal_completed.returncode == 0, minimal_completed.stderr
        minimal_payload = json.loads(minimal_completed.stdout)
        assert minimal_payload["ok"] is True
        assert minimal_payload["recordingInput"] == str(minimal_recording)
        assert minimal_payload["extractedPaths"]["sessionDirectoryPath"] == str(minimal_recording)
        assert minimal_payload["readiness"]["ok"] is True
        minimal_fixture = pathlib.Path(minimal_payload["fixtureDir"])
        minimal_metadata = json.loads((minimal_fixture / "metadata.json").read_text())
        assert minimal_metadata["sessionId"] == "fixture-session"
        assert minimal_metadata["metadataPath"] == "metadata.json"
        assert minimal_metadata["sessionPath"] == "session.json"
        assert minimal_metadata["suppressedEventsPath"] == "suppressed.jsonl"

        transcript_stdin_output_dir = root / "transcript-stdin-fixtures"
        transcript_stdin_completed = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(status_json),
                "--name",
                "official-simple-action-transcript-stdin",
                "--scenario",
                "simple-action-stop",
                "--output-dir",
                str(transcript_stdin_output_dir),
                "--mcp-transcript",
                "-",
                "--require-mcp-transcript-evidence",
                "--check-fixture-set",
            ],
            cwd=repo,
            input=transcript.read_text(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert transcript_stdin_completed.returncode == 0, transcript_stdin_completed.stderr
        transcript_stdin_payload = json.loads(transcript_stdin_completed.stdout)
        assert transcript_stdin_payload["ok"] is True
        assert transcript_stdin_payload["usedMcpTranscript"] == "<stdin>"
        assert transcript_stdin_payload["readiness"]["ok"] is True
        assert transcript_stdin_payload["fixtureSetGate"]["ok"] is True

        cancel_recording_root = root / "cancel-recording"
        cancel_recording_root.mkdir()
        cancel_paths = make_recording(cancel_recording_root)
        cancel_metadata = json.loads(cancel_paths["metadata"].read_text())
        cancel_metadata["endReason"] = "recording_controls_cancelled"
        cancel_events = [
            {"type": "session.started", "sessionId": "official-cancel-session"},
            {
                "type": "session.ended",
                "sessionId": "official-cancel-session",
                "endReason": "recording_controls_cancelled",
            },
        ]
        cancel_metadata["eventCount"] = len(cancel_events)
        write_json(cancel_paths["metadata"], cancel_metadata)
        write_json(cancel_paths["session"], cancel_metadata)
        write_jsonl(cancel_paths["events"], cancel_events)
        cancel_status = root / "official-cancel-response.json"
        write_json(
            cancel_status,
            {
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "metadataPath": str(cancel_paths["metadata"]),
                                    "eventsPath": str(cancel_paths["events"]),
                                }
                            ),
                        }
                    ]
                }
            },
        )
        cancel_coverage_output_dir = root / "cancel-coverage-fixtures"
        cancel_coverage = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(cancel_status),
                "--name",
                "official-cancel-only",
                "--scenario",
                "cancel",
                "--output-dir",
                str(cancel_coverage_output_dir),
                "--require-coverage",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert cancel_coverage.returncode == 1
        cancel_coverage_payload = json.loads(cancel_coverage.stderr)
        assert cancel_coverage_payload["ok"] is False
        assert cancel_coverage_payload["readiness"]["ok"] is True
        assert cancel_coverage_payload["coverage"]["coverageOk"] is False
        assert cancel_coverage_payload["coverage"]["scenarioCoverageOk"] is False
        assert cancel_coverage_payload["coverage"]["requiredOfficialReadinessChecked"] is True
        assert cancel_coverage_payload["coverage"]["requiredOfficialReadinessOk"] is False
        assert cancel_coverage_payload["coverage"]["missingOfficialScenarios"] == [
            default_required_scenario
        ]

        both_stdin = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                "-",
                "--mcp-transcript",
                "-",
                "--name",
                "both-stdin",
                "--output-dir",
                str(root / "both-stdin-fixtures"),
            ],
            cwd=repo,
            input=json.dumps(stdin_status_json),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert both_stdin.returncode == 1
        both_stdin_json = json.loads(both_stdin.stderr)
        assert "cannot read both --status-json and --mcp-transcript from stdin" in both_stdin_json["errors"][0]

        fixture = output_dir / "official-simple-action"
        combined = "\n".join(path.read_text() for path in fixture.glob("*") if path.is_file())
        for secret in [
            "official-secret-session",
            "Private app content",
            "Private Title",
            "Private Button",
            "private-value",
            str(root),
        ]:
            assert secret not in combined, secret

        missing = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(root / "missing-paths.json"),
                "--name",
                "missing",
                "--output-dir",
                str(output_dir),
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing.returncode == 1

        no_paths = root / "no-paths.json"
        write_json(no_paths, {"result": {"content": [{"type": "text", "text": "{}"}]}})
        no_paths_result = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/ingest-official-record-and-replay-fixture.py"),
                "--status-json",
                str(no_paths),
                "--name",
                "no-paths",
                "--output-dir",
                str(output_dir),
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert no_paths_result.returncode == 1
        no_paths_json = json.loads(no_paths_result.stderr)
        assert "could not find metadataPath" in no_paths_json["errors"][0]
        assert "sessionDirectoryPath" in no_paths_json["errors"][0]

    print(
        json.dumps(
            {
                "ok": True,
                "checkedOfficialFixtureIngest": True,
                "checkedOfficialFixtureInspectOnly": True,
                "checkedOfficialSessionDirectoryPathHandoff": True,
                "checkedPostIngestCoverageReport": True,
                "checkedPostIngestCoverageReadiness": True,
                "checkedPostIngestRequireCoverageFailure": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
