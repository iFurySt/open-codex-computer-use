#!/usr/bin/env python3

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from record_and_replay_scenarios import scenario_recipe


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n")


def fixture_manifest(name, source, scenario, event_count):
    return {
        "fixtureFormatVersion": 1,
        "name": name,
        "scenario": scenario,
        "scenarioRecipe": scenario_recipe(scenario),
        "source": source,
        "officialPluginVersion": "record-and-replay 1.0.857" if source == "official" else None,
        "capturedAt": "2026-06-27",
        "importedAt": "2026-06-27",
        "eventCount": event_count,
        "suppressedEventCount": 0,
        "eventTypes": {},
        "files": {
            "metadata": "metadata.json",
            "session": "session.json",
            "events": "events.jsonl",
            "suppressed": "suppressed.jsonl",
            "mcpTranscript": "mcp-transcript.json",
        },
        "redaction": {
            "screenshotsCopied": False,
            "mcpTranscriptSanitized": True,
            "preserveAppAttribution": False,
            "textKeys": ["title"],
            "timestampKeys": ["timestamp"],
            "sessionIdKeys": ["sessionId"],
            "pathKeysRewrittenRelative": ["eventsPath"],
            "pathKeysRedacted": ["path", "*Path"],
        },
    }


def mcp_transcript():
    return {
        "startResponseShape": {"result": {"content": []}},
        "repeatStartResponseShape": {"result": {"content": []}},
        "statusResponseShape": {"result": {"content": []}},
        "stopResponseShape": {"result": {"content": []}},
        "repeatStopResponseShape": {"result": {"content": []}},
        "finalStatusResponseShape": {"result": {"content": []}},
    }


def action_event_for_scenario(session_id, scenario):
    if scenario == "keyboard-input-stop":
        return {
            "type": "keyboard.text_input",
            "sessionId": session_id,
            "textLength": 4,
            "focusedAccessibilityElement": {
                "role": "AXTextField",
                "title": "<redacted-title:length=5>",
                "actions": ["AXConfirm"],
            },
        }
    if scenario == "drag-stop":
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
                "title": "<redacted-title:length=6>",
                "actions": ["AXPress"],
            },
        }
    return {
        "type": "mouse.click",
        "sessionId": session_id,
        "button": "left",
        "location": {"x": 10, "y": 20},
        "targetAccessibilityElement": {
            "role": "AXButton",
            "title": "<redacted-title:length=4>",
            "actions": ["AXPress"],
        },
    }


def action_events(session_id, scenario="simple-action-stop", end_reason="recording_controls_stopped"):
    if scenario == "timeout":
        return [
            {"type": "session.started", "sessionId": session_id},
            {"type": "session.ended", "sessionId": session_id, "endReason": end_reason},
        ]
    return [
        {"type": "session.started", "sessionId": session_id},
        {
            "type": "AX.focusedWindowChanged",
            "sessionId": session_id,
            "accessibilityInspectorPayload": {
                "kind": "full",
                "diffFromPrevious": False,
                "renderedText": "<redacted-renderedText:length=10>",
                "treeLines": ["<redacted-treeLines:length=10>"],
                "screenshotNeededForContext": False,
                "screenshotAvailable": False,
            },
        },
        action_event_for_scenario(session_id, scenario),
        {"type": "session.ended", "sessionId": session_id, "endReason": end_reason},
    ]


