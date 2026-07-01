#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile

from record_and_replay_scenarios import scenario_recipe


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def make_fixture(root, name, source="official", scenario="simple-action-stop"):
    fixture = root / name
    fixture.mkdir(parents=True)
    write_json(
        fixture / "fixture-manifest.json",
        {
            "fixtureFormatVersion": 1,
            "name": name,
            "source": source,
            "scenario": scenario,
            "scenarioRecipe": scenario_recipe(scenario),
            "officialPluginVersion": "record-and-replay 1.0.857" if source == "official" else None,
            "eventCount": 4,
        },
    )
    return fixture


def write_jsonl(path, records):
    path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n")


def response_shape(paths):
    return {
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        {
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


def make_ready_fixture(root, name, scenario="simple-action-stop"):
    fixture = make_fixture(root, name, source="official", scenario=scenario)
    metadata_path = fixture / "metadata.json"
    session_path = fixture / "session.json"
    events_path = fixture / "events.jsonl"
    suppressed_path = fixture / "suppressed.jsonl"
    events = [
        {"type": "session.started", "sessionId": "ready-session"},
        {
            "type": "AX.focusedWindowChanged",
            "sessionId": "ready-session",
            "accessibilityInspectorPayload": {
                "kind": "full",
                "diffFromPrevious": False,
                "treeLines": ["AXWindow Ready"],
            },
        },
        {
            "type": "mouse.click",
            "sessionId": "ready-session",
            "button": "left",
            "location": {"x": 10, "y": 20},
            "targetAccessibilityElement": {"role": "AXButton", "title": "Ready"},
        },
        {
            "type": "session.ended",
            "sessionId": "ready-session",
            "endReason": "recording_controls_stopped",
        },
    ]
    write_jsonl(events_path, events)
    write_jsonl(suppressed_path, [])
    metadata = {
        "sessionId": "ready-session",
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
    shape = response_shape(
        {
            "metadata": metadata_path,
            "session": session_path,
            "events": events_path,
            "suppressed": suppressed_path,
        }
    )
    write_json(
        fixture / "mcp-transcript.json",
        {
            "startResponseShape": shape,
            "repeatStartResponseShape": shape,
            "statusResponseShape": shape,
            "stopResponseShape": shape,
            "repeatStopResponseShape": shape,
            "finalStatusResponseShape": shape,
        },
    )
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
    script = repo / "scripts/check-event-stream-official-fixture-coverage.py"
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        fixture_root = root / "fixtures"

        missing = run([sys.executable, str(script), "--fixture-root", str(fixture_root)], repo)
        assert missing.returncode == 1
        missing_json = json.loads(missing.stderr)
        assert missing_json["coverageOk"] is False
        assert missing_json["hasRequiredOfficialSuccessfulFixture"] is False
        assert missing_json["missingOfficialScenarios"] == ["simple-action-stop"]
        assert missing_json["recommendedOfficialScenarios"] == [
            "simple-action-stop",
            "keyboard-input-stop",
            "drag-stop",
            "cancel",
            "timeout",
        ]
        assert missing_json["missingRecommendedOfficialScenarios"] == [
            "cancel",
            "drag-stop",
            "keyboard-input-stop",
            "simple-action-stop",
            "timeout",
        ]
        assert missing_json["hasRecommendedOfficialScenarioCoverage"] is False

        allow_missing = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--allow-missing",
            ],
            repo,
        )
        assert allow_missing.returncode == 0
        allow_json = json.loads(allow_missing.stdout)
        assert allow_json["ok"] is True
        assert allow_json["coverageOk"] is False
        assert allow_json["scenarioCoverageOk"] is False

        allow_missing_readiness = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--allow-missing",
                "--check-readiness",
            ],
            repo,
        )
        assert allow_missing_readiness.returncode == 0
        allow_missing_readiness_json = json.loads(allow_missing_readiness.stdout)
        assert allow_missing_readiness_json["ok"] is True
        assert allow_missing_readiness_json["coverageOk"] is False
        assert allow_missing_readiness_json["requiredOfficialReadinessChecked"] is True
        assert allow_missing_readiness_json["requiredOfficialReadinessOk"] is False
        assert allow_missing_readiness_json["notReadyOfficialScenarios"] == []

        make_fixture(fixture_root, "candidate-action", source="ocu")
        ignored_candidate = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--allow-missing",
            ],
            repo,
        )
        assert ignored_candidate.returncode == 0
        ignored_json = json.loads(ignored_candidate.stdout)
        assert ignored_json["availableOfficialScenarios"] == []

        make_fixture(fixture_root, "official-action")
        covered = run([sys.executable, str(script), "--fixture-root", str(fixture_root)], repo)
        assert covered.returncode == 0, covered.stderr
        covered_json = json.loads(covered.stdout)
        assert covered_json["ok"] is True
        assert covered_json["coverageOk"] is True
        assert covered_json["scenarioCoverageOk"] is True
        assert covered_json["hasRequiredOfficialSuccessfulFixture"] is True
        assert covered_json["requiredOfficialReadinessChecked"] is False
        assert covered_json["requiredOfficialReadinessOk"] is None
        assert covered_json["hasRecommendedOfficialScenarioCoverage"] is False
        assert covered_json["availableOfficialScenarios"] == ["simple-action-stop"]
        assert covered_json["missingOfficialScenarios"] == []
        assert covered_json["missingRecommendedOfficialScenarios"] == [
            "cancel",
            "drag-stop",
            "keyboard-input-stop",
            "timeout",
        ]
        assert covered_json["officialFixtures"][0]["path"].startswith("/tmp/") is False

        custom_recommended = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--recommended-scenario",
                "simple-action-stop",
            ],
            repo,
        )
        assert custom_recommended.returncode == 0, custom_recommended.stderr
        custom_recommended_json = json.loads(custom_recommended.stdout)
        assert custom_recommended_json["recommendedOfficialScenarios"] == ["simple-action-stop"]
        assert custom_recommended_json["missingRecommendedOfficialScenarios"] == []
        assert custom_recommended_json["hasRecommendedOfficialScenarioCoverage"] is True

        covered_not_ready = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--check-readiness",
            ],
            repo,
        )
        assert covered_not_ready.returncode == 1
        covered_not_ready_json = json.loads(covered_not_ready.stderr)
        assert covered_not_ready_json["scenarioCoverageOk"] is True
        assert covered_not_ready_json["coverageOk"] is False
        assert covered_not_ready_json["hasRequiredOfficialSuccessfulFixture"] is False
        assert covered_not_ready_json["requiredOfficialReadinessChecked"] is True
        assert covered_not_ready_json["requiredOfficialReadinessOk"] is False
        assert covered_not_ready_json["notReadyOfficialScenarios"] == ["simple-action-stop"]
        assert any("failed readiness" in error for error in covered_not_ready_json["errors"])

        ready_root = root / "ready"
        make_ready_fixture(ready_root, "official-ready-action")
        ready = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(ready_root),
                "--require-readiness",
            ],
            repo,
        )
        assert ready.returncode == 0, ready.stderr
        ready_json = json.loads(ready.stdout)
        assert ready_json["ok"] is True
        assert ready_json["scenarioCoverageOk"] is True
        assert ready_json["coverageOk"] is True
        assert ready_json["hasRequiredOfficialSuccessfulFixture"] is True
        assert ready_json["requiredOfficialReadinessChecked"] is True
        assert ready_json["requiredOfficialReadinessOk"] is True
        assert ready_json["notReadyOfficialScenarios"] == []
        assert ready_json["officialFixtureSetReadiness"]["ok"] is True

        duplicate_root = root / "duplicates"
        make_fixture(duplicate_root, "official-action-a")
        make_fixture(duplicate_root, "official-action-b")
        duplicate = run(
            [sys.executable, str(script), "--fixture-root", str(duplicate_root), "--allow-missing"],
            repo,
        )
        assert duplicate.returncode == 1
        duplicate_json = json.loads(duplicate.stderr)
        assert any("duplicate official scenario" in error for error in duplicate_json["errors"])

        missing_scenario_root = root / "missing-scenario"
        fixture = make_fixture(missing_scenario_root, "official-action")
        manifest = json.loads((fixture / "fixture-manifest.json").read_text())
        del manifest["scenario"]
        write_json(fixture / "fixture-manifest.json", manifest)
        missing_scenario = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(missing_scenario_root),
                "--allow-missing",
            ],
            repo,
        )
        assert missing_scenario.returncode == 1
        missing_scenario_json = json.loads(missing_scenario.stderr)
        assert any("official fixture missing scenario" in error for error in missing_scenario_json["errors"])

        recipe_drift_root = root / "recipe-drift"
        recipe_drift_fixture = make_fixture(recipe_drift_root, "official-action")
        recipe_drift_manifest_path = recipe_drift_fixture / "fixture-manifest.json"
        recipe_drift_manifest = json.loads(recipe_drift_manifest_path.read_text())
        recipe_drift_manifest["scenarioRecipe"]["expectedActionEvents"] = ["keyboard.text_input"]
        write_json(recipe_drift_manifest_path, recipe_drift_manifest)
        recipe_drift = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(recipe_drift_root),
            ],
            repo,
        )
        assert recipe_drift.returncode == 1
        recipe_drift_json = json.loads(recipe_drift.stderr)
        assert recipe_drift_json["availableOfficialScenarios"] == ["simple-action-stop"]
        assert recipe_drift_json["officialFixtures"][0]["scenarioRecipeMatches"] is False
        assert any("scenarioRecipe does not match scenario" in error for error in recipe_drift_json["errors"])

    print(
        json.dumps(
            {
                "ok": True,
                "checkedMissingCoverageFailure": True,
                "checkedAllowMissingReport": True,
                "checkedCandidateIgnored": True,
                "checkedCoverageSuccess": True,
                "checkedReadinessReport": True,
                "checkedReadinessFailure": True,
                "checkedReadinessSuccess": True,
                "checkedRecommendedCoverageReport": True,
                "checkedDuplicateScenarioFailure": True,
                "checkedMissingScenarioFailure": True,
                "checkedScenarioRecipeDriftFailure": True,
                "checkedScenarioRecipeManifest": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
