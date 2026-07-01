#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile

from record_and_replay_scenarios import DEFAULT_REQUIRED_SCENARIOS, scenario_recipe


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n")


def make_recording(root: pathlib.Path, session_id: str, source_label: str) -> pathlib.Path:
    recording = root / session_id
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
                "treeLines": [f"AXWindow {source_label}", "+ AXButton Pair"],
            },
        },
        {
            "type": "mouse.click",
            "sessionId": session_id,
            "button": "left",
            "location": {"x": 10, "y": 20},
            "targetAccessibilityElement": {"role": "AXButton", "title": "Pair"},
        },
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
    shape = {
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(metadata),
                }
            ]
        }
    }
    write_json(
        recording / "mcp-transcript.json",
        {
            "startResponseShape": shape,
            "repeatStartResponseShape": shape,
            "statusResponseShape": shape,
            "stopResponseShape": shape,
            "repeatStopResponseShape": shape,
            "finalStatusResponseShape": shape,
        },
    )
    return recording


def run(command, cwd):
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def import_fixture(repo: pathlib.Path, recording: pathlib.Path, output: pathlib.Path, source: str):
    completed = run(
        [
            sys.executable,
            str(repo / "scripts/import-event-stream-fixture.py"),
            str(recording),
            "--name",
            f"{source}-simple-action",
            "--output-dir",
            str(output),
            "--source",
            source,
            "--scenario",
            "simple-action-stop",
            "--official-plugin-version",
            "record-and-replay 1.0.857",
            "--mcp-transcript",
            str(recording / "mcp-transcript.json"),
        ],
        repo,
    )
    assert completed.returncode == 0, completed.stderr


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    script = repo / "scripts/prepare-record-and-replay-ocu-candidate-pairing.py"
    default_required_scenario = DEFAULT_REQUIRED_SCENARIOS[0]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        official_root = root / "official"
        candidate_root = root / "candidates"

        missing = run(
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
        assert missing.returncode == 0, missing.stderr
        missing_json = json.loads(missing.stdout)
        assert missing_json["scenarioStatus"]["officialFixtureReady"] is False
        assert missing_json["scenarioRecipe"]["scenario"] == default_required_scenario
        assert missing_json["scenarioRecipe"]["expectedActionEvents"] == ["mouse.click"]
        assert missing_json["scenarioRecipe"]["ocuCandidateSourceKind"] == "run-action-smoke"
        assert "Import a ready official fixture" in missing_json["nextActions"][0]
        assert missing_json["commands"]["sourceKind"] == "run-action-smoke"
        assert "--run-action-smoke" in missing_json["commands"]["ingestCandidate"]

        official_recording = make_recording(root / "recordings", "official-session", "Official")
        import_fixture(repo, official_recording, official_root, "official")
        no_candidate = run(
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
        assert no_candidate.returncode == 0, no_candidate.stderr
        no_candidate_json = json.loads(no_candidate.stdout)
        assert no_candidate_json["scenarioStatus"]["officialFixtureReady"] is True
        assert no_candidate_json["scenarioStatus"]["candidateFixturePresent"] is False
        assert "commands.ingestCandidate" in no_candidate_json["nextActions"][0]

        candidate_recording = make_recording(root / "recordings", "candidate-session", "Official")
        import_fixture(repo, candidate_recording, candidate_root, "ocu")
        paired = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(candidate_root),
                "--require-candidate-ready",
            ],
            repo,
        )
        assert paired.returncode == 0, paired.stderr
        paired_json = json.loads(paired.stdout)
        assert paired_json["scenarioStatus"]["candidateFixtureReady"] is True
        assert paired_json["scenarioStatus"]["candidateComparePassed"] is True

        keyboard = run(
            [
                sys.executable,
                str(script),
                "--scenario",
                "keyboard-input-stop",
                "--official-root",
                str(official_root),
                "--candidate-root",
                str(candidate_root),
            ],
            repo,
        )
        assert keyboard.returncode == 0, keyboard.stderr
        keyboard_json = json.loads(keyboard.stdout)
        assert keyboard_json["commands"]["sourceKind"] == "recording-required"
        assert keyboard_json["scenarioRecipe"]["expectedActionEvents"] == ["keyboard.text_input"]
        assert keyboard_json["scenarioRecipe"]["ocuCandidateSourceKind"] == "recording-required"
        assert "cannot use synthetic --run-action-smoke" in keyboard_json["nextActions"][-1]

        recipe_drift_root = root / "recipe-drift-official"
        recipe_drift_fixture = recipe_drift_root / "official-action"
        recipe_drift_fixture.mkdir(parents=True)
        recipe = scenario_recipe("simple-action-stop")
        recipe["expectedActionEvents"] = ["keyboard.text_input"]
        write_json(
            recipe_drift_fixture / "fixture-manifest.json",
            {
                "fixtureFormatVersion": 1,
                "name": "official-action",
                "source": "official",
                "scenario": "simple-action-stop",
                "scenarioRecipe": recipe,
                "officialPluginVersion": "record-and-replay 1.0.857",
                "eventCount": 4,
            },
        )
        coverage_error = run(
            [
                sys.executable,
                str(script),
                "--official-root",
                str(recipe_drift_root),
                "--candidate-root",
                str(candidate_root),
            ],
            repo,
        )
        assert coverage_error.returncode == 0, coverage_error.stderr
        coverage_error_json = json.loads(coverage_error.stdout)
        assert coverage_error_json["ok"] is False
        assert coverage_error_json["officialCoverageErrors"]
        assert any(
            "scenarioRecipe does not match scenario" in error
            for error in coverage_error_json["officialCoverageErrors"]
        )
        assert "Fix official fixture coverage errors" in coverage_error_json["nextActions"][0]

    print(
        json.dumps(
            {
                "ok": True,
                "checkedMissingOfficialPreflight": True,
                "checkedNoCandidatePreflight": True,
                "checkedPairedCandidatePreflight": True,
                "checkedKeyboardRecordingRequiredScenario": True,
                "checkedCoverageErrorReport": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
