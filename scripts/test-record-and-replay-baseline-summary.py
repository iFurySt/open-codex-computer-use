#!/usr/bin/env python3

import json
import pathlib
import shlex
import subprocess
import sys
import tempfile

from record_and_replay_baseline_contract import (
    NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
    REQUIRED_BASELINE_CHECKS,
    STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
)


TOOL_NAMES = ["event_stream_start", "event_stream_status", "event_stream_stop"]
NO_ACTIVE = {"isRecording": False, "maxDurationSeconds": 1800}


def write_json(path: pathlib.Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path: pathlib.Path, records: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(record, sort_keys=True) for record in records) + "\n")


def run(command: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def parse_last_json(stdout: str) -> dict:
    records = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        records.append(json.loads(line))
    assert records, stdout
    return records[-1]


def write_inputs(root: pathlib.Path, has_official_golden: bool) -> dict[str, pathlib.Path]:
    root.mkdir(parents=True, exist_ok=True)
    paths = {
        "standalone": root / "standalone.json",
        "npm": root / "npm.json",
        "surface": root / "surface.json",
        "no_active": root / "no-active.json",
        "raw_timeout": root / "raw-timeout.json",
        "fixture_set": root / "fixture-set.json",
        "coverage": root / "coverage.json",
        "official_ingest": root / "official-ingest.json",
        "candidate_ingest": root / "candidate-ingest.json",
        "official_capture_preflight": root / "official-capture-preflight.json",
        "ocu_pairing_preflight": root / "ocu-pairing-preflight.json",
        "baseline_audit_targets": root / "baseline-audit-targets.json",
        "baseline_contract": root / "baseline-contract.json",
        "matrix": root / "matrix.jsonl",
        "screenshot": root / "screenshot.jsonl",
        "action": root / "action.jsonl",
    }
    write_json(
        paths["baseline_contract"],
        {
            "ok": True,
            "checkedRequiredBaselineChecks": True,
            "checkedNoDuplicateRequiredBaselineChecks": True,
            "checkedStandaloneSmokeRequiredKeys": True,
            "checkedStandaloneSummaryEvidenceKeys": True,
            "checkedStandaloneLifecycleSummaryRenames": True,
            "checkedNpmStagedSmokeRequiredKeys": True,
            "checkedNpmStagedSummaryEvidenceKeys": True,
            "checkedNpmStagedSummaryMatchesSmoke": True,
        },
    )
    write_json(
        paths["standalone"],
        {
            "checkedGeneratedRepoSelfCheck": True,
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
            "checkedRuntimeContract": True,
            "checkedRuntimeTimeoutDiagnostics": True,
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
            "checkedEventsOnlyValidation": True,
            "checkedScaffoldSkill": True,
            "checkedScaffoldSkillFailureExit": True,
            "checkedSkillCreatorHandoff": True,
            "checkedCancelledRecordingContract": True,
            "checkedCancelledRecordingRejected": True,
            "checkedScreenshotPathContainment": True,
            "checkedLifecycleSmoke": True,
            "checkedOneActive": True,
            "checkedIdempotentStop": True,
            "checkedFinalStatus": True,
        },
    )
    write_json(
        paths["npm"],
        {
            "checkedNpmLauncher": True,
            "checkedNpmPythonLauncherDiagnostics": True,
            "checkedStandaloneRepoScaffold": True,
            "checkedManifestContract": True,
            "checkedReadmeHandoffContract": True,
            "checkedReadmeOfficialEvidenceHandoff": True,
            "checkedReadmeOfficialGoldenGap": True,
            "checkedReadmeWaitNotifyBoundary": True,
            "checkedGeneratedRepoSelfCheck": True,
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
            "checkedNoActiveStatusStop": True,
            "checkedRuntimeTimeoutDiagnostics": True,
            "checkedInitializeSurfaceContract": True,
            "checkedToolMetadataContract": True,
            "checkedToolInputSchemaNoArguments": True,
            "checkedRequiresObjectParams": True,
            "checkedRequiresStringToolName": True,
            "checkedRequiresObjectArguments": True,
            "checkedRejectsUnexpectedArguments": True,
            "checkedRejectsNonObjectArguments": True,
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
            "checkedSkillPackaging": True,
            "checkedRecordingToSkillManifestContract": True,
            "checkedCancelledRecordingContract": True,
            "checkedStrictValidation": True,
            "checkedDeclaredHandoffPaths": True,
            "checkedScreenshotPathContainment": True,
            "checkedEventsOnlyValidation": True,
            "checkedScaffoldSkill": True,
            "checkedScaffoldSkillFailureExit": True,
            "checkedCancelledRecordingRejected": True,
            "checkedRecordingToSkillHandoff": True,
            "checkedSkillCreatorHandoff": True,
        },
    )
    write_json(
        paths["surface"],
        {
            "results": [
                {
                    "label": "local-open-computer-use",
                    "ok": True,
                    "protocolVersion": "2025-11-25",
                    "serverName": "Record & Replay",
                    "toolNames": TOOL_NAMES,
                },
                {
                    "label": "official-record-and-replay",
                    "ok": True,
                    "protocolVersion": "2025-11-25",
                    "serverName": "Record & Replay",
                    "toolNames": TOOL_NAMES,
                },
            ]
        },
    )
    write_json(
        paths["no_active"],
        {
            "ok": True,
            "fixture": "/tmp/record-and-replay-official-no-active-status-stop-1.0.857.json",
            "checkedTools": ["event_stream_status", "event_stream_stop"],
            "createdSessionFiles": False,
            "actual": {
                "event_stream_status": NO_ACTIVE,
                "event_stream_stop": NO_ACTIVE,
            },
        },
    )
    write_json(
        paths["raw_timeout"],
        {
            "ok": True,
            "checkedOfficialRawStartTimeoutBoundary": True,
            "checkedOfficialRawStartStatusStopTimeout": True,
            "checkedOfficialRawStartDoesNotReturnRecordingPaths": True,
            "checkedOfficialRawSurface": True,
            "checkedRawProbeFixtureRedaction": True,
            "officialRawToolCallCount": 3,
            "officialRawTimeoutCount": 3,
            "fixtures": [
                "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json"
            ],
        },
    )
    write_json(
        paths["fixture_set"],
        {
            "ok": True,
            "checkedFixtureSetGate": True,
            "checkedRequiredSimpleActionStopScenario": True,
            "checkedCandidatePairing": True,
            "checkedCandidateReadinessFailure": True,
            "checkedStopEndReasonPolicy": True,
            "checkedAxDiffComparisonPolicy": True,
            "checkedSuppressedStreamComparisonPolicy": True,
            "checkedAxDiffComparisonFailure": True,
            "checkedCancelScenarioPolicy": True,
            "checkedKeyboardInputScenarioPolicy": True,
            "checkedDragScenarioPolicy": True,
            "checkedTimeoutScenarioPolicy": True,
        },
    )
    missing_required = [] if has_official_golden else ["simple-action-stop"]
    missing_recommended = [] if has_official_golden else ["simple-action-stop"]
    not_ready = [] if has_official_golden else []
    write_json(
        paths["coverage"],
        {
            "coverageOk": has_official_golden,
            "scenarioCoverageOk": has_official_golden,
            "hasRequiredOfficialSuccessfulFixture": has_official_golden,
            "requiredOfficialReadinessChecked": True,
            "requiredOfficialReadinessOk": has_official_golden,
            "hasRecommendedOfficialScenarioCoverage": has_official_golden,
            "requiredOfficialScenarios": ["simple-action-stop"],
            "recommendedOfficialScenarios": ["simple-action-stop"],
            "availableOfficialScenarios": ["simple-action-stop"] if has_official_golden else [],
            "missingOfficialScenarios": missing_required,
            "missingRecommendedOfficialScenarios": missing_recommended,
            "notReadyOfficialScenarios": not_ready,
        },
    )
    write_json(
        paths["official_ingest"],
        {
            "checkedOfficialFixtureIngest": True,
            "checkedOfficialFixtureInspectOnly": True,
            "checkedOfficialSessionDirectoryPathHandoff": True,
            "checkedPostIngestCoverageReport": True,
            "checkedPostIngestCoverageReadiness": True,
            "checkedPostIngestRequireCoverageFailure": True,
        },
    )
    write_json(
        paths["candidate_ingest"],
        {
            "checkedOcuCandidateIngest": True,
            "checkedCandidateIngestHandoffCommands": True,
            "checkedSmokeJsonImport": True,
            "checkedOfficialCandidatePairing": True,
            "checkedCandidateRedaction": True,
            "checkedKeyboardInputScenarioReadiness": True,
            "checkedDragScenarioReadiness": True,
        },
    )
    write_json(
        paths["official_capture_preflight"],
        {
            "ok": True,
            "checkedMissingScenarioPreflight": True,
            "checkedCapturePacket": True,
            "checkedCapturePacketPostCaptureWorkflow": True,
            "checkedCapturePacketWorkflowVerifier": True,
            "checkedCapturePacketHandoffScripts": True,
            "checkedCapturePacketStrictAuditHandoff": True,
            "checkedCapturePacketStrictExpectedFailureAuditHandoff": True,
            "checkedCapturePacketOcuCandidateOutputDir": True,
            "checkedCapturePacketNoTranscript": True,
            "checkedCapturePacketSet": True,
            "checkedCapturePacketSetPostCaptureWorkflow": True,
            "checkedCapturePacketSetWorkflowVerifier": True,
            "checkedCapturePacketSetNoTranscript": True,
            "checkedCapturePacketSetOcuCandidateHandoff": True,
            "checkedCapturePacketSetContractManifest": True,
            "checkedCapturePacketTranscriptManifest": True,
            "checkedMakeCapturePacketTargets": True,
            "checkedCapturePacketInputSemanticGuard": True,
            "checkedCapturePacketPlaceholderGuard": True,
            "checkedCapturePacketVerifyInputs": True,
            "checkedCapturePacketImportPlaceholderGuard": True,
            "checkedCapturePacketTranscriptPlaceholderGuard": True,
            "checkedCapturePacketSetRootPlaceholderGuard": True,
            "checkedCapturePacketSetRootPreflightPlaceholderGuard": True,
            "checkedCapturePacketSetVerifyAll": True,
            "checkedRequireReadyFailure": True,
            "checkedMissingPluginFailure": True,
            "checkedAllowedMissingPluginKeyboardScenario": True,
            "checkedCoverageErrorFailure": True,
        },
    )
    write_json(
        paths["ocu_pairing_preflight"],
        {
            "ok": True,
            "checkedMissingOfficialPreflight": True,
            "checkedNoCandidatePreflight": True,
            "checkedPairedCandidatePreflight": True,
            "checkedKeyboardRecordingRequiredScenario": True,
            "checkedCoverageErrorReport": True,
        },
    )
    write_json(
        paths["baseline_audit_targets"],
        {
            "ok": True,
            "checkedBaselineAuditMakeTarget": True,
            "checkedBaselineAuditDefaultSummaryPath": True,
            "checkedBaselineAuditCustomSummaryPath": True,
            "checkedBaselineAuditIgnoresStrictSummaryVar": True,
            "checkedStrictOfficialGoldenAuditMakeTarget": True,
            "checkedStrictOfficialGoldenAuditDefaultSummaryPath": True,
            "checkedStrictOfficialGoldenAuditCustomSummaryPath": True,
            "checkedStrictOfficialGoldenAuditIgnoresBaselineSummaryVar": True,
            "checkedStrictOfficialGoldenAuditSeparateSummaryPath": True,
        },
    )
    write_jsonl(
        paths["matrix"],
        [
            {"ok": True, "handoffChecked": True},
            {"ok": True, "mode": "no-active"},
            {"ok": True, "mode": "timeout"},
            {"ok": True, "mode": "wait-timeout"},
            {"ok": True, "mode": "approval"},
            {"ok": True, "mode": "mcp-elicitation"},
            {"ok": True, "mode": "app-agent-wait"},
            {"ok": True, "matrix": "event-stream"},
        ],
    )
    write_jsonl(
        paths["screenshot"],
        [
            {
                "ok": True,
                "screenshotPolicy": "always",
                "screenshotNeededForContextCount": 1,
                "screenshotAvailableCount": 0,
                "screenshotPathCount": 0,
            }
        ],
    )
    write_jsonl(
        paths["action"],
        [
            {
                "ok": True,
                "mode": "actions",
                "actionScenario": "mixed-action-stop",
                "eventCount": 7,
                "eventTypes": [
                    "session.started",
                    "window.changed",
                    "AX.focusedWindowChanged",
                    "mouse.click",
                    "session.ended",
                ],
                "skillPath": "/tmp/SKILL.md",
                "mcpTranscriptPath": "/tmp/mcp-transcript.json",
                "checkedMcpResponseShapesCaptured": True,
                "checkedSkillReadinessCanCreateDraft": True,
                "checkedSkillCreatorFinalizationHandoff": True,
                "checkedGeneratedSkillPathRedaction": True,
            },
            {
                "ok": True,
                "mode": "actions",
                "actionScenario": "simple-action-stop",
                "eventCount": 5,
                "eventTypes": [
                    "session.started",
                    "window.changed",
                    "AX.focusedWindowChanged",
                    "mouse.click",
                    "session.ended",
                ],
                "skillPath": "/tmp/simple/SKILL.md",
                "mcpTranscriptPath": "/tmp/simple-mcp-transcript.json",
                "checkedMcpResponseShapesCaptured": True,
                "checkedSkillReadinessCanCreateDraft": True,
                "checkedSkillCreatorFinalizationHandoff": True,
                "checkedGeneratedSkillPathRedaction": True,
            },
            {
                "ok": True,
                "mode": "actions",
                "actionScenario": "drag-stop",
                "eventCount": 5,
                "eventTypes": [
                    "session.started",
                    "window.changed",
                    "AX.focusedWindowChanged",
                    "mouse.drag",
                    "session.ended",
                ],
                "skillPath": "/tmp/drag/SKILL.md",
                "mcpTranscriptPath": "/tmp/drag-mcp-transcript.json",
                "checkedMcpResponseShapesCaptured": True,
                "checkedSkillReadinessCanCreateDraft": True,
                "checkedSkillCreatorFinalizationHandoff": True,
                "checkedGeneratedSkillPathRedaction": True,
            }
        ],
    )
    return paths


def summary_command(script: pathlib.Path, paths: dict[str, pathlib.Path]) -> list[str]:
    return [
        sys.executable,
        str(script),
        "--standalone-json",
        str(paths["standalone"]),
        "--npm-json",
        str(paths["npm"]),
        "--official-surface-json",
        str(paths["surface"]),
        "--official-no-active-json",
        str(paths["no_active"]),
        "--official-raw-timeout-json",
        str(paths["raw_timeout"]),
        "--official-fixture-set-json",
        str(paths["fixture_set"]),
        "--official-fixture-coverage-json",
        str(paths["coverage"]),
        "--official-fixture-ingest-json",
        str(paths["official_ingest"]),
        "--ocu-candidate-ingest-json",
        str(paths["candidate_ingest"]),
        "--official-capture-preflight-json",
        str(paths["official_capture_preflight"]),
        "--ocu-pairing-preflight-json",
        str(paths["ocu_pairing_preflight"]),
        "--baseline-audit-targets-json",
        str(paths["baseline_audit_targets"]),
        "--baseline-contract-json",
        str(paths["baseline_contract"]),
        "--matrix-jsonl",
        str(paths["matrix"]),
        "--screenshot-jsonl",
        str(paths["screenshot"]),
        "--action-jsonl",
        str(paths["action"]),
    ]


def main() -> None:
    repo = pathlib.Path(__file__).resolve().parents[1]
    script = repo / "scripts/build-record-and-replay-baseline-summary.py"
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        missing_paths = write_inputs(root / "missing", has_official_golden=False)

        default_result = run(summary_command(script, missing_paths), repo)
        assert default_result.returncode == 0, default_result.stderr
        default_summary = parse_last_json(default_result.stdout)
        assert default_summary["ok"] is True
        assert default_summary["checks"] == list(REQUIRED_BASELINE_CHECKS)
        assert default_summary["status"]["usableBaseline"] is True
        assert default_summary["evidence"]["baselineContract"] == {
            "ok": True,
            "checkedRequiredBaselineChecks": True,
            "checkedNoDuplicateRequiredBaselineChecks": True,
            "checkedStandaloneSmokeRequiredKeys": True,
            "checkedStandaloneSummaryEvidenceKeys": True,
            "checkedStandaloneLifecycleSummaryRenames": True,
            "checkedNpmStagedSmokeRequiredKeys": True,
            "checkedNpmStagedSummaryEvidenceKeys": True,
            "checkedNpmStagedSummaryMatchesSmoke": True,
        }
        assert default_summary["status"]["missingUsableBaselineEvidence"] == []
        assert default_summary["status"]["strictOfficialGoldenRequired"] is False
        assert default_summary["status"]["officialGoldenRequirementSatisfied"] is True
        assert default_summary["status"]["officialGoldenGatePassed"] is False
        assert default_summary["status"]["officialRawStartTimeoutBoundaryVerified"] is True
        assert default_summary["status"]["standaloneRepoBaselineReady"] is True
        assert default_summary["status"]["officialSuccessfulRecordingEquivalenceReady"] is False
        assert set(default_summary["evidence"]["standaloneSkillRepo"]) == set(
            STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS
        )
        assert set(default_summary["evidence"]["npmStagedSkillRepo"]) == set(
            NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS
        )
        assert default_summary["evidence"]["officialRawStartTimeout"][
            "checkedOfficialRawStartDoesNotReturnRecordingPaths"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSet"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketPostCaptureWorkflow"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketWorkflowVerifier"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetPostCaptureWorkflow"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetWorkflowVerifier"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketStrictAuditHandoff"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketOcuCandidateOutputDir"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketNoTranscript"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetNoTranscript"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetOcuCandidateHandoff"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetContractManifest"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketTranscriptManifest"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketMakeTargets"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketInputSemanticGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketPlaceholderGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketVerifyInputs"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketImportPlaceholderGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketTranscriptPlaceholderGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetRootPlaceholderGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOfficialCapturePacketSetVerifyAll"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedOcuPairingPairedCandidatePreflight"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditMakeTargets"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditDefaultSummaryPath"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditCustomSummaryPath"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditIgnoresStrictSummaryVar"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenTarget"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPath"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenCustomSummaryPath"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar"
        ] is True
        assert default_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath"
        ] is True
        assert default_summary["evidence"]["standaloneSkillRepo"][
            "checkedOfficialEvidencePreflightManifest"
        ] is True
        assert default_summary["evidence"]["standaloneSkillRepo"][
            "checkedOfficialEvidenceAuditManifest"
        ] is True
        assert default_summary["evidence"]["npmStagedSkillRepo"][
            "checkedOfficialEvidencePreflightManifest"
        ] is True
        assert default_summary["evidence"]["npmStagedSkillRepo"][
            "checkedOfficialEvidenceAuditManifest"
        ] is True
        assert default_summary["status"]["officialSuccessfulRecordingGoldenComplete"] is False
        assert default_summary["status"]["missingRequiredOfficialSuccessfulRecordingScenarios"] == [
            "simple-action-stop"
        ]
        default_next_action_kinds = {
            action.get("kind") for action in default_summary["nextActions"]
        }
        assert "capture-official-successful-recording-golden" in default_next_action_kinds
        assert "capture-recommended-official-golden-set" in default_next_action_kinds
        assert "scaffold-standalone-record-and-replay-repo" in default_next_action_kinds
        assert "fix-usable-baseline-evidence" not in default_next_action_kinds
        default_next_actions_by_kind = {
            action.get("kind"): action for action in default_summary["nextActions"]
        }
        required_capture_commands = default_next_actions_by_kind[
            "capture-official-successful-recording-golden"
        ]["commands"]
        recommended_capture_commands = default_next_actions_by_kind[
            "capture-recommended-official-golden-set"
        ]["commands"]
        standalone_commands = default_next_actions_by_kind[
            "scaffold-standalone-record-and-replay-repo"
        ]["commands"]
        assert (
            "make record-and-replay-official-golden-capture-packet "
            "RNR_SCENARIO=simple-action-stop RNR_PACKET_DIR=<packet-dir>"
        ) in required_capture_commands
        assert "cd <packet-dir> && ./verify-inputs.sh" in required_capture_commands
        assert "cd <packet-dir> && ./inspect-only.sh" in required_capture_commands
        assert "cd <packet-dir> && ./import-fixture.sh" in required_capture_commands
        assert (
            "make record-and-replay-official-golden-capture-packet-set "
            "RNR_PACKET_DIR=<packet-dir>"
        ) in recommended_capture_commands
        assert "cd <packet-dir> && ./verify-all.sh" in recommended_capture_commands
        assert "cd <packet-dir> && ./inspect-all.sh" in recommended_capture_commands
        assert "cd <packet-dir> && ./import-all.sh" in recommended_capture_commands
        assert "cd <packet-dir> && ./ingest-ocu-candidates.sh" in recommended_capture_commands
        assert "make record-and-replay-baseline-audit" in standalone_commands
        assert (
            "open-computer-use scaffold-record-and-replay-skill-repo "
            "--output-dir <new-repo>"
        ) in standalone_commands
        assert "cd <new-repo> && ./scripts/check.sh" in standalone_commands
        assert "cd <new-repo> && ./scripts/recording-lifecycle-smoke.py" in standalone_commands
        fixture_root = root / "summary-next-action-fixtures"
        fixture_root.mkdir()
        required_packet_dir = root / "summary-next-action-required-packet"
        required_packet_command = shlex.split(
            required_capture_commands[0].replace("<packet-dir>", str(required_packet_dir))
        ) + [
            f"RNR_FIXTURE_ROOT={fixture_root}",
            f"RNR_OFFICIAL_PLUGIN_ROOT={root / 'missing-official-plugin'}",
            "RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1",
        ]
        required_packet_result = run(required_packet_command, repo)
        assert required_packet_result.returncode == 0, required_packet_result.stderr
        required_packet_preflight = json.loads((required_packet_dir / "preflight.json").read_text())
        required_packet_recipe = json.loads(
            (required_packet_dir / "scenario-recipe.json").read_text()
        )
        assert required_packet_preflight["stage"] == "preflight"
        assert required_packet_preflight["scenario"] == "simple-action-stop"
        assert required_packet_recipe["scenario"] == "simple-action-stop"
        assert (required_packet_dir / "verify-inputs.sh").exists()
        assert (required_packet_dir / "inspect-only.sh").exists()
        assert (required_packet_dir / "import-fixture.sh").exists()
        recommended_packet_dir = root / "summary-next-action-recommended-packet-set"
        recommended_packet_command = shlex.split(
            recommended_capture_commands[0].replace("<packet-dir>", str(recommended_packet_dir))
        ) + [
            f"RNR_FIXTURE_ROOT={fixture_root}",
            f"RNR_OFFICIAL_PLUGIN_ROOT={root / 'missing-official-plugin'}",
            "RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1",
        ]
        recommended_packet_result = run(recommended_packet_command, repo)
        assert recommended_packet_result.returncode == 0, recommended_packet_result.stderr
        recommended_packet_manifest = json.loads(
            (recommended_packet_dir / "capture-packets.json").read_text()
        )
        assert recommended_packet_manifest["stage"] == "capture-packet-set"
        assert recommended_packet_manifest["scenarios"] == [
            "simple-action-stop",
            "keyboard-input-stop",
            "drag-stop",
            "cancel",
            "timeout",
        ]
        assert (recommended_packet_dir / "verify-all.sh").exists()
        assert (recommended_packet_dir / "inspect-all.sh").exists()
        assert (recommended_packet_dir / "import-all.sh").exists()
        assert (recommended_packet_dir / "ingest-ocu-candidates.sh").exists()

        strict_missing = run(
            summary_command(script, missing_paths) + ["--require-official-golden"],
            repo,
        )
        assert strict_missing.returncode == 1
        strict_missing_summary = parse_last_json(strict_missing.stdout)
        assert strict_missing_summary["ok"] is False
        assert strict_missing_summary["status"]["usableBaseline"] is True
        assert strict_missing_summary["status"]["strictOfficialGoldenRequired"] is True
        assert strict_missing_summary["status"]["officialGoldenRequirementSatisfied"] is False
        assert strict_missing_summary["status"]["officialGoldenGatePassed"] is False
        assert "simple-action-stop" in strict_missing.stderr

        incomplete_paths = write_inputs(root / "incomplete", has_official_golden=False)
        npm_payload = json.loads(incomplete_paths["npm"].read_text())
        npm_payload["checkedSkillCreatorHandoff"] = False
        write_json(incomplete_paths["npm"], npm_payload)
        incomplete_result = run(summary_command(script, incomplete_paths), repo)
        assert incomplete_result.returncode == 1
        incomplete_summary = parse_last_json(incomplete_result.stdout)
        assert incomplete_summary["ok"] is False
        assert incomplete_summary["status"]["usableBaseline"] is False
        assert incomplete_summary["status"]["standaloneRepoBaselineReady"] is False
        assert (
            incomplete_summary["status"]["officialSuccessfulRecordingEquivalenceReady"]
            is False
        )
        assert incomplete_summary["status"]["officialGoldenRequirementSatisfied"] is True
        assert incomplete_summary["status"]["officialGoldenGatePassed"] is False
        assert "npmStagedSkillRepo.checkedSkillCreatorHandoff" in incomplete_summary["status"][
            "missingUsableBaselineEvidence"
        ]
        incomplete_next_action_kinds = {
            action.get("kind") for action in incomplete_summary["nextActions"]
        }
        assert "fix-usable-baseline-evidence" in incomplete_next_action_kinds
        assert "scaffold-standalone-record-and-replay-repo" not in incomplete_next_action_kinds
        assert "usable baseline evidence is incomplete" in incomplete_result.stderr

        action_evidence_paths = write_inputs(
            root / "action-evidence",
            has_official_golden=False,
        )
        action_records = [
            json.loads(line)
            for line in action_evidence_paths["action"].read_text().splitlines()
            if line.strip()
        ]
        action_records[0]["checkedMcpResponseShapesCaptured"] = False
        action_records[0]["checkedSkillReadinessCanCreateDraft"] = False
        action_records[0]["checkedSkillCreatorFinalizationHandoff"] = False
        action_records[0]["checkedGeneratedSkillPathRedaction"] = False
        action_records[1]["eventTypes"].remove("mouse.click")
        action_records[2]["eventTypes"].remove("mouse.drag")
        write_jsonl(action_evidence_paths["action"], action_records)
        action_evidence_result = run(summary_command(script, action_evidence_paths), repo)
        assert action_evidence_result.returncode == 1
        action_evidence_summary = parse_last_json(action_evidence_result.stdout)
        assert action_evidence_summary["status"]["usableBaseline"] is False
        assert (
            "realInputActionSmoke.checkedMcpResponseShapesCaptured"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "realInputActionSmoke.checkedSkillReadinessCanCreateDraft"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "realInputActionSmoke.checkedSkillCreatorFinalizationHandoff"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "realInputActionSmoke.checkedGeneratedSkillPathRedaction"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "realInputActionSmoke.checkedSimpleActionStopCandidate"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "realInputActionSmoke.checkedDragStopCandidate"
            in action_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )

        contract_evidence_paths = write_inputs(
            root / "contract-evidence",
            has_official_golden=False,
        )
        contract_payload = json.loads(contract_evidence_paths["baseline_contract"].read_text())
        contract_payload["checkedStandaloneLifecycleSummaryRenames"] = False
        write_json(contract_evidence_paths["baseline_contract"], contract_payload)
        contract_evidence_result = run(summary_command(script, contract_evidence_paths), repo)
        assert contract_evidence_result.returncode == 1
        contract_evidence_summary = parse_last_json(contract_evidence_result.stdout)
        assert contract_evidence_summary["status"]["usableBaseline"] is False
        assert (
            "baselineContract.checkedStandaloneLifecycleSummaryRenames"
            in contract_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )

        wait_notify_failure_paths = write_inputs(
            root / "wait-notify-failure-evidence",
            has_official_golden=False,
        )
        wait_notify_standalone_payload = json.loads(
            wait_notify_failure_paths["standalone"].read_text()
        )
        wait_notify_standalone_payload["checkedNotifyCallbackFailureExit"] = False
        wait_notify_standalone_payload["checkedNotifySuppressedEventsPathEnv"] = False
        wait_notify_standalone_payload["checkedNotifyCallbackTimeoutFailureExit"] = False
        write_json(wait_notify_failure_paths["standalone"], wait_notify_standalone_payload)
        wait_notify_npm_payload = json.loads(wait_notify_failure_paths["npm"].read_text())
        wait_notify_npm_payload["checkedNotifySuppressedEventsPathEnv"] = False
        wait_notify_npm_payload["checkedNotifyCallbackFailureReason"] = False
        wait_notify_npm_payload["checkedNotifyCallbackTimeoutReason"] = False
        write_json(wait_notify_failure_paths["npm"], wait_notify_npm_payload)
        wait_notify_failure_result = run(
            summary_command(script, wait_notify_failure_paths),
            repo,
        )
        assert wait_notify_failure_result.returncode == 1
        wait_notify_failure_summary = parse_last_json(wait_notify_failure_result.stdout)
        assert wait_notify_failure_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedNotifyCallbackFailureExit"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedNotifySuppressedEventsPathEnv"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedNotifySuppressedEventsPathEnv"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedNotifyCallbackFailureReason"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedNotifyCallbackTimeoutFailureExit"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedNotifyCallbackTimeoutReason"
            in wait_notify_failure_summary["status"]["missingUsableBaselineEvidence"]
        )

        malformed_evidence_paths = write_inputs(root / "malformed-evidence", has_official_golden=False)
        standalone_payload = json.loads(malformed_evidence_paths["standalone"].read_text())
        standalone_payload["checkedRejectedRequestsDoNotCreateSessionFiles"] = False
        write_json(malformed_evidence_paths["standalone"], standalone_payload)
        malformed_evidence_result = run(summary_command(script, malformed_evidence_paths), repo)
        assert malformed_evidence_result.returncode == 1
        malformed_evidence_summary = parse_last_json(malformed_evidence_result.stdout)
        assert malformed_evidence_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedRejectedRequestsDoNotCreateSessionFiles"
            in malformed_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )

        npm_request_shape_paths = write_inputs(root / "npm-request-shape", has_official_golden=False)
        npm_request_shape_payload = json.loads(npm_request_shape_paths["npm"].read_text())
        npm_request_shape_payload["checkedRequiresObjectParams"] = False
        write_json(npm_request_shape_paths["npm"], npm_request_shape_payload)
        npm_request_shape_result = run(summary_command(script, npm_request_shape_paths), repo)
        assert npm_request_shape_result.returncode == 1
        npm_request_shape_summary = parse_last_json(npm_request_shape_result.stdout)
        assert npm_request_shape_summary["status"]["usableBaseline"] is False
        assert (
            "npmStagedSkillRepo.checkedRequiresObjectParams"
            in npm_request_shape_summary["status"]["missingUsableBaselineEvidence"]
        )

        runtime_timeout_paths = write_inputs(
            root / "runtime-timeout-diagnostics",
            has_official_golden=False,
        )
        runtime_timeout_standalone_payload = json.loads(
            runtime_timeout_paths["standalone"].read_text()
        )
        runtime_timeout_standalone_payload["checkedRuntimeTimeoutDiagnostics"] = False
        write_json(
            runtime_timeout_paths["standalone"],
            runtime_timeout_standalone_payload,
        )
        runtime_timeout_npm_payload = json.loads(runtime_timeout_paths["npm"].read_text())
        runtime_timeout_npm_payload["checkedRuntimeTimeoutDiagnostics"] = False
        write_json(runtime_timeout_paths["npm"], runtime_timeout_npm_payload)
        runtime_timeout_result = run(summary_command(script, runtime_timeout_paths), repo)
        assert runtime_timeout_result.returncode == 1
        runtime_timeout_summary = parse_last_json(runtime_timeout_result.stdout)
        assert runtime_timeout_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedRuntimeTimeoutDiagnostics"
            in runtime_timeout_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedRuntimeTimeoutDiagnostics"
            in runtime_timeout_summary["status"]["missingUsableBaselineEvidence"]
        )

        npm_python_launcher_paths = write_inputs(
            root / "npm-python-launcher-diagnostics",
            has_official_golden=False,
        )
        npm_python_launcher_payload = json.loads(
            npm_python_launcher_paths["npm"].read_text()
        )
        npm_python_launcher_payload["checkedNpmPythonLauncherDiagnostics"] = False
        write_json(npm_python_launcher_paths["npm"], npm_python_launcher_payload)
        npm_python_launcher_result = run(
            summary_command(script, npm_python_launcher_paths),
            repo,
        )
        assert npm_python_launcher_result.returncode == 1
        npm_python_launcher_summary = parse_last_json(npm_python_launcher_result.stdout)
        assert npm_python_launcher_summary["status"]["usableBaseline"] is False
        assert (
            "npmStagedSkillRepo.checkedNpmPythonLauncherDiagnostics"
            in npm_python_launcher_summary["status"]["missingUsableBaselineEvidence"]
        )

        lifecycle_evidence_paths = write_inputs(root / "lifecycle-evidence", has_official_golden=False)
        lifecycle_payload = json.loads(lifecycle_evidence_paths["standalone"].read_text())
        lifecycle_payload["checkedOneActive"] = False
        lifecycle_payload["checkedIdempotentStop"] = False
        lifecycle_payload["checkedFinalStatus"] = False
        write_json(lifecycle_evidence_paths["standalone"], lifecycle_payload)
        lifecycle_result = run(summary_command(script, lifecycle_evidence_paths), repo)
        assert lifecycle_result.returncode == 1
        lifecycle_summary = parse_last_json(lifecycle_result.stdout)
        assert lifecycle_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedLifecycleOneActive"
            in lifecycle_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedLifecycleIdempotentStop"
            in lifecycle_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedLifecycleFinalStatus"
            in lifecycle_summary["status"]["missingUsableBaselineEvidence"]
        )

        recording_to_skill_evidence_paths = write_inputs(
            root / "recording-to-skill-evidence",
            has_official_golden=False,
        )
        recording_to_skill_payload = json.loads(
            recording_to_skill_evidence_paths["standalone"].read_text()
        )
        recording_to_skill_payload["checkedStrictValidation"] = False
        recording_to_skill_payload["checkedEventsOnlyValidation"] = False
        recording_to_skill_payload["checkedScaffoldSkill"] = False
        recording_to_skill_payload["checkedSkillCreatorHandoff"] = False
        write_json(
            recording_to_skill_evidence_paths["standalone"],
            recording_to_skill_payload,
        )
        recording_to_skill_result = run(
            summary_command(script, recording_to_skill_evidence_paths),
            repo,
        )
        assert recording_to_skill_result.returncode == 1
        recording_to_skill_summary = parse_last_json(recording_to_skill_result.stdout)
        assert recording_to_skill_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedStrictValidation"
            in recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedEventsOnlyValidation"
            in recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedScaffoldSkill"
            in recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedSkillCreatorHandoff"
            in recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )

        npm_recording_to_skill_paths = write_inputs(
            root / "npm-recording-to-skill-evidence",
            has_official_golden=False,
        )
        npm_recording_to_skill_payload = json.loads(
            npm_recording_to_skill_paths["npm"].read_text()
        )
        npm_recording_to_skill_payload["checkedStrictValidation"] = False
        npm_recording_to_skill_payload["checkedEventsOnlyValidation"] = False
        npm_recording_to_skill_payload["checkedScaffoldSkill"] = False
        write_json(npm_recording_to_skill_paths["npm"], npm_recording_to_skill_payload)
        npm_recording_to_skill_result = run(
            summary_command(script, npm_recording_to_skill_paths),
            repo,
        )
        assert npm_recording_to_skill_result.returncode == 1
        npm_recording_to_skill_summary = parse_last_json(
            npm_recording_to_skill_result.stdout
        )
        assert npm_recording_to_skill_summary["status"]["usableBaseline"] is False
        assert (
            "npmStagedSkillRepo.checkedStrictValidation"
            in npm_recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedEventsOnlyValidation"
            in npm_recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedScaffoldSkill"
            in npm_recording_to_skill_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_manifest_paths = write_inputs(
            root / "preflight-manifest",
            has_official_golden=False,
        )
        preflight_manifest_payload = json.loads(
            preflight_manifest_paths["standalone"].read_text()
        )
        preflight_manifest_payload["checkedOfficialEvidencePreflightManifest"] = False
        write_json(preflight_manifest_paths["standalone"], preflight_manifest_payload)
        preflight_manifest_result = run(
            summary_command(script, preflight_manifest_paths),
            repo,
        )
        assert preflight_manifest_result.returncode == 1
        preflight_manifest_summary = parse_last_json(preflight_manifest_result.stdout)
        assert preflight_manifest_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedOfficialEvidencePreflightManifest"
            in preflight_manifest_summary["status"]["missingUsableBaselineEvidence"]
        )

        audit_manifest_paths = write_inputs(
            root / "audit-manifest",
            has_official_golden=False,
        )
        audit_manifest_payload = json.loads(
            audit_manifest_paths["standalone"].read_text()
        )
        audit_manifest_payload["checkedOfficialEvidenceAuditManifest"] = False
        write_json(audit_manifest_paths["standalone"], audit_manifest_payload)
        audit_manifest_result = run(
            summary_command(script, audit_manifest_paths),
            repo,
        )
        assert audit_manifest_result.returncode == 1
        audit_manifest_summary = parse_last_json(audit_manifest_result.stdout)
        assert audit_manifest_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedOfficialEvidenceAuditManifest"
            in audit_manifest_summary["status"]["missingUsableBaselineEvidence"]
        )

        fixture_set_policy_paths = write_inputs(
            root / "fixture-set-policy-manifest",
            has_official_golden=False,
        )
        fixture_set_policy_payload = json.loads(
            fixture_set_policy_paths["npm"].read_text()
        )
        fixture_set_policy_payload[
            "checkedOfficialFixtureSetComparePolicyManifest"
        ] = False
        write_json(fixture_set_policy_paths["npm"], fixture_set_policy_payload)
        fixture_set_policy_result = run(
            summary_command(script, fixture_set_policy_paths),
            repo,
        )
        assert fixture_set_policy_result.returncode == 1
        fixture_set_policy_summary = parse_last_json(fixture_set_policy_result.stdout)
        assert fixture_set_policy_summary["status"]["usableBaseline"] is False
        assert (
            "npmStagedSkillRepo.checkedOfficialFixtureSetComparePolicyManifest"
            in fixture_set_policy_summary["status"]["missingUsableBaselineEvidence"]
        )

        source_summary_evidence_paths = write_inputs(
            root / "source-summary-evidence",
            has_official_golden=False,
        )
        source_summary_evidence_payload = json.loads(
            source_summary_evidence_paths["npm"].read_text()
        )
        source_summary_evidence_payload[
            "checkedSourceBaselineSummaryEvidence"
        ] = False
        write_json(
            source_summary_evidence_paths["npm"],
            source_summary_evidence_payload,
        )
        source_summary_evidence_result = run(
            summary_command(script, source_summary_evidence_paths),
            repo,
        )
        assert source_summary_evidence_result.returncode == 1
        source_summary_evidence_summary = parse_last_json(
            source_summary_evidence_result.stdout
        )
        assert source_summary_evidence_summary["status"]["usableBaseline"] is False
        assert (
            "npmStagedSkillRepo.checkedSourceBaselineSummaryEvidence"
            in source_summary_evidence_summary["status"]["missingUsableBaselineEvidence"]
        )

        source_summary_state_paths = write_inputs(
            root / "source-summary-official-state-evidence",
            has_official_golden=False,
        )
        source_summary_state_payload = json.loads(
            source_summary_state_paths["standalone"].read_text()
        )
        source_summary_state_payload[
            "checkedSourceBaselineSummaryOfficialGoldenState"
        ] = False
        write_json(
            source_summary_state_paths["standalone"],
            source_summary_state_payload,
        )
        source_summary_state_result = run(
            summary_command(script, source_summary_state_paths),
            repo,
        )
        assert source_summary_state_result.returncode == 1
        source_summary_state_summary = parse_last_json(
            source_summary_state_result.stdout
        )
        assert source_summary_state_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryOfficialGoldenState"
            in source_summary_state_summary["status"]["missingUsableBaselineEvidence"]
        )

        source_summary_session_dir_paths = write_inputs(
            root / "source-summary-session-directory-handoff",
            has_official_golden=False,
        )
        source_summary_session_dir_payload = json.loads(
            source_summary_session_dir_paths["standalone"].read_text()
        )
        source_summary_session_dir_payload[
            "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff"
        ] = False
        write_json(
            source_summary_session_dir_paths["standalone"],
            source_summary_session_dir_payload,
        )
        source_summary_session_dir_result = run(
            summary_command(script, source_summary_session_dir_paths),
            repo,
        )
        assert source_summary_session_dir_result.returncode == 1
        source_summary_session_dir_summary = parse_last_json(
            source_summary_session_dir_result.stdout
        )
        assert source_summary_session_dir_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff"
            in source_summary_session_dir_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        source_summary_contract_paths = write_inputs(
            root / "source-summary-contract-evidence",
            has_official_golden=False,
        )
        source_summary_contract_payload = json.loads(
            source_summary_contract_paths["standalone"].read_text()
        )
        source_summary_contract_payload[
            "checkedSourceBaselineSummaryCapturePacketSetContractManifest"
        ] = False
        write_json(
            source_summary_contract_paths["standalone"],
            source_summary_contract_payload,
        )
        source_summary_contract_result = run(
            summary_command(script, source_summary_contract_paths),
            repo,
        )
        assert source_summary_contract_result.returncode == 1
        source_summary_contract_summary = parse_last_json(
            source_summary_contract_result.stdout
        )
        assert source_summary_contract_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketSetContractManifest"
            in source_summary_contract_summary["status"]["missingUsableBaselineEvidence"]
        )

        source_summary_workflow_paths = write_inputs(
            root / "source-summary-post-capture-workflow-evidence",
            has_official_golden=False,
        )
        source_summary_workflow_payload = json.loads(
            source_summary_workflow_paths["standalone"].read_text()
        )
        source_summary_workflow_payload[
            "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow"
        ] = False
        source_summary_workflow_payload[
            "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier"
        ] = False
        write_json(
            source_summary_workflow_paths["standalone"],
            source_summary_workflow_payload,
        )
        source_summary_workflow_result = run(
            summary_command(script, source_summary_workflow_paths),
            repo,
        )
        assert source_summary_workflow_result.returncode == 1
        source_summary_workflow_summary = parse_last_json(
            source_summary_workflow_result.stdout
        )
        assert source_summary_workflow_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow"
            in source_summary_workflow_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketWorkflowVerifier"
            in source_summary_workflow_summary["status"]["missingUsableBaselineEvidence"]
        )

        source_summary_set_workflow_paths = write_inputs(
            root / "source-summary-packet-set-post-capture-workflow-evidence",
            has_official_golden=False,
        )
        source_summary_set_workflow_payload = json.loads(
            source_summary_set_workflow_paths["standalone"].read_text()
        )
        source_summary_set_workflow_payload[
            "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
        ] = False
        source_summary_set_workflow_payload[
            "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier"
        ] = False
        write_json(
            source_summary_set_workflow_paths["standalone"],
            source_summary_set_workflow_payload,
        )
        source_summary_set_workflow_result = run(
            summary_command(script, source_summary_set_workflow_paths),
            repo,
        )
        assert source_summary_set_workflow_result.returncode == 1
        source_summary_set_workflow_summary = parse_last_json(
            source_summary_set_workflow_result.stdout
        )
        assert source_summary_set_workflow_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
            in source_summary_set_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier"
            in source_summary_set_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        source_summary_strict_handoff_paths = write_inputs(
            root / "source-summary-strict-handoff-evidence",
            has_official_golden=False,
        )
        source_summary_strict_handoff_payload = json.loads(
            source_summary_strict_handoff_paths["standalone"].read_text()
        )
        source_summary_strict_handoff_payload[
            "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff"
        ] = False
        write_json(
            source_summary_strict_handoff_paths["standalone"],
            source_summary_strict_handoff_payload,
        )
        source_summary_strict_handoff_result = run(
            summary_command(script, source_summary_strict_handoff_paths),
            repo,
        )
        assert source_summary_strict_handoff_result.returncode == 1
        source_summary_strict_handoff_summary = parse_last_json(
            source_summary_strict_handoff_result.stdout
        )
        assert source_summary_strict_handoff_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff"
            in source_summary_strict_handoff_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        source_summary_strict_expected_failure_paths = write_inputs(
            root / "source-summary-strict-expected-failure-evidence",
            has_official_golden=False,
        )
        source_summary_strict_expected_failure_payload = json.loads(
            source_summary_strict_expected_failure_paths["standalone"].read_text()
        )
        source_summary_strict_expected_failure_payload[
            "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff"
        ] = False
        write_json(
            source_summary_strict_expected_failure_paths["standalone"],
            source_summary_strict_expected_failure_payload,
        )
        source_summary_strict_expected_failure_result = run(
            summary_command(script, source_summary_strict_expected_failure_paths),
            repo,
        )
        assert source_summary_strict_expected_failure_result.returncode == 1
        source_summary_strict_expected_failure_summary = parse_last_json(
            source_summary_strict_expected_failure_result.stdout
        )
        assert (
            source_summary_strict_expected_failure_summary["status"]["usableBaseline"]
            is False
        )
        assert (
            "standaloneSkillRepo.checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff"
            in source_summary_strict_expected_failure_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        manifest_contract_paths = write_inputs(
            root / "manifest-contract",
            has_official_golden=False,
        )
        manifest_contract_standalone = json.loads(
            manifest_contract_paths["standalone"].read_text()
        )
        manifest_contract_npm = json.loads(manifest_contract_paths["npm"].read_text())
        manifest_contract_standalone["checkedManifestContract"] = False
        manifest_contract_npm["checkedManifestContract"] = False
        write_json(manifest_contract_paths["standalone"], manifest_contract_standalone)
        write_json(manifest_contract_paths["npm"], manifest_contract_npm)
        manifest_contract_result = run(
            summary_command(script, manifest_contract_paths),
            repo,
        )
        assert manifest_contract_result.returncode == 1
        manifest_contract_summary = parse_last_json(manifest_contract_result.stdout)
        assert manifest_contract_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedManifestContract"
            in manifest_contract_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedManifestContract"
            in manifest_contract_summary["status"]["missingUsableBaselineEvidence"]
        )

        readme_scenario_paths = write_inputs(
            root / "readme-scenario-list",
            has_official_golden=False,
        )
        readme_standalone_payload = json.loads(
            readme_scenario_paths["standalone"].read_text()
        )
        readme_npm_payload = json.loads(readme_scenario_paths["npm"].read_text())
        readme_standalone_payload["checkedGeneratedReadmeScenarioList"] = False
        readme_standalone_payload["checkedGeneratedReadmePrerequisites"] = False
        readme_npm_payload["checkedGeneratedReadmeScenarioList"] = False
        readme_npm_payload["checkedGeneratedReadmePrerequisites"] = False
        write_json(readme_scenario_paths["standalone"], readme_standalone_payload)
        write_json(readme_scenario_paths["npm"], readme_npm_payload)
        readme_scenario_result = run(summary_command(script, readme_scenario_paths), repo)
        assert readme_scenario_result.returncode == 1
        readme_scenario_summary = parse_last_json(readme_scenario_result.stdout)
        assert readme_scenario_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedGeneratedReadmeScenarioList"
            in readme_scenario_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedGeneratedReadmePrerequisites"
            in readme_scenario_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedGeneratedReadmeScenarioList"
            in readme_scenario_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedGeneratedReadmePrerequisites"
            in readme_scenario_summary["status"]["missingUsableBaselineEvidence"]
        )

        readme_handoff_paths = write_inputs(
            root / "readme-handoff-contract",
            has_official_golden=False,
        )
        readme_handoff_standalone = json.loads(
            readme_handoff_paths["standalone"].read_text()
        )
        readme_handoff_npm = json.loads(readme_handoff_paths["npm"].read_text())
        for key in [
            "checkedReadmeHandoffContract",
            "checkedReadmeOfficialEvidenceHandoff",
            "checkedReadmeOfficialGoldenGap",
            "checkedReadmeWaitNotifyBoundary",
        ]:
            readme_handoff_standalone[key] = False
            readme_handoff_npm[key] = False
        write_json(readme_handoff_paths["standalone"], readme_handoff_standalone)
        write_json(readme_handoff_paths["npm"], readme_handoff_npm)
        readme_handoff_result = run(summary_command(script, readme_handoff_paths), repo)
        assert readme_handoff_result.returncode == 1
        readme_handoff_summary = parse_last_json(readme_handoff_result.stdout)
        assert readme_handoff_summary["status"]["usableBaseline"] is False
        assert (
            "standaloneSkillRepo.checkedReadmeHandoffContract"
            in readme_handoff_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "standaloneSkillRepo.checkedReadmeOfficialGoldenGap"
            in readme_handoff_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedReadmeOfficialEvidenceHandoff"
            in readme_handoff_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "npmStagedSkillRepo.checkedReadmeWaitNotifyBoundary"
            in readme_handoff_summary["status"]["missingUsableBaselineEvidence"]
        )

        audit_target_paths = write_inputs(
            root / "audit-targets",
            has_official_golden=False,
        )
        audit_target_payload = json.loads(
            audit_target_paths["baseline_audit_targets"].read_text()
        )
        audit_target_payload["checkedBaselineAuditMakeTarget"] = False
        audit_target_payload["checkedBaselineAuditCustomSummaryPath"] = False
        audit_target_payload["checkedBaselineAuditIgnoresStrictSummaryVar"] = False
        audit_target_payload["checkedStrictOfficialGoldenAuditMakeTarget"] = False
        audit_target_payload[
            "checkedStrictOfficialGoldenAuditIgnoresBaselineSummaryVar"
        ] = False
        audit_target_payload[
            "checkedStrictOfficialGoldenAuditSeparateSummaryPath"
        ] = False
        write_json(audit_target_paths["baseline_audit_targets"], audit_target_payload)
        audit_target_result = run(summary_command(script, audit_target_paths), repo)
        assert audit_target_result.returncode == 1
        audit_target_summary = parse_last_json(audit_target_result.stdout)
        assert audit_target_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedBaselineAuditMakeTargets"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "preflightPipelines.checkedBaselineAuditCustomSummaryPath"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "preflightPipelines.checkedBaselineAuditIgnoresStrictSummaryVar"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "preflightPipelines.checkedBaselineAuditStrictOfficialGoldenTarget"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "preflightPipelines.checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )
        assert (
            "preflightPipelines.checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath"
            in audit_target_summary["status"]["missingUsableBaselineEvidence"]
        )

        raw_timeout_paths = write_inputs(root / "raw-timeout", has_official_golden=False)
        raw_timeout_payload = json.loads(raw_timeout_paths["raw_timeout"].read_text())
        raw_timeout_payload["checkedOfficialRawStartDoesNotReturnRecordingPaths"] = False
        write_json(raw_timeout_paths["raw_timeout"], raw_timeout_payload)
        raw_timeout_result = run(summary_command(script, raw_timeout_paths), repo)
        assert raw_timeout_result.returncode == 1
        raw_timeout_summary = parse_last_json(raw_timeout_result.stdout)
        assert raw_timeout_summary["status"]["usableBaseline"] is False
        assert raw_timeout_summary["status"]["officialRawStartTimeoutBoundaryVerified"] is False
        assert (
            "officialRawStartTimeout.checkedOfficialRawStartDoesNotReturnRecordingPaths"
            in raw_timeout_summary["status"]["missingUsableBaselineEvidence"]
        )

        candidate_handoff_paths = write_inputs(
            root / "candidate-handoff",
            has_official_golden=False,
        )
        candidate_handoff_payload = json.loads(
            candidate_handoff_paths["candidate_ingest"].read_text()
        )
        candidate_handoff_payload["checkedCandidateIngestHandoffCommands"] = False
        write_json(candidate_handoff_paths["candidate_ingest"], candidate_handoff_payload)
        candidate_handoff_result = run(
            summary_command(script, candidate_handoff_paths),
            repo,
        )
        assert candidate_handoff_result.returncode == 1
        candidate_handoff_summary = parse_last_json(candidate_handoff_result.stdout)
        assert candidate_handoff_summary["status"]["usableBaseline"] is False
        assert (
            "fixtureIngestPipelines.checkedOcuCandidateIngestHandoffCommands"
            in candidate_handoff_summary["status"]["missingUsableBaselineEvidence"]
        )

        official_session_dir_paths = write_inputs(
            root / "official-session-directory-handoff",
            has_official_golden=False,
        )
        official_session_dir_payload = json.loads(
            official_session_dir_paths["official_ingest"].read_text()
        )
        official_session_dir_payload["checkedOfficialSessionDirectoryPathHandoff"] = False
        write_json(official_session_dir_paths["official_ingest"], official_session_dir_payload)
        official_session_dir_result = run(
            summary_command(script, official_session_dir_paths),
            repo,
        )
        assert official_session_dir_result.returncode == 1
        official_session_dir_summary = parse_last_json(official_session_dir_result.stdout)
        assert official_session_dir_summary["status"]["usableBaseline"] is False
        assert (
            "fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff"
            in official_session_dir_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_paths = write_inputs(root / "preflight", has_official_golden=False)
        preflight_payload = json.loads(preflight_paths["official_capture_preflight"].read_text())
        preflight_payload["checkedCapturePacketSet"] = False
        write_json(preflight_paths["official_capture_preflight"], preflight_payload)
        preflight_result = run(summary_command(script, preflight_paths), repo)
        assert preflight_result.returncode == 1
        preflight_summary = parse_last_json(preflight_result.stdout)
        assert preflight_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSet"
            in preflight_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_packet_no_transcript_paths = write_inputs(
            root / "preflight-no-transcript-packet",
            has_official_golden=False,
        )
        preflight_packet_no_transcript_payload = json.loads(
            preflight_packet_no_transcript_paths["official_capture_preflight"].read_text()
        )
        preflight_packet_no_transcript_payload["checkedCapturePacketNoTranscript"] = False
        write_json(
            preflight_packet_no_transcript_paths["official_capture_preflight"],
            preflight_packet_no_transcript_payload,
        )
        preflight_packet_no_transcript_result = run(
            summary_command(script, preflight_packet_no_transcript_paths),
            repo,
        )
        assert preflight_packet_no_transcript_result.returncode == 1
        preflight_packet_no_transcript_summary = parse_last_json(
            preflight_packet_no_transcript_result.stdout
        )
        assert preflight_packet_no_transcript_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketNoTranscript"
            in preflight_packet_no_transcript_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_handoff_scripts_paths = write_inputs(
            root / "preflight-handoff-scripts",
            has_official_golden=False,
        )
        preflight_handoff_scripts_payload = json.loads(
            preflight_handoff_scripts_paths["official_capture_preflight"].read_text()
        )
        preflight_handoff_scripts_payload["checkedCapturePacketHandoffScripts"] = False
        write_json(
            preflight_handoff_scripts_paths["official_capture_preflight"],
            preflight_handoff_scripts_payload,
        )
        preflight_handoff_scripts_result = run(
            summary_command(script, preflight_handoff_scripts_paths),
            repo,
        )
        assert preflight_handoff_scripts_result.returncode == 1
        preflight_handoff_scripts_summary = parse_last_json(
            preflight_handoff_scripts_result.stdout
        )
        assert preflight_handoff_scripts_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketHandoffScripts"
            in preflight_handoff_scripts_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_strict_audit_handoff_paths = write_inputs(
            root / "preflight-strict-audit-handoff",
            has_official_golden=False,
        )
        preflight_strict_audit_handoff_payload = json.loads(
            preflight_strict_audit_handoff_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_strict_audit_handoff_payload[
            "checkedCapturePacketStrictAuditHandoff"
        ] = False
        write_json(
            preflight_strict_audit_handoff_paths["official_capture_preflight"],
            preflight_strict_audit_handoff_payload,
        )
        preflight_strict_audit_handoff_result = run(
            summary_command(script, preflight_strict_audit_handoff_paths),
            repo,
        )
        assert preflight_strict_audit_handoff_result.returncode == 1
        preflight_strict_audit_handoff_summary = parse_last_json(
            preflight_strict_audit_handoff_result.stdout
        )
        assert (
            preflight_strict_audit_handoff_summary["status"]["usableBaseline"]
            is False
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff"
            in preflight_strict_audit_handoff_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_strict_expected_failure_handoff_paths = write_inputs(
            root / "preflight-strict-expected-failure-handoff",
            has_official_golden=False,
        )
        preflight_strict_expected_failure_handoff_payload = json.loads(
            preflight_strict_expected_failure_handoff_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_strict_expected_failure_handoff_payload[
            "checkedCapturePacketStrictExpectedFailureAuditHandoff"
        ] = False
        write_json(
            preflight_strict_expected_failure_handoff_paths[
                "official_capture_preflight"
            ],
            preflight_strict_expected_failure_handoff_payload,
        )
        preflight_strict_expected_failure_handoff_result = run(
            summary_command(script, preflight_strict_expected_failure_handoff_paths),
            repo,
        )
        assert preflight_strict_expected_failure_handoff_result.returncode == 1
        preflight_strict_expected_failure_handoff_summary = parse_last_json(
            preflight_strict_expected_failure_handoff_result.stdout
        )
        assert (
            preflight_strict_expected_failure_handoff_summary["status"][
                "usableBaseline"
            ]
            is False
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
            in preflight_strict_expected_failure_handoff_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_ocu_candidate_output_dir_paths = write_inputs(
            root / "preflight-ocu-candidate-output-dir",
            has_official_golden=False,
        )
        preflight_ocu_candidate_output_dir_payload = json.loads(
            preflight_ocu_candidate_output_dir_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_ocu_candidate_output_dir_payload[
            "checkedCapturePacketOcuCandidateOutputDir"
        ] = False
        write_json(
            preflight_ocu_candidate_output_dir_paths["official_capture_preflight"],
            preflight_ocu_candidate_output_dir_payload,
        )
        preflight_ocu_candidate_output_dir_result = run(
            summary_command(script, preflight_ocu_candidate_output_dir_paths),
            repo,
        )
        assert preflight_ocu_candidate_output_dir_result.returncode == 1
        preflight_ocu_candidate_output_dir_summary = parse_last_json(
            preflight_ocu_candidate_output_dir_result.stdout
        )
        assert (
            preflight_ocu_candidate_output_dir_summary["status"]["usableBaseline"]
            is False
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketOcuCandidateOutputDir"
            in preflight_ocu_candidate_output_dir_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_no_transcript_paths = write_inputs(
            root / "preflight-no-transcript-packet-set",
            has_official_golden=False,
        )
        preflight_no_transcript_payload = json.loads(
            preflight_no_transcript_paths["official_capture_preflight"].read_text()
        )
        preflight_no_transcript_payload["checkedCapturePacketSetNoTranscript"] = False
        write_json(
            preflight_no_transcript_paths["official_capture_preflight"],
            preflight_no_transcript_payload,
        )
        preflight_no_transcript_result = run(
            summary_command(script, preflight_no_transcript_paths),
            repo,
        )
        assert preflight_no_transcript_result.returncode == 1
        preflight_no_transcript_summary = parse_last_json(preflight_no_transcript_result.stdout)
        assert preflight_no_transcript_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetNoTranscript"
            in preflight_no_transcript_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_set_candidate_handoff_paths = write_inputs(
            root / "preflight-set-candidate-handoff",
            has_official_golden=False,
        )
        preflight_set_candidate_handoff_payload = json.loads(
            preflight_set_candidate_handoff_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_set_candidate_handoff_payload[
            "checkedCapturePacketSetOcuCandidateHandoff"
        ] = False
        write_json(
            preflight_set_candidate_handoff_paths["official_capture_preflight"],
            preflight_set_candidate_handoff_payload,
        )
        preflight_set_candidate_handoff_result = run(
            summary_command(script, preflight_set_candidate_handoff_paths),
            repo,
        )
        assert preflight_set_candidate_handoff_result.returncode == 1
        preflight_set_candidate_handoff_summary = parse_last_json(
            preflight_set_candidate_handoff_result.stdout
        )
        assert (
            preflight_set_candidate_handoff_summary["status"]["usableBaseline"]
            is False
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetOcuCandidateHandoff"
            in preflight_set_candidate_handoff_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_set_contract_paths = write_inputs(
            root / "preflight-set-contract-manifest",
            has_official_golden=False,
        )
        preflight_set_contract_payload = json.loads(
            preflight_set_contract_paths["official_capture_preflight"].read_text()
        )
        preflight_set_contract_payload["checkedCapturePacketSetContractManifest"] = False
        write_json(
            preflight_set_contract_paths["official_capture_preflight"],
            preflight_set_contract_payload,
        )
        preflight_set_contract_result = run(
            summary_command(script, preflight_set_contract_paths),
            repo,
        )
        assert preflight_set_contract_result.returncode == 1
        preflight_set_contract_summary = parse_last_json(
            preflight_set_contract_result.stdout
        )
        assert preflight_set_contract_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetContractManifest"
            in preflight_set_contract_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_packet_workflow_paths = write_inputs(
            root / "preflight-packet-workflow",
            has_official_golden=False,
        )
        preflight_packet_workflow_payload = json.loads(
            preflight_packet_workflow_paths["official_capture_preflight"].read_text()
        )
        preflight_packet_workflow_payload["checkedCapturePacketPostCaptureWorkflow"] = False
        preflight_packet_workflow_payload["checkedCapturePacketWorkflowVerifier"] = False
        write_json(
            preflight_packet_workflow_paths["official_capture_preflight"],
            preflight_packet_workflow_payload,
        )
        preflight_packet_workflow_result = run(
            summary_command(script, preflight_packet_workflow_paths),
            repo,
        )
        assert preflight_packet_workflow_result.returncode == 1
        preflight_packet_workflow_summary = parse_last_json(
            preflight_packet_workflow_result.stdout
        )
        assert preflight_packet_workflow_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow"
            in preflight_packet_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketWorkflowVerifier"
            in preflight_packet_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_packet_set_workflow_paths = write_inputs(
            root / "preflight-packet-set-workflow",
            has_official_golden=False,
        )
        preflight_packet_set_workflow_payload = json.loads(
            preflight_packet_set_workflow_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_packet_set_workflow_payload[
            "checkedCapturePacketSetPostCaptureWorkflow"
        ] = False
        preflight_packet_set_workflow_payload[
            "checkedCapturePacketSetWorkflowVerifier"
        ] = False
        write_json(
            preflight_packet_set_workflow_paths["official_capture_preflight"],
            preflight_packet_set_workflow_payload,
        )
        preflight_packet_set_workflow_result = run(
            summary_command(script, preflight_packet_set_workflow_paths),
            repo,
        )
        assert preflight_packet_set_workflow_result.returncode == 1
        preflight_packet_set_workflow_summary = parse_last_json(
            preflight_packet_set_workflow_result.stdout
        )
        assert preflight_packet_set_workflow_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow"
            in preflight_packet_set_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetWorkflowVerifier"
            in preflight_packet_set_workflow_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_manifest_paths = write_inputs(
            root / "preflight-transcript-manifest",
            has_official_golden=False,
        )
        preflight_manifest_payload = json.loads(
            preflight_manifest_paths["official_capture_preflight"].read_text()
        )
        preflight_manifest_payload["checkedCapturePacketTranscriptManifest"] = False
        write_json(
            preflight_manifest_paths["official_capture_preflight"],
            preflight_manifest_payload,
        )
        preflight_manifest_result = run(
            summary_command(script, preflight_manifest_paths),
            repo,
        )
        assert preflight_manifest_result.returncode == 1
        preflight_manifest_summary = parse_last_json(preflight_manifest_result.stdout)
        assert preflight_manifest_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketTranscriptManifest"
            in preflight_manifest_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_make_paths = write_inputs(
            root / "preflight-make-targets",
            has_official_golden=False,
        )
        preflight_make_payload = json.loads(
            preflight_make_paths["official_capture_preflight"].read_text()
        )
        preflight_make_payload["checkedMakeCapturePacketTargets"] = False
        write_json(
            preflight_make_paths["official_capture_preflight"],
            preflight_make_payload,
        )
        preflight_make_result = run(summary_command(script, preflight_make_paths), repo)
        assert preflight_make_result.returncode == 1
        preflight_make_summary = parse_last_json(preflight_make_result.stdout)
        assert preflight_make_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketMakeTargets"
            in preflight_make_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_semantic_paths = write_inputs(
            root / "preflight-semantic-guard",
            has_official_golden=False,
        )
        preflight_semantic_payload = json.loads(
            preflight_semantic_paths["official_capture_preflight"].read_text()
        )
        preflight_semantic_payload["checkedCapturePacketInputSemanticGuard"] = False
        write_json(
            preflight_semantic_paths["official_capture_preflight"],
            preflight_semantic_payload,
        )
        preflight_semantic_result = run(
            summary_command(script, preflight_semantic_paths),
            repo,
        )
        assert preflight_semantic_result.returncode == 1
        preflight_semantic_summary = parse_last_json(preflight_semantic_result.stdout)
        assert preflight_semantic_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketInputSemanticGuard"
            in preflight_semantic_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_verify_paths = write_inputs(
            root / "preflight-verify-inputs",
            has_official_golden=False,
        )
        preflight_verify_payload = json.loads(
            preflight_verify_paths["official_capture_preflight"].read_text()
        )
        preflight_verify_payload["checkedCapturePacketVerifyInputs"] = False
        write_json(
            preflight_verify_paths["official_capture_preflight"],
            preflight_verify_payload,
        )
        preflight_verify_result = run(
            summary_command(script, preflight_verify_paths),
            repo,
        )
        assert preflight_verify_result.returncode == 1
        preflight_verify_summary = parse_last_json(preflight_verify_result.stdout)
        assert preflight_verify_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketVerifyInputs"
            in preflight_verify_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_import_guard_paths = write_inputs(
            root / "preflight-import-guard",
            has_official_golden=False,
        )
        preflight_import_guard_payload = json.loads(
            preflight_import_guard_paths["official_capture_preflight"].read_text()
        )
        preflight_import_guard_payload[
            "checkedCapturePacketImportPlaceholderGuard"
        ] = False
        write_json(
            preflight_import_guard_paths["official_capture_preflight"],
            preflight_import_guard_payload,
        )
        preflight_import_guard_result = run(
            summary_command(script, preflight_import_guard_paths),
            repo,
        )
        assert preflight_import_guard_result.returncode == 1
        preflight_import_guard_summary = parse_last_json(
            preflight_import_guard_result.stdout
        )
        assert preflight_import_guard_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketImportPlaceholderGuard"
            in preflight_import_guard_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_set_guard_paths = write_inputs(
            root / "preflight-set-guard",
            has_official_golden=False,
        )
        preflight_set_guard_payload = json.loads(
            preflight_set_guard_paths["official_capture_preflight"].read_text()
        )
        preflight_set_guard_payload["checkedCapturePacketSetRootPlaceholderGuard"] = False
        write_json(
            preflight_set_guard_paths["official_capture_preflight"],
            preflight_set_guard_payload,
        )
        preflight_set_guard_result = run(
            summary_command(script, preflight_set_guard_paths),
            repo,
        )
        assert preflight_set_guard_result.returncode == 1
        preflight_set_guard_summary = parse_last_json(preflight_set_guard_result.stdout)
        assert preflight_set_guard_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetRootPlaceholderGuard"
            in preflight_set_guard_summary["status"]["missingUsableBaselineEvidence"]
        )

        preflight_set_preflight_guard_paths = write_inputs(
            root / "preflight-set-preflight-guard",
            has_official_golden=False,
        )
        preflight_set_preflight_guard_payload = json.loads(
            preflight_set_preflight_guard_paths[
                "official_capture_preflight"
            ].read_text()
        )
        preflight_set_preflight_guard_payload[
            "checkedCapturePacketSetRootPreflightPlaceholderGuard"
        ] = False
        write_json(
            preflight_set_preflight_guard_paths["official_capture_preflight"],
            preflight_set_preflight_guard_payload,
        )
        preflight_set_preflight_guard_result = run(
            summary_command(script, preflight_set_preflight_guard_paths),
            repo,
        )
        assert preflight_set_preflight_guard_result.returncode == 1
        preflight_set_preflight_guard_summary = parse_last_json(
            preflight_set_preflight_guard_result.stdout
        )
        assert (
            preflight_set_preflight_guard_summary["status"]["usableBaseline"]
            is False
        )
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard"
            in preflight_set_preflight_guard_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        preflight_set_verify_paths = write_inputs(
            root / "preflight-set-verify-all",
            has_official_golden=False,
        )
        preflight_set_verify_payload = json.loads(
            preflight_set_verify_paths["official_capture_preflight"].read_text()
        )
        preflight_set_verify_payload["checkedCapturePacketSetVerifyAll"] = False
        write_json(
            preflight_set_verify_paths["official_capture_preflight"],
            preflight_set_verify_payload,
        )
        preflight_set_verify_result = run(
            summary_command(script, preflight_set_verify_paths),
            repo,
        )
        assert preflight_set_verify_result.returncode == 1
        preflight_set_verify_summary = parse_last_json(
            preflight_set_verify_result.stdout
        )
        assert preflight_set_verify_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOfficialCapturePacketSetVerifyAll"
            in preflight_set_verify_summary["status"][
                "missingUsableBaselineEvidence"
            ]
        )

        pairing_preflight_paths = write_inputs(
            root / "pairing-preflight",
            has_official_golden=False,
        )
        pairing_preflight_payload = json.loads(
            pairing_preflight_paths["ocu_pairing_preflight"].read_text()
        )
        pairing_preflight_payload["checkedPairedCandidatePreflight"] = False
        write_json(pairing_preflight_paths["ocu_pairing_preflight"], pairing_preflight_payload)
        pairing_preflight_result = run(summary_command(script, pairing_preflight_paths), repo)
        assert pairing_preflight_result.returncode == 1
        pairing_preflight_summary = parse_last_json(pairing_preflight_result.stdout)
        assert pairing_preflight_summary["status"]["usableBaseline"] is False
        assert (
            "preflightPipelines.checkedOcuPairingPairedCandidatePreflight"
            in pairing_preflight_summary["status"]["missingUsableBaselineEvidence"]
        )

        not_ready_paths = write_inputs(root / "not-ready", has_official_golden=True)
        coverage_payload = json.loads(not_ready_paths["coverage"].read_text())
        coverage_payload["coverageOk"] = False
        coverage_payload["hasRequiredOfficialSuccessfulFixture"] = False
        coverage_payload["requiredOfficialReadinessOk"] = False
        coverage_payload["missingOfficialScenarios"] = []
        coverage_payload["notReadyOfficialScenarios"] = ["simple-action-stop"]
        coverage_payload["availableOfficialScenarios"] = ["simple-action-stop"]
        write_json(not_ready_paths["coverage"], coverage_payload)
        strict_not_ready = run(
            summary_command(script, not_ready_paths) + ["--require-official-golden"],
            repo,
        )
        assert strict_not_ready.returncode == 1
        strict_not_ready_summary = parse_last_json(strict_not_ready.stdout)
        assert strict_not_ready_summary["status"]["officialSuccessfulRecordingGoldenComplete"] is False
        assert strict_not_ready_summary["status"]["officialGoldenGatePassed"] is False
        assert strict_not_ready_summary["status"][
            "notReadyRequiredOfficialSuccessfulRecordingScenarios"
        ] == ["simple-action-stop"]
        assert "notReady=simple-action-stop" in strict_not_ready.stderr

        coverage_error_paths = write_inputs(root / "coverage-error", has_official_golden=True)
        coverage_error_payload = json.loads(coverage_error_paths["coverage"].read_text())
        coverage_error_payload["coverageOk"] = False
        coverage_error_payload["scenarioCoverageOk"] = False
        coverage_error_payload["hasRequiredOfficialSuccessfulFixture"] = False
        coverage_error_payload["requiredOfficialReadinessOk"] = False
        coverage_error_payload["missingOfficialScenarios"] = []
        coverage_error_payload["notReadyOfficialScenarios"] = []
        coverage_error_payload["availableOfficialScenarios"] = ["simple-action-stop"]
        coverage_error_payload["errors"] = [
            "official-action: fixture-manifest.json scenarioRecipe does not match scenario 'simple-action-stop'"
        ]
        write_json(coverage_error_paths["coverage"], coverage_error_payload)
        strict_coverage_error = run(
            summary_command(script, coverage_error_paths) + ["--require-official-golden"],
            repo,
        )
        assert strict_coverage_error.returncode == 1
        strict_coverage_error_summary = parse_last_json(strict_coverage_error.stdout)
        assert strict_coverage_error_summary["status"][
            "officialSuccessfulRecordingGoldenComplete"
        ] is False
        assert strict_coverage_error_summary["status"]["officialGoldenGatePassed"] is False
        assert strict_coverage_error_summary["status"]["officialFixtureCoverageErrors"] == [
            "official-action: fixture-manifest.json scenarioRecipe does not match scenario 'simple-action-stop'"
        ]
        assert strict_coverage_error_summary["evidence"]["officialFixtureSetGate"][
            "coverageErrors"
        ] == strict_coverage_error_summary["status"]["officialFixtureCoverageErrors"]
        assert "coverageErrors=official-action: fixture-manifest.json scenarioRecipe" in (
            strict_coverage_error.stderr
        )

        covered_paths = write_inputs(root / "covered", has_official_golden=True)
        strict_covered = run(
            summary_command(script, covered_paths) + ["--require-official-golden"],
            repo,
        )
        assert strict_covered.returncode == 0, strict_covered.stderr
        strict_covered_summary = parse_last_json(strict_covered.stdout)
        assert strict_covered_summary["ok"] is True
        assert strict_covered_summary["status"]["strictOfficialGoldenRequired"] is True
        assert strict_covered_summary["status"]["officialGoldenRequirementSatisfied"] is True
        assert strict_covered_summary["status"]["officialGoldenGatePassed"] is True
        assert strict_covered_summary["status"]["officialSuccessfulRecordingGoldenComplete"] is True
        assert strict_covered_summary["status"]["standaloneRepoBaselineReady"] is True
        assert (
            strict_covered_summary["status"]["officialSuccessfulRecordingEquivalenceReady"]
            is True
        )
        strict_covered_next_action_kinds = {
            action.get("kind") for action in strict_covered_summary["nextActions"]
        }
        assert "capture-official-successful-recording-golden" not in (
            strict_covered_next_action_kinds
        )
        assert "scaffold-standalone-record-and-replay-repo" in (
            strict_covered_next_action_kinds
        )

    print(
        json.dumps(
            {
                "ok": True,
                "checkedDefaultAllowsMissingOfficialGolden": True,
                "checkedIncompleteUsableBaselineEvidenceFails": True,
                "checkedRealInputActionConcreteEvidence": True,
                "checkedWaitNotifyCallbackFailureEvidence": True,
                "checkedWaitNotifyCallbackTimeoutEvidence": True,
                "checkedRuntimeTimeoutDiagnosticsEvidence": True,
                "checkedNpmPythonLauncherDiagnosticsEvidence": True,
                "checkedGeneratedReadmePrerequisitesEvidence": True,
                "checkedReadmeHandoffContractEvidence": True,
                "checkedCapturePacketHandoffScriptsEvidence": True,
                "checkedCapturePacketStrictAuditHandoffEvidence": True,
                "checkedCapturePacketOcuCandidateOutputDirEvidence": True,
                "checkedCapturePacketSetOcuCandidateHandoffEvidence": True,
                "checkedCandidateIngestHandoffCommandsEvidence": True,
                "checkedStandaloneLifecycleSemanticsEvidence": True,
                "checkedStandaloneRecordingToSkillConcreteEvidence": True,
                "checkedNpmRecordingToSkillConcreteEvidence": True,
                "checkedBaselineAuditTargetEvidence": True,
                "checkedStrictCoverageErrorsReported": True,
                "checkedStrictNotReadyOfficialGoldenFails": True,
                "checkedStrictMissingOfficialGoldenFails": True,
                "checkedStrictCoveredOfficialGoldenPasses": True,
                "checkedNextActionPacketCommandsGeneratePackets": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
