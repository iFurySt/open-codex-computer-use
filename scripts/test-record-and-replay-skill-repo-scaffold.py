#!/usr/bin/env python3

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import atexit

from record_and_replay_scenarios import (
    DEFAULT_RECOMMENDED_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_recipe,
)


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parents[1]
    baseline_summary_path = repo / "dist/record-and-replay-baseline-summary.json"
    baseline_summary_original = baseline_summary_path.read_text()
    atexit.register(lambda: baseline_summary_path.write_text(baseline_summary_original))
    baseline_summary = json.loads(baseline_summary_original)
    baseline_summary.setdefault("evidence", {}).setdefault(
        "fixtureIngestPipelines",
        {},
    )["checkedOfficialSessionDirectoryPathHandoff"] = True
    baseline_summary_path.write_text(json.dumps(baseline_summary, indent=2, sort_keys=True) + "\n")
    with tempfile.TemporaryDirectory() as tmp:
        output_dir = pathlib.Path(tmp) / "standalone-rnr-skill"
        result = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/scaffold-record-and-replay-skill-repo.py"),
                "--output-dir",
                str(output_dir),
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        payload = json.loads(result.stdout)
        assert payload["ok"] is True

        skill_path = output_dir / "skills/open-computer-use-record-and-replay/SKILL.md"
        readme_path = output_dir / "README.md"
        package_script = output_dir / "scripts/package-skill.sh"
        check_script = output_dir / "scripts/check.sh"
        verify_package_script = output_dir / "scripts/verify-package-artifact.py"
        verify_manifest_script = output_dir / "scripts/verify-manifest.py"
        verify_source_summary_script = output_dir / "scripts/verify-source-baseline-summary.py"
        verify_readme_script = output_dir / "scripts/verify-readme-handoff.py"
        verify_runtime_script = output_dir / "scripts/verify-runtime.py"
        verify_skill_workflow_script = output_dir / "scripts/verify-skill-workflow.py"
        wait_notify_smoke_script = output_dir / "scripts/wait-notify-contract-smoke.py"
        recording_to_skill_smoke_script = output_dir / "scripts/recording-to-skill-smoke.py"
        lifecycle_smoke_script = output_dir / "scripts/recording-lifecycle-smoke.py"
        workflow_path = output_dir / ".github/workflows/ci.yml"
        manifest_path = output_dir / "record-and-replay-skill-repo.json"
        source_summary_path = output_dir / "evidence/source-baseline-summary.json"
        assert skill_path.exists()
        assert readme_path.exists()
        assert package_script.exists()
        assert check_script.exists()
        assert verify_package_script.exists()
        assert verify_manifest_script.exists()
        assert verify_source_summary_script.exists()
        assert verify_readme_script.exists()
        assert verify_runtime_script.exists()
        assert verify_skill_workflow_script.exists()
        assert wait_notify_smoke_script.exists()
        assert recording_to_skill_smoke_script.exists()
        assert lifecycle_smoke_script.exists()
        assert workflow_path.exists()
        assert manifest_path.exists()
        assert source_summary_path.exists()

        skill_text = skill_path.read_text()
        assert "name: open-computer-use-record-and-replay" in skill_text
        assert "event_stream_start" in skill_text
        assert "open-computer-use event-stream scaffold-skill" in skill_text
        assert "ask whether the user wants to use that active recording or wait" in skill_text
        assert "safetySignals" in skill_text
        assert "skillEvidence.hasSafetySignals=true" in skill_text
        assert "explicit user confirmation before replay" in skill_text

        combined = "\n".join(path.read_text() for path in output_dir.rglob("*") if path.is_file())
        assert str(repo) not in combined
        assert "open-computer-use install-codex-record-and-replay-mcp" in combined
        assert "./scripts/check.sh" in combined
        assert "./scripts/verify-runtime.py" in combined
        assert "./scripts/verify-skill-workflow.py" in combined
        assert "scripts/verify-readme-handoff.py" in combined
        assert "scripts/verify-source-baseline-summary.py" in combined
        assert "evidence/source-baseline-summary.json" in combined
        assert "scripts/recording-to-skill-smoke.py" in combined
        assert "./scripts/recording-lifecycle-smoke.py" in combined
        assert "npm i -g open-computer-use" in combined
        assert "Python 3 must be available as `python3`" in combined
        assert "PYTHON=/path/to/python3" in combined
        assert "frontmatter description is required" in combined
        assert "frontmatter name must be" in combined
        assert "Record & Replay tool metadata drifted" in combined
        assert "checkedSkillWorkflow" in combined
        assert "checkedSourceBaselineSummaryEvidence" in combined
        assert "checkedStatusNotUsedAsWaitLoopGuard" in combined
        assert "checkedMcpNoDirectEventContentsGuard" in combined
        assert "Do not poll while the user is recording." in combined
        assert "Use `event_stream_status` only when the user asks for status" in combined
        assert "The MCP server does not expose event-stream contents directly." in combined
        assert "forbiddenSnippets" in combined
        assert "EXPECTED_INITIALIZE_CAPABILITIES" in combined
        assert "notifications/initialized" in combined
        assert "listChanged" in combined
        assert "destructiveHint" in combined
        assert "readOnlyHint" in combined
        assert "--strict-ocu --require-skill-draft <metadataPath-or-sessionPath>" in combined
        assert "--require-skill-draft <eventsPath>" in combined
        assert "session.ended.endReason=recording_controls_cancelled" in combined
        assert "single `session.started` opening event" in combined
        assert "single `session.ended`" in combined
        assert "final-event closure" in combined
        assert "metadata/session alias consistency" in combined
        assert "declared `metadataPath`" in combined
        assert "checkedDeclaredHandoffPaths" in combined
        assert "checkedScreenshotPathContainment" in combined
        assert "checks the declared handoff path evidence" in combined
        assert "Cancelled, incomplete, or" in combined
        assert "must not be used to" in combined
        assert "create or update a skill" in combined
        assert "event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>" in combined
        assert "The scaffold command also runs the skill-draft validation gate" in combined
        assert "checkedEventsOnlyValidation" in combined
        assert "checkedScaffoldSkill" in combined
        assert "checkedCancelledRecordingRejected" in combined
        assert "checkedSkillCreatorHandoff" in combined
        assert "checkedWaitNotifyContract" in combined
        assert "checkedNoActiveStatusStop" in combined
        assert "EXPECTED_NO_ACTIVE_RESPONSE" in combined
        assert "synthetic-recording-workflow" in combined
        assert "Complete the `skill-creator` workflow, including validation" in combined
        assert "not a standalone runbook or replay plan" in combined
        assert "does not start a recording" in combined
        assert "Independent Wait / Notify Integration" in combined
        assert "event-stream wait --json --session-id <id> --notify-command" in combined
        assert "`wait --json` adds `waitTimedOut` and `waitSessionMatched`." in combined
        assert "`--notify-command` receives the final status JSON on stdin" in combined
        assert "OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON" in combined
        assert "Keep this listener path outside the official-compatible MCP tool surface." in combined
        assert "## Official Evidence" in combined
        assert "record-and-replay-event-stream-surface-1.0.857.json" in combined
        assert "record-and-replay-official-no-active-status-stop-1.0.857.json" in combined
        assert "record-and-replay-official-raw-start-timeout-1.0.857.json" in combined
        assert "baseline contract smoke" in combined
        assert "official-golden-capture-preflight-smoke" in combined
        assert "ocu-candidate-pairing-preflight-smoke" in combined
        assert "source checks and preflight" in combined
        assert "scripts are not copied into this" in combined
        assert "default standalone" in combined
        assert "self-check still does not" in combined
        assert "make record-and-replay-baseline-audit" in combined
        assert "make record-and-replay-official-golden-gate-audit" in combined
        assert "dist/record-and-replay-baseline-summary.json" in combined
        assert "dist/record-and-replay-official-golden-gate-summary.json" in combined
        assert "Successful recording fixtures are still required" in combined
        assert "The minimum required official successful recording scenario is" in combined
        assert "officialEvidence.scenarioRecipes" in combined
        assert "OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS" in combined
        assert "runtimeVersion=" in combined
        assert (
            "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime"
            in combined
        )

        verify_runtime_text = verify_runtime_script.read_text()
        assert "OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS" in verify_runtime_text
        assert "runtimeVersion=" in verify_runtime_text
        assert (
            "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime"
            in verify_runtime_text
        )

        manifest = json.loads(manifest_path.read_text())
        required_scenarios = list(DEFAULT_REQUIRED_SCENARIOS)
        recommended_scenarios = list(DEFAULT_RECOMMENDED_SCENARIOS)
        required_readme_list = ", ".join(f"`{scenario}`" for scenario in required_scenarios)
        recommended_readme_list = (
            ", ".join(f"`{scenario}`" for scenario in recommended_scenarios[:-1])
            + f", and `{recommended_scenarios[-1]}`"
        )
        readme_text = readme_path.read_text()
        assert (
            "The minimum required official successful recording scenario is\n"
            f"{required_readme_list}. The recommended calibration set is\n"
            f"{recommended_readme_list}."
        ) in readme_text
        for scenario in recommended_scenarios:
            assert f"`{scenario}`" in combined
        assert manifest["runtimeDependency"] == "open-computer-use"
        source_baseline_summary = json.loads(
            (repo / "dist/record-and-replay-baseline-summary.json").read_text()
        )
        source_has_successful_recording_golden = (
            source_baseline_summary["status"]["officialSuccessfulRecordingGoldenComplete"]
            is True
        )
        assert manifest["officialEvidence"] == {
            "baselineVersion": "record-and-replay/1.0.857",
            "nonRecordingSurfaceFixture": "record-and-replay-event-stream-surface-1.0.857.json",
            "noActiveStatusStopFixture": (
                "record-and-replay-official-no-active-status-stop-1.0.857.json"
            ),
            "hostlessRawStartTimeoutFixture": (
                "record-and-replay-official-raw-start-timeout-1.0.857.json"
            ),
            "sourceRepoBaselineChecks": {
                "baselineContract": "baseline-contract-smoke",
                "officialRawStartTimeout": "official-raw-start-timeout-fixture-smoke",
                "officialFixtureSetGate": {
                    "check": "official-fixture-set-smoke",
                    "sameScenarioComparePolicy": {
                        "requiresAxDiffEvidence": True,
                        "requiresSameAxDiffMarkers": True,
                        "requiresSameSuppressedEventSequence": True,
                        "requiresSameSuppressedSchema": True,
                    },
                },
                "officialFixtureIngest": {
                    "check": "official-fixture-ingest-smoke",
                    "requiredEvidence": [
                        "checkedOfficialSessionDirectoryPathHandoff",
                    ],
                },
                "officialGoldenCapturePreflight": {
                    "check": "official-golden-capture-preflight-smoke",
                    "requiredEvidence": [
                        "checkedOfficialCapturePacketInputSemanticGuard",
                        "checkedOfficialCapturePacketSetContractManifest",
                        "checkedOfficialCapturePacketPostCaptureWorkflow",
                        "checkedOfficialCapturePacketWorkflowVerifier",
                        "checkedOfficialCapturePacketSetPostCaptureWorkflow",
                        "checkedOfficialCapturePacketSetWorkflowVerifier",
                        "checkedOfficialCapturePacketStrictAuditHandoff",
                        "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
                    ],
                },
                "ocuCandidatePairingPreflight": (
                    "ocu-candidate-pairing-preflight-smoke"
                ),
            },
            "sourceRepoBaselineAudit": {
                "usableBaseline": "make record-and-replay-baseline-audit",
                "strictOfficialGoldenGate": (
                    "make record-and-replay-official-golden-gate-audit"
                ),
                "auditTargetDryRunSmoke": (
                    "make record-and-replay-baseline-audit-targets-smoke"
                ),
                "baselineSummaryArtifact": (
                    "dist/record-and-replay-baseline-summary.json"
                ),
                "copiedBaselineSummaryEvidence": (
                    "evidence/source-baseline-summary.json"
                ),
                "strictOfficialGoldenSummaryArtifact": (
                    "dist/record-and-replay-official-golden-gate-summary.json"
                ),
                "baselineSummaryEnvVar": "RNR_BASELINE_SUMMARY_JSON",
                "strictOfficialGoldenSummaryEnvVar": (
                    "RNR_OFFICIAL_GOLDEN_SUMMARY_JSON"
                ),
                "strictOfficialGoldenExpectedFailureAudit": (
                    "scripts/check-record-and-replay-baseline-summary.py "
                    "dist/record-and-replay-official-golden-gate-summary.json "
                    "--allow-strict-official-golden-missing"
                ),
                "verifiesSummaryArtifactSeparation": True,
                "verifiesSummaryEnvVarIsolation": True,
            },
            "standaloneRepoBoundary": {
                "defaultChecksDoNotStartOfficialRecording": True,
                "preflightScriptsRemainInOpenComputerUseRepo": True,
                "doesNotCopyOpenComputerUseRuntimeSource": True,
            },
            "hasSuccessfulRecordingGolden": source_has_successful_recording_golden,
            "requiredSuccessfulRecordingScenarios": required_scenarios,
            "recommendedSuccessfulRecordingScenarios": recommended_scenarios,
            "scenarioRecipes": {
                scenario: scenario_recipe(scenario) for scenario in recommended_scenarios
            },
            "successfulRecordingGoldenRequiredFor": [
                "session file schema equivalence",
                "event field schema equivalence",
                "AX compact diff algorithm equivalence",
                "screenshot trigger equivalence",
                "timeout endReason equivalence",
            ],
        }
        assert manifest["mcpServer"]["args"] == ["event-stream", "mcp"]
        assert manifest["mcpServer"]["capabilities"] == {"tools": {"listChanged": False}}
        assert manifest["checks"]["packageSkill"] == "scripts/package-skill.sh"
        assert manifest["checks"]["packageArtifact"] == "scripts/verify-package-artifact.py"
        assert manifest["checks"]["manifestContract"] == "scripts/verify-manifest.py"
        assert manifest["checks"]["sourceBaselineSummaryEvidence"] == (
            "scripts/verify-source-baseline-summary.py"
        )
        assert manifest["checks"]["readmeHandoffContract"] == "scripts/verify-readme-handoff.py"
        assert manifest["checks"]["runtimeContract"] == "scripts/verify-runtime.py"
        assert manifest["checks"]["skillWorkflow"] == "scripts/verify-skill-workflow.py"
        assert manifest["checks"]["waitNotifyContractSmoke"] == (
            "scripts/wait-notify-contract-smoke.py"
        )
        assert manifest["checks"]["recordingToSkillSmoke"] == "scripts/recording-to-skill-smoke.py"
        assert manifest["checks"]["selfCheck"] == "scripts/check.sh"
        assert manifest["optionalChecks"]["recordingLifecycleSmoke"] == (
            "scripts/recording-lifecycle-smoke.py"
        )
        assert manifest["mcpServer"]["tools"] == [
            "event_stream_start",
            "event_stream_status",
            "event_stream_stop",
        ]
        assert manifest["mcpServer"]["requiresObjectParams"] is True
        assert manifest["mcpServer"]["requiresStringToolName"] is True
        assert manifest["mcpServer"]["requiresObjectArguments"] is True
        assert manifest["mcpServer"]["rejectsUnexpectedArguments"] is True
        assert manifest["mcpServer"]["rejectedRequestsDoNotCreateSessionFiles"] is True
        assert manifest["mcpServer"]["noActiveResponse"] == {
            "event_stream_status": {
                "isRecording": False,
                "maxDurationSeconds": 1800,
            },
            "event_stream_stop": {
                "isRecording": False,
                "maxDurationSeconds": 1800,
            },
        }
        assert [tool["name"] for tool in manifest["mcpServer"]["toolMetadata"]] == manifest["mcpServer"]["tools"]
        assert manifest["mcpServer"]["toolMetadata"][0]["description"].startswith(
            "Start recording the user's actions"
        )
        assert manifest["mcpServer"]["toolMetadata"][1]["annotations"]["readOnlyHint"] is True
        assert manifest["mcpServer"]["toolMetadata"][2]["inputSchema"] == {
            "additionalProperties": False,
            "properties": {},
            "type": "object",
        }
        assert manifest["extensionLayer"]["officialCompatibleMcpSurface"] is False
        assert "event-stream wait --json --session-id <id> --notify-command <json-argv>" in (
            manifest["extensionLayer"]["commands"]
        )
        assert manifest["extensionLayer"]["waitNotify"]["resultFields"] == [
            "waitTimedOut",
            "waitSessionMatched",
        ]
        assert manifest["extensionLayer"]["waitNotify"]["stdin"] == "final status JSON"
        assert (
            "OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH"
            in manifest["extensionLayer"]["waitNotify"]["environmentVariables"]
        )
        assert (
            "OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH"
            in manifest["extensionLayer"]["waitNotify"]["environmentVariables"]
        )
        assert (
            manifest["extensionLayer"]["waitNotify"][
                "callbackSkippedWhenWaitSessionMatchedFalse"
            ]
            is True
        )
        assert (
            manifest["extensionLayer"]["waitNotify"]["callbackFailureMakesCliFail"]
            is True
        )
        assert (
            manifest["extensionLayer"]["waitNotify"]["callbackTimeoutMakesCliFail"]
            is True
        )
        assert manifest["recordingToSkill"]["strictValidation"]["command"] == (
            "event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>"
        )
        assert manifest["recordingToSkill"]["strictValidation"]["requiresDeclaredHandoffPaths"] == [
            "metadataPath",
            "sessionPath",
            "eventsPath",
            "suppressedEventsPath",
        ]
        assert (
            manifest["recordingToSkill"]["strictValidation"]["requiresMetadataSessionAlias"]
            is True
        )
        assert (
            manifest["recordingToSkill"]["strictValidation"][
                "requiresScreenshotPathsInsideSession"
            ]
            is True
        )
        assert manifest["recordingToSkill"]["strictValidation"]["requiresSkillDraftReady"] is True
        assert manifest["recordingToSkill"]["eventsOnlyValidation"] == {
            "command": "event-stream validate --json --require-skill-draft <eventsPath>",
            "provesMetadataSessionAlias": False,
            "provesDeclaredHandoffPaths": False,
        }
        assert manifest["recordingToSkill"]["scaffoldSkill"] == {
            "command": "event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>",
            "runsSkillDraftValidationGate": True,
        }
        assert manifest["recordingToSkill"]["rejectsCancelledRecordings"] is True

        workflow_text = workflow_path.read_text()
        assert "run: ./scripts/check.sh" in workflow_text
        for line in workflow_text.splitlines():
            if "uses:" in line:
                assert re.search(r"@[0-9a-f]{40}(\\s|$)", line), line

        subprocess.run(
            ["bash", "-n", str(package_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["bash", "-n", str(check_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(verify_manifest_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(verify_source_summary_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(verify_readme_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(verify_runtime_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(lifecycle_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(recording_to_skill_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(verify_skill_workflow_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ["python3", "-m", "py_compile", str(wait_notify_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        original_skill_text = skill_path.read_text()
        try:
            mutated_skill_lines = [
                "description: " if line.startswith("description: ") else line
                for line in original_skill_text.splitlines()
            ]
            skill_path.write_text("\n".join(mutated_skill_lines) + "\n")
            invalid_package = subprocess.run(
                [str(package_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_package.returncode != 0
            assert "frontmatter description is required" in invalid_package.stderr
        finally:
            skill_path.write_text(original_skill_text)

        manifest_check = subprocess.run(
            [str(verify_manifest_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        manifest_payload = json.loads(manifest_check.stdout)
        assert manifest_payload["ok"] is True
        assert manifest_payload["checkedManifestContract"] is True
        assert manifest_payload["checkedStrictExpectedFailureAudit"] is True
        assert manifest_payload["checkedOfficialFixtureSetComparePolicy"] is True
        assert manifest_payload["checkedSourceBaselineSummaryEvidenceCheck"] is True
        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineAudit"][
                "strictOfficialGoldenExpectedFailureAudit"
            ] = "missing"
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "strict expected-failure audit command drifted" in invalid_manifest.stderr
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        source_summary_check = subprocess.run(
            [str(verify_source_summary_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        source_summary_payload = json.loads(source_summary_check.stdout)
        assert source_summary_payload["ok"] is True
        assert source_summary_payload["checkedSourceBaselineSummaryEvidence"] is True
        assert source_summary_payload["checkedSourceBaselineSummaryOfficialGoldenState"] is True
        assert (
            source_summary_payload["checkedSourceBaselineSummaryOfficialGoldenGap"]
            is not source_has_successful_recording_golden
        )
        assert (
            source_summary_payload["checkedSourceBaselineSummaryOfficialGoldenComplete"]
            is source_has_successful_recording_golden
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketSetContractManifest"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff"
            ]
            is True
        )
        assert (
            source_summary_payload[
                "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff"
            ]
            is True
        )
        source_summary = json.loads(source_summary_path.read_text())
        assert source_summary["status"]["usableBaseline"] is True
        assert source_summary["status"]["standaloneRepoBaselineReady"] is True
        assert (
            source_summary["status"]["officialSuccessfulRecordingGoldenComplete"]
            is source_has_successful_recording_golden
        )
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetContractManifest"
        ] is True
        assert source_summary["evidence"]["fixtureIngestPipelines"][
            "checkedOfficialSessionDirectoryPathHandoff"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketPostCaptureWorkflow"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketWorkflowVerifier"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetPostCaptureWorkflow"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetWorkflowVerifier"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketStrictAuditHandoff"
        ] is True
        assert source_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
        ] is True
        assert source_summary["evidence"]["standaloneSkillRepo"][
            "checkedOfficialFixtureSetComparePolicyManifest"
        ] is True
        assert source_summary["evidence"]["npmStagedSkillRepo"][
            "checkedOfficialFixtureSetComparePolicyManifest"
        ] is True
        if not source_has_successful_recording_golden:
            try:
                mutated_summary = json.loads(source_summary_path.read_text())
                mutated_summary["status"]["officialGoldenGatePassed"] = True
                mutated_summary["status"]["officialSuccessfulRecordingGoldenComplete"] = True
                mutated_summary["status"]["officialSuccessfulRecordingEquivalenceReady"] = True
                mutated_summary["status"]["requiresOfficialGoldenCapture"] = False
                mutated_summary["status"][
                    "missingRequiredOfficialSuccessfulRecordingScenarios"
                ] = []
                mutated_summary["status"][
                    "notReadyRequiredOfficialSuccessfulRecordingScenarios"
                ] = []
                mutated_summary["status"]["officialFixtureCoverageErrors"] = []
                source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
                completed_source_summary = subprocess.run(
                    [str(verify_source_summary_script)],
                    cwd=output_dir,
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                completed_payload = json.loads(completed_source_summary.stdout)
                assert completed_payload["checkedSourceBaselineSummaryOfficialGoldenState"] is True
                assert completed_payload["checkedSourceBaselineSummaryOfficialGoldenGap"] is False
                assert (
                    completed_payload["checkedSourceBaselineSummaryOfficialGoldenComplete"]
                    is True
                )
            finally:
                source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["status"]["officialSuccessfulRecordingEquivalenceReady"] = (
                not source_has_successful_recording_golden
            )
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert (
                "official golden state must be either current required gap or completed equivalence"
                in invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["fixtureIngestPipelines"][
                "checkedOfficialSessionDirectoryPathHandoff"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "official sessionDirectoryPath handoff evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketSetContractManifest"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet set contract manifest evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketPostCaptureWorkflow"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet post-capture workflow evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketSetPostCaptureWorkflow"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet set post-capture workflow evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketWorkflowVerifier"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet workflow verifier evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketSetWorkflowVerifier"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet set workflow verifier evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketStrictAuditHandoff"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert "capture packet strict audit handoff evidence missing" in (
                invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_summary = json.loads(source_summary_path.read_text())
            mutated_summary["evidence"]["preflightPipelines"][
                "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
            ] = False
            source_summary_path.write_text(json.dumps(mutated_summary, indent=2) + "\n")
            invalid_source_summary = subprocess.run(
                [str(verify_source_summary_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_source_summary.returncode != 0
            assert (
                "capture packet strict expected-failure audit handoff evidence missing"
                in invalid_source_summary.stderr
            )
        finally:
            source_summary_path.write_text(json.dumps(source_summary, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialFixtureSetGate"
            ]["sameScenarioComparePolicy"]["requiresSameSuppressedSchema"] = False
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official fixture set suppressed schema policy missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert (
                "official capture packet strict expected-failure audit handoff evidence missing"
                in invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketSetContractManifest"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official capture packet set contract manifest evidence missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketPostCaptureWorkflow"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official capture packet post-capture workflow evidence missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketWorkflowVerifier"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official capture packet workflow verifier evidence missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketSetPostCaptureWorkflow"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert (
                invalid_manifest.returncode != 0
            )
            assert (
                "official capture packet set post-capture workflow evidence missing"
                in invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketSetWorkflowVerifier"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official capture packet set workflow verifier evidence missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        try:
            mutated_manifest = json.loads(manifest_path.read_text())
            mutated_manifest["officialEvidence"]["sourceRepoBaselineChecks"][
                "officialGoldenCapturePreflight"
            ]["requiredEvidence"].remove(
                "checkedOfficialCapturePacketStrictAuditHandoff"
            )
            manifest_path.write_text(json.dumps(mutated_manifest, indent=2) + "\n")
            invalid_manifest = subprocess.run(
                [str(verify_manifest_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_manifest.returncode != 0
            assert "official capture packet strict audit handoff evidence missing" in (
                invalid_manifest.stderr
            )
        finally:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        readme_check = subprocess.run(
            [str(verify_readme_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        readme_payload = json.loads(readme_check.stdout)
        assert readme_payload["ok"] is True
        assert readme_payload["checkedReadmeHandoffContract"] is True
        assert readme_payload["checkedReadmeOfficialEvidenceHandoff"] is True
        assert readme_payload["checkedReadmeOfficialGoldenGap"] is True
        assert readme_payload["checkedReadmeWaitNotifyBoundary"] is True
        original_readme_text = readme_path.read_text()
        try:
            readme_path.write_text(
                original_readme_text.replace(
                    "make record-and-replay-official-golden-gate-audit",
                    "missing-strict-gate",
                )
            )
            invalid_readme = subprocess.run(
                [str(verify_readme_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_readme.returncode != 0
            assert "missingRequiredSnippets" in invalid_readme.stderr
        finally:
            readme_path.write_text(original_readme_text)

        workflow_check = subprocess.run(
            [str(verify_skill_workflow_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        workflow_payload = json.loads(workflow_check.stdout)
        assert workflow_payload["ok"] is True
        assert workflow_payload["checkedSkillWorkflow"] is True
        assert workflow_payload["checkedStatusNotUsedAsWaitLoopGuard"] is True
        assert workflow_payload["checkedMcpNoDirectEventContentsGuard"] is True
        try:
            skill_path.write_text(original_skill_text.replace("Do not poll while the user is recording.", ""))
            invalid_workflow = subprocess.run(
                [str(verify_skill_workflow_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_workflow.returncode != 0
            assert "missingRequiredSnippets" in invalid_workflow.stderr
        finally:
            skill_path.write_text(original_skill_text)
        try:
            skill_path.write_text(
                original_skill_text.replace(
                    "Use `event_stream_status` only when the user asks for status or returns after recording; do not use it to wait for completion.",
                    "",
                )
            )
            invalid_status_workflow = subprocess.run(
                [str(verify_skill_workflow_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_status_workflow.returncode != 0
            assert "missingRequiredSnippets" in invalid_status_workflow.stderr
        finally:
            skill_path.write_text(original_skill_text)
        try:
            skill_path.write_text(
                original_skill_text.replace(
                    "The MCP server does not expose event-stream contents directly.",
                    "",
                )
            )
            invalid_handoff_workflow = subprocess.run(
                [str(verify_skill_workflow_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_handoff_workflow.returncode != 0
            assert "missingRequiredSnippets" in invalid_handoff_workflow.stderr
        finally:
            skill_path.write_text(original_skill_text)
        try:
            skill_path.write_text(
                original_skill_text.replace(
                    "OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON",
                    "REMOVED_STATUS_JSON_ENV",
                )
            )
            invalid_wait_workflow = subprocess.run(
                [str(verify_skill_workflow_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_wait_workflow.returncode != 0
            assert "missingRequiredSnippets" in invalid_wait_workflow.stderr
        finally:
            skill_path.write_text(original_skill_text)

        subprocess.run(
            [str(package_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert (output_dir / "dist/skills/open-computer-use-record-and-replay.skill").exists()
        package_check = subprocess.run(
            [str(verify_package_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        package_payload = json.loads(package_check.stdout)
        assert package_payload["ok"] is True
        assert package_payload["checkedPackageArtifact"] is True
        assert package_payload["checkedPackageSkillArchive"] is True
        assert package_payload["checkedPackageSkillFrontmatter"] is True
        assert package_payload["checkedPackageSkillHandoff"] is True
        packaged_skill = output_dir / "dist/skills/open-computer-use-record-and-replay.skill"
        original_packaged_skill = packaged_skill.read_bytes()
        try:
            packaged_skill.write_bytes(b"not a zip")
            invalid_package = subprocess.run(
                [str(verify_package_script)],
                cwd=output_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert invalid_package.returncode != 0
            assert "failed to read skill package" in invalid_package.stderr
        finally:
            packaged_skill.write_bytes(original_packaged_skill)

        subprocess.run(
            ["swift", "build", "--product", "OpenComputerUse"],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        fake_runtime = pathlib.Path(tmp) / "stale-open-computer-use"
        fake_runtime.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${1:-}\" == \"--version\" ]]; then\n"
            "  echo '0.1.51'\n"
            "  exit 0\n"
            "fi\n"
            "cat >/dev/null\n",
        )
        fake_runtime.chmod(0o755)
        timed_out_runtime = subprocess.run(
            [str(verify_runtime_script)],
            cwd=output_dir,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(fake_runtime),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
                "OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS": "0.2",
            },
        )
        assert timed_out_runtime.returncode != 0
        assert "runtimeVersion={'ok': True" in timed_out_runtime.stderr
        assert "0.1.51" in timed_out_runtime.stderr
        assert (
            "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime"
            in timed_out_runtime.stderr
        )
        timed_out_lifecycle = subprocess.run(
            [str(lifecycle_smoke_script)],
            cwd=output_dir,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(fake_runtime),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
                "OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS": "0.2",
            },
        )
        assert timed_out_lifecycle.returncode != 0
        assert "runtimeVersion={'ok': True" in timed_out_lifecycle.stderr
        assert "0.1.51" in timed_out_lifecycle.stderr
        assert (
            "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime"
            in timed_out_lifecycle.stderr
        )
        runtime_check = subprocess.run(
            [str(verify_runtime_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(repo / ".build/debug/OpenComputerUse"),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        runtime_payload = json.loads(runtime_check.stdout)
        assert runtime_payload["ok"] is True
        assert runtime_payload["tools"] == [
            "event_stream_start",
            "event_stream_status",
            "event_stream_stop",
        ]
        assert runtime_payload["checkedInitializeSurfaceContract"] is True
        assert runtime_payload["checkedToolMetadataContract"] is True
        assert runtime_payload["checkedToolInputSchemaNoArguments"] is True
        assert runtime_payload["checkedNoActiveStatusStop"] is True
        assert runtime_payload["checkedRejectsUnexpectedArguments"] is True
        assert runtime_payload["checkedRejectsNonObjectArguments"] is True
        assert runtime_payload["checkedRequiresObjectParams"] is True
        assert runtime_payload["checkedRequiresStringToolName"] is True
        assert runtime_payload["checkedRequiresObjectArguments"] is True
        assert runtime_payload["checkedRejectedRequestsDoNotCreateSessionFiles"] is True
        wait_notify_check = subprocess.run(
            [str(wait_notify_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(repo / ".build/debug/OpenComputerUse"),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        wait_notify_payload = json.loads(wait_notify_check.stdout)
        assert wait_notify_payload["ok"] is True
        assert wait_notify_payload["checkedWaitNotifyContract"] is True
        assert wait_notify_payload["checkedNotifySuppressedEventsPathEnv"] is True
        assert wait_notify_payload["checkedNotifyCallbackFailureExit"] is True
        assert wait_notify_payload["checkedNotifyCallbackFailureReason"] is True
        assert wait_notify_payload["checkedNotifyCallbackTimeoutFailureExit"] is True
        assert wait_notify_payload["checkedNotifyCallbackTimeoutReason"] is True
        assert wait_notify_payload["waitTimedOut"] is True
        assert wait_notify_payload["waitSessionMatched"] is False
        assert wait_notify_payload["callbackSkipped"] is True
        assert wait_notify_payload["callbackFailureDetected"] is True
        assert wait_notify_payload["callbackFailureReason"] == "nonZeroExit"
        assert wait_notify_payload["callbackTimeoutDetected"] is True
        assert wait_notify_payload["callbackTimeoutReason"] == "timeout"
        recording_to_skill_check = subprocess.run(
            [str(recording_to_skill_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(repo / ".build/debug/OpenComputerUse"),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        recording_to_skill_payload = json.loads(recording_to_skill_check.stdout)
        assert recording_to_skill_payload["ok"] is True
        assert recording_to_skill_payload["checkedStrictValidation"] is True
        assert recording_to_skill_payload["checkedScreenshotPathContainment"] is True
        assert recording_to_skill_payload["checkedEventsOnlyValidation"] is True
        assert recording_to_skill_payload["checkedScaffoldSkill"] is True
        assert recording_to_skill_payload["checkedScaffoldSkillFailureExit"] is True
        assert recording_to_skill_payload["checkedCancelledRecordingRejected"] is True
        assert recording_to_skill_payload["checkedSkillCreatorHandoff"] is True
        lifecycle_check = subprocess.run(
            [str(lifecycle_smoke_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(repo / ".build/debug/OpenComputerUse"),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        lifecycle_payload = json.loads(lifecycle_check.stdout)
        assert lifecycle_payload["ok"] is True
        assert lifecycle_payload["checkedOneActive"] is True
        assert lifecycle_payload["checkedIdempotentStop"] is True
        assert lifecycle_payload["checkedFinalStatus"] is True
        assert "session.started" in lifecycle_payload["eventTypes"]
        assert "session.ended" in lifecycle_payload["eventTypes"]
        check_run = subprocess.run(
            [str(check_script)],
            cwd=output_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **os.environ,
                "OPEN_COMPUTER_USE_CLI": str(repo / ".build/debug/OpenComputerUse"),
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            },
        )
        assert "open-computer-use-record-and-replay.skill" in check_run.stdout
        check_lines = [line for line in check_run.stdout.splitlines() if line.startswith("{")]
        assert check_lines
        check_payloads = [json.loads(line) for line in check_lines]
        assert any(payload.get("checkedManifestContract") is True for payload in check_payloads)
        assert any(payload.get("checkedPackageArtifact") is True for payload in check_payloads)
        assert any(
            payload.get("checkedSourceBaselineSummaryEvidence") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedSourceBaselineSummaryOfficialGoldenState") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff")
            is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedReadmeHandoffContract") is True
            for payload in check_payloads
        )
        assert any(payload.get("checkedSkillWorkflow") is True for payload in check_payloads)
        assert any(
            payload.get("checkedStatusNotUsedAsWaitLoopGuard") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedMcpNoDirectEventContentsGuard") is True
            for payload in check_payloads
        )
        assert any(payload.get("checkedWaitNotifyContract") is True for payload in check_payloads)
        assert any(
            payload.get("checkedNotifyCallbackFailureExit") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedNotifyCallbackFailureReason") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedNotifyCallbackTimeoutFailureExit") is True
            for payload in check_payloads
        )
        assert any(
            payload.get("checkedNotifyCallbackTimeoutReason") is True
            for payload in check_payloads
        )
        assert any(payload.get("checkedScaffoldSkill") is True for payload in check_payloads)
        assert check_payloads[-1]["ok"] is True

    print(
        json.dumps(
            {
                "ok": True,
                "checkedStandaloneRepoScaffold": True,
                "checkedManifestContract": True,
                "checkedReadmeHandoffContract": True,
                "checkedReadmeOfficialEvidenceHandoff": True,
                "checkedReadmeOfficialGoldenGap": True,
                "checkedReadmeWaitNotifyBoundary": True,
                "checkedGeneratedReadmePrerequisites": True,
                "checkedGeneratedReadmeScenarioList": True,
                "checkedOfficialEvidenceManifest": True,
                "checkedOfficialEvidenceScenarioManifest": True,
                "checkedOfficialEvidencePreflightManifest": True,
                "checkedOfficialEvidenceAuditManifest": True,
                "checkedOfficialFixtureSetComparePolicyManifest": True,
                "checkedSourceBaselineSummaryEvidence": True,
                "checkedSourceBaselineSummaryOfficialGoldenState": True,
                "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff": True,
                "checkedSourceBaselineSummaryCapturePacketSetContractManifest": True,
                "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow": True,
                "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier": True,
                "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow": True,
                "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier": True,
                "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff": True,
                "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff": True,
                "checkedPackageArtifact": True,
                "checkedSkillPackaging": True,
                "checkedRuntimeTimeoutDiagnostics": True,
                "checkedRuntimeContract": True,
                "checkedInitializeSurfaceContract": True,
                "checkedToolMetadataContract": True,
                "checkedToolInputSchemaNoArguments": True,
                "checkedNoActiveStatusStop": True,
                "checkedRejectsUnexpectedArguments": True,
                "checkedRejectsNonObjectArguments": True,
                "checkedRequiresObjectParams": True,
                "checkedRequiresStringToolName": True,
                "checkedRequiresObjectArguments": True,
                "checkedRejectedRequestsDoNotCreateSessionFiles": True,
                "checkedSkillWorkflow": True,
                "checkedStatusNotUsedAsWaitLoopGuard": True,
                "checkedMcpNoDirectEventContentsGuard": True,
                "checkedWaitNotifyContract": True,
                "checkedNotifySuppressedEventsPathEnv": True,
                "checkedNotifyCallbackFailureExit": True,
                "checkedNotifyCallbackFailureReason": True,
                "checkedNotifyCallbackTimeoutFailureExit": True,
                "checkedNotifyCallbackTimeoutReason": True,
                "checkedRecordingToSkillHandoff": True,
                "checkedStrictValidation": True,
                "checkedDeclaredHandoffPaths": True,
                "checkedScreenshotPathContainment": True,
                "checkedEventsOnlyValidation": True,
                "checkedScaffoldSkill": True,
                "checkedScaffoldSkillFailureExit": True,
                "checkedCancelledRecordingContract": True,
                "checkedCancelledRecordingRejected": True,
                "checkedSkillCreatorHandoff": True,
                "checkedLifecycleSmoke": True,
                "checkedOneActive": True,
                "checkedIdempotentStop": True,
                "checkedFinalStatus": True,
                "checkedGeneratedRepoSelfCheck": True,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
