#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys

from record_and_replay_baseline_contract import REQUIRED_BASELINE_CHECKS


EXPECTED_NO_ACTIVE_RESPONSE = {"isRecording": False, "maxDurationSeconds": 1800}
REQUIRED_MATRIX_MODES = {
    "no-active",
    "timeout",
    "wait-timeout",
    "approval",
    "mcp-elicitation",
    "app-agent-wait",
}
REQUIRED_ACTION_EVENT_TYPES = {
    "session.started",
    "window.changed",
    "AX.focusedWindowChanged",
    "mouse.click",
    "session.ended",
}
REQUIRED_ACTION_SCENARIO_EVENT_TYPES = {
    "simple-action-stop": {
        "session.started",
        "window.changed",
        "AX.focusedWindowChanged",
        "mouse.click",
        "session.ended",
    },
    "drag-stop": {
        "session.started",
        "window.changed",
        "AX.focusedWindowChanged",
        "mouse.drag",
        "session.ended",
    },
}


def load_json(path: pathlib.Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def json_lines(path: pathlib.Path) -> list[dict]:
    records = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        value = json.loads(line)
        if isinstance(value, dict):
            records.append(value)
    return records


def find_record(records: list[dict], predicate, description: str) -> dict:
    matches = [record for record in records if predicate(record)]
    if not matches:
        raise ValueError(f"missing {description}")
    return matches[-1]


def action_record_ok(record: dict, required_event_types: set[str]) -> tuple[bool, list[str]]:
    event_types = set(record.get("eventTypes", []))
    missing_event_types = sorted(required_event_types - event_types)
    ok = (
        record.get("ok") is True
        and not missing_event_types
        and record.get("checkedMcpResponseShapesCaptured") is True
        and record.get("checkedSkillReadinessCanCreateDraft") is True
        and record.get("checkedSkillCreatorFinalizationHandoff") is True
        and record.get("checkedGeneratedSkillPathRedaction") is True
    )
    return ok, missing_event_types


def compact_surface_result(official_surface: dict, label: str) -> dict:
    result = next(
        item for item in official_surface.get("results", []) if item.get("label") == label
    )
    return {
        "ok": result.get("ok") is True,
        "protocolVersion": result.get("protocolVersion"),
        "serverName": result.get("serverName"),
        "toolNames": result.get("toolNames"),
    }


def missing_false_values(prefix: str, values: dict[str, bool]) -> list[str]:
    return [f"{prefix}.{key}" for key, value in values.items() if value is not True]


def build_summary(args: argparse.Namespace) -> dict:
    standalone = load_json(args.standalone_json)
    npm = load_json(args.npm_json)
    official_surface = load_json(args.official_surface_json)
    official_no_active = load_json(args.official_no_active_json)
    official_raw_timeout = load_json(args.official_raw_timeout_json)
    official_fixture_set = load_json(args.official_fixture_set_json)
    official_fixture_coverage = load_json(args.official_fixture_coverage_json)
    official_fixture_ingest = load_json(args.official_fixture_ingest_json)
    ocu_candidate_ingest = load_json(args.ocu_candidate_ingest_json)
    official_capture_preflight = load_json(args.official_capture_preflight_json)
    ocu_pairing_preflight = load_json(args.ocu_pairing_preflight_json)
    baseline_audit_targets = load_json(args.baseline_audit_targets_json)
    baseline_contract = load_json(args.baseline_contract_json)
    matrix_records = json_lines(args.matrix_jsonl)
    screenshot_records = json_lines(args.screenshot_jsonl)
    action_records = json_lines(args.action_jsonl)

    screenshot_record = find_record(
        screenshot_records,
        lambda record: record.get("ok") is True and record.get("screenshotPolicy") == "always",
        "screenshot context smoke record",
    )
    action_record = find_record(
        action_records,
        lambda record: record.get("mode") == "actions"
        and record.get("actionScenario") in (None, "mixed-action-stop"),
        "real input action smoke record",
    )
    scenario_action_records = {
        scenario: find_record(
            action_records,
            lambda record, scenario=scenario: (
                record.get("mode") == "actions"
                and record.get("actionScenario") == scenario
            ),
            f"{scenario} action smoke record",
        )
        for scenario in REQUIRED_ACTION_SCENARIO_EVENT_TYPES
    }
    official_successful_recording_golden_complete = (
        official_fixture_coverage.get("coverageOk") is True
        and official_fixture_coverage.get("hasRequiredOfficialSuccessfulFixture") is True
        and official_fixture_coverage.get("requiredOfficialReadinessChecked") is True
        and official_fixture_coverage.get("requiredOfficialReadinessOk") is True
    )
    recommended_official_recording_coverage_complete = (
        official_fixture_coverage.get("hasRecommendedOfficialScenarioCoverage") is True
    )
    official_golden_gate_passed = official_successful_recording_golden_complete
    official_golden_requirement_satisfied = (
        not args.require_official_golden or official_golden_gate_passed
    )
    local_surface = compact_surface_result(official_surface, "local-open-computer-use")
    official_surface_result = compact_surface_result(official_surface, "official-record-and-replay")
    matrix_modes = sorted({record.get("mode") for record in matrix_records if record.get("mode")})
    missing_matrix_modes = sorted(REQUIRED_MATRIX_MODES - set(matrix_modes))
    missing_action_event_types = sorted(
        REQUIRED_ACTION_EVENT_TYPES - set(action_record.get("eventTypes", []))
    )
    scenario_candidate_evidence = {}
    for scenario, required_event_types in REQUIRED_ACTION_SCENARIO_EVENT_TYPES.items():
        scenario_record = scenario_action_records[scenario]
        scenario_ok, scenario_missing_event_types = action_record_ok(
            scenario_record,
            required_event_types,
        )
        scenario_candidate_evidence[scenario] = {
            "ok": scenario_record.get("ok") is True,
            "eventCount": scenario_record.get("eventCount"),
            "eventTypes": scenario_record.get("eventTypes"),
            "checkedRequiredEventTypes": not scenario_missing_event_types,
            "missingEventTypes": scenario_missing_event_types,
            "checkedMcpResponseShapesCaptured": (
                scenario_record.get("checkedMcpResponseShapesCaptured") is True
            ),
            "checkedSkillReadinessCanCreateDraft": (
                scenario_record.get("checkedSkillReadinessCanCreateDraft") is True
            ),
            "checkedSkillCreatorFinalizationHandoff": (
                scenario_record.get("checkedSkillCreatorFinalizationHandoff") is True
            ),
            "checkedGeneratedSkillPathRedaction": (
                scenario_record.get("checkedGeneratedSkillPathRedaction") is True
            ),
            "checkedScenarioCandidate": scenario_ok,
        }

    event_stream_matrix_evidence = {
        "ok": any(
            record.get("ok") is True and record.get("matrix") == "event-stream"
            for record in matrix_records
        ),
        "checkedDefaultLifecycleHandoff": any(
            record.get("ok") is True and record.get("handoffChecked") is True
            for record in matrix_records
        ),
        "checkedRequiredModes": not missing_matrix_modes,
        "checkedModes": matrix_modes,
        "missingModes": missing_matrix_modes,
    }
    screenshot_context_evidence = {
        "ok": screenshot_record.get("ok") is True,
        "checkedScreenshotPolicyAlways": screenshot_record.get("screenshotPolicy") == "always",
        "checkedScreenshotNeededForContext": (
            screenshot_record.get("screenshotNeededForContextCount", 0) > 0
        ),
        "screenshotAvailableCount": screenshot_record.get("screenshotAvailableCount"),
        "screenshotPathCount": screenshot_record.get("screenshotPathCount"),
        "checkedScreenshotPathWhenAvailable": (
            screenshot_record.get("screenshotAvailableCount", 0) <= 0
            or screenshot_record.get("screenshotPathCount", 0) > 0
        ),
    }
    real_input_action_evidence = {
        "ok": action_record.get("ok") is True,
        "eventCount": action_record.get("eventCount"),
        "eventTypes": action_record.get("eventTypes"),
        "checkedRequiredEventTypes": not missing_action_event_types,
        "missingEventTypes": missing_action_event_types,
        "checkedSkillDraftGenerated": bool(action_record.get("skillPath")),
        "checkedMcpTranscriptCaptured": bool(action_record.get("mcpTranscriptPath")),
        "checkedMcpResponseShapesCaptured": (
            action_record.get("checkedMcpResponseShapesCaptured") is True
        ),
        "checkedSkillReadinessCanCreateDraft": (
            action_record.get("checkedSkillReadinessCanCreateDraft") is True
        ),
        "checkedSkillCreatorFinalizationHandoff": (
            action_record.get("checkedSkillCreatorFinalizationHandoff") is True
        ),
        "checkedGeneratedSkillPathRedaction": (
            action_record.get("checkedGeneratedSkillPathRedaction") is True
        ),
        "checkedSimpleActionStopCandidate": scenario_candidate_evidence[
            "simple-action-stop"
        ]["checkedScenarioCandidate"],
        "checkedDragStopCandidate": scenario_candidate_evidence["drag-stop"][
            "checkedScenarioCandidate"
        ],
        "scenarioCandidates": scenario_candidate_evidence,
    }
    official_surface_evidence = {
        "fixture": "record-and-replay-event-stream-surface-1.0.857.json",
        "local": local_surface,
        "official": official_surface_result,
    }
    official_no_active_evidence = {
        "ok": official_no_active.get("ok") is True,
        "fixture": pathlib.Path(official_no_active.get("fixture", "")).name,
        "checkedTools": official_no_active.get("checkedTools"),
        "checkedNoSessionFilesCreated": (
            official_no_active.get("createdSessionFiles") is False
        ),
        "checkedStatusShape": (
            official_no_active.get("actual", {}).get("event_stream_status")
            == EXPECTED_NO_ACTIVE_RESPONSE
        ),
        "checkedStopShape": (
            official_no_active.get("actual", {}).get("event_stream_stop")
            == EXPECTED_NO_ACTIVE_RESPONSE
        ),
        "status": official_no_active.get("actual", {}).get("event_stream_status"),
        "stop": official_no_active.get("actual", {}).get("event_stream_stop"),
    }
    raw_timeout_fixtures = official_raw_timeout.get("fixtures") or []
    raw_timeout_fixture_name = next(
        (
            pathlib.Path(item).name
            for item in raw_timeout_fixtures
            if "raw-start-timeout" in pathlib.Path(item).name
        ),
        None,
    )
    official_raw_timeout_evidence = {
        "ok": official_raw_timeout.get("ok") is True,
        "fixture": raw_timeout_fixture_name,
        "checkedOfficialRawStartTimeoutBoundary": (
            official_raw_timeout.get("checkedOfficialRawStartTimeoutBoundary") is True
        ),
        "checkedOfficialRawStartStatusStopTimeout": (
            official_raw_timeout.get("checkedOfficialRawStartStatusStopTimeout") is True
        ),
        "checkedOfficialRawStartDoesNotReturnRecordingPaths": (
            official_raw_timeout.get("checkedOfficialRawStartDoesNotReturnRecordingPaths")
            is True
        ),
        "checkedOfficialRawSurface": (
            official_raw_timeout.get("checkedOfficialRawSurface") is True
        ),
        "checkedRawProbeFixtureRedaction": (
            official_raw_timeout.get("checkedRawProbeFixtureRedaction") is True
        ),
        "officialRawToolCallCount": official_raw_timeout.get("officialRawToolCallCount"),
        "officialRawTimeoutCount": official_raw_timeout.get("officialRawTimeoutCount"),
    }
    official_fixture_set_evidence = {
        "ok": official_fixture_set.get("ok") is True,
        "checkedFixtureSetGate": official_fixture_set.get("checkedFixtureSetGate") is True,
        "checkedRequiredSimpleActionStopScenario": (
            official_fixture_set.get("checkedRequiredSimpleActionStopScenario") is True
        ),
        "checkedCandidatePairing": (
            official_fixture_set.get("checkedCandidatePairing") is True
        ),
        "checkedCandidateReadinessFailure": (
            official_fixture_set.get("checkedCandidateReadinessFailure") is True
        ),
        "checkedAxDiffComparisonPolicy": (
            official_fixture_set.get("checkedAxDiffComparisonPolicy") is True
        ),
        "checkedSuppressedStreamComparisonPolicy": (
            official_fixture_set.get("checkedSuppressedStreamComparisonPolicy") is True
        ),
        "checkedAxDiffComparisonFailure": (
            official_fixture_set.get("checkedAxDiffComparisonFailure") is True
        ),
        "checkedStopEndReasonPolicy": (
            official_fixture_set.get("checkedStopEndReasonPolicy") is True
        ),
        "checkedCancelScenarioPolicy": (
            official_fixture_set.get("checkedCancelScenarioPolicy") is True
        ),
        "checkedKeyboardInputScenarioPolicy": (
            official_fixture_set.get("checkedKeyboardInputScenarioPolicy") is True
        ),
        "checkedDragScenarioPolicy": (
            official_fixture_set.get("checkedDragScenarioPolicy") is True
        ),
        "checkedTimeoutScenarioPolicy": (
            official_fixture_set.get("checkedTimeoutScenarioPolicy") is True
        ),
        "coverageOk": official_fixture_coverage.get("coverageOk") is True,
        "scenarioCoverageOk": official_fixture_coverage.get("scenarioCoverageOk") is True,
        "requiredOfficialScenarios": official_fixture_coverage.get("requiredOfficialScenarios"),
        "recommendedOfficialScenarios": official_fixture_coverage.get(
            "recommendedOfficialScenarios"
        ),
        "requiredOfficialReadinessChecked": (
            official_fixture_coverage.get("requiredOfficialReadinessChecked") is True
        ),
        "requiredOfficialReadinessOk": (
            official_fixture_coverage.get("requiredOfficialReadinessOk") is True
        ),
        "repoAvailableOfficialScenarios": official_fixture_coverage.get(
            "availableOfficialScenarios"
        ),
        "repoHasRequiredOfficialSuccessfulFixture": (
            official_fixture_coverage.get("hasRequiredOfficialSuccessfulFixture") is True
        ),
        "repoHasRecommendedOfficialScenarioCoverage": (
            official_fixture_coverage.get("hasRecommendedOfficialScenarioCoverage") is True
        ),
        "missingRepoOfficialScenarios": official_fixture_coverage.get(
            "missingOfficialScenarios"
        ),
        "notReadyRepoOfficialScenarios": official_fixture_coverage.get(
            "notReadyOfficialScenarios"
        ),
        "missingRepoRecommendedOfficialScenarios": official_fixture_coverage.get(
            "missingRecommendedOfficialScenarios"
        ),
        "coverageErrors": official_fixture_coverage.get("errors") or [],
    }
    fixture_ingest_evidence = {
        "checkedOfficialFixtureIngest": (
            official_fixture_ingest.get("checkedOfficialFixtureIngest") is True
        ),
        "checkedOfficialFixtureInspectOnly": (
            official_fixture_ingest.get("checkedOfficialFixtureInspectOnly") is True
        ),
        "checkedOfficialSessionDirectoryPathHandoff": (
            official_fixture_ingest.get("checkedOfficialSessionDirectoryPathHandoff") is True
        ),
        "checkedPostIngestCoverageReport": (
            official_fixture_ingest.get("checkedPostIngestCoverageReport") is True
        ),
        "checkedPostIngestCoverageReadiness": (
            official_fixture_ingest.get("checkedPostIngestCoverageReadiness") is True
        ),
        "checkedPostIngestRequireCoverageFailure": (
            official_fixture_ingest.get("checkedPostIngestRequireCoverageFailure") is True
        ),
        "checkedOcuCandidateIngest": (
            ocu_candidate_ingest.get("checkedOcuCandidateIngest") is True
        ),
        "checkedOcuCandidateIngestHandoffCommands": (
            ocu_candidate_ingest.get("checkedCandidateIngestHandoffCommands") is True
        ),
        "checkedOcuSmokeJsonImport": (
            ocu_candidate_ingest.get("checkedSmokeJsonImport") is True
        ),
        "checkedOcuOfficialCandidatePairing": (
            ocu_candidate_ingest.get("checkedOfficialCandidatePairing") is True
        ),
        "checkedOcuCandidateRedaction": (
            ocu_candidate_ingest.get("checkedCandidateRedaction") is True
        ),
        "checkedOcuKeyboardInputScenarioReadiness": (
            ocu_candidate_ingest.get("checkedKeyboardInputScenarioReadiness") is True
        ),
        "checkedOcuDragScenarioReadiness": (
            ocu_candidate_ingest.get("checkedDragScenarioReadiness") is True
        ),
    }
    preflight_evidence = {
        "checkedOfficialCaptureMissingScenarioPreflight": (
            official_capture_preflight.get("checkedMissingScenarioPreflight") is True
        ),
        "checkedOfficialCapturePacket": (
            official_capture_preflight.get("checkedCapturePacket") is True
        ),
        "checkedOfficialCapturePacketPostCaptureWorkflow": (
            official_capture_preflight.get("checkedCapturePacketPostCaptureWorkflow")
            is True
        ),
        "checkedOfficialCapturePacketWorkflowVerifier": (
            official_capture_preflight.get("checkedCapturePacketWorkflowVerifier")
            is True
        ),
        "checkedOfficialCapturePacketHandoffScripts": (
            official_capture_preflight.get("checkedCapturePacketHandoffScripts")
            is True
        ),
        "checkedOfficialCapturePacketStrictAuditHandoff": (
            official_capture_preflight.get("checkedCapturePacketStrictAuditHandoff")
            is True
        ),
        "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff": (
            official_capture_preflight.get(
                "checkedCapturePacketStrictExpectedFailureAuditHandoff"
            )
            is True
        ),
        "checkedOfficialCapturePacketOcuCandidateOutputDir": (
            official_capture_preflight.get("checkedCapturePacketOcuCandidateOutputDir")
            is True
        ),
        "checkedOfficialCapturePacketNoTranscript": (
            official_capture_preflight.get("checkedCapturePacketNoTranscript")
            is True
        ),
        "checkedOfficialCapturePacketSet": (
            official_capture_preflight.get("checkedCapturePacketSet") is True
        ),
        "checkedOfficialCapturePacketSetPostCaptureWorkflow": (
            official_capture_preflight.get("checkedCapturePacketSetPostCaptureWorkflow")
            is True
        ),
        "checkedOfficialCapturePacketSetWorkflowVerifier": (
            official_capture_preflight.get("checkedCapturePacketSetWorkflowVerifier")
            is True
        ),
        "checkedOfficialCapturePacketSetNoTranscript": (
            official_capture_preflight.get("checkedCapturePacketSetNoTranscript")
            is True
        ),
        "checkedOfficialCapturePacketSetOcuCandidateHandoff": (
            official_capture_preflight.get("checkedCapturePacketSetOcuCandidateHandoff")
            is True
        ),
        "checkedOfficialCapturePacketSetContractManifest": (
            official_capture_preflight.get("checkedCapturePacketSetContractManifest")
            is True
        ),
        "checkedOfficialCapturePacketTranscriptManifest": (
            official_capture_preflight.get("checkedCapturePacketTranscriptManifest")
            is True
        ),
        "checkedOfficialCapturePacketMakeTargets": (
            official_capture_preflight.get("checkedMakeCapturePacketTargets") is True
        ),
        "checkedOfficialCapturePacketInputSemanticGuard": (
            official_capture_preflight.get("checkedCapturePacketInputSemanticGuard")
            is True
        ),
        "checkedOfficialCapturePacketPlaceholderGuard": (
            official_capture_preflight.get("checkedCapturePacketPlaceholderGuard") is True
        ),
        "checkedOfficialCapturePacketVerifyInputs": (
            official_capture_preflight.get("checkedCapturePacketVerifyInputs") is True
        ),
        "checkedOfficialCapturePacketImportPlaceholderGuard": (
            official_capture_preflight.get("checkedCapturePacketImportPlaceholderGuard")
            is True
        ),
        "checkedOfficialCapturePacketTranscriptPlaceholderGuard": (
            official_capture_preflight.get("checkedCapturePacketTranscriptPlaceholderGuard")
            is True
        ),
        "checkedOfficialCapturePacketSetRootPlaceholderGuard": (
            official_capture_preflight.get("checkedCapturePacketSetRootPlaceholderGuard")
            is True
        ),
        "checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard": (
            official_capture_preflight.get(
                "checkedCapturePacketSetRootPreflightPlaceholderGuard"
            )
            is True
        ),
        "checkedOfficialCapturePacketSetVerifyAll": (
            official_capture_preflight.get("checkedCapturePacketSetVerifyAll") is True
        ),
        "checkedOfficialCaptureRequireReadyFailure": (
            official_capture_preflight.get("checkedRequireReadyFailure") is True
        ),
        "checkedOfficialCaptureMissingPluginFailure": (
            official_capture_preflight.get("checkedMissingPluginFailure") is True
        ),
        "checkedOfficialCaptureKeyboardScenario": (
            official_capture_preflight.get("checkedAllowedMissingPluginKeyboardScenario")
            is True
        ),
        "checkedOfficialCaptureCoverageErrorFailure": (
            official_capture_preflight.get("checkedCoverageErrorFailure") is True
        ),
        "checkedOcuPairingMissingOfficialPreflight": (
            ocu_pairing_preflight.get("checkedMissingOfficialPreflight") is True
        ),
        "checkedOcuPairingNoCandidatePreflight": (
            ocu_pairing_preflight.get("checkedNoCandidatePreflight") is True
        ),
        "checkedOcuPairingPairedCandidatePreflight": (
            ocu_pairing_preflight.get("checkedPairedCandidatePreflight") is True
        ),
        "checkedOcuPairingKeyboardRecordingRequiredScenario": (
            ocu_pairing_preflight.get("checkedKeyboardRecordingRequiredScenario") is True
        ),
        "checkedOcuPairingCoverageErrorReport": (
            ocu_pairing_preflight.get("checkedCoverageErrorReport") is True
        ),
        "checkedBaselineAuditMakeTargets": (
            baseline_audit_targets.get("checkedBaselineAuditMakeTarget") is True
        ),
        "checkedBaselineAuditDefaultSummaryPath": (
            baseline_audit_targets.get("checkedBaselineAuditDefaultSummaryPath") is True
        ),
        "checkedBaselineAuditCustomSummaryPath": (
            baseline_audit_targets.get("checkedBaselineAuditCustomSummaryPath") is True
        ),
        "checkedBaselineAuditIgnoresStrictSummaryVar": (
            baseline_audit_targets.get("checkedBaselineAuditIgnoresStrictSummaryVar")
            is True
        ),
        "checkedBaselineAuditStrictOfficialGoldenTarget": (
            baseline_audit_targets.get("checkedStrictOfficialGoldenAuditMakeTarget") is True
        ),
        "checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPath": (
            baseline_audit_targets.get(
                "checkedStrictOfficialGoldenAuditDefaultSummaryPath"
            )
            is True
        ),
        "checkedBaselineAuditStrictOfficialGoldenCustomSummaryPath": (
            baseline_audit_targets.get(
                "checkedStrictOfficialGoldenAuditCustomSummaryPath"
            )
            is True
        ),
        "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar": (
            baseline_audit_targets.get(
                "checkedStrictOfficialGoldenAuditIgnoresBaselineSummaryVar"
            )
            is True
        ),
        "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath": (
            baseline_audit_targets.get(
                "checkedStrictOfficialGoldenAuditSeparateSummaryPath"
            )
            is True
        ),
    }
    baseline_contract_evidence = {
        "ok": baseline_contract.get("ok") is True,
        "checkedRequiredBaselineChecks": (
            baseline_contract.get("checkedRequiredBaselineChecks") is True
        ),
        "checkedNoDuplicateRequiredBaselineChecks": (
            baseline_contract.get("checkedNoDuplicateRequiredBaselineChecks") is True
        ),
        "checkedStandaloneSmokeRequiredKeys": (
            baseline_contract.get("checkedStandaloneSmokeRequiredKeys") is True
        ),
        "checkedStandaloneSummaryEvidenceKeys": (
            baseline_contract.get("checkedStandaloneSummaryEvidenceKeys") is True
        ),
        "checkedStandaloneLifecycleSummaryRenames": (
            baseline_contract.get("checkedStandaloneLifecycleSummaryRenames") is True
        ),
        "checkedNpmStagedSmokeRequiredKeys": (
            baseline_contract.get("checkedNpmStagedSmokeRequiredKeys") is True
        ),
        "checkedNpmStagedSummaryEvidenceKeys": (
            baseline_contract.get("checkedNpmStagedSummaryEvidenceKeys") is True
        ),
        "checkedNpmStagedSummaryMatchesSmoke": (
            baseline_contract.get("checkedNpmStagedSummaryMatchesSmoke") is True
        ),
    }
    standalone_evidence = {
        "checkedGeneratedRepoSelfCheck": (
            standalone.get("checkedGeneratedRepoSelfCheck") is True
        ),
        "checkedManifestContract": standalone.get("checkedManifestContract") is True,
        "checkedReadmeHandoffContract": (
            standalone.get("checkedReadmeHandoffContract") is True
        ),
        "checkedReadmeOfficialEvidenceHandoff": (
            standalone.get("checkedReadmeOfficialEvidenceHandoff") is True
        ),
        "checkedReadmeOfficialGoldenGap": (
            standalone.get("checkedReadmeOfficialGoldenGap") is True
        ),
        "checkedReadmeWaitNotifyBoundary": (
            standalone.get("checkedReadmeWaitNotifyBoundary") is True
        ),
        "checkedGeneratedReadmePrerequisites": (
            standalone.get("checkedGeneratedReadmePrerequisites") is True
        ),
        "checkedGeneratedReadmeScenarioList": (
            standalone.get("checkedGeneratedReadmeScenarioList") is True
        ),
        "checkedOfficialEvidenceManifest": (
            standalone.get("checkedOfficialEvidenceManifest") is True
        ),
        "checkedOfficialEvidenceScenarioManifest": (
            standalone.get("checkedOfficialEvidenceScenarioManifest") is True
        ),
        "checkedOfficialEvidencePreflightManifest": (
            standalone.get("checkedOfficialEvidencePreflightManifest") is True
        ),
        "checkedOfficialEvidenceAuditManifest": (
            standalone.get("checkedOfficialEvidenceAuditManifest") is True
        ),
        "checkedOfficialFixtureSetComparePolicyManifest": (
            standalone.get("checkedOfficialFixtureSetComparePolicyManifest") is True
        ),
        "checkedSourceBaselineSummaryEvidence": (
            standalone.get("checkedSourceBaselineSummaryEvidence") is True
        ),
        "checkedSourceBaselineSummaryOfficialGoldenState": (
            standalone.get("checkedSourceBaselineSummaryOfficialGoldenState") is True
        ),
        "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff": (
            standalone.get(
                "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff"
            )
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetContractManifest": (
            standalone.get("checkedSourceBaselineSummaryCapturePacketSetContractManifest")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow": (
            standalone.get("checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier": (
            standalone.get("checkedSourceBaselineSummaryCapturePacketWorkflowVerifier")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow": (
            standalone.get(
                "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
            )
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier": (
            standalone.get("checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff": (
            standalone.get("checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff": (
            standalone.get(
                "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff"
            )
            is True
        ),
        "checkedPackageArtifact": standalone.get("checkedPackageArtifact") is True,
        "checkedRuntimeContract": standalone.get("checkedRuntimeContract") is True,
        "checkedRuntimeTimeoutDiagnostics": (
            standalone.get("checkedRuntimeTimeoutDiagnostics") is True
        ),
        "checkedInitializeSurfaceContract": (
            standalone.get("checkedInitializeSurfaceContract") is True
        ),
        "checkedToolMetadataContract": (
            standalone.get("checkedToolMetadataContract") is True
        ),
        "checkedToolInputSchemaNoArguments": (
            standalone.get("checkedToolInputSchemaNoArguments") is True
        ),
        "checkedNoActiveStatusStop": standalone.get("checkedNoActiveStatusStop") is True,
        "checkedRequiresObjectParams": standalone.get("checkedRequiresObjectParams") is True,
        "checkedRequiresStringToolName": (
            standalone.get("checkedRequiresStringToolName") is True
        ),
        "checkedRequiresObjectArguments": (
            standalone.get("checkedRequiresObjectArguments") is True
        ),
        "checkedRejectsUnexpectedArguments": (
            standalone.get("checkedRejectsUnexpectedArguments") is True
        ),
        "checkedRejectsNonObjectArguments": (
            standalone.get("checkedRejectsNonObjectArguments") is True
        ),
        "checkedRejectedRequestsDoNotCreateSessionFiles": (
            standalone.get("checkedRejectedRequestsDoNotCreateSessionFiles") is True
        ),
        "checkedStatusNotUsedAsWaitLoopGuard": (
            standalone.get("checkedStatusNotUsedAsWaitLoopGuard") is True
        ),
        "checkedMcpNoDirectEventContentsGuard": (
            standalone.get("checkedMcpNoDirectEventContentsGuard") is True
        ),
        "checkedWaitNotifyContract": standalone.get("checkedWaitNotifyContract") is True,
        "checkedNotifySuppressedEventsPathEnv": (
            standalone.get("checkedNotifySuppressedEventsPathEnv") is True
        ),
        "checkedNotifyCallbackFailureExit": (
            standalone.get("checkedNotifyCallbackFailureExit") is True
        ),
        "checkedNotifyCallbackFailureReason": (
            standalone.get("checkedNotifyCallbackFailureReason") is True
        ),
        "checkedNotifyCallbackTimeoutFailureExit": (
            standalone.get("checkedNotifyCallbackTimeoutFailureExit") is True
        ),
        "checkedNotifyCallbackTimeoutReason": (
            standalone.get("checkedNotifyCallbackTimeoutReason") is True
        ),
        "checkedRecordingToSkillHandoff": (
            standalone.get("checkedRecordingToSkillHandoff") is True
        ),
        "checkedStrictValidation": standalone.get("checkedStrictValidation") is True,
        "checkedDeclaredHandoffPaths": standalone.get("checkedDeclaredHandoffPaths") is True,
        "checkedScreenshotPathContainment": (
            standalone.get("checkedScreenshotPathContainment") is True
        ),
        "checkedEventsOnlyValidation": (
            standalone.get("checkedEventsOnlyValidation") is True
        ),
        "checkedScaffoldSkill": standalone.get("checkedScaffoldSkill") is True,
        "checkedScaffoldSkillFailureExit": (
            standalone.get("checkedScaffoldSkillFailureExit") is True
        ),
        "checkedSkillCreatorHandoff": (
            standalone.get("checkedSkillCreatorHandoff") is True
        ),
        "checkedCancelledRecordingContract": (
            standalone.get("checkedCancelledRecordingContract") is True
        ),
        "checkedCancelledRecordingRejected": (
            standalone.get("checkedCancelledRecordingRejected") is True
        ),
        "checkedLifecycleSmoke": standalone.get("checkedLifecycleSmoke") is True,
        "checkedLifecycleOneActive": standalone.get("checkedOneActive") is True,
        "checkedLifecycleIdempotentStop": (
            standalone.get("checkedIdempotentStop") is True
        ),
        "checkedLifecycleFinalStatus": standalone.get("checkedFinalStatus") is True,
    }
    npm_evidence = {
        "checkedNpmLauncher": npm.get("checkedNpmLauncher") is True,
        "checkedNpmPythonLauncherDiagnostics": (
            npm.get("checkedNpmPythonLauncherDiagnostics") is True
        ),
        "checkedStandaloneRepoScaffold": npm.get("checkedStandaloneRepoScaffold") is True,
        "checkedManifestContract": npm.get("checkedManifestContract") is True,
        "checkedReadmeHandoffContract": npm.get("checkedReadmeHandoffContract") is True,
        "checkedReadmeOfficialEvidenceHandoff": (
            npm.get("checkedReadmeOfficialEvidenceHandoff") is True
        ),
        "checkedReadmeOfficialGoldenGap": (
            npm.get("checkedReadmeOfficialGoldenGap") is True
        ),
        "checkedReadmeWaitNotifyBoundary": (
            npm.get("checkedReadmeWaitNotifyBoundary") is True
        ),
        "checkedGeneratedReadmePrerequisites": (
            npm.get("checkedGeneratedReadmePrerequisites") is True
        ),
        "checkedGeneratedReadmeScenarioList": (
            npm.get("checkedGeneratedReadmeScenarioList") is True
        ),
        "checkedOfficialEvidenceManifest": (
            npm.get("checkedOfficialEvidenceManifest") is True
        ),
        "checkedOfficialEvidenceScenarioManifest": (
            npm.get("checkedOfficialEvidenceScenarioManifest") is True
        ),
        "checkedOfficialEvidencePreflightManifest": (
            npm.get("checkedOfficialEvidencePreflightManifest") is True
        ),
        "checkedOfficialEvidenceAuditManifest": (
            npm.get("checkedOfficialEvidenceAuditManifest") is True
        ),
        "checkedOfficialFixtureSetComparePolicyManifest": (
            npm.get("checkedOfficialFixtureSetComparePolicyManifest") is True
        ),
        "checkedSourceBaselineSummaryEvidence": (
            npm.get("checkedSourceBaselineSummaryEvidence") is True
        ),
        "checkedSourceBaselineSummaryOfficialGoldenState": (
            npm.get("checkedSourceBaselineSummaryOfficialGoldenState") is True
        ),
        "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff": (
            npm.get("checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetContractManifest": (
            npm.get("checkedSourceBaselineSummaryCapturePacketSetContractManifest")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow": (
            npm.get("checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier": (
            npm.get("checkedSourceBaselineSummaryCapturePacketWorkflowVerifier")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow": (
            npm.get("checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier": (
            npm.get("checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff": (
            npm.get("checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff")
            is True
        ),
        "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff": (
            npm.get(
                "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff"
            )
            is True
        ),
        "checkedPackageArtifact": npm.get("checkedPackageArtifact") is True,
        "checkedGeneratedRepoSelfCheck": npm.get("checkedGeneratedRepoSelfCheck") is True,
        "checkedRuntimeTimeoutDiagnostics": (
            npm.get("checkedRuntimeTimeoutDiagnostics") is True
        ),
        "checkedInitializeSurfaceContract": (
            npm.get("checkedInitializeSurfaceContract") is True
        ),
        "checkedToolMetadataContract": npm.get("checkedToolMetadataContract") is True,
        "checkedToolInputSchemaNoArguments": (
            npm.get("checkedToolInputSchemaNoArguments") is True
        ),
        "checkedNoActiveStatusStop": npm.get("checkedNoActiveStatusStop") is True,
        "checkedRequiresObjectParams": npm.get("checkedRequiresObjectParams") is True,
        "checkedRequiresStringToolName": (
            npm.get("checkedRequiresStringToolName") is True
        ),
        "checkedRequiresObjectArguments": (
            npm.get("checkedRequiresObjectArguments") is True
        ),
        "checkedRejectsUnexpectedArguments": (
            npm.get("checkedRejectsUnexpectedArguments") is True
        ),
        "checkedRejectsNonObjectArguments": (
            npm.get("checkedRejectsNonObjectArguments") is True
        ),
        "checkedRejectedRequestsDoNotCreateSessionFiles": (
            npm.get("checkedRejectedRequestsDoNotCreateSessionFiles") is True
        ),
        "checkedSkillWorkflow": npm.get("checkedSkillWorkflow") is True,
        "checkedStatusNotUsedAsWaitLoopGuard": (
            npm.get("checkedStatusNotUsedAsWaitLoopGuard") is True
        ),
        "checkedMcpNoDirectEventContentsGuard": (
            npm.get("checkedMcpNoDirectEventContentsGuard") is True
        ),
        "checkedWaitNotifyContract": npm.get("checkedWaitNotifyContract") is True,
        "checkedNotifySuppressedEventsPathEnv": (
            npm.get("checkedNotifySuppressedEventsPathEnv") is True
        ),
        "checkedNotifyCallbackFailureExit": (
            npm.get("checkedNotifyCallbackFailureExit") is True
        ),
        "checkedNotifyCallbackFailureReason": (
            npm.get("checkedNotifyCallbackFailureReason") is True
        ),
        "checkedNotifyCallbackTimeoutFailureExit": (
            npm.get("checkedNotifyCallbackTimeoutFailureExit") is True
        ),
        "checkedNotifyCallbackTimeoutReason": (
            npm.get("checkedNotifyCallbackTimeoutReason") is True
        ),
        "checkedSkillPackaging": npm.get("checkedSkillPackaging") is True,
        "checkedRecordingToSkillManifestContract": (
            npm.get("checkedRecordingToSkillManifestContract") is True
        ),
        "checkedCancelledRecordingContract": (
            npm.get("checkedCancelledRecordingContract") is True
        ),
        "checkedStrictValidation": npm.get("checkedStrictValidation") is True,
        "checkedDeclaredHandoffPaths": npm.get("checkedDeclaredHandoffPaths") is True,
        "checkedScreenshotPathContainment": (
            npm.get("checkedScreenshotPathContainment") is True
        ),
        "checkedEventsOnlyValidation": npm.get("checkedEventsOnlyValidation") is True,
        "checkedScaffoldSkill": npm.get("checkedScaffoldSkill") is True,
        "checkedScaffoldSkillFailureExit": (
            npm.get("checkedScaffoldSkillFailureExit") is True
        ),
        "checkedCancelledRecordingRejected": (
            npm.get("checkedCancelledRecordingRejected") is True
        ),
        "checkedRecordingToSkillHandoff": (
            npm.get("checkedRecordingToSkillHandoff") is True
        ),
        "checkedSkillCreatorHandoff": npm.get("checkedSkillCreatorHandoff") is True,
    }

    official_non_recording_baseline_verified = (
        local_surface.get("ok") is True
        and official_surface_result.get("ok") is True
        and official_no_active_evidence["ok"] is True
        and official_no_active_evidence["checkedNoSessionFilesCreated"] is True
        and official_no_active_evidence["checkedStatusShape"] is True
        and official_no_active_evidence["checkedStopShape"] is True
        and not missing_false_values(
            "officialRawStartTimeout",
            {
                key: value
                for key, value in official_raw_timeout_evidence.items()
                if key.startswith("checked") or key == "ok"
            },
        )
    )
    standalone_repo_scaffold_baseline_verified = (
        not missing_false_values("standaloneSkillRepo", standalone_evidence)
        and not missing_false_values("npmStagedSkillRepo", npm_evidence)
    )
    usable_baseline_missing_evidence = (
        missing_false_values(
            "baselineContract",
            {
                key: value
                for key, value in baseline_contract_evidence.items()
                if key.startswith("checked") or key == "ok"
            },
        )
        + missing_false_values(
            "eventStreamMatrix",
            {
                "ok": event_stream_matrix_evidence["ok"],
                "checkedDefaultLifecycleHandoff": event_stream_matrix_evidence[
                    "checkedDefaultLifecycleHandoff"
                ],
                "checkedRequiredModes": event_stream_matrix_evidence["checkedRequiredModes"],
            },
        )
        + missing_false_values(
            "screenshotContextSmoke",
            {
                "ok": screenshot_context_evidence["ok"],
                "checkedScreenshotPolicyAlways": screenshot_context_evidence[
                    "checkedScreenshotPolicyAlways"
                ],
                "checkedScreenshotNeededForContext": screenshot_context_evidence[
                    "checkedScreenshotNeededForContext"
                ],
                "checkedScreenshotPathWhenAvailable": screenshot_context_evidence[
                    "checkedScreenshotPathWhenAvailable"
                ],
            },
        )
        + missing_false_values(
            "realInputActionSmoke",
            {
                "ok": real_input_action_evidence["ok"],
                "checkedRequiredEventTypes": real_input_action_evidence[
                    "checkedRequiredEventTypes"
                ],
                "checkedSkillDraftGenerated": real_input_action_evidence[
                    "checkedSkillDraftGenerated"
                ],
                "checkedMcpTranscriptCaptured": real_input_action_evidence[
                    "checkedMcpTranscriptCaptured"
                ],
                "checkedMcpResponseShapesCaptured": real_input_action_evidence[
                    "checkedMcpResponseShapesCaptured"
                ],
                "checkedSkillReadinessCanCreateDraft": real_input_action_evidence[
                    "checkedSkillReadinessCanCreateDraft"
                ],
                "checkedSkillCreatorFinalizationHandoff": real_input_action_evidence[
                    "checkedSkillCreatorFinalizationHandoff"
                ],
                "checkedGeneratedSkillPathRedaction": real_input_action_evidence[
                    "checkedGeneratedSkillPathRedaction"
                ],
                "checkedSimpleActionStopCandidate": real_input_action_evidence[
                    "checkedSimpleActionStopCandidate"
                ],
                "checkedDragStopCandidate": real_input_action_evidence[
                    "checkedDragStopCandidate"
                ],
            },
        )
        + missing_false_values(
            "officialSurfaceCompare",
            {
                "localOk": local_surface.get("ok") is True,
                "officialOk": official_surface_result.get("ok") is True,
            },
        )
        + missing_false_values(
            "officialNoActiveResponse",
            {
                "ok": official_no_active_evidence["ok"],
                "checkedNoSessionFilesCreated": official_no_active_evidence[
                    "checkedNoSessionFilesCreated"
                ],
                "checkedStatusShape": official_no_active_evidence["checkedStatusShape"],
                "checkedStopShape": official_no_active_evidence["checkedStopShape"],
            },
        )
        + missing_false_values(
            "officialRawStartTimeout",
            {
                key: value
                for key, value in official_raw_timeout_evidence.items()
                if key.startswith("checked") or key == "ok"
            },
        )
        + missing_false_values(
            "officialFixtureSetGate",
            {
                key: value
                for key, value in official_fixture_set_evidence.items()
                if key.startswith("checked") or key == "ok"
            },
        )
        + missing_false_values("fixtureIngestPipelines", fixture_ingest_evidence)
        + missing_false_values("preflightPipelines", preflight_evidence)
        + missing_false_values("standaloneSkillRepo", standalone_evidence)
        + missing_false_values("npmStagedSkillRepo", npm_evidence)
    )
    usable_baseline = not usable_baseline_missing_evidence
    standalone_repo_baseline_ready = (
        usable_baseline and standalone_repo_scaffold_baseline_verified
    )
    official_successful_recording_equivalence_ready = (
        usable_baseline and official_successful_recording_golden_complete
    )
    missing_required_official_scenarios = (
        official_fixture_coverage.get("missingOfficialScenarios") or []
    )
    not_ready_required_official_scenarios = (
        official_fixture_coverage.get("notReadyOfficialScenarios") or []
    )
    missing_recommended_official_scenarios = (
        official_fixture_coverage.get("missingRecommendedOfficialScenarios") or []
    )
    next_actions = []
    if not usable_baseline:
        next_actions.append(
            {
                "kind": "fix-usable-baseline-evidence",
                "reason": "required baseline evidence is incomplete",
                "missingEvidence": usable_baseline_missing_evidence,
                "commands": ["make record-and-replay-baseline-smoke"],
            }
        )
    if not official_successful_recording_golden_complete:
        scenario = (
            missing_required_official_scenarios[0]
            if missing_required_official_scenarios
            else "simple-action-stop"
        )
        next_actions.append(
            {
                "kind": "capture-official-successful-recording-golden",
                "reason": "required official successful recording fixture is missing or not ready",
                "scenario": scenario,
                "missingRequiredScenarios": missing_required_official_scenarios,
                "notReadyRequiredScenarios": not_ready_required_official_scenarios,
                "commands": [
                    (
                        "make record-and-replay-official-golden-capture-packet "
                        f"RNR_SCENARIO={scenario} RNR_PACKET_DIR=<packet-dir>"
                    ),
                    "cd <packet-dir> && ./verify-inputs.sh",
                    "cd <packet-dir> && ./inspect-only.sh",
                    "cd <packet-dir> && ./import-fixture.sh",
                    (
                        "./scripts/ingest-official-record-and-replay-fixture.py "
                        "--status-json <event_stream_stop-response.json> "
                        f"--name official-{scenario}-1.0.857 "
                        f"--scenario {scenario} --inspect-only"
                    ),
                    "make record-and-replay-official-golden-gate-audit",
                ],
            }
        )
    if missing_recommended_official_scenarios:
        next_actions.append(
            {
                "kind": "capture-recommended-official-golden-set",
                "reason": "recommended calibration scenarios are not fully covered",
                "missingRecommendedScenarios": missing_recommended_official_scenarios,
                "commands": [
                    (
                        "make record-and-replay-official-golden-capture-packet-set "
                        "RNR_PACKET_DIR=<packet-dir>"
                    ),
                    "cd <packet-dir> && ./verify-all.sh",
                    "cd <packet-dir> && ./inspect-all.sh",
                    "cd <packet-dir> && ./import-all.sh",
                    "cd <packet-dir> && ./ingest-ocu-candidates.sh",
                ],
            }
        )
    if standalone_repo_baseline_ready:
        next_actions.append(
            {
                "kind": "scaffold-standalone-record-and-replay-repo",
                "reason": "standalone repo baseline is ready, but official equivalence still depends on golden fixtures",
                "commands": [
                    "make record-and-replay-baseline-audit",
                    "open-computer-use scaffold-record-and-replay-skill-repo --output-dir <new-repo>",
                    "cd <new-repo> && ./scripts/check.sh",
                    "cd <new-repo> && ./scripts/recording-lifecycle-smoke.py",
                ],
            }
        )

    return {
        "ok": usable_baseline and official_golden_requirement_satisfied,
        "baseline": "record-and-replay",
        "checks": list(REQUIRED_BASELINE_CHECKS),
        "status": {
            "usableBaseline": usable_baseline,
            "missingUsableBaselineEvidence": usable_baseline_missing_evidence,
            "strictOfficialGoldenRequired": args.require_official_golden,
            "officialGoldenRequirementSatisfied": official_golden_requirement_satisfied,
            "officialGoldenGatePassed": official_golden_gate_passed,
            "officialNonRecordingBaselineVerified": official_non_recording_baseline_verified,
            "officialRawStartTimeoutBoundaryVerified": not missing_false_values(
                "officialRawStartTimeout",
                {
                    key: value
                    for key, value in official_raw_timeout_evidence.items()
                    if key.startswith("checked") or key == "ok"
                },
            ),
            "standaloneRepoScaffoldBaselineVerified": (
                standalone_repo_scaffold_baseline_verified
            ),
            "standaloneRepoBaselineReady": standalone_repo_baseline_ready,
            "officialSuccessfulRecordingGoldenComplete": (
                official_successful_recording_golden_complete
            ),
            "officialSuccessfulRecordingEquivalenceReady": (
                official_successful_recording_equivalence_ready
            ),
            "recommendedOfficialRecordingCoverageComplete": (
                recommended_official_recording_coverage_complete
            ),
            "requiresOfficialGoldenCapture": (
                not official_successful_recording_golden_complete
            ),
            "missingRequiredOfficialSuccessfulRecordingScenarios": (
                missing_required_official_scenarios
            ),
            "notReadyRequiredOfficialSuccessfulRecordingScenarios": (
                not_ready_required_official_scenarios
            ),
            "missingRecommendedOfficialSuccessfulRecordingScenarios": (
                missing_recommended_official_scenarios
            ),
            "officialFixtureCoverageErrors": official_fixture_coverage.get("errors") or [],
        },
        "nextActions": next_actions,
        "evidence": {
            "baselineContract": baseline_contract_evidence,
            "eventStreamMatrix": event_stream_matrix_evidence,
            "screenshotContextSmoke": screenshot_context_evidence,
            "realInputActionSmoke": real_input_action_evidence,
            "officialSurfaceCompare": official_surface_evidence,
            "officialNoActiveResponse": official_no_active_evidence,
            "officialRawStartTimeout": official_raw_timeout_evidence,
            "officialFixtureSetGate": official_fixture_set_evidence,
            "fixtureIngestPipelines": fixture_ingest_evidence,
            "preflightPipelines": preflight_evidence,
            "standaloneSkillRepo": standalone_evidence,
            "npmStagedSkillRepo": npm_evidence,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build the final machine-readable Record & Replay baseline summary."
    )
    parser.add_argument("--standalone-json", required=True, type=pathlib.Path)
    parser.add_argument("--npm-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-surface-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-no-active-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-raw-timeout-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-fixture-set-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-fixture-coverage-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-fixture-ingest-json", required=True, type=pathlib.Path)
    parser.add_argument("--ocu-candidate-ingest-json", required=True, type=pathlib.Path)
    parser.add_argument("--official-capture-preflight-json", required=True, type=pathlib.Path)
    parser.add_argument("--ocu-pairing-preflight-json", required=True, type=pathlib.Path)
    parser.add_argument("--baseline-audit-targets-json", required=True, type=pathlib.Path)
    parser.add_argument("--baseline-contract-json", required=True, type=pathlib.Path)
    parser.add_argument("--matrix-jsonl", required=True, type=pathlib.Path)
    parser.add_argument("--screenshot-jsonl", required=True, type=pathlib.Path)
    parser.add_argument("--action-jsonl", required=True, type=pathlib.Path)
    parser.add_argument(
        "--require-official-golden",
        action="store_true",
        help="Return non-zero unless required official successful recording fixtures exist.",
    )
    args = parser.parse_args()

    summary = build_summary(args)
    print(json.dumps(summary, sort_keys=True), flush=True)
    if not summary["status"]["usableBaseline"]:
        missing = summary["status"].get("missingUsableBaselineEvidence") or []
        print(
            "Record & Replay usable baseline evidence is incomplete: " + ", ".join(missing),
            file=sys.stderr,
        )
    if not summary["status"]["officialGoldenRequirementSatisfied"]:
        missing = summary["status"].get("missingRequiredOfficialSuccessfulRecordingScenarios") or []
        not_ready = (
            summary["status"].get("notReadyRequiredOfficialSuccessfulRecordingScenarios")
            or []
        )
        details = []
        if missing:
            details.append("missing=" + ", ".join(missing))
        if not_ready:
            details.append("notReady=" + ", ".join(not_ready))
        coverage_errors = (
            summary["status"].get("officialFixtureCoverageErrors")
            or []
        )
        if coverage_errors:
            details.append("coverageErrors=" + " | ".join(coverage_errors))
        if not details:
            details.append("readiness=failed")
        print(
            "official successful recording golden fixture coverage/readiness is incomplete: "
            + "; ".join(details),
            file=sys.stderr,
        )
    if not summary["ok"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
