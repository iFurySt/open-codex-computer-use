#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys
from typing import Any

from record_and_replay_baseline_contract import (
    NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
    REQUIRED_BASELINE_CHECKS,
    STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
)

REQUIRED_BASELINE_CHECK_SET = set(REQUIRED_BASELINE_CHECKS)


def load_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def bool_at(root: dict[str, Any], *path: str) -> bool:
    value: Any = root
    for key in path:
        if not isinstance(value, dict):
            return False
        value = value.get(key)
    return value is True


def list_at(root: dict[str, Any], *path: str) -> list[Any]:
    value: Any = root
    for key in path:
        if not isinstance(value, dict):
            return []
        value = value.get(key)
    return value if isinstance(value, list) else []


def string_set_at(root: dict[str, Any], *path: str) -> set[str]:
    return {item for item in list_at(root, *path) if isinstance(item, str)}


def duplicate_strings_at(root: dict[str, Any], *path: str) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for item in list_at(root, *path):
        if not isinstance(item, str):
            continue
        if item in seen:
            duplicates.add(item)
        seen.add(item)
    return sorted(duplicates)


def next_action_kinds(summary: dict[str, Any]) -> set[str]:
    actions = summary.get("nextActions")
    if not isinstance(actions, list):
        return set()
    return {
        action.get("kind")
        for action in actions
        if isinstance(action, dict) and isinstance(action.get("kind"), str)
    }


def next_action_commands(summary: dict[str, Any], kind: str) -> list[str]:
    actions = summary.get("nextActions")
    if not isinstance(actions, list):
        return []
    commands: list[str] = []
    for action in actions:
        if not isinstance(action, dict) or action.get("kind") != kind:
            continue
        value = action.get("commands")
        if not isinstance(value, list):
            continue
        commands.extend(command for command in value if isinstance(command, str))
    return commands


def has_command_containing(commands: list[str], *needles: str) -> bool:
    return any(all(needle in command for needle in needles) for command in commands)


def upper_camel(value: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in value.split("_") if part)


def evidence_check_name(prefix: str, key: str) -> str:
    return f"checked{prefix}{upper_camel(key)}Evidence"


