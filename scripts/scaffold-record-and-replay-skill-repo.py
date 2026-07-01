#!/usr/bin/env python3

import argparse
import json
import pathlib
import shutil
import sys
import textwrap

from record_and_replay_scenarios import (
    DEFAULT_RECOMMENDED_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_recipe,
)


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_SKILL_NAME = "open-computer-use-record-and-replay"
SOURCE_SKILL_DIR = REPO_ROOT / "skills" / SOURCE_SKILL_NAME


PACKAGE_SCRIPT = """#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_root="${repo_root}/skills"
dist_dir="${repo_root}/dist/skills"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required" >&2
  exit 1
fi

rm -rf "${dist_dir}"
mkdir -p "${dist_dir}"

while IFS= read -r skill_md; do
  skill_dir="$(dirname "${skill_md}")"
  skill_name="$(basename "${skill_dir}")"
  python3 - "${skill_md}" "${skill_name}" <<'PY'
import pathlib
import sys

skill_path = pathlib.Path(sys.argv[1])
expected_name = sys.argv[2]
content = skill_path.read_text()
if not content.startswith("---\\n"):
    raise SystemExit(f"{skill_path} is missing YAML frontmatter")
try:
    _prefix, frontmatter, _rest = content.split("---", 2)
except ValueError as error:
    raise SystemExit(f"{skill_path} has malformed YAML frontmatter") from error

fields = {}
for line in frontmatter.splitlines():
    if ":" not in line:
        continue
    key, value = line.split(":", 1)
    fields[key.strip()] = value.strip()

if fields.get("name") != expected_name:
    raise SystemExit(
        f"{skill_path} frontmatter name must be {expected_name!r}, got {fields.get('name')!r}"
    )
if not fields.get("description"):
    raise SystemExit(f"{skill_path} frontmatter description is required")
PY
  zip_path="${dist_dir}/${skill_name}-skill.zip"
  skill_path="${dist_dir}/${skill_name}.skill"
  (
    cd "${skills_root}"
    zip -q -r "${zip_path}" "${skill_name}"
  )
  cp "${zip_path}" "${skill_path}"
  echo "${zip_path}"
  echo "${skill_path}"
done < <(find "${skills_root}" -mindepth 2 -maxdepth 2 -name SKILL.md -print | sort)
"""


CHECK_SCRIPT = """#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/package-skill.sh"
"${repo_root}/scripts/verify-package-artifact.py"
"${repo_root}/scripts/verify-manifest.py"
"${repo_root}/scripts/verify-source-baseline-summary.py"
"${repo_root}/scripts/verify-readme-handoff.py"
"${repo_root}/scripts/verify-runtime.py"
"${repo_root}/scripts/verify-skill-workflow.py"
"${repo_root}/scripts/wait-notify-contract-smoke.py"
"${repo_root}/scripts/recording-to-skill-smoke.py"
"""


VERIFY_PACKAGE_ARTIFACT_SCRIPT = """#!/usr/bin/env python3

import json
import pathlib
import sys
import zipfile


REQUIRED_SKILL_SNIPPETS = [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
    "open-computer-use event-stream validate",
    "open-computer-use event-stream scaffold-skill",
    "OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH",
]


def require(failures, condition, message):
    if not condition:
        failures.append(message)


def parse_frontmatter(text):
    if not text.startswith("---\\n"):
        raise ValueError("SKILL.md is missing YAML frontmatter")
    try:
        _prefix, frontmatter, _rest = text.split("---", 2)
    except ValueError as error:
        raise ValueError("SKILL.md has malformed YAML frontmatter") from error
    fields = {}
    for line in frontmatter.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    manifest = json.loads((repo_root / "record-and-replay-skill-repo.json").read_text())
    skill_name = manifest.get("skill", {}).get("name") or "open-computer-use-record-and-replay"
    dist_dir = repo_root / "dist" / "skills"
    zip_path = dist_dir / f"{skill_name}-skill.zip"
    skill_path = dist_dir / f"{skill_name}.skill"
    expected_skill_md = f"{skill_name}/SKILL.md"
    failures = []

    require(failures, zip_path.exists(), f"missing packaged zip: {zip_path}")
    require(failures, skill_path.exists(), f"missing .skill artifact: {skill_path}")
    if not zip_path.exists() or not skill_path.exists():
        raise AssertionError(json.dumps({"failures": failures}, indent=2, sort_keys=True))

    require(
        failures,
        zip_path.read_bytes() == skill_path.read_bytes(),
        ".skill artifact must match packaged zip bytes",
    )

    try:
        with zipfile.ZipFile(skill_path) as archive:
            names = sorted(archive.namelist())
            require(failures, expected_skill_md in names, f"missing {expected_skill_md} in package")
            unsafe = [
                name
                for name in names
                if name.startswith("/")
                or name.startswith("../")
                or "/../" in name
                or not name.startswith(f"{skill_name}/")
            ]
            require(failures, not unsafe, f"unsafe or unexpected package paths: {unsafe}")
            skill_text = archive.read(expected_skill_md).decode("utf-8")
    except Exception as error:
        raise AssertionError(
            json.dumps(
                {"failures": failures + [f"failed to read skill package: {error}"]},
                indent=2,
                sort_keys=True,
            )
        ) from error

    try:
        frontmatter = parse_frontmatter(skill_text)
    except ValueError as error:
        failures.append(str(error))
        frontmatter = {}

    require(
        failures,
        frontmatter.get("name") == skill_name,
        f"packaged SKILL.md frontmatter name must be {skill_name!r}",
    )
    require(
        failures,
        bool(frontmatter.get("description")),
        "packaged SKILL.md frontmatter description is required",
    )
    missing_snippets = [snippet for snippet in REQUIRED_SKILL_SNIPPETS if snippet not in skill_text]
    require(
        failures,
        not missing_snippets,
        f"packaged SKILL.md missing handoff snippets: {missing_snippets}",
    )

    if failures:
        raise AssertionError(json.dumps({"failures": failures}, indent=2, sort_keys=True))

    print(
        json.dumps(
            {
                "ok": True,
                "checkedPackageArtifact": True,
                "checkedPackageSkillArchive": True,
                "checkedPackageSkillFrontmatter": True,
                "checkedPackageSkillHandoff": True,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""


VERIFY_MANIFEST_SCRIPT = """#!/usr/bin/env python3

import json
import pathlib
import sys


EXPECTED_TOOLS = [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
]
EXPECTED_REQUIRED_SCENARIOS = ["simple-action-stop"]
EXPECTED_RECOMMENDED_SCENARIOS = [
    "simple-action-stop",
    "keyboard-input-stop",
    "drag-stop",
    "cancel",
    "timeout",
]
EXPECTED_STRICT_MISSING_AUDIT = (
    "scripts/check-record-and-replay-baseline-summary.py "
    "dist/record-and-replay-official-golden-gate-summary.json "
    "--allow-strict-official-golden-missing"
)