def make_fixture(root, name, source="official", scenario="simple-action-stop", end_reason="recording_controls_stopped"):
    fixture = root / name
    fixture.mkdir(parents=True)
    events = action_events(name, scenario, end_reason)
    write_jsonl(fixture / "events.jsonl", events)
    write_jsonl(fixture / "suppressed.jsonl", [])
    metadata = {
        "sessionId": name,
        "state": "stopped",
        "active": False,
        "endReason": end_reason,
        "eventCount": len(events),
        "suppressedEventCount": 0,
        "eventsPath": "events.jsonl",
        "metadataPath": "metadata.json",
        "sessionPath": "session.json",
        "suppressedEventsPath": "suppressed.jsonl",
    }
    write_json(fixture / "metadata.json", metadata)
    write_json(fixture / "session.json", metadata)
    write_json(fixture / "mcp-transcript.json", mcp_transcript())
    write_json(fixture / "fixture-manifest.json", fixture_manifest(name, source, scenario, len(events)))
    return fixture


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
    script = repo / "scripts/check-event-stream-official-fixture-set.py"
    import_script = repo / "scripts/import-event-stream-fixture.py"

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        official_root = root / "official"
        candidate_root = root / "candidate"
        official = make_fixture(official_root, "official-action")
        candidate = make_fixture(candidate_root, "candidate-action", source="ocu")

        success = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(candidate_root),
            ],
            repo,
        )
        assert success.returncode == 0, success.stderr
        success_json = json.loads(success.stdout)
        assert success_json["ok"] is True
        assert success_json["requiredScenarios"] == ["simple-action-stop"]
        assert success_json["availableOfficialScenarios"] == ["simple-action-stop"]
        assert success_json["availableCandidateScenarios"] == ["simple-action-stop"]
        assert success_json["comparePolicy"] == {
            "requiresAxDiffEvidence": True,
            "requiresSameAxDiffMarkers": True,
            "requiresSuppressedEventSequence": True,
            "requiresSuppressedSchema": True,
        }
        assert success_json["scenarioResults"][0]["officialReadiness"]["ok"] is True
        assert success_json["scenarioResults"][0]["candidateCompare"]["ok"] is True

        missing_candidate = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(root / "empty-candidate"),
            ],
            repo,
        )
        assert missing_candidate.returncode == 1
        missing_candidate_json = json.loads(missing_candidate.stderr)
        assert "missing OCU candidate fixture scenario: simple-action-stop" in missing_candidate_json["errors"]

        ax_diff_official_root = root / "ax-diff-official"
        ax_diff_candidate_root = root / "ax-diff-candidate"
        ax_diff_official = make_fixture(ax_diff_official_root, "official-action")
        make_fixture(ax_diff_candidate_root, "candidate-action", source="ocu")
        ax_diff_events_path = ax_diff_official / "events.jsonl"
        ax_diff_events = [
            json.loads(line)
            for line in ax_diff_events_path.read_text().splitlines()
            if line.strip()
        ]
        for event in ax_diff_events:
            if event.get("type") == "AX.focusedWindowChanged":
                event["accessibilityInspectorPayload"] = {
                    "kind": "diff",
                    "diffFromPrevious": True,
                    "renderedText": "~ 1 button Old -> 1 button New\n+ 2 button Done",
                    "treeLines": [
                        "~ 1 button Old -> 1 button New",
                        "+ 2 button Done",
                    ],
                    "cumulativeDiffFromInitial": True,
                    "cumulativeRenderedText": "+ 2 button Done",
                    "cumulativeTreeLines": [
                        "+ 2 button Done",
                    ],
                    "screenshotNeededForContext": False,
                    "screenshotAvailable": False,
                }
        write_jsonl(ax_diff_events_path, ax_diff_events)
        ax_diff_mismatch = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(ax_diff_official_root),
                "--candidate-root",
                str(ax_diff_candidate_root),
            ],
            repo,
        )
        assert ax_diff_mismatch.returncode == 1
        ax_diff_mismatch_json = json.loads(ax_diff_mismatch.stderr)
        assert "OCU candidate scenario failed official comparison: simple-action-stop" in (
            ax_diff_mismatch_json["errors"]
        )
        candidate_compare_errors = (
            ax_diff_mismatch_json["scenarioResults"][0]["candidateCompare"]["errors"]
        )
        assert "candidate missing AX diff payload" in candidate_compare_errors
        assert "candidate missing cumulative AX diff payload" in candidate_compare_errors

        bad_candidate_root = root / "bad-candidate"
        make_fixture(bad_candidate_root, "candidate-action", source="ocu")
        bad_candidate_metadata_path = bad_candidate_root / "candidate-action" / "metadata.json"
        bad_candidate_metadata = json.loads(bad_candidate_metadata_path.read_text())
        bad_candidate_metadata["state"] = "recording"
        bad_candidate_metadata["active"] = True
        write_json(bad_candidate_metadata_path, bad_candidate_metadata)
        bad_candidate = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(bad_candidate_root),
            ],
            repo,
        )
        assert bad_candidate.returncode == 1
        bad_candidate_json = json.loads(bad_candidate.stderr)
        assert "OCU candidate scenario failed readiness: simple-action-stop" in bad_candidate_json["errors"]
        candidate_readiness_errors = (
            bad_candidate_json["scenarioResults"][0]["candidateReadiness"]["recordings"][0]["errors"]
        )
        assert "metadata state is not final: recording" in candidate_readiness_errors

        bad_end_reason_root = root / "bad-end-reason"
        make_fixture(bad_end_reason_root, "official-action", end_reason="recording_controls_cancelled")
        bad_end_reason = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(bad_end_reason_root),
            ],
            repo,
        )
        assert bad_end_reason.returncode == 1
        bad_end_reason_json = json.loads(bad_end_reason.stderr)
        assert "official fixture scenario failed readiness: simple-action-stop" in bad_end_reason_json["errors"]
        readiness_errors = bad_end_reason_json["scenarioResults"][0]["officialReadiness"]["recordings"][0]["errors"]
        assert "missing required endReason: recording_controls_stopped" in readiness_errors

        cancel_root = root / "cancel-official"
        make_fixture(
            cancel_root,
            "official-cancel",
            scenario="cancel",
            end_reason="recording_controls_cancelled",
        )
        cancel_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(cancel_root),
                "--require-scenario",
                "cancel",
            ],
            repo,
        )
        assert cancel_result.returncode == 0, cancel_result.stderr
        cancel_json = json.loads(cancel_result.stdout)
        assert cancel_json["scenarioResults"][0]["officialReadiness"]["ok"] is True

        keyboard_root = root / "keyboard-official"
        make_fixture(keyboard_root, "official-keyboard", scenario="keyboard-input-stop")
        keyboard_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(keyboard_root),
                "--require-scenario",
                "keyboard-input-stop",
            ],
            repo,
        )
        assert keyboard_result.returncode == 0, keyboard_result.stderr
        keyboard_json = json.loads(keyboard_result.stdout)
        assert keyboard_json["scenarioResults"][0]["officialReadiness"]["ok"] is True

        drag_root = root / "drag-official"
        make_fixture(drag_root, "official-drag", scenario="drag-stop")
        drag_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(drag_root),
                "--require-scenario",
                "drag-stop",
            ],
            repo,
        )
        assert drag_result.returncode == 0, drag_result.stderr
        drag_json = json.loads(drag_result.stdout)
        assert drag_json["scenarioResults"][0]["officialReadiness"]["ok"] is True

        timeout_root = root / "timeout-official"
        make_fixture(
            timeout_root,
            "official-timeout",
            scenario="timeout",
            end_reason="recording_time_limit_reached",
        )
        timeout_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(timeout_root),
                "--require-scenario",
                "timeout",
            ],
            repo,
        )
        assert timeout_result.returncode == 0, timeout_result.stderr
        timeout_json = json.loads(timeout_result.stdout)
        timeout_readiness = timeout_json["scenarioResults"][0]["officialReadiness"]
        assert timeout_readiness["ok"] is True
        timeout_recording = timeout_readiness["recordings"][0]
        assert timeout_recording["actionEventCount"] == 0
        assert timeout_recording["hasAccessibilityPayload"] is False
        assert timeout_recording["endReasons"] == {"recording_time_limit_reached": 2}

        keyboard_missing_event_root = root / "keyboard-missing-event"
        make_fixture(keyboard_missing_event_root, "official-keyboard", scenario="keyboard-input-stop")
        keyboard_events_path = keyboard_missing_event_root / "official-keyboard" / "events.jsonl"
        keyboard_events = [
            json.loads(line)
            for line in keyboard_events_path.read_text().splitlines()
            if line.strip()
        ]
        keyboard_events = [
            {**event, "type": "mouse.click"}
            if event.get("type") == "keyboard.text_input"
            else event
            for event in keyboard_events
        ]
        write_jsonl(keyboard_events_path, keyboard_events)
        keyboard_missing_event = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(keyboard_missing_event_root),
                "--require-scenario",
                "keyboard-input-stop",
            ],
            repo,
        )
        assert keyboard_missing_event.returncode == 1
        keyboard_missing_event_json = json.loads(keyboard_missing_event.stderr)
        assert "official fixture scenario failed readiness: keyboard-input-stop" in keyboard_missing_event_json["errors"]
        keyboard_readiness_errors = (
            keyboard_missing_event_json["scenarioResults"][0]["officialReadiness"]["recordings"][0]["errors"]
        )
        assert "missing required event type: keyboard.text_input" in keyboard_readiness_errors

        no_scenario_root = root / "no-scenario"
        no_scenario = make_fixture(no_scenario_root, "official-action")
        manifest = json.loads((no_scenario / "fixture-manifest.json").read_text())
        del manifest["scenario"]
        write_json(no_scenario / "fixture-manifest.json", manifest)
        no_scenario_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(no_scenario_root),
            ],
            repo,
        )
        assert no_scenario_result.returncode == 1
        no_scenario_json = json.loads(no_scenario_result.stderr)
        assert any("fixture-manifest.json missing scenario" in error for error in no_scenario_json["errors"])

        recipe_drift_root = root / "recipe-drift"
        recipe_drift = make_fixture(recipe_drift_root, "official-action")
        recipe_manifest_path = recipe_drift / "fixture-manifest.json"
        recipe_manifest = json.loads(recipe_manifest_path.read_text())
        recipe_manifest["scenarioRecipe"]["expectedActionEvents"] = ["keyboard.text_input"]
        write_json(recipe_manifest_path, recipe_manifest)
        recipe_drift_result = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(recipe_drift_root),
            ],
            repo,
        )
        assert recipe_drift_result.returncode == 1
        recipe_drift_json = json.loads(recipe_drift_result.stderr)
        assert any("scenarioRecipe does not match scenario" in error for error in recipe_drift_json["errors"])

        imported_root = root / "imported"
        import_result = run(
            [
                sys.executable,
                str(import_script),
                str(official),
                "--name",
                "imported-action",
                "--output-dir",
                str(imported_root),
                "--scenario",
                "simple-action-stop",
                "--mcp-transcript",
                str(official / "mcp-transcript.json"),
            ],
            repo,
        )
        assert import_result.returncode == 0, import_result.stderr
        imported_manifest = json.loads((imported_root / "imported-action" / "fixture-manifest.json").read_text())
        assert imported_manifest["scenario"] == "simple-action-stop"

        shutil.rmtree(candidate)
        make_fixture(candidate_root, "candidate-action", source="ocu", scenario="different-scenario")
        mismatched_candidate = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(candidate_root),
            ],
            repo,
        )
        assert mismatched_candidate.returncode == 1
        mismatched_candidate_json = json.loads(mismatched_candidate.stderr)
        assert "missing OCU candidate fixture scenario: simple-action-stop" in mismatched_candidate_json["errors"]

    print(
        json.dumps(
            {
                "ok": True,
                "checkedFixtureSetGate": True,
                "checkedRequiredSimpleActionStopScenario": True,
                "checkedCandidatePairing": True,
                "checkedCandidateReadinessFailure": True,
                "checkedMissingCandidateFailure": True,
                "checkedAxDiffComparisonPolicy": True,
                "checkedSuppressedStreamComparisonPolicy": True,
                "checkedAxDiffComparisonFailure": True,
                "checkedStopEndReasonPolicy": True,
                "checkedCancelScenarioPolicy": True,
                "checkedKeyboardInputScenarioPolicy": True,
                "checkedDragScenarioPolicy": True,
                "checkedTimeoutScenarioPolicy": True,
                "checkedMissingScenarioFailure": True,
                "checkedScenarioRecipeDriftFailure": True,
                "checkedImportScenarioManifest": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