def check_summary(
    summary: dict[str, Any],
    require_official_golden: bool,
    allow_strict_official_golden_missing: bool = False,
) -> dict[str, Any]:
    status = summary.get("status")
    if not isinstance(status, dict):
        return {
            "ok": False,
            "failures": ["missing status object"],
            "checks": {},
        }

    declared_checks = string_set_at(summary, "checks")
    missing_declared_checks = sorted(REQUIRED_BASELINE_CHECK_SET - declared_checks)
    unknown_declared_checks = sorted(declared_checks - REQUIRED_BASELINE_CHECK_SET)
    duplicate_declared_checks = duplicate_strings_at(summary, "checks")
    actions = next_action_kinds(summary)
    required_capture_commands = next_action_commands(
        summary,
        "capture-official-successful-recording-golden",
    )
    recommended_capture_commands = next_action_commands(
        summary,
        "capture-recommended-official-golden-set",
    )
    standalone_commands = next_action_commands(
        summary,
        "scaffold-standalone-record-and-replay-repo",
    )
    missing_golden = not bool_at(
        summary, "status", "officialSuccessfulRecordingGoldenComplete"
    )
    required_gaps = list_at(
        summary,
        "status",
        "missingRequiredOfficialSuccessfulRecordingScenarios",
    )
    not_ready_required = list_at(
        summary,
        "status",
        "notReadyRequiredOfficialSuccessfulRecordingScenarios",
    )
    coverage_errors = list_at(summary, "status", "officialFixtureCoverageErrors")
    missing_recommended_golden = bool(
        list_at(summary, "status", "missingRecommendedOfficialSuccessfulRecordingScenarios")
    )
    strict_mode_expected = (
        require_official_golden or allow_strict_official_golden_missing
    )
    official_golden_requirement_satisfied = bool_at(
        summary, "status", "officialGoldenRequirementSatisfied"
    )
    expected_equivalence_ready = (
        bool_at(summary, "status", "usableBaseline")
        and bool_at(summary, "status", "officialSuccessfulRecordingGoldenComplete")
    )
    standalone_ready = bool_at(summary, "status", "standaloneRepoBaselineReady")
    expected_top_level_ok = (
        bool_at(summary, "status", "usableBaseline")
        and bool_at(summary, "status", "officialGoldenRequirementSatisfied")
    )
    failures: list[str] = []
    checks = {
        "checkedBaselineName": summary.get("baseline") == "record-and-replay",
        "checkedTopLevelOkMatchesPolicy": summary.get("ok") is expected_top_level_ok,
        "checkedRequiredBaselineChecksDeclared": not missing_declared_checks,
        "checkedNoUnknownBaselineChecksDeclared": not unknown_declared_checks,
        "checkedNoDuplicateBaselineChecksDeclared": not duplicate_declared_checks,
        "checkedUsableBaseline": bool_at(summary, "status", "usableBaseline"),
        "checkedNoMissingUsableBaselineEvidence": (
            list_at(summary, "status", "missingUsableBaselineEvidence") == []
        ),
        "checkedStandaloneRepoBaselineReady": bool_at(
            summary, "status", "standaloneRepoBaselineReady"
        ),
        "checkedOfficialNonRecordingBaselineVerified": bool_at(
            summary, "status", "officialNonRecordingBaselineVerified"
        ),
        "checkedOfficialRawStartTimeoutBoundaryVerified": bool_at(
            summary, "status", "officialRawStartTimeoutBoundaryVerified"
        ),
        "checkedOfficialSurfaceLocalEvidence": bool_at(
            summary, "evidence", "officialSurfaceCompare", "local", "ok"
        ),
        "checkedOfficialSurfaceBundledEvidence": bool_at(
            summary, "evidence", "officialSurfaceCompare", "official", "ok"
        ),
        "checkedOfficialNoActiveResponseEvidence": bool_at(
            summary, "evidence", "officialNoActiveResponse", "ok"
        ),
        "checkedOfficialNoActiveNoSessionFilesEvidence": bool_at(
            summary,
            "evidence",
            "officialNoActiveResponse",
            "checkedNoSessionFilesCreated",
        ),
        "checkedOfficialNoActiveStatusShapeEvidence": bool_at(
            summary, "evidence", "officialNoActiveResponse", "checkedStatusShape"
        ),
        "checkedOfficialNoActiveStopShapeEvidence": bool_at(
            summary, "evidence", "officialNoActiveResponse", "checkedStopShape"
        ),
        "checkedOfficialRawStartTimeoutEvidence": bool_at(
            summary, "evidence", "officialRawStartTimeout", "ok"
        ),
        "checkedOfficialRawStartTimeoutBoundaryEvidence": bool_at(
            summary,
            "evidence",
            "officialRawStartTimeout",
            "checkedOfficialRawStartTimeoutBoundary",
        ),
        "checkedOfficialRawStartStatusStopTimeoutEvidence": bool_at(
            summary,
            "evidence",
            "officialRawStartTimeout",
            "checkedOfficialRawStartStatusStopTimeout",
        ),
        "checkedOfficialRawStartDoesNotReturnRecordingPathsEvidence": bool_at(
            summary,
            "evidence",
            "officialRawStartTimeout",
            "checkedOfficialRawStartDoesNotReturnRecordingPaths",
        ),
        "checkedOfficialRawSurfaceEvidence": bool_at(
            summary,
            "evidence",
            "officialRawStartTimeout",
            "checkedOfficialRawSurface",
        ),
        "checkedOfficialRawProbeFixtureRedactionEvidence": bool_at(
            summary,
            "evidence",
            "officialRawStartTimeout",
            "checkedRawProbeFixtureRedaction",
        ),
        "checkedBaselineContractEvidence": bool_at(
            summary, "evidence", "baselineContract", "ok"
        ),
        "checkedBaselineContractRequiredChecksEvidence": bool_at(
            summary,
            "evidence",
            "baselineContract",
            "checkedRequiredBaselineChecks",
        ),
        "checkedBaselineContractNoDuplicateChecksEvidence": bool_at(
            summary,
            "evidence",
            "baselineContract",
            "checkedNoDuplicateRequiredBaselineChecks",
        ),
        "checkedBaselineContractStandaloneSummaryRenamesEvidence": bool_at(
            summary,
            "evidence",
            "baselineContract",
            "checkedStandaloneLifecycleSummaryRenames",
        ),
        "checkedBaselineAuditMakeTargetsEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditMakeTargets",
        ),
        "checkedBaselineAuditDefaultSummaryPathEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditDefaultSummaryPath",
        ),
        "checkedBaselineAuditCustomSummaryPathEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditCustomSummaryPath",
        ),
        "checkedBaselineAuditIgnoresStrictSummaryVarEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditIgnoresStrictSummaryVar",
        ),
        "checkedBaselineAuditStrictOfficialGoldenTargetEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditStrictOfficialGoldenTarget",
        ),
        "checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPathEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPath",
        ),
        "checkedBaselineAuditStrictOfficialGoldenCustomSummaryPathEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditStrictOfficialGoldenCustomSummaryPath",
        ),
        "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVarEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar",
        ),
        "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPathEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath",
        ),
        "checkedOfficialCaptureMissingScenarioPreflightEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCaptureMissingScenarioPreflight",
        ),
        "checkedOfficialCapturePacketEvidence": bool_at(
            summary, "evidence", "preflightPipelines", "checkedOfficialCapturePacket"
        ),
        "checkedOfficialCapturePacketPostCaptureWorkflowEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketPostCaptureWorkflow",
        ),
        "checkedOfficialCapturePacketWorkflowVerifierEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketWorkflowVerifier",
        ),
        "checkedOfficialCapturePacketHandoffScriptsEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketHandoffScripts",
        ),
        "checkedOfficialCapturePacketStrictAuditHandoffEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketStrictAuditHandoff",
        ),
        "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoffEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
        ),
        "checkedOfficialCapturePacketOcuCandidateOutputDirEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketOcuCandidateOutputDir",
        ),
        "checkedOfficialCapturePacketNoTranscriptEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketNoTranscript",
        ),
        "checkedOfficialCapturePacketSetEvidence": bool_at(
            summary, "evidence", "preflightPipelines", "checkedOfficialCapturePacketSet"
        ),
        "checkedOfficialCapturePacketSetPostCaptureWorkflowEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetPostCaptureWorkflow",
        ),
        "checkedOfficialCapturePacketSetWorkflowVerifierEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetWorkflowVerifier",
        ),
        "checkedOfficialCapturePacketSetNoTranscriptEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetNoTranscript",
        ),
        "checkedOfficialCapturePacketSetOcuCandidateHandoffEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetOcuCandidateHandoff",
        ),
        "checkedOfficialCapturePacketSetContractManifestEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetContractManifest",
        ),
        "checkedOfficialCapturePacketTranscriptManifestEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketTranscriptManifest",
        ),
        "checkedOfficialCapturePacketMakeTargetsEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketMakeTargets",
        ),
        "checkedOfficialCapturePacketInputSemanticGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketInputSemanticGuard",
        ),
        "checkedOfficialCapturePacketPlaceholderGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketPlaceholderGuard",
        ),
        "checkedOfficialCapturePacketVerifyInputsEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketVerifyInputs",
        ),
        "checkedOfficialCapturePacketImportPlaceholderGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketImportPlaceholderGuard",
        ),
        "checkedOfficialCapturePacketTranscriptPlaceholderGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketTranscriptPlaceholderGuard",
        ),
        "checkedOfficialCapturePacketSetRootPlaceholderGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetRootPlaceholderGuard",
        ),
        "checkedOfficialCapturePacketSetRootPreflightPlaceholderGuardEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard",
        ),
        "checkedOfficialCapturePacketSetVerifyAllEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCapturePacketSetVerifyAll",
        ),
        "checkedOfficialCaptureRequireReadyFailureEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCaptureRequireReadyFailure",
        ),
        "checkedOfficialCaptureMissingPluginFailureEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCaptureMissingPluginFailure",
        ),
        "checkedOfficialCaptureKeyboardScenarioEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCaptureKeyboardScenario",
        ),
        "checkedOfficialCaptureCoverageErrorFailureEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOfficialCaptureCoverageErrorFailure",
        ),
        "checkedOcuPairingMissingOfficialPreflightEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOcuPairingMissingOfficialPreflight",
        ),
        "checkedOcuPairingNoCandidatePreflightEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOcuPairingNoCandidatePreflight",
        ),
        "checkedOcuPairingPairedCandidatePreflightEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOcuPairingPairedCandidatePreflight",
        ),
        "checkedOcuPairingKeyboardRecordingRequiredScenarioEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOcuPairingKeyboardRecordingRequiredScenario",
        ),
        "checkedOcuPairingCoverageErrorReportEvidence": bool_at(
            summary,
            "evidence",
            "preflightPipelines",
            "checkedOcuPairingCoverageErrorReport",
        ),
        "checkedGoldenRequirementSatisfied": bool_at(
            summary, "status", "officialGoldenRequirementSatisfied"
        )
        if not allow_strict_official_golden_missing
        else not official_golden_requirement_satisfied,
        "checkedStrictModeMatchesExpectation": (
            bool_at(summary, "status", "strictOfficialGoldenRequired")
            == strict_mode_expected
        ),
        "checkedGoldenGateConsistency": (
            bool_at(summary, "status", "officialGoldenGatePassed")
            == bool_at(summary, "status", "officialSuccessfulRecordingGoldenComplete")
        ),
        "checkedEquivalenceRequiresGolden": (
            not bool_at(summary, "status", "officialSuccessfulRecordingEquivalenceReady")
            or (
                bool_at(summary, "status", "usableBaseline")
                and bool_at(summary, "status", "officialSuccessfulRecordingGoldenComplete")
            )
        ),
        "checkedEquivalenceReadyMatchesPolicy": (
            bool_at(summary, "status", "officialSuccessfulRecordingEquivalenceReady")
            == expected_equivalence_ready
        ),
        "checkedStandaloneReadyRequiresUsableBaseline": (
            not standalone_ready or bool_at(summary, "status", "usableBaseline")
        ),
        "checkedRequiresOfficialGoldenCaptureConsistency": (
            bool_at(summary, "status", "requiresOfficialGoldenCapture") == missing_golden
        ),
        "checkedMissingGoldenHasScenarioGapOrCoverageError": (
            not missing_golden
            or bool(required_gaps)
            or bool(not_ready_required)
            or bool(coverage_errors)
        ),
        "checkedOfficialGoldenCompleteHasNoRequiredGaps": (
            missing_golden
            or (not required_gaps and not not_ready_required and not coverage_errors)
        ),
        "checkedMissingGoldenHasNextAction": (
            not missing_golden
            or "capture-official-successful-recording-golden" in actions
        ),
        "checkedMissingGoldenNextActionPacketMakeCommand": (
            not missing_golden
            or has_command_containing(
                required_capture_commands,
                "make record-and-replay-official-golden-capture-packet",
                "RNR_SCENARIO=",
                "RNR_PACKET_DIR=<packet-dir>",
            )
        ),
        "checkedMissingGoldenNextActionVerifyStep": (
            not missing_golden
            or has_command_containing(required_capture_commands, "./verify-inputs.sh")
        ),
        "checkedMissingGoldenNextActionInspectStep": (
            not missing_golden
            or has_command_containing(required_capture_commands, "./inspect-only.sh")
        ),
        "checkedMissingGoldenNextActionImportStep": (
            not missing_golden
            or has_command_containing(required_capture_commands, "./import-fixture.sh")
        ),
        "checkedMissingGoldenNextActionStrictGateStep": (
            not missing_golden
            or has_command_containing(
                required_capture_commands,
                "make record-and-replay-official-golden-gate",
            )
        ),
        "checkedMissingGoldenNextActionStrictAuditStep": (
            not missing_golden
            or has_command_containing(
                required_capture_commands,
                "make record-and-replay-official-golden-gate-audit",
            )
        ),
        "checkedRecommendedGoldenNextActionPacketSetCommand": (
            not missing_recommended_golden
            or has_command_containing(
                recommended_capture_commands,
                "make record-and-replay-official-golden-capture-packet-set",
                "RNR_PACKET_DIR=<packet-dir>",
            )
        ),
        "checkedRecommendedGoldenNextActionVerifyAllStep": (
            not missing_recommended_golden
            or has_command_containing(recommended_capture_commands, "./verify-all.sh")
        ),
        "checkedRecommendedGoldenNextActionInspectAllStep": (
            not missing_recommended_golden
            or has_command_containing(recommended_capture_commands, "./inspect-all.sh")
        ),
        "checkedRecommendedGoldenNextActionImportAllStep": (
            not missing_recommended_golden
            or has_command_containing(recommended_capture_commands, "./import-all.sh")
        ),
        "checkedRecommendedGoldenNextActionIngestOcuCandidatesStep": (
            not missing_recommended_golden
            or has_command_containing(
                recommended_capture_commands,
                "./ingest-ocu-candidates.sh",
            )
        ),
        "checkedStandaloneNextActionWhenReady": (
            not standalone_ready
            or "scaffold-standalone-record-and-replay-repo" in actions
        ),
        "checkedStandaloneNextActionBaselineAuditCommand": (
            not standalone_ready
            or has_command_containing(
                standalone_commands,
                "make record-and-replay-baseline-audit",
            )
        ),
        "checkedStandaloneNextActionScaffoldCommand": (
            not standalone_ready
            or has_command_containing(
                standalone_commands,
                "open-computer-use scaffold-record-and-replay-skill-repo",
                "--output-dir <new-repo>",
            )
        ),
        "checkedStandaloneNextActionCheckCommand": (
            not standalone_ready
            or has_command_containing(standalone_commands, "./scripts/check.sh")
        ),
        "checkedStandaloneNextActionLifecycleSmokeCommand": (
            not standalone_ready
            or has_command_containing(
                standalone_commands,
                "./scripts/recording-lifecycle-smoke.py",
            )
        ),
    }

    direct_evidence_requirements = {
        "baselineContract": (
            "BaselineContract",
            [
                "ok",
                "checkedRequiredBaselineChecks",
                "checkedNoDuplicateRequiredBaselineChecks",
                "checkedStandaloneSmokeRequiredKeys",
                "checkedStandaloneSummaryEvidenceKeys",
                "checkedStandaloneLifecycleSummaryRenames",
                "checkedNpmStagedSmokeRequiredKeys",
                "checkedNpmStagedSummaryEvidenceKeys",
                "checkedNpmStagedSummaryMatchesSmoke",
            ],
        ),
        "eventStreamMatrix": (
            "EventStreamMatrix",
            [
                "ok",
                "checkedDefaultLifecycleHandoff",
                "checkedRequiredModes",
            ],
        ),
        "screenshotContextSmoke": (
            "ScreenshotContextSmoke",
            [
                "ok",
                "checkedScreenshotPolicyAlways",
                "checkedScreenshotNeededForContext",
                "checkedScreenshotPathWhenAvailable",
            ],
        ),
        "realInputActionSmoke": (
            "RealInputActionSmoke",
            [
                "ok",
                "checkedRequiredEventTypes",
                "checkedSkillDraftGenerated",
                "checkedMcpTranscriptCaptured",
                "checkedMcpResponseShapesCaptured",
                "checkedSkillReadinessCanCreateDraft",
                "checkedSkillCreatorFinalizationHandoff",
                "checkedGeneratedSkillPathRedaction",
                "checkedSimpleActionStopCandidate",
                "checkedDragStopCandidate",
            ],
        ),
        "officialFixtureSetGate": (
            "OfficialFixtureSetGate",
            [
                "ok",
                "checkedFixtureSetGate",
                "checkedRequiredSimpleActionStopScenario",
                "checkedCandidatePairing",
                "checkedCandidateReadinessFailure",
                "checkedAxDiffComparisonPolicy",
                "checkedSuppressedStreamComparisonPolicy",
                "checkedAxDiffComparisonFailure",
                "checkedStopEndReasonPolicy",
                "checkedCancelScenarioPolicy",
                "checkedKeyboardInputScenarioPolicy",
                "checkedDragScenarioPolicy",
                "checkedTimeoutScenarioPolicy",
            ],
        ),
        "fixtureIngestPipelines": (
            "FixtureIngestPipelines",
            [
                "checkedOfficialFixtureIngest",
                "checkedOfficialFixtureInspectOnly",
                "checkedOfficialSessionDirectoryPathHandoff",
                "checkedPostIngestCoverageReport",
                "checkedPostIngestCoverageReadiness",
                "checkedPostIngestRequireCoverageFailure",
                "checkedOcuCandidateIngest",
                "checkedOcuCandidateIngestHandoffCommands",
                "checkedOcuSmokeJsonImport",
                "checkedOcuOfficialCandidatePairing",
                "checkedOcuCandidateRedaction",
                "checkedOcuKeyboardInputScenarioReadiness",
                "checkedOcuDragScenarioReadiness",
            ],
        ),
        "standaloneSkillRepo": (
            "StandaloneSkillRepo",
            STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
        ),
        "npmStagedSkillRepo": (
            "NpmStagedSkillRepo",
            NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
        ),
    }
    for section, (prefix, keys) in direct_evidence_requirements.items():
        for key in keys:
            checks[evidence_check_name(prefix, key)] = bool_at(
                summary, "evidence", section, key
            )

    if allow_strict_official_golden_missing:
        checks["checkedStrictOfficialGoldenMissingFailure"] = (
            bool_at(summary, "status", "strictOfficialGoldenRequired")
            and not official_golden_requirement_satisfied
            and not bool_at(summary, "status", "officialGoldenGatePassed")
            and not bool_at(summary, "status", "officialSuccessfulRecordingGoldenComplete")
            and not bool_at(
                summary,
                "status",
                "officialSuccessfulRecordingEquivalenceReady",
            )
        )
        checks["checkedStrictMissingGoldenHasRequiredGap"] = bool(
            required_gaps or not_ready_required
        )
        checks["checkedNoOfficialFixtureCoverageErrors"] = not coverage_errors
    elif not require_official_golden:
        checks["checkedAllowsMissingOfficialGoldenButNotEquivalence"] = (
            bool_at(summary, "status", "officialGoldenRequirementSatisfied")
            and (
                bool_at(summary, "status", "officialSuccessfulRecordingGoldenComplete")
                or not bool_at(
                    summary,
                    "status",
                    "officialSuccessfulRecordingEquivalenceReady",
                )
            )
        )
    else:
        checks["checkedOfficialGoldenGatePassed"] = bool_at(
            summary, "status", "officialGoldenGatePassed"
        )
        checks["checkedOfficialSuccessfulRecordingEquivalenceReady"] = bool_at(
            summary,
            "status",
            "officialSuccessfulRecordingEquivalenceReady",
        )
        checks["checkedNoRequiredOfficialScenarioGaps"] = not list_at(
            summary,
            "status",
            "missingRequiredOfficialSuccessfulRecordingScenarios",
        ) and not list_at(
            summary,
            "status",
            "notReadyRequiredOfficialSuccessfulRecordingScenarios",
        )
        checks["checkedNoOfficialFixtureCoverageErrors"] = not list_at(
            summary, "status", "officialFixtureCoverageErrors"
        )

    for key, passed in checks.items():
        if passed is not True:
            failures.append(key)

    return {
        "ok": not failures,
        "failures": failures,
        "checks": checks,
        "summaryStatus": {
            "usableBaseline": status.get("usableBaseline"),
            "standaloneRepoBaselineReady": status.get("standaloneRepoBaselineReady"),
            "officialGoldenRequirementSatisfied": status.get(
                "officialGoldenRequirementSatisfied"
            ),
            "officialGoldenGatePassed": status.get("officialGoldenGatePassed"),
            "officialSuccessfulRecordingGoldenComplete": status.get(
                "officialSuccessfulRecordingGoldenComplete"
            ),
            "officialSuccessfulRecordingEquivalenceReady": status.get(
                "officialSuccessfulRecordingEquivalenceReady"
            ),
            "missingRequiredOfficialSuccessfulRecordingScenarios": status.get(
                "missingRequiredOfficialSuccessfulRecordingScenarios"
            ),
            "notReadyRequiredOfficialSuccessfulRecordingScenarios": status.get(
                "notReadyRequiredOfficialSuccessfulRecordingScenarios"
            ),
            "officialFixtureCoverageErrors": status.get("officialFixtureCoverageErrors"),
        },
        "declaredChecks": {
            "missingRequired": missing_declared_checks,
            "unknown": unknown_declared_checks,
            "duplicates": duplicate_declared_checks,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Audit a saved Record & Replay baseline summary JSON without rerunning the "
            "desktop smoke suite."
        )
    )
    parser.add_argument("summary_json", type=pathlib.Path)
    parser.add_argument(
        "--require-official-golden",
        action="store_true",
        help=(
            "Require official successful recording golden readiness and equivalence. "
            "Default mode only requires the usable standalone baseline and keeps the "
            "golden gap explicit."
        ),
    )
    parser.add_argument(
        "--allow-strict-official-golden-missing",
        action="store_true",
        help=(
            "Audit a strict official golden summary that is expected to fail only "
            "because required official successful recording fixtures are still "
            "missing or not ready. This still requires the usable baseline, "
            "standalone repo baseline, official non-recording evidence, raw "
            "timeout boundary, nextActions, and zero fixture coverage errors."
        ),
    )
    args = parser.parse_args()
    if args.require_official_golden and args.allow_strict_official_golden_missing:
        parser.error(
            "--require-official-golden and "
            "--allow-strict-official-golden-missing are mutually exclusive"
        )

    try:
        summary = load_json(args.summary_json)
        result = check_summary(
            summary,
            args.require_official_golden,
            args.allow_strict_official_golden_missing,
        )
    except Exception as exc:
        result = {
            "ok": False,
            "failures": [str(exc)],
            "checks": {},
        }

    print(json.dumps(result, indent=2, sort_keys=True))
    if result.get("ok") is not True:
        failures = result.get("failures") or []
        if failures:
            print("baseline summary audit failed: " + ", ".join(failures), file=sys.stderr)
        else:
            print("baseline summary audit failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
