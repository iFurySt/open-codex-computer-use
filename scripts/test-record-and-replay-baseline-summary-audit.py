#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile


def load_summary_fixtures(repo: pathlib.Path):
    module_path = repo / "scripts/test-record-and-replay-baseline-summary.py"
    spec = importlib.util.spec_from_file_location("baseline_summary_fixtures", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_audit_module(repo: pathlib.Path):
    module_path = repo / "scripts/check-record-and-replay-baseline-summary.py"
    spec = importlib.util.spec_from_file_location("baseline_summary_audit", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(command: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def parse_json(stdout: str) -> dict:
    return json.loads(stdout)


def write_json(path: pathlib.Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def build_summary(
    repo: pathlib.Path,
    fixture_module,
    root: pathlib.Path,
    has_official_golden: bool,
    require_official_golden: bool = False,
) -> tuple[pathlib.Path, dict]:
    builder = repo / "scripts/build-record-and-replay-baseline-summary.py"
    paths = fixture_module.write_inputs(root, has_official_golden=has_official_golden)
    command = fixture_module.summary_command(builder, paths)
    if require_official_golden:
        command.append("--require-official-golden")
    result = run(command, repo)
    assert result.returncode == 0, result.stderr
    summary = fixture_module.parse_last_json(result.stdout)
    summary_path = root / "baseline-summary.json"
    write_json(summary_path, summary)
    return summary_path, summary


def main() -> None:
    repo = pathlib.Path(__file__).resolve().parents[1]
    fixture_module = load_summary_fixtures(repo)
    audit_module = load_audit_module(repo)
    audit = repo / "scripts/check-record-and-replay-baseline-summary.py"

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)

        default_summary_path, default_summary = build_summary(
            repo,
            fixture_module,
            root / "default",
            has_official_golden=False,
        )
        assert default_summary["status"]["usableBaseline"] is True
        assert default_summary["status"]["officialSuccessfulRecordingGoldenComplete"] is False
        assert default_summary["checks"] == list(audit_module.REQUIRED_BASELINE_CHECKS)
        assert set(default_summary["checks"]) == set(audit_module.REQUIRED_BASELINE_CHECKS)
        default_audit = run([sys.executable, str(audit), str(default_summary_path)], repo)
        assert default_audit.returncode == 0, default_audit.stderr
        default_audit_json = parse_json(default_audit.stdout)
        assert default_audit_json["ok"] is True
        assert default_audit_json["checks"]["checkedAllowsMissingOfficialGoldenButNotEquivalence"] is True

        strict_missing_audit = run(
            [
                sys.executable,
                str(audit),
                str(default_summary_path),
                "--require-official-golden",
            ],
            repo,
        )
        assert strict_missing_audit.returncode == 1
        strict_missing_json = parse_json(strict_missing_audit.stdout)
        assert strict_missing_json["ok"] is False
        assert "checkedStrictModeMatchesExpectation" in strict_missing_json["failures"]
        assert "checkedOfficialGoldenGatePassed" in strict_missing_json["failures"]
        assert "checkedOfficialSuccessfulRecordingEquivalenceReady" in strict_missing_json[
            "failures"
        ]

        expected_strict_missing_summary = json.loads(json.dumps(default_summary))
        expected_strict_missing_summary["ok"] = False
        expected_strict_missing_summary["status"][
            "strictOfficialGoldenRequired"
        ] = True
        expected_strict_missing_summary["status"][
            "officialGoldenRequirementSatisfied"
        ] = False
        expected_strict_missing_path = root / "expected-strict-missing-summary.json"
        write_json(expected_strict_missing_path, expected_strict_missing_summary)
        expected_strict_missing_audit = run(
            [
                sys.executable,
                str(audit),
                str(expected_strict_missing_path),
                "--allow-strict-official-golden-missing",
            ],
            repo,
        )
        assert expected_strict_missing_audit.returncode == 0, (
            expected_strict_missing_audit.stderr
        )
        expected_strict_missing_json = parse_json(expected_strict_missing_audit.stdout)
        assert expected_strict_missing_json["ok"] is True
        assert expected_strict_missing_json["checks"][
            "checkedStrictOfficialGoldenMissingFailure"
        ] is True
        assert expected_strict_missing_json["checks"][
            "checkedStrictMissingGoldenHasRequiredGap"
        ] is True

        default_with_allow_missing_audit = run(
            [
                sys.executable,
                str(audit),
                str(default_summary_path),
                "--allow-strict-official-golden-missing",
            ],
            repo,
        )
        assert default_with_allow_missing_audit.returncode == 1
        default_with_allow_missing_json = parse_json(default_with_allow_missing_audit.stdout)
        assert "checkedStrictModeMatchesExpectation" in default_with_allow_missing_json[
            "failures"
        ]

        unexplained_strict_missing_summary = json.loads(
            json.dumps(expected_strict_missing_summary)
        )
        unexplained_strict_missing_summary["status"][
            "missingRequiredOfficialSuccessfulRecordingScenarios"
        ] = []
        unexplained_strict_missing_summary["status"][
            "notReadyRequiredOfficialSuccessfulRecordingScenarios"
        ] = []
        unexplained_strict_missing_path = (
            root / "unexplained-strict-missing-summary.json"
        )
        write_json(unexplained_strict_missing_path, unexplained_strict_missing_summary)
        unexplained_strict_missing_audit = run(
            [
                sys.executable,
                str(audit),
                str(unexplained_strict_missing_path),
                "--allow-strict-official-golden-missing",
            ],
            repo,
        )
        assert unexplained_strict_missing_audit.returncode == 1
        unexplained_strict_missing_json = parse_json(
            unexplained_strict_missing_audit.stdout
        )
        assert "checkedStrictMissingGoldenHasRequiredGap" in (
            unexplained_strict_missing_json["failures"]
        )

        strict_summary_path, strict_summary = build_summary(
            repo,
            fixture_module,
            root / "strict-covered",
            has_official_golden=True,
            require_official_golden=True,
        )
        assert strict_summary["status"]["officialSuccessfulRecordingEquivalenceReady"] is True
        strict_audit = run(
            [
                sys.executable,
                str(audit),
                str(strict_summary_path),
                "--require-official-golden",
            ],
            repo,
        )
        assert strict_audit.returncode == 0, strict_audit.stderr
        assert parse_json(strict_audit.stdout)["ok"] is True

        inconsistent_summary = dict(default_summary)
        inconsistent_summary["status"] = dict(default_summary["status"])
        inconsistent_summary["status"]["officialSuccessfulRecordingEquivalenceReady"] = True
        inconsistent_path = root / "inconsistent-summary.json"
        write_json(inconsistent_path, inconsistent_summary)
        inconsistent_audit = run([sys.executable, str(audit), str(inconsistent_path)], repo)
        assert inconsistent_audit.returncode == 1
        inconsistent_json = parse_json(inconsistent_audit.stdout)
        assert "checkedEquivalenceRequiresGolden" in inconsistent_json["failures"]
        assert "checkedEquivalenceReadyMatchesPolicy" in inconsistent_json["failures"]
        assert "checkedAllowsMissingOfficialGoldenButNotEquivalence" in inconsistent_json[
            "failures"
        ]

        derived_status_summary = json.loads(json.dumps(default_summary))
        derived_status = derived_status_summary["status"]
        derived_status["requiresOfficialGoldenCapture"] = False
        derived_status["missingRequiredOfficialSuccessfulRecordingScenarios"] = []
        derived_status["notReadyRequiredOfficialSuccessfulRecordingScenarios"] = []
        derived_status["officialFixtureCoverageErrors"] = []
        derived_status["standaloneRepoBaselineReady"] = True
        derived_status["usableBaseline"] = False
        derived_status_path = root / "derived-status-summary.json"
        write_json(derived_status_path, derived_status_summary)
        derived_status_audit = run(
            [sys.executable, str(audit), str(derived_status_path)],
            repo,
        )
        assert derived_status_audit.returncode == 1
        derived_status_json = parse_json(derived_status_audit.stdout)
        assert "checkedTopLevelOkMatchesPolicy" in derived_status_json["failures"]
        assert "checkedUsableBaseline" in derived_status_json["failures"]
        assert "checkedStandaloneReadyRequiresUsableBaseline" in derived_status_json[
            "failures"
        ]
        assert "checkedRequiresOfficialGoldenCaptureConsistency" in derived_status_json[
            "failures"
        ]
        assert "checkedMissingGoldenHasScenarioGapOrCoverageError" in derived_status_json[
            "failures"
        ]

        complete_with_gaps_summary = json.loads(json.dumps(strict_summary))
        complete_with_gaps_summary["status"][
            "missingRequiredOfficialSuccessfulRecordingScenarios"
        ] = ["simple-action-stop"]
        complete_with_gaps_path = root / "complete-with-gaps-summary.json"
        write_json(complete_with_gaps_path, complete_with_gaps_summary)
        complete_with_gaps_audit = run(
            [sys.executable, str(audit), str(complete_with_gaps_path)],
            repo,
        )
        assert complete_with_gaps_audit.returncode == 1
        complete_with_gaps_json = parse_json(complete_with_gaps_audit.stdout)
        assert "checkedOfficialGoldenCompleteHasNoRequiredGaps" in complete_with_gaps_json[
            "failures"
        ]

        incomplete_summary_path, incomplete_summary = build_summary(
            repo,
            fixture_module,
            root / "incomplete-base",
            has_official_golden=False,
        )
        incomplete_summary["status"]["usableBaseline"] = False
        incomplete_summary["status"]["missingUsableBaselineEvidence"] = [
            "standaloneSkillRepo.checkedRuntimeContract"
        ]
        write_json(incomplete_summary_path, incomplete_summary)
        incomplete_audit = run([sys.executable, str(audit), str(incomplete_summary_path)], repo)
        assert incomplete_audit.returncode == 1
        incomplete_json = parse_json(incomplete_audit.stdout)
        assert "checkedUsableBaseline" in incomplete_json["failures"]
        assert "checkedNoMissingUsableBaselineEvidence" in incomplete_json["failures"]

        top_level_mismatch_summary = dict(default_summary)
        top_level_mismatch_summary["ok"] = False
        top_level_mismatch_path = root / "top-level-mismatch-summary.json"
        write_json(top_level_mismatch_path, top_level_mismatch_summary)
        top_level_mismatch_audit = run(
            [sys.executable, str(audit), str(top_level_mismatch_path)],
            repo,
        )
        assert top_level_mismatch_audit.returncode == 1
        top_level_mismatch_json = parse_json(top_level_mismatch_audit.stdout)
        assert "checkedTopLevelOkMatchesPolicy" in top_level_mismatch_json["failures"]

        baseline_name_mismatch_summary = dict(default_summary)
        baseline_name_mismatch_summary["baseline"] = "record-and-replay-copy"
        baseline_name_mismatch_path = root / "baseline-name-mismatch-summary.json"
        write_json(baseline_name_mismatch_path, baseline_name_mismatch_summary)
        baseline_name_mismatch_audit = run(
            [sys.executable, str(audit), str(baseline_name_mismatch_path)],
            repo,
        )
        assert baseline_name_mismatch_audit.returncode == 1
        baseline_name_mismatch_json = parse_json(baseline_name_mismatch_audit.stdout)
        assert "checkedBaselineName" in baseline_name_mismatch_json["failures"]

        declared_checks_summary = json.loads(json.dumps(default_summary))
        declared_checks_summary["checks"] = [
            check
            for check in declared_checks_summary["checks"]
            if check
            not in {
                "official-no-active-response-compare",
                "npm-staged-skill-repo-smoke",
            }
        ]
        declared_checks_path = root / "declared-checks-summary.json"
        write_json(declared_checks_path, declared_checks_summary)
        declared_checks_audit = run(
            [sys.executable, str(audit), str(declared_checks_path)],
            repo,
        )
        assert declared_checks_audit.returncode == 1
        declared_checks_json = parse_json(declared_checks_audit.stdout)
        assert "checkedRequiredBaselineChecksDeclared" in declared_checks_json["failures"]
        assert declared_checks_json["declaredChecks"]["missingRequired"] == [
            "npm-staged-skill-repo-smoke",
            "official-no-active-response-compare",
        ]
        assert declared_checks_json["declaredChecks"]["unknown"] == []
        assert declared_checks_json["declaredChecks"]["duplicates"] == []

        extra_declared_checks_summary = json.loads(json.dumps(default_summary))
        extra_declared_checks_summary["checks"].extend(
            [
                "event-stream-smoke-matrix",
                "obsolete-record-and-replay-smoke",
            ]
        )
        extra_declared_checks_path = root / "extra-declared-checks-summary.json"
        write_json(extra_declared_checks_path, extra_declared_checks_summary)
        extra_declared_checks_audit = run(
            [sys.executable, str(audit), str(extra_declared_checks_path)],
            repo,
        )
        assert extra_declared_checks_audit.returncode == 1
        extra_declared_checks_json = parse_json(extra_declared_checks_audit.stdout)
        assert "checkedNoUnknownBaselineChecksDeclared" in extra_declared_checks_json[
            "failures"
        ]
        assert "checkedNoDuplicateBaselineChecksDeclared" in extra_declared_checks_json[
            "failures"
        ]
        assert extra_declared_checks_json["declaredChecks"]["unknown"] == [
            "obsolete-record-and-replay-smoke"
        ]
        assert extra_declared_checks_json["declaredChecks"]["duplicates"] == [
            "event-stream-smoke-matrix"
        ]

        audit_target_evidence_summary = dict(default_summary)
        audit_target_evidence_summary["evidence"] = dict(default_summary["evidence"])
        audit_target_evidence_summary["evidence"]["preflightPipelines"] = dict(
            default_summary["evidence"]["preflightPipelines"]
        )
        audit_target_evidence_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditMakeTargets"
        ] = False
        audit_target_evidence_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditIgnoresStrictSummaryVar"
        ] = False
        audit_target_evidence_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenTarget"
        ] = False
        audit_target_evidence_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar"
        ] = False
        audit_target_evidence_summary["evidence"]["preflightPipelines"][
            "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath"
        ] = False
        audit_target_evidence_path = root / "audit-target-evidence-summary.json"
        write_json(audit_target_evidence_path, audit_target_evidence_summary)
        audit_target_evidence_audit = run(
            [sys.executable, str(audit), str(audit_target_evidence_path)],
            repo,
        )
        assert audit_target_evidence_audit.returncode == 1
        audit_target_evidence_json = parse_json(audit_target_evidence_audit.stdout)
        assert "checkedBaselineAuditMakeTargetsEvidence" in audit_target_evidence_json[
            "failures"
        ]
        assert (
            "checkedBaselineAuditIgnoresStrictSummaryVarEvidence"
            in audit_target_evidence_json["failures"]
        )
        assert (
            "checkedBaselineAuditStrictOfficialGoldenTargetEvidence"
            in audit_target_evidence_json["failures"]
        )
        assert (
            "checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVarEvidence"
            in audit_target_evidence_json["failures"]
        )
        assert (
            "checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPathEvidence"
            in audit_target_evidence_json["failures"]
        )

        preflight_evidence_summary = json.loads(json.dumps(default_summary))
        preflight_evidence = preflight_evidence_summary["evidence"]["preflightPipelines"]
        preflight_evidence["checkedOfficialCapturePacketPostCaptureWorkflow"] = False
        preflight_evidence["checkedOfficialCapturePacketWorkflowVerifier"] = False
        preflight_evidence["checkedOfficialCapturePacketHandoffScripts"] = False
        preflight_evidence["checkedOfficialCapturePacketStrictAuditHandoff"] = False
        preflight_evidence[
            "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
        ] = False
        preflight_evidence["checkedOfficialCapturePacketOcuCandidateOutputDir"] = False
        preflight_evidence["checkedOfficialCapturePacketNoTranscript"] = False
        preflight_evidence["checkedOfficialCapturePacketTranscriptManifest"] = False
        preflight_evidence["checkedOfficialCapturePacketInputSemanticGuard"] = False
        preflight_evidence["checkedOfficialCapturePacketSetOcuCandidateHandoff"] = False
        preflight_evidence["checkedOfficialCapturePacketSetPostCaptureWorkflow"] = False
        preflight_evidence["checkedOfficialCapturePacketSetWorkflowVerifier"] = False
        preflight_evidence["checkedOfficialCapturePacketSetContractManifest"] = False
        preflight_evidence["checkedOfficialCapturePacketSetVerifyAll"] = False
        preflight_evidence["checkedOcuPairingPairedCandidatePreflight"] = False
        preflight_evidence_path = root / "preflight-evidence-summary.json"
        write_json(preflight_evidence_path, preflight_evidence_summary)
        preflight_evidence_audit = run(
            [sys.executable, str(audit), str(preflight_evidence_path)],
            repo,
        )
        assert preflight_evidence_audit.returncode == 1
        preflight_evidence_json = parse_json(preflight_evidence_audit.stdout)
        assert (
            "checkedOfficialCapturePacketPostCaptureWorkflowEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketWorkflowVerifierEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketHandoffScriptsEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketStrictAuditHandoffEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoffEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketOcuCandidateOutputDirEvidence"
            in preflight_evidence_json["failures"]
        )
        assert "checkedOfficialCapturePacketNoTranscriptEvidence" in preflight_evidence_json[
            "failures"
        ]
        assert (
            "checkedOfficialCapturePacketTranscriptManifestEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketInputSemanticGuardEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketSetOcuCandidateHandoffEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketSetPostCaptureWorkflowEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketSetWorkflowVerifierEvidence"
            in preflight_evidence_json["failures"]
        )
        assert (
            "checkedOfficialCapturePacketSetContractManifestEvidence"
            in preflight_evidence_json["failures"]
        )
        assert "checkedOfficialCapturePacketSetVerifyAllEvidence" in preflight_evidence_json[
            "failures"
        ]
        assert "checkedOcuPairingPairedCandidatePreflightEvidence" in preflight_evidence_json[
            "failures"
        ]

        contract_evidence_summary = json.loads(json.dumps(default_summary))
        contract_evidence_summary["evidence"]["baselineContract"][
            "checkedStandaloneLifecycleSummaryRenames"
        ] = False
        contract_evidence_path = root / "contract-evidence-summary.json"
        write_json(contract_evidence_path, contract_evidence_summary)
        contract_evidence_audit = run(
            [sys.executable, str(audit), str(contract_evidence_path)],
            repo,
        )
        assert contract_evidence_audit.returncode == 1
        contract_evidence_json = parse_json(contract_evidence_audit.stdout)
        assert (
            "checkedBaselineContractStandaloneSummaryRenamesEvidence"
            in contract_evidence_json["failures"]
        )
        assert (
            "checkedBaselineContractCheckedStandaloneLifecycleSummaryRenamesEvidence"
            in contract_evidence_json["failures"]
        )

        usable_evidence_summary = json.loads(json.dumps(default_summary))
        usable_evidence = usable_evidence_summary["evidence"]
        usable_evidence["eventStreamMatrix"]["ok"] = False
        usable_evidence["screenshotContextSmoke"][
            "checkedScreenshotNeededForContext"
        ] = False
        usable_evidence["realInputActionSmoke"][
            "checkedMcpResponseShapesCaptured"
        ] = False
        usable_evidence["realInputActionSmoke"][
            "checkedSimpleActionStopCandidate"
        ] = False
        usable_evidence["realInputActionSmoke"]["checkedDragStopCandidate"] = False
        usable_evidence["officialFixtureSetGate"]["checkedCandidatePairing"] = False
        usable_evidence["officialFixtureSetGate"][
            "checkedAxDiffComparisonPolicy"
        ] = False
        usable_evidence["officialFixtureSetGate"][
            "checkedSuppressedStreamComparisonPolicy"
        ] = False
        usable_evidence["officialFixtureSetGate"][
            "checkedAxDiffComparisonFailure"
        ] = False
        usable_evidence["fixtureIngestPipelines"][
            "checkedOfficialFixtureInspectOnly"
        ] = False
        usable_evidence["fixtureIngestPipelines"][
            "checkedOfficialSessionDirectoryPathHandoff"
        ] = False
        usable_evidence["fixtureIngestPipelines"][
            "checkedOcuCandidateIngestHandoffCommands"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedGeneratedReadmePrerequisites"
        ] = False
        usable_evidence["standaloneSkillRepo"]["checkedManifestContract"] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedOfficialEvidenceAuditManifest"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedOfficialFixtureSetComparePolicyManifest"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryEvidence"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryOfficialGoldenState"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetContractManifest"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier"
        ] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff"
        ] = False
        usable_evidence["standaloneSkillRepo"]["checkedPackageArtifact"] = False
        usable_evidence["standaloneSkillRepo"][
            "checkedNotifySuppressedEventsPathEnv"
        ] = False
        usable_evidence["standaloneSkillRepo"]["checkedGeneratedReadmeScenarioList"] = False
        usable_evidence["standaloneSkillRepo"]["checkedRuntimeTimeoutDiagnostics"] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedNpmPythonLauncherDiagnostics"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedGeneratedReadmePrerequisites"
        ] = False
        usable_evidence["npmStagedSkillRepo"]["checkedManifestContract"] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedOfficialEvidenceAuditManifest"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedOfficialFixtureSetComparePolicyManifest"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryEvidence"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryOfficialGoldenState"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetContractManifest"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier"
        ] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff"
        ] = False
        usable_evidence["npmStagedSkillRepo"]["checkedPackageArtifact"] = False
        usable_evidence["npmStagedSkillRepo"][
            "checkedNotifySuppressedEventsPathEnv"
        ] = False
        usable_evidence["npmStagedSkillRepo"]["checkedRuntimeTimeoutDiagnostics"] = False
        usable_evidence["npmStagedSkillRepo"]["checkedScaffoldSkill"] = False
        usable_evidence_path = root / "usable-evidence-summary.json"
        write_json(usable_evidence_path, usable_evidence_summary)
        usable_evidence_audit = run(
            [sys.executable, str(audit), str(usable_evidence_path)],
            repo,
        )
        assert usable_evidence_audit.returncode == 1
        usable_evidence_json = parse_json(usable_evidence_audit.stdout)
        assert "checkedEventStreamMatrixOkEvidence" in usable_evidence_json["failures"]
        assert (
            "checkedScreenshotContextSmokeCheckedScreenshotNeededForContextEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedRealInputActionSmokeCheckedMcpResponseShapesCapturedEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedRealInputActionSmokeCheckedSimpleActionStopCandidateEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedRealInputActionSmokeCheckedDragStopCandidateEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedOfficialFixtureSetGateCheckedCandidatePairingEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedFixtureIngestPipelinesCheckedOfficialFixtureInspectOnlyEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedGeneratedReadmeScenarioListEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedGeneratedReadmePrerequisitesEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedManifestContractEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketSetContractManifestEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflowEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketWorkflowVerifierEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflowEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketSetWorkflowVerifierEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryCapturePacketStrictAuditHandoffEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedPackageArtifactEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedSourceBaselineSummaryOfficialGoldenStateEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedRuntimeTimeoutDiagnosticsEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedStandaloneSkillRepoCheckedNotifySuppressedEventsPathEnvEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedGeneratedReadmePrerequisitesEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedManifestContractEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketSetContractManifestEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflowEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketWorkflowVerifierEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflowEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketSetWorkflowVerifierEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryCapturePacketStrictAuditHandoffEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedPackageArtifactEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedSourceBaselineSummaryOfficialGoldenStateEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedRuntimeTimeoutDiagnosticsEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedNotifySuppressedEventsPathEnvEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedNpmPythonLauncherDiagnosticsEvidence"
            in usable_evidence_json["failures"]
        )
        assert (
            "checkedNpmStagedSkillRepoCheckedScaffoldSkillEvidence"
            in usable_evidence_json["failures"]
        )

        next_action_command_summary = json.loads(json.dumps(default_summary))
        for action in next_action_command_summary["nextActions"]:
            if action.get("kind") == "capture-official-successful-recording-golden":
                action["commands"] = [
                    command
                    for command in action["commands"]
                    if "record-and-replay-official-golden-capture-packet" not in command
                    and "./verify-inputs.sh" not in command
                ]
            elif action.get("kind") == "capture-recommended-official-golden-set":
                action["commands"] = [
                    command
                    for command in action["commands"]
                    if "./verify-all.sh" not in command
                    and "./ingest-ocu-candidates.sh" not in command
                ]
            elif action.get("kind") == "scaffold-standalone-record-and-replay-repo":
                action["commands"] = [
                    command
                    for command in action["commands"]
                    if "record-and-replay-baseline-audit" not in command
                    and "./scripts/check.sh" not in command
                ]
        next_action_command_path = root / "next-action-command-summary.json"
        write_json(next_action_command_path, next_action_command_summary)
        next_action_command_audit = run(
            [sys.executable, str(audit), str(next_action_command_path)],
            repo,
        )
        assert next_action_command_audit.returncode == 1
        next_action_command_json = parse_json(next_action_command_audit.stdout)
        assert (
            "checkedMissingGoldenNextActionPacketMakeCommand"
            in next_action_command_json["failures"]
        )
        assert (
            "checkedMissingGoldenNextActionVerifyStep"
            in next_action_command_json["failures"]
        )
        assert (
            "checkedRecommendedGoldenNextActionVerifyAllStep"
            in next_action_command_json["failures"]
        )
        assert (
            "checkedRecommendedGoldenNextActionIngestOcuCandidatesStep"
            in next_action_command_json["failures"]
        )
        assert (
            "checkedStandaloneNextActionBaselineAuditCommand"
            in next_action_command_json["failures"]
        )
        assert (
            "checkedStandaloneNextActionCheckCommand"
            in next_action_command_json["failures"]
        )

        official_boundary_evidence_summary = json.loads(json.dumps(default_summary))
        official_boundary_evidence_summary["evidence"]["officialSurfaceCompare"]["official"][
            "ok"
        ] = False
        official_boundary_evidence_summary["evidence"]["officialNoActiveResponse"][
            "checkedStopShape"
        ] = False
        official_boundary_evidence_summary["evidence"]["officialRawStartTimeout"][
            "checkedOfficialRawStartDoesNotReturnRecordingPaths"
        ] = False
        official_boundary_evidence_path = root / "official-boundary-evidence-summary.json"
        write_json(official_boundary_evidence_path, official_boundary_evidence_summary)
        official_boundary_evidence_audit = run(
            [sys.executable, str(audit), str(official_boundary_evidence_path)],
            repo,
        )
        assert official_boundary_evidence_audit.returncode == 1
        official_boundary_evidence_json = parse_json(
            official_boundary_evidence_audit.stdout
        )
        assert "checkedOfficialSurfaceBundledEvidence" in official_boundary_evidence_json[
            "failures"
        ]
        assert "checkedOfficialNoActiveStopShapeEvidence" in official_boundary_evidence_json[
            "failures"
        ]
        assert (
            "checkedOfficialRawStartDoesNotReturnRecordingPathsEvidence"
            in official_boundary_evidence_json["failures"]
        )

    print(
        json.dumps(
            {
                "ok": True,
                "checkedDefaultMissingOfficialGoldenAudit": True,
                "checkedBuilderChecksMatchAuditRequirements": True,
                "checkedStrictMissingOfficialGoldenAuditFails": True,
                "checkedExpectedStrictMissingOfficialGoldenAudit": True,
                "checkedStrictCoveredOfficialGoldenAudit": True,
                "checkedInconsistentEquivalenceAuditFails": True,
                "checkedDerivedStatusAuditFails": True,
                "checkedCompleteGoldenWithGapsAuditFails": True,
                "checkedIncompleteBaselineAuditFails": True,
                "checkedTopLevelOkPolicyAuditFails": True,
                "checkedBaselineNameAuditFails": True,
                "checkedDeclaredChecksAuditFails": True,
                "checkedExtraDeclaredChecksAuditFails": True,
                "checkedBaselineAuditTargetEvidenceAuditFails": True,
                "checkedPreflightPipelineEvidenceAuditFails": True,
                "checkedUsableBaselineDirectEvidenceAuditFails": True,
                "checkedNextActionCommandAuditFails": True,
                "checkedOfficialBoundaryEvidenceAuditFails": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