def require(failures, condition, message):
    if not condition:
        failures.append(message)


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    manifest_path = repo_root / "record-and-replay-skill-repo.json"
    manifest = json.loads(manifest_path.read_text())
    failures = []

    require(
        failures,
        manifest.get("kind") == "open-computer-use-record-and-replay-thin-skill-repo",
        "unexpected repository kind",
    )
    require(failures, manifest.get("runtimeDependency") == "open-computer-use", "runtime dependency drifted")

    official = manifest.get("officialEvidence", {})
    source_summary_path = repo_root / "evidence" / "source-baseline-summary.json"
    source_summary = {}
    if source_summary_path.exists():
        try:
            source_summary = json.loads(source_summary_path.read_text())
        except Exception:
            source_summary = {}
    source_golden_complete = (
        (source_summary.get("status") or {}).get("officialSuccessfulRecordingGoldenComplete")
    )
    require(
        failures,
        official.get("baselineVersion") == "record-and-replay/1.0.857",
        "official baseline version drifted",
    )
    require(
        failures,
        isinstance(official.get("hasSuccessfulRecordingGolden"), bool),
        "standalone manifest official successful recording golden state must be boolean",
    )
    if isinstance(source_golden_complete, bool):
        require(
            failures,
            official.get("hasSuccessfulRecordingGolden") == source_golden_complete,
            "standalone manifest official successful recording golden state drifted from source baseline summary",
        )
    require(
        failures,
        official.get("requiredSuccessfulRecordingScenarios") == EXPECTED_REQUIRED_SCENARIOS,
        "required official scenario list drifted",
    )
    require(
        failures,
        official.get("recommendedSuccessfulRecordingScenarios") == EXPECTED_RECOMMENDED_SCENARIOS,
        "recommended official scenario list drifted",
    )
    require(
        failures,
        sorted((official.get("scenarioRecipes") or {}).keys()) == sorted(EXPECTED_RECOMMENDED_SCENARIOS),
        "scenario recipe list drifted",
    )

    baseline_checks = official.get("sourceRepoBaselineChecks", {})
    fixture_set_gate = baseline_checks.get("officialFixtureSetGate", {})
    fixture_ingest = baseline_checks.get("officialFixtureIngest", {})
    fixture_compare_policy = fixture_set_gate.get("sameScenarioComparePolicy", {})
    capture_preflight = baseline_checks.get("officialGoldenCapturePreflight", {})
    require(
        failures,
        fixture_set_gate.get("check") == "official-fixture-set-smoke",
        "official fixture set gate smoke drifted",
    )
    require(
        failures,
        fixture_compare_policy.get("requiresAxDiffEvidence") is True,
        "official fixture set AX diff evidence policy missing",
    )
    require(
        failures,
        fixture_compare_policy.get("requiresSameAxDiffMarkers") is True,
        "official fixture set AX diff marker policy missing",
    )
    require(
        failures,
        fixture_compare_policy.get("requiresSameSuppressedEventSequence") is True,
        "official fixture set suppressed event sequence policy missing",
    )
    require(
        failures,
        fixture_compare_policy.get("requiresSameSuppressedSchema") is True,
        "official fixture set suppressed schema policy missing",
    )
    require(
        failures,
        fixture_ingest.get("check") == "official-fixture-ingest-smoke",
        "official fixture ingest smoke drifted",
    )
    fixture_ingest_evidence = fixture_ingest.get("requiredEvidence") or []
    require(
        failures,
        "checkedOfficialSessionDirectoryPathHandoff" in fixture_ingest_evidence,
        "official sessionDirectoryPath handoff evidence missing",
    )
    require(
        failures,
        capture_preflight.get("check") == "official-golden-capture-preflight-smoke",
        "official capture preflight smoke drifted",
    )
    capture_preflight_evidence = capture_preflight.get("requiredEvidence") or []
    require(
        failures,
        "checkedOfficialCapturePacketInputSemanticGuard" in capture_preflight_evidence,
        "official capture semantic guard evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketSetContractManifest" in capture_preflight_evidence,
        "official capture packet set contract manifest evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketPostCaptureWorkflow" in capture_preflight_evidence,
        "official capture packet post-capture workflow evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketWorkflowVerifier" in capture_preflight_evidence,
        "official capture packet workflow verifier evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketSetPostCaptureWorkflow" in capture_preflight_evidence,
        "official capture packet set post-capture workflow evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketSetWorkflowVerifier" in capture_preflight_evidence,
        "official capture packet set workflow verifier evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketStrictAuditHandoff" in capture_preflight_evidence,
        "official capture packet strict audit handoff evidence missing",
    )
    require(
        failures,
        "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff"
        in capture_preflight_evidence,
        "official capture packet strict expected-failure audit handoff evidence missing",
    )

    audit = official.get("sourceRepoBaselineAudit", {})
    require(
        failures,
        audit.get("usableBaseline") == "make record-and-replay-baseline-audit",
        "source repo baseline audit command drifted",
    )
    require(
        failures,
        audit.get("strictOfficialGoldenGate") == "make record-and-replay-official-golden-gate-audit",
        "strict official golden audit command drifted",
    )
    require(
        failures,
        audit.get("auditTargetDryRunSmoke") == "make record-and-replay-baseline-audit-targets-smoke",
        "audit target dry-run smoke command drifted",
    )
    require(
        failures,
        audit.get("baselineSummaryArtifact") == "dist/record-and-replay-baseline-summary.json",
        "baseline summary artifact drifted",
    )
    require(
        failures,
        audit.get("strictOfficialGoldenSummaryArtifact")
        == "dist/record-and-replay-official-golden-gate-summary.json",
        "strict official golden summary artifact drifted",
    )
    require(
        failures,
        audit.get("baselineSummaryEnvVar") == "RNR_BASELINE_SUMMARY_JSON",
        "baseline summary env var drifted",
    )
    require(
        failures,
        audit.get("strictOfficialGoldenSummaryEnvVar") == "RNR_OFFICIAL_GOLDEN_SUMMARY_JSON",
        "strict official golden summary env var drifted",
    )
    require(
        failures,
        audit.get("strictOfficialGoldenExpectedFailureAudit") == EXPECTED_STRICT_MISSING_AUDIT,
        "strict expected-failure audit command drifted",
    )
    require(
        failures,
        audit.get("verifiesSummaryArtifactSeparation") is True,
        "summary artifact separation evidence missing",
    )
    require(
        failures,
        audit.get("verifiesSummaryEnvVarIsolation") is True,
        "summary env var isolation evidence missing",
    )

    mcp = manifest.get("mcpServer", {})
    require(failures, mcp.get("tools") == EXPECTED_TOOLS, "official MCP tool list drifted")
    require(failures, mcp.get("requiresObjectParams") is True, "object params guard missing")
    require(failures, mcp.get("requiresStringToolName") is True, "string tool name guard missing")
    require(failures, mcp.get("requiresObjectArguments") is True, "object arguments guard missing")
    require(failures, mcp.get("rejectsUnexpectedArguments") is True, "unexpected arguments guard missing")
    require(
        failures,
        mcp.get("rejectedRequestsDoNotCreateSessionFiles") is True,
        "malformed MCP request side-effect guard missing",
    )
    require(
        failures,
        mcp.get("noActiveResponse", {}).get("event_stream_status")
        == {"isRecording": False, "maxDurationSeconds": 1800},
        "no-active status response drifted",
    )
    require(
        failures,
        mcp.get("noActiveResponse", {}).get("event_stream_stop")
        == {"isRecording": False, "maxDurationSeconds": 1800},
        "no-active stop response drifted",
    )

    extension = manifest.get("extensionLayer", {})
    wait_notify = extension.get("waitNotify", {})
    require(
        failures,
        extension.get("officialCompatibleMcpSurface") is False,
        "extension layer must remain outside official MCP surface",
    )
    require(
        failures,
        "OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH"
        in (wait_notify.get("environmentVariables") or []),
        "notify suppressed events path handoff missing",
    )
    require(
        failures,
        wait_notify.get("callbackFailureMakesCliFail") is True,
        "notify callback failure contract missing",
    )
    require(
        failures,
        wait_notify.get("callbackTimeoutMakesCliFail") is True,
        "notify callback timeout contract missing",
    )

    recording_to_skill = manifest.get("recordingToSkill", {})
    strict_validation = recording_to_skill.get("strictValidation", {})
    require(
        failures,
        strict_validation.get("requiresDeclaredHandoffPaths")
        == ["metadataPath", "sessionPath", "eventsPath", "suppressedEventsPath"],
        "recording strict validation handoff paths drifted",
    )
    require(
        failures,
        strict_validation.get("requiresScreenshotPathsInsideSession") is True,
        "screenshot containment gate missing",
    )
    require(
        failures,
        recording_to_skill.get("rejectsCancelledRecordings") is True,
        "cancelled recording rejection contract missing",
    )

    checks = manifest.get("checks", {})
    require(failures, checks.get("manifestContract") == "scripts/verify-manifest.py", "manifest self-check missing")
    require(
        failures,
        checks.get("packageArtifact") == "scripts/verify-package-artifact.py",
        "package artifact self-check missing",
    )
    require(
        failures,
        checks.get("sourceBaselineSummaryEvidence") == "scripts/verify-source-baseline-summary.py",
        "source baseline summary evidence check missing",
    )
    require(
        failures,
        checks.get("readmeHandoffContract") == "scripts/verify-readme-handoff.py",
        "README handoff self-check missing",
    )
    require(failures, checks.get("runtimeContract") == "scripts/verify-runtime.py", "runtime check missing")
    require(failures, checks.get("skillWorkflow") == "scripts/verify-skill-workflow.py", "skill workflow check missing")
    require(failures, checks.get("waitNotifyContractSmoke") == "scripts/wait-notify-contract-smoke.py", "wait/notify check missing")
    require(failures, checks.get("recordingToSkillSmoke") == "scripts/recording-to-skill-smoke.py", "recording-to-skill check missing")
    require(failures, checks.get("selfCheck") == "scripts/check.sh", "self-check entry missing")

    if failures:
        raise AssertionError(json.dumps({"failures": failures}, indent=2, sort_keys=True))

    print(
        json.dumps(
            {
                "ok": True,
                "checkedManifestContract": True,
                "checkedPackageArtifactCheck": True,
                "checkedOfficialEvidenceAuditManifest": True,
                "checkedStrictExpectedFailureAudit": True,
                "checkedOfficialFixtureSetComparePolicy": True,
                "checkedSourceBaselineSummaryEvidenceCheck": True,
                "checkedMcpNoArgSurfaceContract": True,
                "checkedWaitNotifyExtensionContract": True,
                "checkedRecordingToSkillContract": True,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""


VERIFY_SOURCE_BASELINE_SUMMARY_SCRIPT = """#!/usr/bin/env python3

import json
import pathlib
import sys


EXPECTED_REQUIRED_GAPS = ["simple-action-stop"]
EXPECTED_RECOMMENDED_GAPS = [
    "simple-action-stop",
    "keyboard-input-stop",
    "drag-stop",
    "cancel",
    "timeout",
]
EXPECTED_SUMMARY_EVIDENCE_PATH = "evidence/source-baseline-summary.json"


def require(failures, condition, message):
    if not condition:
        failures.append(message)


def bool_at(root, *path):
    value = root
    for key in path:
        if not isinstance(value, dict):
            return False
        value = value.get(key)
    return value is True


def official_golden_state(status):
    missing_required = status.get("missingRequiredOfficialSuccessfulRecordingScenarios") or []
    not_ready_required = status.get("notReadyRequiredOfficialSuccessfulRecordingScenarios") or []
    coverage_errors = status.get("officialFixtureCoverageErrors") or []
    missing_recommended = status.get("missingRecommendedOfficialSuccessfulRecordingScenarios") or []

    current_required_gap = (
        status.get("officialGoldenGatePassed") is False
        and status.get("officialSuccessfulRecordingGoldenComplete") is False
        and status.get("officialSuccessfulRecordingEquivalenceReady") is False
        and status.get("requiresOfficialGoldenCapture") is True
        and missing_required == EXPECTED_REQUIRED_GAPS
    )
    completed_equivalence = (
        status.get("officialGoldenGatePassed") is True
        and status.get("officialSuccessfulRecordingGoldenComplete") is True
        and status.get("officialSuccessfulRecordingEquivalenceReady") is True
        and status.get("requiresOfficialGoldenCapture") is False
        and missing_required == []
        and not_ready_required == []
        and coverage_errors == []
    )
    current_recommended_gap = (
        sorted(missing_recommended) == sorted(EXPECTED_RECOMMENDED_GAPS)
    )
    return current_required_gap, current_recommended_gap, completed_equivalence


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    manifest = json.loads((repo_root / "record-and-replay-skill-repo.json").read_text())
    evidence_path = repo_root / EXPECTED_SUMMARY_EVIDENCE_PATH
    failures = []

    source_audit = (
        manifest.get("officialEvidence", {})
        .get("sourceRepoBaselineAudit", {})
    )
    require(
        failures,
        source_audit.get("copiedBaselineSummaryEvidence")
        == EXPECTED_SUMMARY_EVIDENCE_PATH,
        "copied baseline summary evidence path drifted",
    )
    require(
        failures,
        manifest.get("checks", {}).get("sourceBaselineSummaryEvidence")
        == "scripts/verify-source-baseline-summary.py",
        "source baseline summary check not declared",
    )
    require(
        failures,
        evidence_path.exists(),
        "missing copied source baseline summary evidence",
    )
    if evidence_path.exists():
        summary = json.loads(evidence_path.read_text())
        status = summary.get("status", {})
        evidence = summary.get("evidence", {})
        require(failures, summary.get("baseline") == "record-and-replay", "baseline name drifted")
        require(failures, summary.get("ok") is True, "baseline summary must be usable in default mode")
        require(failures, status.get("usableBaseline") is True, "usable baseline evidence missing")
        require(
            failures,
            status.get("standaloneRepoBaselineReady") is True,
            "standalone repo baseline readiness missing",
        )
        require(
            failures,
            status.get("officialGoldenRequirementSatisfied") is True,
            "default official golden requirement policy drifted",
        )
        (
            current_required_gap,
            current_recommended_gap,
            completed_equivalence,
        ) = official_golden_state(status)
        require(
            failures,
            current_required_gap or completed_equivalence,
            "official golden state must be either current required gap or completed equivalence",
        )
        if current_required_gap:
            require(
                failures,
                current_recommended_gap,
                "recommended official golden gap drifted",
            )
        require(
            failures,
            bool_at(evidence, "officialFixtureSetGate", "checkedAxDiffComparisonPolicy"),
            "official fixture set AX diff compare policy evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "officialFixtureSetGate", "checkedSuppressedStreamComparisonPolicy"),
            "official fixture set suppressed stream compare policy evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "fixtureIngestPipelines", "checkedOfficialSessionDirectoryPathHandoff"),
            "official sessionDirectoryPath handoff evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketSetContractManifest"),
            "capture packet set contract manifest evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketPostCaptureWorkflow"),
            "capture packet post-capture workflow evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketWorkflowVerifier"),
            "capture packet workflow verifier evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketSetPostCaptureWorkflow"),
            "capture packet set post-capture workflow evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketSetWorkflowVerifier"),
            "capture packet set workflow verifier evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "preflightPipelines", "checkedOfficialCapturePacketStrictAuditHandoff"),
            "capture packet strict audit handoff evidence missing",
        )
        require(
            failures,
            bool_at(
                evidence,
                "preflightPipelines",
                "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
            ),
            "capture packet strict expected-failure audit handoff evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "standaloneSkillRepo", "checkedOfficialFixtureSetComparePolicyManifest"),
            "source standalone fixture-set compare policy manifest evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "npmStagedSkillRepo", "checkedOfficialFixtureSetComparePolicyManifest"),
            "npm staged fixture-set compare policy manifest evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "standaloneSkillRepo", "checkedGeneratedRepoSelfCheck"),
            "source standalone generated repo self-check evidence missing",
        )
        require(
            failures,
            bool_at(evidence, "npmStagedSkillRepo", "checkedGeneratedRepoSelfCheck"),
            "npm staged generated repo self-check evidence missing",
        )

    if failures:
        raise AssertionError(json.dumps({"failures": failures}, indent=2, sort_keys=True))

    print(
        json.dumps(
            {
                "ok": True,
                "checkedSourceBaselineSummaryEvidence": True,
                "checkedSourceBaselineSummaryDefaultUsable": True,
                "checkedSourceBaselineSummaryOfficialGoldenState": True,
                "checkedSourceBaselineSummaryOfficialGoldenGap": current_required_gap,
                "checkedSourceBaselineSummaryOfficialGoldenComplete": completed_equivalence,
                "checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff": True,
                "checkedSourceBaselineSummaryCapturePacketSetContractManifest": True,
                "checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow": True,
                "checkedSourceBaselineSummaryCapturePacketWorkflowVerifier": True,
                "checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow": True,
                "checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier": True,
                "checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff": True,
                "checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff": True,
                "checkedSourceBaselineSummaryStandaloneEvidence": True,
                "evidencePath": EXPECTED_SUMMARY_EVIDENCE_PATH,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""


VERIFY_SKILL_WORKFLOW_SCRIPT = """#!/usr/bin/env python3

import json
import pathlib
import sys


REQUIRED_SNIPPETS = [
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
    "Do not add cancel, wait, callback, webhook, or extra arguments to this MCP surface.",
    "Call `event_stream_start` once.",
    "If it reports an already active recording, do not start another one.",
    "End the turn and let the user perform the workflow.",
    "recording can last up to 30 minutes",
    "Do not poll while the user is recording.",
    "Use `event_stream_status` only when the user asks for status or returns after recording",
    "do not use it to wait for completion",
    "When the user says they are done, call `event_stream_stop`.",
    "read `eventsPath`, `metadataPath`, and, when present, `sessionPath`",
    "The MCP server does not expose event-stream contents directly.",
    "Treat `events.jsonl` as the primary evidence.",
    "open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>",
    "open-computer-use event-stream validate --json --require-skill-draft <eventsPath>",
    "open-computer-use event-stream summarize --json <metadataPath-or-sessionPath>",
    "open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>",
    "If the user says they clicked Discard or cancelled recording, do not call `event_stream_stop` again.",
    "Before finalizing the skill, read and follow the `skill-creator` skill.",
    "Use `runtimeInputs`",
    "Use `safetySignals`",
    "If `summaryLimits.hasTruncatedSummary=true`",
    "session.started` is missing, duplicated, or not the first event",
    "session.ended` appears more than once, or whose `session.ended` is not the final event",
    "## Independent Wait / Notify Integration",
    "open-computer-use event-stream wait --json --session-id <id> --notify-command",
    "`wait --json` adds `waitTimedOut` and `waitSessionMatched`.",
    "`--notify-command` receives the final status JSON on stdin",
    "OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON",
    "OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH",
    "Keep this listener path outside the official-compatible MCP tool surface.",
]

FORBIDDEN_SNIPPETS = [
    "event_stream_cancel",
    "event_stream_wait",
]


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    skill_paths = sorted((repo_root / "skills").glob("*/SKILL.md"))
    if len(skill_paths) != 1:
        raise AssertionError(f"expected exactly one skill entrypoint, found {skill_paths!r}")
    skill_path = skill_paths[0]
    text = skill_path.read_text()

    missing = [snippet for snippet in REQUIRED_SNIPPETS if snippet not in text]
    forbidden = [snippet for snippet in FORBIDDEN_SNIPPETS if snippet in text]
    if missing or forbidden:
        raise AssertionError(
            json.dumps(
                {
                    "missingRequiredSnippets": missing,
                    "forbiddenSnippets": forbidden,
                    "skillPath": str(skill_path.relative_to(repo_root)),
                },
                sort_keys=True,
            )
        )

    print(
        json.dumps(
            {
                "ok": True,
                "checkedSkillWorkflow": True,
                "checkedStatusNotUsedAsWaitLoopGuard": True,
                "checkedMcpNoDirectEventContentsGuard": True,
                "skillPath": str(skill_path.relative_to(repo_root)),
                "requiredSnippetCount": len(REQUIRED_SNIPPETS),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""


VERIFY_README_HANDOFF_SCRIPT = """#!/usr/bin/env python3

import json
import pathlib
import sys


REQUIRED_SNIPPETS = [
    "npm i -g open-computer-use",
    "open-computer-use install-codex-record-and-replay-mcp",
    "Python 3 must be available as `python3`",
    "Set `OPEN_COMPUTER_USE_CLI=/path/to/open-computer-use`",
    "The Record & Replay MCP server must expose only these official-compatible tools",
    "event_stream_start",
    "event_stream_status",
    "event_stream_stop",
    "OCU extension commands such as `event-stream wait`, `validate`, `summarize`, and",
    "record-and-replay-event-stream-surface-1.0.857.json",
    "record-and-replay-official-no-active-status-stop-1.0.857.json",
    "record-and-replay-official-raw-start-timeout-1.0.857.json",
    "hostless official raw `event_stream_start/status/stop`",
    "must not be treated as a successful recording",
    "official fixture set gate also requires same-scenario",
    "AX diff evidence, AX diff marker alignment",
    "suppressed event sequence, and suppressed schema comparison",
    "make record-and-replay-baseline-audit",
    "make record-and-replay-official-golden-gate-audit",
    "scripts/check-record-and-replay-baseline-summary.py",
    "--allow-strict-official-golden-missing",
    "dist/record-and-replay-baseline-summary.json",
    "evidence/source-baseline-summary.json",
    "dist/record-and-replay-official-golden-gate-summary.json",
    "The minimum required official successful recording scenario is",
    "`simple-action-stop`. The recommended calibration set is",
    "`simple-action-stop`, `keyboard-input-stop`, `drag-stop`, `cancel`, and `timeout`.",
    "officialEvidence.scenarioRecipes",
    "Successful recording fixtures are still required before claiming official",
    "event schema, AX diff, screenshot, or timeout endReason equivalence",
    "open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>",
    "open-computer-use event-stream validate --json --require-skill-draft <eventsPath>",
    "open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>",
    "Cancelled, incomplete, or malformed recordings must not be used to",
    "create or update a skill.",
    "open-computer-use event-stream wait --json --session-id <id> --notify-command",
    "Keep this listener path outside the official-compatible MCP tool",
    "./scripts/recording-lifecycle-smoke.py",
    "./scripts/verify-runtime.py",
    "scripts/verify-source-baseline-summary.py",
    "./scripts/verify-skill-workflow.py",
]


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    readme_path = repo_root / "README.md"
    text = readme_path.read_text()

    missing = [snippet for snippet in REQUIRED_SNIPPETS if snippet not in text]
    if missing:
        raise AssertionError(
            json.dumps(
                {
                    "missingRequiredSnippets": missing,
                    "readmePath": str(readme_path.relative_to(repo_root)),
                },
                sort_keys=True,
            )
        )

    print(
        json.dumps(
            {
                "ok": True,
                "checkedReadmeHandoffContract": True,
                "checkedReadmeOfficialEvidenceHandoff": True,
                "checkedReadmeOfficialGoldenGap": True,
                "checkedReadmeWaitNotifyBoundary": True,
                "requiredSnippetCount": len(REQUIRED_SNIPPETS),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""


RECORDING_TO_SKILL_SMOKE_SCRIPT = """#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import sys
import tempfile


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\\n")


def write_jsonl(path, records):
    path.write_text("".join(json.dumps(record, sort_keys=True) + "\\n" for record in records))


def main():
    cli = os.environ.get("OPEN_COMPUTER_USE_CLI", "open-computer-use")
    env = {**os.environ, "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1"}
    with tempfile.TemporaryDirectory(prefix="record-and-replay-skill-smoke-") as tmp:
        root = pathlib.Path(tmp)
        session_dir = root / "session"
        session_dir.mkdir()
        events = [
            {
                "type": "session.started",
                "sessionId": "synthetic-skill-smoke",
                "timestamp": "2026-06-27T00:00:00Z",
            },
            {
                "type": "mouse.click",
                "timestamp": "2026-06-27T00:00:01Z",
                "app": {"name": "Example"},
                "window": {"title": "Example Window"},
                "button": "left",
                "location": {"x": 10, "y": 20},
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": "Create",
                    "label": "Create",
                },
            },
            {
                "type": "session.ended",
                "sessionId": "synthetic-skill-smoke",
                "timestamp": "2026-06-27T00:00:02Z",
                "endReason": "recording_controls_stopped",
            },
        ]
        metadata = {
            "sessionId": "synthetic-skill-smoke",
            "state": "stopped",
            "active": False,
            "startTime": "2026-06-27T00:00:00Z",
            "endTime": "2026-06-27T00:00:02Z",
            "endReason": "recording_controls_stopped",
            "eventCount": len(events),
            "suppressedEventCount": 0,
            "metadataPath": "metadata.json",
            "sessionPath": "session.json",
            "eventsPath": "events.jsonl",
            "suppressedEventsPath": "suppressed.jsonl",
        }
        write_jsonl(session_dir / "events.jsonl", events)
        write_json(session_dir / "metadata.json", metadata)
        write_json(session_dir / "session.json", metadata)
        (session_dir / "suppressed.jsonl").write_text("")

        validation = subprocess.run(
            [
                cli,
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                "--require-skill-draft",
                str(session_dir / "metadata.json"),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        validation_payload = json.loads(validation.stdout)
        if validation_payload.get("ok") is not True or validation_payload.get("skillDraftReady") is not True:
            raise AssertionError(validation_payload)
        declared_paths = validation_payload.get("declaredPaths")
        expected_handoff_paths = [
            "metadataPath",
            "sessionPath",
            "eventsPath",
            "suppressedEventsPath",
        ]
        if not isinstance(declared_paths, dict):
            raise AssertionError(validation_payload)
        for key in expected_handoff_paths:
            evidence = declared_paths.get(key)
            if not isinstance(evidence, dict) or evidence.get("exists") is not True:
                raise AssertionError(validation_payload)

        external_screenshot_session_dir = root / "external-screenshot-session"
        external_screenshot_session_dir.mkdir()
        external_screenshot = root / "outside-session-screenshot.png"
        external_screenshot.write_bytes(b"\\x89PNG")
        external_screenshot_events = [
            {
                "type": "session.started",
                "sessionId": "synthetic-external-screenshot-smoke",
                "timestamp": "2026-06-27T00:00:00Z",
            },
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "synthetic-external-screenshot-smoke",
                "timestamp": "2026-06-27T00:00:00.500Z",
                "accessibilityInspectorPayload": {
                    "screenshotPath": str(external_screenshot),
                },
            },
            {
                "type": "mouse.click",
                "sessionId": "synthetic-external-screenshot-smoke",
                "timestamp": "2026-06-27T00:00:01Z",
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": "Create",
                },
            },
            {
                "type": "session.ended",
                "sessionId": "synthetic-external-screenshot-smoke",
                "timestamp": "2026-06-27T00:00:02Z",
                "endReason": "recording_controls_stopped",
            },
        ]
        external_screenshot_metadata = {
            "sessionId": "synthetic-external-screenshot-smoke",
            "state": "stopped",
            "active": False,
            "startTime": "2026-06-27T00:00:00Z",
            "endTime": "2026-06-27T00:00:02Z",
            "endReason": "recording_controls_stopped",
            "eventCount": len(external_screenshot_events),
            "suppressedEventCount": 0,
            "metadataPath": "metadata.json",
            "sessionPath": "session.json",
            "eventsPath": "events.jsonl",
            "suppressedEventsPath": "suppressed.jsonl",
        }
        write_jsonl(external_screenshot_session_dir / "events.jsonl", external_screenshot_events)
        write_json(external_screenshot_session_dir / "metadata.json", external_screenshot_metadata)
        write_json(external_screenshot_session_dir / "session.json", external_screenshot_metadata)
        (external_screenshot_session_dir / "suppressed.jsonl").write_text("")
        external_screenshot_validation = subprocess.run(
            [
                cli,
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                str(external_screenshot_session_dir / "metadata.json"),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        external_screenshot_payload = json.loads(
            external_screenshot_validation.stdout or external_screenshot_validation.stderr
        )
        if external_screenshot_validation.returncode == 0:
            raise AssertionError("external screenshotPath validation should fail")
        expected_screenshot_error = (
            "screenshotPath from event line 2 must stay inside session directory: "
            f"{external_screenshot}"
        )
        if expected_screenshot_error not in external_screenshot_payload.get("errors", []):
            raise AssertionError(external_screenshot_payload)

        events_only_validation = subprocess.run(
            [
                cli,
                "event-stream",
                "validate",
                "--json",
                "--require-skill-draft",
                str(session_dir / "events.jsonl"),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        events_only_payload = json.loads(events_only_validation.stdout)
        if events_only_payload.get("ok") is not True or events_only_payload.get("skillDraftReady") is not True:
            raise AssertionError(events_only_payload)
        if events_only_payload.get("metadataPath") is not None:
            raise AssertionError(events_only_payload)

        output_dir = root / "draft-skill"
        scaffold = subprocess.run(
            [
                cli,
                "event-stream",
                "scaffold-skill",
                "--json",
                str(session_dir / "metadata.json"),
                "--skill-name",
                "synthetic-recording-workflow",
                "--description",
                "Replay the synthetic Record & Replay workflow.",
                "--output-dir",
                str(output_dir),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        scaffold_payload = json.loads(scaffold.stdout)
        if scaffold_payload.get("ok") is not True:
            raise AssertionError(scaffold_payload)

        skill_text = (output_dir / "SKILL.md").read_text()
        summary = json.loads((output_dir / "references" / "recording-summary.json").read_text())
        if "synthetic-recording-workflow" not in skill_text or "Click role=" not in skill_text:
            raise AssertionError(skill_text)
        for required_snippet in [
            "skill-creator",
            "Complete the `skill-creator` workflow, including validation",
            "not a standalone runbook or replay plan",
        ]:
            if required_snippet not in skill_text:
                raise AssertionError(skill_text)
        if str(root) in skill_text or str(root) in json.dumps(summary, sort_keys=True):
            raise AssertionError("generated scaffold leaked temporary local paths")
        readiness = summary.get("skillReadiness", {})
        if readiness.get("canCreateSkillDraft") is not True:
            raise AssertionError(readiness)

        invalid_session_dir = root / "invalid-session"
        invalid_session_dir.mkdir()
        invalid_events = [
            {
                "type": "session.started",
                "sessionId": "synthetic-invalid-skill-smoke",
                "timestamp": "2026-06-27T00:00:00Z",
            },
            {
                "type": "session.ended",
                "sessionId": "synthetic-invalid-skill-smoke",
                "timestamp": "2026-06-27T00:00:01Z",
                "endReason": "recording_controls_stopped",
            },
        ]
        invalid_metadata = {
            "sessionId": "synthetic-invalid-skill-smoke",
            "state": "stopped",
            "active": False,
            "startTime": "2026-06-27T00:00:00Z",
            "endTime": "2026-06-27T00:00:01Z",
            "endReason": "recording_controls_stopped",
            "eventCount": len(invalid_events),
            "suppressedEventCount": 0,
            "metadataPath": "metadata.json",
            "sessionPath": "session.json",
            "eventsPath": "events.jsonl",
            "suppressedEventsPath": "suppressed.jsonl",
        }
        write_jsonl(invalid_session_dir / "events.jsonl", invalid_events)
        write_json(invalid_session_dir / "metadata.json", invalid_metadata)
        write_json(invalid_session_dir / "session.json", invalid_metadata)
        (invalid_session_dir / "suppressed.jsonl").write_text("")
        invalid_scaffold = subprocess.run(
            [
                cli,
                "event-stream",
                "scaffold-skill",
                "--json",
                str(invalid_session_dir / "metadata.json"),
                "--skill-name",
                "invalid-recording-workflow",
                "--description",
                "This should not be generated.",
                "--output-dir",
                str(root / "invalid-draft-skill"),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        invalid_payload = json.loads(invalid_scaffold.stdout or invalid_scaffold.stderr)
        if invalid_scaffold.returncode == 0:
            raise AssertionError("failed scaffold-skill should make the CLI command fail")
        if invalid_payload.get("ok") is not False:
            raise AssertionError(invalid_payload)

        cancelled_session_dir = root / "cancelled-session"
        cancelled_session_dir.mkdir()
        cancelled_events = [
            {
                "type": "session.started",
                "sessionId": "synthetic-cancelled-skill-smoke",
                "timestamp": "2026-06-27T00:00:00Z",
            },
            {
                "type": "mouse.click",
                "timestamp": "2026-06-27T00:00:01Z",
                "app": {"name": "Example"},
                "window": {"title": "Example Window"},
                "button": "left",
                "location": {"x": 10, "y": 20},
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": "Discard",
                    "label": "Discard",
                },
            },
            {
                "type": "session.ended",
                "sessionId": "synthetic-cancelled-skill-smoke",
                "timestamp": "2026-06-27T00:00:02Z",
                "endReason": "recording_controls_cancelled",
            },
        ]
        cancelled_metadata = {
            "sessionId": "synthetic-cancelled-skill-smoke",
            "state": "cancelled",
            "active": False,
            "startTime": "2026-06-27T00:00:00Z",
            "endTime": "2026-06-27T00:00:02Z",
            "endReason": "recording_controls_cancelled",
            "eventCount": len(cancelled_events),
            "suppressedEventCount": 0,
            "metadataPath": "metadata.json",
            "sessionPath": "session.json",
            "eventsPath": "events.jsonl",
            "suppressedEventsPath": "suppressed.jsonl",
        }
        write_jsonl(cancelled_session_dir / "events.jsonl", cancelled_events)
        write_json(cancelled_session_dir / "metadata.json", cancelled_metadata)
        write_json(cancelled_session_dir / "session.json", cancelled_metadata)
        (cancelled_session_dir / "suppressed.jsonl").write_text("")
        cancelled_reason = "recording was cancelled; do not create or update a skill from this event stream"

        for cancelled_input, extra_args in [
            (cancelled_session_dir / "metadata.json", ["--strict-ocu"]),
            (cancelled_session_dir / "events.jsonl", []),
        ]:
            cancelled_validation = subprocess.run(
                [
                    cli,
                    "event-stream",
                    "validate",
                    "--json",
                    *extra_args,
                    "--require-skill-draft",
                    str(cancelled_input),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
            cancelled_validation_payload = json.loads(
                cancelled_validation.stdout or cancelled_validation.stderr
            )
            if cancelled_validation.returncode == 0:
                raise AssertionError("cancelled validation should fail with --require-skill-draft")
            if cancelled_reason not in json.dumps(cancelled_validation_payload, sort_keys=True):
                raise AssertionError(cancelled_validation_payload)

        cancelled_scaffold = subprocess.run(
            [
                cli,
                "event-stream",
                "scaffold-skill",
                "--json",
                str(cancelled_session_dir / "metadata.json"),
                "--skill-name",
                "cancelled-recording-workflow",
                "--description",
                "This should not be generated.",
                "--output-dir",
                str(root / "cancelled-draft-skill"),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        cancelled_payload = json.loads(cancelled_scaffold.stdout or cancelled_scaffold.stderr)
        if cancelled_scaffold.returncode == 0:
            raise AssertionError("cancelled scaffold-skill should make the CLI command fail")
        if cancelled_payload.get("ok") is not False:
            raise AssertionError(cancelled_payload)
        if cancelled_reason not in json.dumps(cancelled_payload, sort_keys=True):
            raise AssertionError(cancelled_payload)

        print(
            json.dumps(
                {
                    "ok": True,
                    "skillName": scaffold_payload.get("skillName"),
                    "checkedStrictValidation": True,
                    "checkedDeclaredHandoffPaths": True,
                    "checkedScreenshotPathContainment": True,
                    "checkedEventsOnlyValidation": True,
                    "checkedScaffoldSkill": True,
                    "checkedScaffoldSkillFailureExit": True,
                    "checkedCancelledRecordingRejected": True,
                    "checkedSkillCreatorHandoff": True,
                },
                sort_keys=True,
            )
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
"""


WAIT_NOTIFY_CONTRACT_SMOKE_SCRIPT = """#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import sys
import tempfile


def main():
    cli = os.environ.get("OPEN_COMPUTER_USE_CLI", "open-computer-use")
    with tempfile.TemporaryDirectory(prefix="record-and-replay-wait-notify-") as tmp:
        root = pathlib.Path(tmp)
        recordings = root / "recordings"
        callback_marker = root / "callback-ran.json"
        callback_script = root / "callback.py"
        callback_script.write_text(
            "import pathlib\\n"
            "import sys\\n"
            f"pathlib.Path({str(callback_marker)!r}).write_text(sys.stdin.read())\\n"
        )
        env = {
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
        }
        result = subprocess.run(
            [
                cli,
                "event-stream",
                "wait",
                "--json",
                "--session-id",
                "missing-session-for-contract-smoke",
                "--timeout",
                "0.05",
                "--notify-command",
                json.dumps([sys.executable, str(callback_script)]),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        payload = json.loads(result.stdout)
        if payload.get("waitTimedOut") is not True:
            raise AssertionError(payload)
        if payload.get("waitSessionMatched") is not False:
            raise AssertionError(payload)
        notification = payload.get("notification", {})
        if notification.get("skipped") is not True or notification.get("reason") != "waitTimedOut":
            raise AssertionError(payload)
        if callback_marker.exists():
            raise AssertionError("wait notify callback ran for an unmatched session")
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("wait on an unmatched session should not create recording session files")

        completed_session_id = "session-wait-notify-contract"
        completed_session_dir = recordings / completed_session_id
        completed_session_dir.mkdir(parents=True, exist_ok=True)
        events_path = completed_session_dir / "events.jsonl"
        metadata_path = completed_session_dir / "metadata.json"
        suppressed_path = completed_session_dir / "suppressed.jsonl"
        session_path = completed_session_dir / "session.json"
        events_path.write_text(
            json.dumps(
                {
                    "type": "session.started",
                    "timestamp": "2026-06-27T00:00:00.000Z",
                    "sessionId": completed_session_id,
                }
            )
            + "\\n"
            + json.dumps(
                {
                    "type": "session.ended",
                    "timestamp": "2026-06-27T00:00:01.000Z",
                    "sessionId": completed_session_id,
                    "endReason": "recording_controls_stopped",
                }
            )
            + "\\n"
        )
        suppressed_path.write_text("")
        metadata = {
            "sessionID": completed_session_id,
            "sessionId": completed_session_id,
            "state": "stopped",
            "active": False,
            "startedAt": "2026-06-27T00:00:00.000Z",
            "endedAt": "2026-06-27T00:00:01.000Z",
            "endReason": "recording_controls_stopped",
            "eventsPath": str(events_path),
            "metadataPath": str(metadata_path),
            "sessionPath": str(session_path),
            "suppressedEventsPath": str(suppressed_path),
            "eventCount": 2,
            "suppressedEventCount": 0,
        }
        metadata_path.write_text(json.dumps(metadata, sort_keys=True))
        session_path.write_text(json.dumps(metadata, sort_keys=True))

        success_status_path = root / "notify-success-status.json"
        success_suppressed_path = root / "notify-success-suppressed-path.txt"
        success_script = root / "notify-success.py"
        success_script.write_text(
            "import os\\n"
            "import pathlib\\n"
            "import sys\\n"
            "pathlib.Path(sys.argv[1]).write_text(sys.stdin.read())\\n"
            "pathlib.Path(sys.argv[2]).write_text("
            "os.environ.get('OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH', '')"
            ")\\n"
        )
        success_result = subprocess.run(
            [
                cli,
                "event-stream",
                "wait",
                "--json",
                "--session-id",
                completed_session_id,
                "--timeout",
                "1",
                "--notify-command",
                json.dumps([
                    sys.executable,
                    str(success_script),
                    str(success_status_path),
                    str(success_suppressed_path),
                ]),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        success_payload = json.loads(success_result.stdout)
        success_notification = success_payload.get("notification", {})
        if success_payload.get("waitTimedOut") is not False:
            raise AssertionError(success_payload)
        if success_payload.get("waitSessionMatched") is not True:
            raise AssertionError(success_payload)
        if success_notification.get("ok") is not True:
            raise AssertionError(success_payload)
        success_callback_status = json.loads(success_status_path.read_text())
        if success_callback_status.get("sessionId") != completed_session_id:
            raise AssertionError(success_callback_status)
        if pathlib.Path(success_suppressed_path.read_text()) != suppressed_path:
            raise AssertionError("notify callback did not receive suppressed events path")

        failure_script = root / "notify-fail.py"
        failure_script.write_text("import sys\\nsys.exit(7)\\n")
        failure_result = subprocess.run(
            [
                cli,
                "event-stream",
                "wait",
                "--json",
                "--session-id",
                completed_session_id,
                "--timeout",
                "1",
                "--notify-command",
                json.dumps([sys.executable, str(failure_script)]),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        failure_payload = json.loads(failure_result.stdout)
        failure_notification = failure_payload.get("notification", {})
        if failure_payload.get("waitTimedOut") is not False:
            raise AssertionError(failure_payload)
        if failure_payload.get("waitSessionMatched") is not True:
            raise AssertionError(failure_payload)
        if failure_notification.get("ok") is not False:
            raise AssertionError(failure_payload)
        if failure_notification.get("reason") != "nonZeroExit":
            raise AssertionError(failure_payload)
        if failure_notification.get("exitCode") != 7:
            raise AssertionError(failure_payload)
        if failure_result.returncode == 0:
            raise AssertionError("failed notify callback should make the CLI command fail")

        timeout_script = root / "notify-sleep.py"
        timeout_script.write_text("import time\\ntime.sleep(2)\\n")
        timeout_env = {
            **env,
            "OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS": "0.1",
        }
        timeout_result = subprocess.run(
            [
                cli,
                "event-stream",
                "wait",
                "--json",
                "--session-id",
                completed_session_id,
                "--timeout",
                "1",
                "--notify-command",
                json.dumps([sys.executable, str(timeout_script)]),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=timeout_env,
        )
        timeout_payload = json.loads(timeout_result.stdout)
        timeout_notification = timeout_payload.get("notification", {})
        if timeout_payload.get("waitTimedOut") is not False:
            raise AssertionError(timeout_payload)
        if timeout_payload.get("waitSessionMatched") is not True:
            raise AssertionError(timeout_payload)
        if timeout_notification.get("ok") is not False:
            raise AssertionError(timeout_payload)
        if timeout_notification.get("timedOut") is not True:
            raise AssertionError(timeout_payload)
        if timeout_notification.get("reason") != "timeout":
            raise AssertionError(timeout_payload)
        if timeout_result.returncode == 0:
            raise AssertionError("timed out notify callback should make the CLI command fail")

        print(
            json.dumps(
                {
                    "ok": True,
                    "checkedWaitNotifyContract": True,
                    "checkedNotifySuppressedEventsPathEnv": True,
                    "checkedNotifyCallbackFailureExit": True,
                    "checkedNotifyCallbackFailureReason": True,
                    "checkedNotifyCallbackTimeoutFailureExit": True,
                    "checkedNotifyCallbackTimeoutReason": True,
                    "waitTimedOut": payload.get("waitTimedOut"),
                    "waitSessionMatched": payload.get("waitSessionMatched"),
                    "callbackSkipped": notification.get("skipped"),
                    "callbackFailureDetected": True,
                    "callbackFailureReason": failure_notification.get("reason"),
                    "callbackTimeoutDetected": True,
                    "callbackTimeoutReason": timeout_notification.get("reason"),
                },
                sort_keys=True,
            )
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
"""


RECORDING_LIFECYCLE_SMOKE_SCRIPT = """#!/usr/bin/env python3

import json
import os
import pathlib
import select
import subprocess
import sys
import tempfile


def read_line(process, timeout=10, timeout_message=None):
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        if timeout_message is not None:
            raise RuntimeError(timeout_message())
        raise RuntimeError("timed out waiting for Record & Replay MCP response")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("Record & Replay MCP server exited before responding")
    return json.loads(line)


def send_message(process, message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\\n")
    process.stdin.flush()


def request(process, message, timeout=10, timeout_message=None):
    send_message(process, message)
    response = read_line(process, timeout=timeout, timeout_message=timeout_message)
    if "error" in response:
        raise AssertionError(response["error"])
    return response


def tool_text(response):
    content = response.get("result", {}).get("content", [])
    if not content or content[0].get("type") != "text":
        raise AssertionError(f"unexpected tool response: {response!r}")
    return json.loads(content[0]["text"])


def runtime_version(cli):
    try:
        completed = subprocess.run(
            [cli, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except Exception as error:
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}
    return {
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def mcp_timeout_message(cli, command, process):
    parts = [
        "timed out waiting for Record & Replay MCP response",
        f"runtime={cli!r}",
        f"command={command!r}",
        f"runtimeVersion={runtime_version(cli)!r}",
    ]
    poll = process.poll()
    if poll is None:
        parts.append("processStillRunning=true")
    else:
        parts.append(f"processReturnCode={poll}")
        if process.stderr:
            parts.append(f"stderr={process.stderr.read().strip()!r}")
    parts.append(
        "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime if this points to an older install."
    )
    return "; ".join(parts)


def main():
    cli = os.environ.get("OPEN_COMPUTER_USE_CLI", "open-computer-use")
    response_timeout = float(os.environ.get("OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS", "10"))
    with tempfile.TemporaryDirectory(prefix="record-and-replay-lifecycle-") as tmp:
        recordings = pathlib.Path(tmp) / "recordings"
        env = {
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1",
            "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
            "OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve",
            "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
            "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
        }
        command = [cli, "event-stream", "mcp"]
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        request_failed = False
        try:
            timeout_message = lambda: mcp_timeout_message(cli, command, process)
            initialize = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-11-25",
                        "capabilities": {},
                        "clientInfo": {
                            "name": "record-and-replay-lifecycle-smoke",
                            "version": "0",
                        },
                    },
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            send_message(
                process,
                {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            )
            tools = request(
                process,
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            start = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {"name": "event_stream_start", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            repeat_start = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "tools/call",
                    "params": {"name": "event_stream_start", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            status = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 5,
                    "method": "tools/call",
                    "params": {"name": "event_stream_status", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            stop = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 6,
                    "method": "tools/call",
                    "params": {"name": "event_stream_stop", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            repeat_stop = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 7,
                    "method": "tools/call",
                    "params": {"name": "event_stream_stop", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
            final_status = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 8,
                    "method": "tools/call",
                    "params": {"name": "event_stream_status", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=timeout_message,
            )
        except BaseException:
            request_failed = True
            raise
        finally:
            if process.stdin:
                process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            stderr = process.stderr.read() if process.stderr else ""
            if not request_failed and process.returncode != 0:
                raise AssertionError(stderr)

        initialize_result = initialize["result"]
        if initialize_result.get("serverInfo", {}).get("name") != "Record & Replay":
            raise AssertionError(initialize_result)
        tool_names = [tool.get("name") for tool in tools.get("result", {}).get("tools", [])]
        if tool_names != ["event_stream_start", "event_stream_status", "event_stream_stop"]:
            raise AssertionError(tool_names)

        started = tool_text(start)
        repeated_start = tool_text(repeat_start)
        current = tool_text(status)
        stopped = tool_text(stop)
        repeated = tool_text(repeat_stop)
        final = tool_text(final_status)
        session_id = started.get("sessionId")
        if not session_id or started.get("state") != "recording":
            raise AssertionError(started)
        if (
            repeated_start.get("sessionId") != session_id
            or repeated_start.get("state") != "recording"
        ):
            raise AssertionError(repeated_start)
        if current.get("sessionId") != session_id or current.get("state") != "recording":
            raise AssertionError(current)
        if (
            stopped.get("sessionId") != session_id
            or stopped.get("state") != "stopped"
            or stopped.get("endReason") != "recording_controls_stopped"
        ):
            raise AssertionError(stopped)
        if (
            repeated.get("sessionId") != session_id
            or repeated.get("state") != "stopped"
            or repeated.get("endReason") != "recording_controls_stopped"
        ):
            raise AssertionError(repeated)
        if (
            final.get("sessionId") != session_id
            or final.get("state") != "stopped"
            or final.get("endReason") != "recording_controls_stopped"
        ):
            raise AssertionError(final)

        metadata_path = pathlib.Path(stopped["metadataPath"])
        events_path = pathlib.Path(stopped["eventsPath"])
        session_path = pathlib.Path(stopped["sessionPath"])
        for path in [metadata_path, events_path, session_path]:
            if not path.exists():
                raise AssertionError(f"missing recording artifact: {path}")

        events = [
            json.loads(line)
            for line in events_path.read_text().splitlines()
            if line.strip()
        ]
        event_types = [event.get("type") for event in events]
        for required in ["session.started", "session.ended"]:
            if required not in event_types:
                raise AssertionError({"missing": required, "eventTypes": event_types})

        validation = subprocess.run(
            [
                cli,
                "event-stream",
                "validate",
                "--json",
                "--strict-ocu",
                "--require-event-type",
                "session.started",
                "--require-event-type",
                "session.ended",
                str(metadata_path),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={**os.environ, "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1"},
        )
        validation_payload = json.loads(validation.stdout)
        if validation_payload.get("ok") is not True:
            raise AssertionError(validation_payload)

        print(
            json.dumps(
                {
                    "ok": True,
                    "sessionId": session_id,
                    "eventCount": stopped.get("eventCount"),
                    "eventTypes": sorted(set(event_types)),
                    "checkedOneActive": True,
                    "checkedIdempotentStop": True,
                    "checkedFinalStatus": True,
                },
                sort_keys=True,
            )
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
"""


GITHUB_CI_WORKFLOW = """name: ci

on:
  pull_request:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  ci:
    runs-on: macos-26

    steps:
      - name: Check out repository
        uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd

      - name: Set up Node.js
        uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e
        with:
          node-version: "24"

      - name: Install Open Computer Use runtime
        run: npm i -g open-computer-use

      - name: Run standalone skill checks
        run: ./scripts/check.sh
"""


VERIFY_RUNTIME_SCRIPT = """#!/usr/bin/env python3

import json
import os
import pathlib
import select
import subprocess
import sys
import tempfile
import time


EXPECTED_TOOLS = [
    {
        "name": "event_stream_start",
        "description": (
            "Start recording the user's actions for up to 30 minutes. If a recording is already "
            "active, return that active session instead of starting another one."
        ),
        "annotations": {
            "destructiveHint": False,
            "idempotentHint": False,
            "openWorldHint": False,
            "readOnlyHint": False,
        },
        "inputSchema": {
            "additionalProperties": False,
            "properties": {},
            "type": "object",
        },
    },
    {
        "name": "event_stream_status",
        "description": (
            "Get the current or most recent Record & Replay recording status including paths to "
            "metadata and events during the recording."
        ),
        "annotations": {
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
            "readOnlyHint": True,
        },
        "inputSchema": {
            "additionalProperties": False,
            "properties": {},
            "type": "object",
        },
    },
    {
        "name": "event_stream_stop",
        "description": (
            "Stop the active event stream recording if one is running and return status including "
            "paths to metadata and events during the recording."
        ),
        "annotations": {
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
            "readOnlyHint": False,
        },
        "inputSchema": {
            "additionalProperties": False,
            "properties": {},
            "type": "object",
        },
    },
]

EXPECTED_TOOL_NAMES = [tool["name"] for tool in EXPECTED_TOOLS]
TOOL_CONTRACT_KEYS = ["name", "description", "inputSchema", "annotations"]
EXPECTED_INITIALIZE_CAPABILITIES = {"tools": {"listChanged": False}}
EXPECTED_NO_ACTIVE_RESPONSE = {"isRecording": False, "maxDurationSeconds": 1800}


def runtime_version(cli):
    try:
        completed = subprocess.run(
            [cli, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except Exception as error:
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}
    return {
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def mcp_timeout_message(cli, command, process):
    parts = [
        "timed out waiting for Record & Replay MCP response",
        f"runtime={cli!r}",
        f"command={command!r}",
        f"runtimeVersion={runtime_version(cli)!r}",
    ]
    poll = process.poll()
    if poll is None:
        parts.append("processStillRunning=true")
    else:
        parts.append(f"processReturnCode={poll}")
        if process.stderr:
            parts.append(f"stderr={process.stderr.read().strip()!r}")
    parts.append(
        "Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime if this points to an older install."
    )
    return "; ".join(parts)


def read_line(process, timeout=10, timeout_message=None):
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.1)
        if ready:
            line = process.stdout.readline()
            if line:
                return line
        if process.poll() is not None:
            break
    if timeout_message is not None:
        raise RuntimeError(timeout_message())
    raise RuntimeError("timed out waiting for Record & Replay MCP response")


def send_message(process, message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\\n")
    process.stdin.flush()


def request(process, message, timeout=10, timeout_message=None):
    send_message(process, message)
    response = json.loads(read_line(process, timeout=timeout, timeout_message=timeout_message))
    if "error" in response:
        raise AssertionError(response["error"])
    return response


def tool_text(response):
    content = response.get("result", {}).get("content", [])
    if not content or content[0].get("type") != "text":
        raise AssertionError(f"unexpected tool response: {response!r}")
    return json.loads(content[0]["text"])


def tool_error_text(response):
    result = response.get("result", {})
    if result.get("isError") is not True:
        raise AssertionError(f"expected tool error response: {response!r}")
    content = result.get("content", [])
    if not content or content[0].get("type") != "text":
        raise AssertionError(f"unexpected tool error response: {response!r}")
    return content[0]["text"]


def main():
    cli = os.environ.get("OPEN_COMPUTER_USE_CLI", "open-computer-use")
    response_timeout = float(os.environ.get("OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS", "10"))
    with tempfile.TemporaryDirectory(prefix="record-and-replay-runtime-verify-") as tmp:
        recordings = pathlib.Path(tmp) / "recordings"
        env = {
            **os.environ,
            "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": os.environ.get(
                "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY",
                "1",
            ),
            "OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0",
            "OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never",
            "OPEN_COMPUTER_USE_EVENT_STREAM_DIR": str(recordings),
        }
        command = [cli, "event-stream", "mcp"]
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        try:
            initialize = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-11-25",
                        "capabilities": {},
                        "clientInfo": {"name": "record-and-replay-skill-repo-verify", "version": "0"},
                    },
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            send_message(
                process,
                {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            )
            tools_list = request(
                process,
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            no_active_status = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {"name": "event_stream_status", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            no_active_stop = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "tools/call",
                    "params": {"name": "event_stream_stop", "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            unexpected_arguments = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 5,
                    "method": "tools/call",
                    "params": {"name": "event_stream_status", "arguments": {"unexpected": True}},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            non_object_arguments = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 6,
                    "method": "tools/call",
                    "params": {"name": "event_stream_start", "arguments": []},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            missing_tool_name = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 7,
                    "method": "tools/call",
                    "params": {"arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            non_string_tool_name = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 8,
                    "method": "tools/call",
                    "params": {"name": ["event_stream_start"], "arguments": {}},
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            missing_tool_params = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 9,
                    "method": "tools/call",
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
            non_object_tool_params = request(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 10,
                    "method": "tools/call",
                    "params": [],
                },
                timeout=response_timeout,
                timeout_message=lambda: mcp_timeout_message(cli, command, process),
            )
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()

        result = initialize.get("result", {})
        server_info = result.get("serverInfo", {})
        if server_info.get("name") != "Record & Replay":
            raise AssertionError(f"unexpected server name: {server_info!r}")
        if result.get("protocolVersion") != "2025-11-25":
            raise AssertionError(f"unexpected protocolVersion: {result.get('protocolVersion')!r}")
        if result.get("capabilities") != EXPECTED_INITIALIZE_CAPABILITIES:
            raise AssertionError(
                f"unexpected capabilities: {result.get('capabilities')!r}"
            )
        if "instructions" in result:
            raise AssertionError("Record & Replay initialize result should not include instructions")
        checked_initialize_surface_contract = True

        tools = tools_list.get("result", {}).get("tools", [])
        tool_names = [tool.get("name") for tool in tools]
        if tool_names != EXPECTED_TOOL_NAMES:
            raise AssertionError(f"unexpected tools: {tool_names!r}")
        comparable_tools = []
        for tool in tools:
            missing_keys = [key for key in TOOL_CONTRACT_KEYS if key not in tool]
            if missing_keys:
                raise AssertionError(f"tool {tool.get('name')!r} is missing keys: {missing_keys!r}")
            comparable_tools.append({key: tool[key] for key in TOOL_CONTRACT_KEYS})
        if comparable_tools != EXPECTED_TOOLS:
            raise AssertionError(
                "Record & Replay tool metadata drifted: "
                + json.dumps(
                    {"expected": EXPECTED_TOOLS, "actual": comparable_tools},
                    sort_keys=True,
                    separators=(",", ":"),
                )
            )
        checked_tool_metadata_contract = True
        checked_tool_input_schema_no_arguments = all(
            tool.get("inputSchema") == {
                "additionalProperties": False,
                "properties": {},
                "type": "object",
            }
            for tool in comparable_tools
        )
        if not checked_tool_input_schema_no_arguments:
            raise AssertionError(f"unexpected no-arg input schemas: {comparable_tools!r}")

        for label, response in [
            ("event_stream_status", no_active_status),
            ("event_stream_stop", no_active_stop),
        ]:
            payload = tool_text(response)
            if payload != EXPECTED_NO_ACTIVE_RESPONSE:
                raise AssertionError(
                    f"unexpected no-active {label} response: "
                    + json.dumps(
                        {"expected": EXPECTED_NO_ACTIVE_RESPONSE, "actual": payload},
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                )
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("no-active status/stop should not create recording session files")

        unexpected_arguments_error = tool_error_text(unexpected_arguments)
        if "event_stream_status does not accept arguments" not in unexpected_arguments_error:
            raise AssertionError(unexpected_arguments)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected no-arg contract check should not create recording session files")

        non_object_arguments_error = tool_error_text(non_object_arguments)
        if "tools/call arguments must be an object" not in non_object_arguments_error:
            raise AssertionError(non_object_arguments)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected non-object arguments should not create recording session files")

        missing_tool_name_error = tool_error_text(missing_tool_name)
        if "tools/call params.name must be a non-empty string" not in missing_tool_name_error:
            raise AssertionError(missing_tool_name)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected missing tool name should not create recording session files")

        non_string_tool_name_error = tool_error_text(non_string_tool_name)
        if "tools/call params.name must be a non-empty string" not in non_string_tool_name_error:
            raise AssertionError(non_string_tool_name)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected non-string tool name should not create recording session files")

        missing_tool_params_error = tool_error_text(missing_tool_params)
        if "tools/call params must be an object" not in missing_tool_params_error:
            raise AssertionError(missing_tool_params)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected missing tool params should not create recording session files")

        non_object_tool_params_error = tool_error_text(non_object_tool_params)
        if "tools/call params must be an object" not in non_object_tool_params_error:
            raise AssertionError(non_object_tool_params)
        if (recordings / "latest-session.json").exists() or (recordings / "active-session.json").exists():
            raise AssertionError("rejected non-object tool params should not create recording session files")

        print(json.dumps({
            "ok": True,
            "server": server_info,
            "tools": tool_names,
            "checkedInitializeSurfaceContract": checked_initialize_surface_contract,
            "checkedToolMetadataContract": checked_tool_metadata_contract,
            "checkedToolInputSchemaNoArguments": checked_tool_input_schema_no_arguments,
            "checkedNoActiveStatusStop": True,
            "checkedRejectsUnexpectedArguments": True,
            "checkedRejectsNonObjectArguments": True,
            "checkedRequiresObjectParams": True,
            "checkedRequiresStringToolName": True,
            "checkedRequiresObjectArguments": True,
            "checkedRejectedRequestsDoNotCreateSessionFiles": True,
        }, sort_keys=True))
        return 0


if __name__ == "__main__":
    sys.exit(main())
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scaffold a standalone thin Record & Replay skill repository."
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=pathlib.Path,
        help="Directory to create. It must be empty unless --force is passed.",
    )
    parser.add_argument(
        "--repo-name",
        default="open-computer-use-record-and-replay-skill",
        help="Human-readable repository name used in README text.",
    )
    parser.add_argument(
        "--skill-name",
        default=SOURCE_SKILL_NAME,
        help="Skill directory name to create under skills/.",
    )
    parser.add_argument("--force", action="store_true", help="Replace output-dir if it exists.")
    return parser.parse_args()


def write_text(path: pathlib.Path, content: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(path.stat().st_mode | 0o111)


def read_skill_frontmatter(skill_path: pathlib.Path) -> dict[str, str]:
    content = skill_path.read_text()
    if not content.startswith("---\n"):
        raise ValueError(f"skill has no frontmatter: {skill_path}")
    _, frontmatter, _ = content.split("---", 2)
    result: dict[str, str] = {}
    for raw_line in frontmatter.splitlines():
        if ":" not in raw_line:
            continue
        key, value = raw_line.split(":", 1)
        result[key.strip()] = value.strip()
    return result


def markdown_code_list(values: list[str]) -> str:
    formatted = [f"`{value}`" for value in values]
    if not formatted:
        return ""
    if len(formatted) == 1:
        return formatted[0]
    if len(formatted) == 2:
        return " and ".join(formatted)
    return ", ".join(formatted[:-1]) + f", and {formatted[-1]}"


def source_baseline_summary_projection() -> dict[str, object]:
    summary_path = REPO_ROOT / "dist" / "record-and-replay-baseline-summary.json"
    if not summary_path.exists():
        raise ValueError(
            "missing source baseline summary artifact: "
            f"{summary_path}; run make record-and-replay-baseline-audit first"
        )
    summary = json.loads(summary_path.read_text())
    status = summary.get("status")
    evidence = summary.get("evidence")
    if not isinstance(status, dict) or not isinstance(evidence, dict):
        raise ValueError(f"invalid source baseline summary artifact: {summary_path}")
    return {
        "baseline": summary.get("baseline"),
        "checks": summary.get("checks"),
        "ok": summary.get("ok"),
        "status": {
            key: status.get(key)
            for key in [
                "usableBaseline",
                "standaloneRepoBaselineReady",
                "officialGoldenRequirementSatisfied",
                "officialGoldenGatePassed",
                "officialSuccessfulRecordingGoldenComplete",
                "officialSuccessfulRecordingEquivalenceReady",
                "requiresOfficialGoldenCapture",
                "missingUsableBaselineEvidence",
                "missingRequiredOfficialSuccessfulRecordingScenarios",
                "notReadyRequiredOfficialSuccessfulRecordingScenarios",
                "missingRecommendedOfficialSuccessfulRecordingScenarios",
                "officialFixtureCoverageErrors",
            ]
        },
        "evidence": {
            "officialFixtureSetGate": {
                key: (evidence.get("officialFixtureSetGate") or {}).get(key)
                for key in [
                    "ok",
                    "checkedAxDiffComparisonPolicy",
                    "checkedSuppressedStreamComparisonPolicy",
                    "checkedAxDiffComparisonFailure",
                ]
            },
            "fixtureIngestPipelines": {
                key: (evidence.get("fixtureIngestPipelines") or {}).get(key)
                for key in [
                    "checkedOfficialSessionDirectoryPathHandoff",
                ]
            },
            "preflightPipelines": {
                key: (evidence.get("preflightPipelines") or {}).get(key)
                for key in [
                    "checkedOfficialCapturePacketInputSemanticGuard",
                    "checkedOfficialCapturePacketSetContractManifest",
                    "checkedOfficialCapturePacketPostCaptureWorkflow",
                    "checkedOfficialCapturePacketWorkflowVerifier",
                    "checkedOfficialCapturePacketSetPostCaptureWorkflow",
                    "checkedOfficialCapturePacketSetWorkflowVerifier",
                    "checkedOfficialCapturePacketStrictAuditHandoff",
                    "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
                ]
            },
            "standaloneSkillRepo": {
                key: (evidence.get("standaloneSkillRepo") or {}).get(key)
                for key in [
                    "checkedGeneratedRepoSelfCheck",
                    "checkedManifestContract",
                    "checkedOfficialFixtureSetComparePolicyManifest",
                ]
            },
            "npmStagedSkillRepo": {
                key: (evidence.get("npmStagedSkillRepo") or {}).get(key)
                for key in [
                    "checkedGeneratedRepoSelfCheck",
                    "checkedManifestContract",
                    "checkedOfficialFixtureSetComparePolicyManifest",
                ]
            },
        },
    }


def scaffold(args: argparse.Namespace) -> dict[str, object]:
    output_dir = args.output_dir
    if output_dir.exists():
        if not args.force:
            raise ValueError(f"output-dir already exists: {output_dir}; pass --force to replace it")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    if not (SOURCE_SKILL_DIR / "SKILL.md").exists():
        raise ValueError(f"missing source skill: {SOURCE_SKILL_DIR}")

    skill_dir = output_dir / "skills" / args.skill_name
    shutil.copytree(SOURCE_SKILL_DIR, skill_dir)

    frontmatter = read_skill_frontmatter(skill_dir / "SKILL.md")
    if frontmatter.get("name") != args.skill_name:
        raise ValueError(
            f"source skill frontmatter name={frontmatter.get('name')} does not match {args.skill_name}"
        )

    required_scenarios = list(DEFAULT_REQUIRED_SCENARIOS)
    recommended_scenarios = list(DEFAULT_RECOMMENDED_SCENARIOS)
    required_scenario_list = markdown_code_list(required_scenarios)
    recommended_scenario_list = markdown_code_list(recommended_scenarios)

    readme = textwrap.dedent(
        f"""\
        # {args.repo_name}

        Thin standalone skill repository for Open Computer Use Record & Replay.

        This repo intentionally does not contain desktop automation runtime code. It expects
        users to install `open-computer-use` and configures agents to use the official-compatible
        Record & Replay MCP surface:

        ```sh
        npm i -g open-computer-use
        open-computer-use install-codex-record-and-replay-mcp
        ```

        ## Prerequisites

        Python 3 must be available as `python3` for the generated repository
        self-check scripts. If you create this repository through the npm
        launcher, set `PYTHON=/path/to/python3` when your shell cannot find
        Python 3 automatically.

        Install the skill from this repository:

        ```sh
        npx skills add <your-repo-url-or-path> -g -a codex --skill {args.skill_name} -y
        ```

        The skill entrypoint is:

        ```text
        skills/{args.skill_name}/SKILL.md
        ```

        ## Runtime Contract

        The Record & Replay MCP server must expose only these official-compatible tools,
        with matching initialize capabilities, descriptions, empty input schemas,
        and MCP annotations:

        ```text
        event_stream_start
        event_stream_status
        event_stream_stop
        ```

        OCU extension commands such as `event-stream wait`, `validate`, `summarize`, and
        `scaffold-skill` remain CLI/runtime helpers and are not added to the MCP tool surface.

        ## Official Evidence

        The runtime contract is pinned to the official `record-and-replay` 1.0.857
        evidence used by the Open Computer Use baseline:

        - `record-and-replay-event-stream-surface-1.0.857.json` proves the
          non-recording initialize / `tools/list` surface.
        - `record-and-replay-official-no-active-status-stop-1.0.857.json` proves
          no-active `event_stream_status` / `event_stream_stop` return
          `isRecording=false` and `maxDurationSeconds=1800` without creating
          session files.
        - `record-and-replay-official-raw-start-timeout-1.0.857.json` documents
          the current hostless official raw `event_stream_start/status/stop`
          timeout boundary and must not be treated as a successful recording
          golden.

        The Open Computer Use source repo also gates this standalone contract with
        a baseline contract smoke, preflight checks for official capture packets,
        same-scenario OCU candidate pairing, and audit target dry-runs that keep
        baseline / strict summary artifacts and override variables isolated. Those
        source checks and preflight scripts are not copied into this standalone
        repo, and the default standalone self-check still does not start official
        recording.

        To preserve release or standalone handoff evidence in the source repo,
        run the baseline audit target before cutting over. By default this writes
        `dist/record-and-replay-baseline-summary.json`; this scaffold copies a
        redacted projection of that artifact to `evidence/source-baseline-summary.json`
        and the generated `scripts/check.sh` audits it:

        ```sh
        make record-and-replay-baseline-audit
        ```

        After official successful recording fixtures are imported, use the strict
        golden gate audit instead. By default this writes a separate
        `dist/record-and-replay-official-golden-gate-summary.json`, so a failing
        strict gate does not overwrite the usable baseline artifact:

        ```sh
        make record-and-replay-official-golden-gate-audit
        ```

        Before official successful recording fixtures are imported, that strict
        audit is expected to fail. To verify that its saved summary failed only
        because the required official golden is missing, run:

        ```sh
        scripts/check-record-and-replay-baseline-summary.py \\
          dist/record-and-replay-official-golden-gate-summary.json \\
          --allow-strict-official-golden-missing
        ```

        Successful recording fixtures are still required before claiming official
        event schema, AX diff, screenshot, or timeout endReason equivalence.
        The minimum required official successful recording scenario is
        {required_scenario_list}. The recommended calibration set is
        {recommended_scenario_list}. The machine-readable `record-and-replay-skill-repo.json`
        manifest also includes `officialEvidence.scenarioRecipes`, which records
        each scenario's capture goal, expected action events, expected end reason,
        evidence requirements, and OCU candidate source.
        The source repo's official fixture set gate also requires same-scenario
        compare policy for AX diff evidence, AX diff marker alignment,
        suppressed event sequence, and suppressed schema comparison before OCU
        candidates can be treated as calibrated against official recordings.

        ## Recording Handoff

        After a recording stops, treat `events.jsonl` as the primary evidence and
        `metadata.json` / `session.json` as session state and path metadata. Before
        creating a reusable skill from a recording, run the installed runtime validator:

        ```sh
        open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>
        ```

        If the host only returns `eventsPath`, run the non-strict events-only gate:

        ```sh
        open-computer-use event-stream validate --json --require-skill-draft <eventsPath>
        ```

        Events-only validation can prove JSONL readability, completion,
        single `session.started` opening event, single `session.ended`
        final-event closure, high-level action evidence, blocking diagnostics,
        and cancellation inferred from
        `session.ended.endReason=recording_controls_cancelled`; it cannot prove
        OCU metadata/session alias consistency or the declared `metadataPath` /
        `sessionPath` / `eventsPath` / `suppressedEventsPath` handoff paths.
        Cancelled, incomplete, or malformed recordings must not be used to
        create or update a skill.

        Generate the first draft only after validation passes:

        ```sh
        open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath> \\
          --skill-name <new-skill-name> \\
          --output-dir <output-dir>
        ```

        The scaffold command also runs the skill-draft validation gate before writing
        files. The generated draft is a starting point: the agent still needs to read
        the original `events.jsonl`, resolve runtime inputs and safety signals, and
        finish the normal skill creation workflow before reporting that a reusable
        skill exists.

        ## Package

        ```sh
        ./scripts/package-skill.sh
        ```

        The package script writes `.zip` and `.skill` artifacts under `dist/skills/`.

        ## Check

        Run the generated repository self-check before publishing or installing it:

        ```sh
        ./scripts/check.sh
        ```

        The check packages the skill, verifies the runtime contract, and verifies
        that the README and skill workflow still preserve the official Record &
        Replay handoff semantics: start once, do not poll, stop only after the user
        returns, keep official golden gaps visible, and do not stop again after
        cancellation. Set
        `OPEN_COMPUTER_USE_CLI=/path/to/open-computer-use` when testing a specific
        runtime binary.

        `scripts/check.sh` runs `scripts/verify-readme-handoff.py` to keep the
        official evidence list, baseline / strict audit handoff commands,
        required and recommended successful recording scenarios, and wait/notify
        boundary documented in this README.

        `scripts/check.sh` also runs `scripts/verify-source-baseline-summary.py`.
        That check consumes `evidence/source-baseline-summary.json`, which is a
        redacted projection of the source repo's latest default baseline audit
        artifact. It verifies that the source baseline was usable, that the
        standalone repo baseline evidence was ready, and that the official
        successful recording golden gap was still explicit.

        The generated GitHub Actions workflow runs the same check after installing
        the published `open-computer-use` runtime.

        `scripts/check.sh` also runs `scripts/wait-notify-contract-smoke.py`, which
        does not start a recording. It waits on an intentionally missing session
        with `--notify-command`, confirms `waitTimedOut=true`,
        `waitSessionMatched=false`, confirms the callback is skipped, and confirms
        no recording session files are created.

        `scripts/check.sh` then runs `scripts/recording-to-skill-smoke.py`, which
        also does not start a recording. It creates a temporary synthetic completed
        recording, runs `event-stream validate --strict-ocu --require-skill-draft`,
        checks the declared handoff path evidence, runs the events-only validation
        gate, and verifies that the installed runtime can generate a draft skill
        with `event-stream scaffold-skill`.

        ## Independent Wait / Notify Integration

        Wrappers that need to resume automatically after the user clicks Done or
        Discard should use the OCU CLI extension layer, not extra MCP tools:

        ```sh
        open-computer-use event-stream start --json
        open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'
        ```

        `wait --json` returns `waitTimedOut` and `waitSessionMatched`.
        `--notify-command` receives the final status JSON on stdin and the
        `OPEN_COMPUTER_USE_EVENT_STREAM_*` environment variables documented in the
        skill. Keep this listener path outside the official-compatible MCP tool
        surface.

        ## Optional Lifecycle Smoke

        To verify that the installed runtime can create and stop a minimal recording
        session, run:

        ```sh
        ./scripts/recording-lifecycle-smoke.py
        ```

        This starts a short Record & Replay session with OCU controls disabled, stops
        it through the same `event-stream mcp` process, and validates the resulting
        `metadata.json`, `session.json`, and `events.jsonl` with the installed runtime.
        It is intentionally separate from `scripts/check.sh` because it starts a real
        local recording session and may require desktop permissions on macOS.

        ## Verify Runtime Contract

        This check does not start a recording. It only verifies that the configured
        `open-computer-use` runtime exposes the official-compatible Record & Replay
        MCP surface, including initialize capabilities, tool descriptions, no-arg
        schemas, and annotations:

        ```sh
        ./scripts/verify-runtime.py
        ```

        Set `OPEN_COMPUTER_USE_CLI=/path/to/open-computer-use` to test a specific
        runtime binary.

        ## Verify Skill Workflow

        This check does not start a recording. It verifies that `SKILL.md` keeps the
        official handoff constraints for agents: use only the three MCP tools,
        end the turn after start, avoid polling, read returned recording paths, run
        validation before scaffold, and avoid calling stop again after Discard:

        ```sh
        ./scripts/verify-skill-workflow.py
        ```
        """
    )
    write_text(output_dir / "README.md", readme)
    write_text(output_dir / ".gitignore", "dist/\n.DS_Store\n")
    write_text(output_dir / ".github" / "workflows" / "ci.yml", GITHUB_CI_WORKFLOW)
    write_text(output_dir / "scripts" / "package-skill.sh", PACKAGE_SCRIPT, executable=True)
    write_text(
        output_dir / "scripts" / "verify-package-artifact.py",
        VERIFY_PACKAGE_ARTIFACT_SCRIPT,
        executable=True,
    )
    write_text(output_dir / "scripts" / "check.sh", CHECK_SCRIPT, executable=True)
    write_text(output_dir / "scripts" / "verify-manifest.py", VERIFY_MANIFEST_SCRIPT, executable=True)
    write_text(
        output_dir / "scripts" / "verify-source-baseline-summary.py",
        VERIFY_SOURCE_BASELINE_SUMMARY_SCRIPT,
        executable=True,
    )
    write_text(
        output_dir / "scripts" / "verify-readme-handoff.py",
        VERIFY_README_HANDOFF_SCRIPT,
        executable=True,
    )
    write_text(output_dir / "scripts" / "verify-runtime.py", VERIFY_RUNTIME_SCRIPT, executable=True)
    write_text(
        output_dir / "scripts" / "verify-skill-workflow.py",
        VERIFY_SKILL_WORKFLOW_SCRIPT,
        executable=True,
    )
    write_text(
        output_dir / "scripts" / "recording-to-skill-smoke.py",
        RECORDING_TO_SKILL_SMOKE_SCRIPT,
        executable=True,
    )
    write_text(
        output_dir / "scripts" / "wait-notify-contract-smoke.py",
        WAIT_NOTIFY_CONTRACT_SMOKE_SCRIPT,
        executable=True,
    )
    write_text(
        output_dir / "scripts" / "recording-lifecycle-smoke.py",
        RECORDING_LIFECYCLE_SMOKE_SCRIPT,
        executable=True,
    )

    scenario_recipes = {
        scenario: scenario_recipe(scenario) for scenario in recommended_scenarios
    }
    source_baseline_summary = source_baseline_summary_projection()
    has_successful_recording_golden = (
        (source_baseline_summary.get("status") or {}).get(
            "officialSuccessfulRecordingGoldenComplete"
        )
        is True
    )
    write_text(
        output_dir / "evidence" / "source-baseline-summary.json",
        json.dumps(source_baseline_summary, indent=2, sort_keys=True) + "\n",
    )

    manifest = {
        "name": args.repo_name,
        "kind": "open-computer-use-record-and-replay-thin-skill-repo",
        "runtimeDependency": "open-computer-use",
        "skill": {
            "name": args.skill_name,
            "path": f"skills/{args.skill_name}/SKILL.md",
        },
        "officialEvidence": {
            "baselineVersion": "record-and-replay/1.0.857",
            "nonRecordingSurfaceFixture": (
                "record-and-replay-event-stream-surface-1.0.857.json"
            ),
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
            "hasSuccessfulRecordingGolden": has_successful_recording_golden,
            "requiredSuccessfulRecordingScenarios": required_scenarios,
            "recommendedSuccessfulRecordingScenarios": recommended_scenarios,
            "scenarioRecipes": scenario_recipes,
            "successfulRecordingGoldenRequiredFor": [
                "session file schema equivalence",
                "event field schema equivalence",
                "AX compact diff algorithm equivalence",
                "screenshot trigger equivalence",
                "timeout endReason equivalence",
            ],
        },
        "mcpServer": {
            "command": "open-computer-use",
            "args": ["event-stream", "mcp"],
            "capabilities": {"tools": {"listChanged": False}},
            "tools": ["event_stream_start", "event_stream_status", "event_stream_stop"],
            "requiresObjectParams": True,
            "requiresStringToolName": True,
            "requiresObjectArguments": True,
            "rejectsUnexpectedArguments": True,
            "rejectedRequestsDoNotCreateSessionFiles": True,
            "noActiveResponse": {
                "event_stream_status": {
                    "isRecording": False,
                    "maxDurationSeconds": 1800,
                },
                "event_stream_stop": {
                    "isRecording": False,
                    "maxDurationSeconds": 1800,
                },
            },
            "toolMetadata": [
                {
                    "name": "event_stream_start",
                    "description": "Start recording the user's actions for up to 30 minutes. If a recording is already active, return that active session instead of starting another one.",
                    "annotations": {
                        "destructiveHint": False,
                        "idempotentHint": False,
                        "openWorldHint": False,
                        "readOnlyHint": False,
                    },
                    "inputSchema": {
                        "additionalProperties": False,
                        "properties": {},
                        "type": "object",
                    },
                },
                {
                    "name": "event_stream_status",
                    "description": "Get the current or most recent Record & Replay recording status including paths to metadata and events during the recording.",
                    "annotations": {
                        "destructiveHint": False,
                        "idempotentHint": True,
                        "openWorldHint": False,
                        "readOnlyHint": True,
                    },
                    "inputSchema": {
                        "additionalProperties": False,
                        "properties": {},
                        "type": "object",
                    },
                },
                {
                    "name": "event_stream_stop",
                    "description": "Stop the active event stream recording if one is running and return status including paths to metadata and events during the recording.",
                    "annotations": {
                        "destructiveHint": False,
                        "idempotentHint": True,
                        "openWorldHint": False,
                        "readOnlyHint": False,
                    },
                    "inputSchema": {
                        "additionalProperties": False,
                        "properties": {},
                        "type": "object",
                    },
                },
            ],
        },
        "extensionLayer": {
            "officialCompatibleMcpSurface": False,
            "commands": [
                "event-stream start --json",
                "event-stream status --json",
                "event-stream stop --json",
                "event-stream cancel --json",
                "event-stream wait --json --session-id <id>",
                "event-stream wait --json --session-id <id> --notify-command <json-argv>",
                "event-stream validate --json --require-skill-draft <recording>",
                "event-stream summarize --json <recording>",
                "event-stream scaffold-skill --json <recording>",
            ],
            "waitNotify": {
                "resultFields": ["waitTimedOut", "waitSessionMatched"],
                "stdin": "final status JSON",
                "environmentVariables": [
                    "OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_STATE",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH",
                    "OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH",
                ],
                "callbackSkippedWhenWaitSessionMatchedFalse": True,
                "callbackFailureMakesCliFail": True,
                "callbackTimeoutMakesCliFail": True,
            },
        },
        "recordingToSkill": {
            "strictValidation": {
                "command": "event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>",
                "requiresDeclaredHandoffPaths": [
                    "metadataPath",
                    "sessionPath",
                    "eventsPath",
                    "suppressedEventsPath",
                ],
                "requiresMetadataSessionAlias": True,
                "requiresScreenshotPathsInsideSession": True,
                "requiresSkillDraftReady": True,
            },
            "eventsOnlyValidation": {
                "command": "event-stream validate --json --require-skill-draft <eventsPath>",
                "provesMetadataSessionAlias": False,
                "provesDeclaredHandoffPaths": False,
            },
            "scaffoldSkill": {
                "command": "event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>",
                "runsSkillDraftValidationGate": True,
            },
            "rejectsCancelledRecordings": True,
        },
        "checks": {
            "packageSkill": "scripts/package-skill.sh",
            "packageArtifact": "scripts/verify-package-artifact.py",
            "manifestContract": "scripts/verify-manifest.py",
            "sourceBaselineSummaryEvidence": "scripts/verify-source-baseline-summary.py",
            "readmeHandoffContract": "scripts/verify-readme-handoff.py",
            "runtimeContract": "scripts/verify-runtime.py",
            "skillWorkflow": "scripts/verify-skill-workflow.py",
            "waitNotifyContractSmoke": "scripts/wait-notify-contract-smoke.py",
            "recordingToSkillSmoke": "scripts/recording-to-skill-smoke.py",
            "selfCheck": "scripts/check.sh",
        },
        "optionalChecks": {
            "recordingLifecycleSmoke": "scripts/recording-lifecycle-smoke.py",
        },
    }
    write_text(output_dir / "record-and-replay-skill-repo.json", json.dumps(manifest, indent=2) + "\n")

    return {
        "ok": True,
        "outputDir": str(output_dir),
        "skillPath": str(skill_dir / "SKILL.md"),
        "manifestPath": str(output_dir / "record-and-replay-skill-repo.json"),
    }


def main() -> int:
    args = parse_args()
    try:
        result = scaffold(args)
    except ValueError as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
