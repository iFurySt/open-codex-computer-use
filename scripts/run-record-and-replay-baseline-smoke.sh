#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

require_official_golden=0
summary_json=""

usage() {
  cat <<'EOF'
Usage: scripts/run-record-and-replay-baseline-smoke.sh [--require-official-golden] [--summary-json <path>]

Runs the opt-in Record & Replay baseline smoke suite.

Options:
  --require-official-golden  Return non-zero unless required official successful
                             recording fixtures are present in the repository.
  --summary-json <path>      Write the final machine-readable baseline summary
                             JSON to this path while still printing it to stdout.
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-official-golden)
      require_official_golden=1
      shift
      ;;
    --summary-json)
      if [[ $# -lt 2 ]]; then
        echo "--summary-json requires a path" >&2
        usage >&2
        exit 2
      fi
      summary_json="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_step() {
  local name="$1"
  shift
  echo "==> ${name}" >&2
  "$@"
}

run_json_step() {
  local name="$1"
  local output_file="$2"
  shift 2
  echo "==> ${name}" >&2
  "$@" | tee "${output_file}"
}

assert_json_true_keys() {
  local json_file="$1"
  shift
  python3 - "${json_file}" "$@" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
keys = sys.argv[2:]
payload = json.loads(path.read_text())
missing = [key for key in keys if payload.get(key) is not True]
if missing:
    raise SystemExit(
        "expected true JSON keys missing from "
        + str(path)
        + ": "
        + ", ".join(missing)
        + "\n"
        + json.dumps(payload, indent=2, sort_keys=True)
    )
PY
}

assert_json_contract_true_keys() {
  local json_file="$1"
  local contract_name="$2"
  python3 - "${json_file}" "${contract_name}" <<'PY'
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path.cwd() / "scripts"))
import record_and_replay_baseline_contract as contract

path = pathlib.Path(sys.argv[1])
contract_name = sys.argv[2]
keys = getattr(contract, contract_name)
payload = json.loads(path.read_text())
missing = [key for key in keys if payload.get(key) is not True]
if missing:
    raise SystemExit(
        "expected true JSON keys missing from "
        + str(path)
        + ": "
        + ", ".join(missing)
        + "\n"
        + json.dumps(payload, indent=2, sort_keys=True)
    )
PY
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ocu-rnr-baseline-smoke.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
standalone_json="${tmp_dir}/standalone-skill-repo-smoke.json"
npm_json="${tmp_dir}/npm-staged-skill-repo-smoke.json"
official_surface_json="${tmp_dir}/official-surface-compare.json"
official_no_active_json="${tmp_dir}/official-no-active-response.json"
official_raw_timeout_json="${tmp_dir}/official-raw-start-timeout.json"
official_fixture_set_json="${tmp_dir}/official-fixture-set-smoke.json"
official_fixture_coverage_json="${tmp_dir}/official-fixture-coverage.json"
official_fixture_ingest_json="${tmp_dir}/official-fixture-ingest-smoke.json"
ocu_candidate_ingest_json="${tmp_dir}/ocu-candidate-ingest-smoke.json"
official_capture_preflight_json="${tmp_dir}/official-capture-preflight-smoke.json"
ocu_pairing_preflight_json="${tmp_dir}/ocu-pairing-preflight-smoke.json"
baseline_audit_targets_json="${tmp_dir}/baseline-audit-targets-smoke.json"
baseline_contract_json="${tmp_dir}/baseline-contract-smoke.json"
matrix_jsonl="${tmp_dir}/event-stream-matrix.jsonl"
screenshot_jsonl="${tmp_dir}/event-stream-screenshot-smoke.jsonl"
action_jsonl="${tmp_dir}/event-stream-action-smoke.jsonl"
action_simple_jsonl="${tmp_dir}/event-stream-action-simple-smoke.jsonl"
action_drag_jsonl="${tmp_dir}/event-stream-action-drag-smoke.jsonl"
generated_summary_json="${tmp_dir}/record-and-replay-baseline-summary.json"

run_json_step "baseline contract smoke" "${baseline_contract_json}" ./scripts/test-record-and-replay-baseline-contract.py
assert_json_true_keys \
  "${baseline_contract_json}" \
  checkedRequiredBaselineChecks \
  checkedNoDuplicateRequiredBaselineChecks \
  checkedStandaloneSmokeRequiredKeys \
  checkedStandaloneSummaryEvidenceKeys \
  checkedStandaloneLifecycleSummaryRenames \
  checkedNpmStagedSmokeRequiredKeys \
  checkedNpmStagedSummaryEvidenceKeys \
  checkedNpmStagedSummaryMatchesSmoke
run_json_step "event-stream smoke matrix" "${matrix_jsonl}" ./scripts/run-event-stream-smoke-matrix.sh
run_json_step "event-stream screenshot context smoke" "${screenshot_jsonl}" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_SCREENSHOTS=1 ./scripts/run-event-stream-smoke-tests.sh
run_json_step "event-stream real input action smoke" "${action_jsonl}" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 ./scripts/run-event-stream-smoke-tests.sh
run_json_step "event-stream simple action candidate smoke" "${action_simple_jsonl}" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop ./scripts/run-event-stream-smoke-tests.sh
cat "${action_simple_jsonl}" >>"${action_jsonl}"
run_json_step "event-stream drag action candidate smoke" "${action_drag_jsonl}" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=drag-stop ./scripts/run-event-stream-smoke-tests.sh
cat "${action_drag_jsonl}" >>"${action_jsonl}"
python3 - "${matrix_jsonl}" "${screenshot_jsonl}" "${action_jsonl}" <<'PY'
import json
import pathlib
import sys


def json_lines(path):
    records = []
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        records.append(json.loads(line))
    return records


matrix = json_lines(sys.argv[1])
screenshot = json_lines(sys.argv[2])
action = json_lines(sys.argv[3])
matrix_modes = {record.get("mode") for record in matrix if record.get("mode")}
required_modes = {
    "no-active",
    "timeout",
    "wait-timeout",
    "approval",
    "mcp-elicitation",
    "app-agent-wait",
}
missing_modes = sorted(required_modes - matrix_modes)
has_default_lifecycle = any(
    record.get("ok") is True and record.get("handoffChecked") is True for record in matrix
)
has_matrix_summary = any(record.get("ok") is True and record.get("matrix") == "event-stream" for record in matrix)
if missing_modes or not has_default_lifecycle or not has_matrix_summary:
    raise SystemExit(
        "event-stream matrix evidence incomplete\n"
        + json.dumps(
            {
                "missingModes": missing_modes,
                "hasDefaultLifecycle": has_default_lifecycle,
                "hasMatrixSummary": has_matrix_summary,
                "records": matrix,
            },
            indent=2,
            sort_keys=True,
        )
    )

screenshot_records = [
    record
    for record in screenshot
    if record.get("ok") is True and record.get("screenshotPolicy") == "always"
]
if not screenshot_records:
    raise SystemExit(
        "missing screenshot context smoke JSON record\n"
        + json.dumps(screenshot, indent=2, sort_keys=True)
    )
screenshot_record = screenshot_records[-1]
if (
    screenshot_record.get("screenshotContextChecked") is not True
    or not isinstance(screenshot_record.get("screenshotNeededForContextCount"), int)
    or screenshot_record.get("screenshotNeededForContextCount") <= 0
):
    raise SystemExit(
        "event-stream screenshot context evidence incomplete\n"
        + json.dumps(screenshot_record, indent=2, sort_keys=True)
    )
if (
    isinstance(screenshot_record.get("screenshotAvailableCount"), int)
    and screenshot_record.get("screenshotAvailableCount") > 0
    and screenshot_record.get("screenshotPathCount", 0) <= 0
):
    raise SystemExit(
        "event-stream screenshot context reported available screenshots without paths\n"
        + json.dumps(screenshot_record, indent=2, sort_keys=True)
    )

action_records = [record for record in action if record.get("mode") == "actions"]
if not action_records:
    raise SystemExit("missing action smoke JSON record\n" + json.dumps(action, indent=2, sort_keys=True))
mixed_records = [
    record
    for record in action_records
    if record.get("actionScenario") in (None, "mixed-action-stop")
]
action_record = mixed_records[-1] if mixed_records else action_records[-1]
required_event_types = {
    "session.started",
    "window.changed",
    "AX.focusedWindowChanged",
    "mouse.click",
    "session.ended",
}
action_event_types = set(action_record.get("eventTypes", []))
missing_event_types = sorted(required_event_types - action_event_types)
if (
    action_record.get("ok") is not True
    or missing_event_types
    or not action_record.get("skillPath")
    or not action_record.get("mcpTranscriptPath")
    or action_record.get("checkedMcpResponseShapesCaptured") is not True
    or action_record.get("checkedSkillReadinessCanCreateDraft") is not True
    or action_record.get("checkedSkillCreatorFinalizationHandoff") is not True
    or action_record.get("checkedGeneratedSkillPathRedaction") is not True
):
    raise SystemExit(
        "event-stream action evidence incomplete\n"
        + json.dumps(
            {
                "missingEventTypes": missing_event_types,
                "record": action_record,
            },
            indent=2,
            sort_keys=True,
        )
    )

scenario_requirements = {
    "simple-action-stop": {"mouse.click"},
    "drag-stop": {"mouse.drag"},
}
for scenario, required_types in scenario_requirements.items():
    scenario_records = [
        record for record in action_records if record.get("actionScenario") == scenario
    ]
    if not scenario_records:
        raise SystemExit(
            f"missing event-stream action scenario evidence for {scenario}\n"
            + json.dumps(action_records, indent=2, sort_keys=True)
        )
    scenario_record = scenario_records[-1]
    scenario_event_types = set(scenario_record.get("eventTypes", []))
    scenario_required_event_types = (
        {"session.started", "window.changed", "AX.focusedWindowChanged", "session.ended"}
        | required_types
    )
    scenario_missing_event_types = sorted(
        scenario_required_event_types - scenario_event_types
    )
    if (
        scenario_record.get("ok") is not True
        or scenario_missing_event_types
        or scenario_record.get("checkedMcpResponseShapesCaptured") is not True
        or scenario_record.get("checkedSkillReadinessCanCreateDraft") is not True
        or scenario_record.get("checkedSkillCreatorFinalizationHandoff") is not True
        or scenario_record.get("checkedGeneratedSkillPathRedaction") is not True
    ):
        raise SystemExit(
            f"event-stream action scenario evidence incomplete for {scenario}\n"
            + json.dumps(
                {
                    "missingEventTypes": scenario_missing_event_types,
                    "record": scenario_record,
                },
                indent=2,
                sort_keys=True,
            )
        )
PY
run_json_step "official Record & Replay surface compare" "${official_surface_json}" ./scripts/compare-event-stream-surface.py --use-default-official
python3 - "${official_surface_json}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
by_label = {result.get("label"): result for result in payload.get("results", [])}
required = ["local-open-computer-use", "official-record-and-replay"]
missing = [label for label in required if by_label.get(label, {}).get("ok") is not True]
if payload.get("ok") is not True or missing:
    raise SystemExit(
        "official surface compare did not prove required labels: "
        + ", ".join(missing)
        + "\n"
        + json.dumps(payload, indent=2, sort_keys=True)
    )
PY
run_json_step "official no-active response compare" "${official_no_active_json}" ./scripts/compare-event-stream-no-active.py
python3 - "${official_no_active_json}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected_response = {"isRecording": False, "maxDurationSeconds": 1800}
actual = payload.get("actual", {})
checked_tools = payload.get("checkedTools", [])
missing_tools = [
    tool for tool in ["event_stream_status", "event_stream_stop"] if tool not in checked_tools
]
if (
    payload.get("ok") is not True
    or payload.get("createdSessionFiles") is not False
    or missing_tools
    or actual.get("event_stream_status") != expected_response
    or actual.get("event_stream_stop") != expected_response
):
    raise SystemExit(
        "official no-active response compare did not prove required shape\n"
        + json.dumps(
            {
                "missingTools": missing_tools,
                "payload": payload,
            },
            indent=2,
            sort_keys=True,
        )
    )
PY
run_json_step "official raw start timeout fixture smoke" "${official_raw_timeout_json}" ./scripts/test-event-stream-probe-fixtures.py
assert_json_true_keys \
  "${official_raw_timeout_json}" \
  checkedOfficialRawStartTimeoutBoundary \
  checkedOfficialRawStartStatusStopTimeout \
  checkedOfficialRawStartDoesNotReturnRecordingPaths \
  checkedOfficialRawSurface \
  checkedRawProbeFixtureRedaction
run_json_step "official fixture set gate smoke" "${official_fixture_set_json}" ./scripts/test-event-stream-official-fixture-set.py
assert_json_true_keys \
  "${official_fixture_set_json}" \
  checkedFixtureSetGate \
  checkedRequiredSimpleActionStopScenario \
  checkedCandidatePairing \
  checkedCandidateReadinessFailure \
  checkedMissingCandidateFailure \
  checkedAxDiffComparisonPolicy \
  checkedSuppressedStreamComparisonPolicy \
  checkedAxDiffComparisonFailure \
  checkedStopEndReasonPolicy \
  checkedCancelScenarioPolicy \
  checkedKeyboardInputScenarioPolicy \
  checkedDragScenarioPolicy \
  checkedTimeoutScenarioPolicy \
  checkedMissingScenarioFailure \
  checkedImportScenarioManifest
run_json_step "official fixture coverage report" "${official_fixture_coverage_json}" ./scripts/check-event-stream-official-fixture-coverage.py --allow-missing --check-readiness
run_json_step "official fixture ingest smoke" "${official_fixture_ingest_json}" ./scripts/test-official-record-and-replay-fixture-ingest.py
assert_json_true_keys \
  "${official_fixture_ingest_json}" \
  checkedOfficialFixtureIngest \
  checkedOfficialFixtureInspectOnly \
  checkedOfficialSessionDirectoryPathHandoff \
  checkedPostIngestCoverageReport \
  checkedPostIngestCoverageReadiness \
  checkedPostIngestRequireCoverageFailure
run_json_step "OCU candidate ingest smoke" "${ocu_candidate_ingest_json}" ./scripts/test-ocu-record-and-replay-candidate-ingest.py
assert_json_true_keys \
  "${ocu_candidate_ingest_json}" \
  checkedOcuCandidateIngest \
  checkedCandidateIngestHandoffCommands \
  checkedSmokeJsonImport \
  checkedOfficialCandidatePairing \
  checkedCandidateRedaction \
  checkedKeyboardInputScenarioReadiness \
  checkedDragScenarioReadiness
run_json_step "official golden capture preflight smoke" "${official_capture_preflight_json}" ./scripts/test-record-and-replay-official-golden-capture-preflight.py
assert_json_true_keys \
  "${official_capture_preflight_json}" \
  checkedMissingScenarioPreflight \
  checkedCapturePacket \
  checkedCapturePacketPostCaptureWorkflow \
  checkedCapturePacketHandoffScripts \
  checkedCapturePacketStrictAuditHandoff \
  checkedCapturePacketStrictExpectedFailureAuditHandoff \
  checkedCapturePacketOcuCandidateOutputDir \
  checkedCapturePacketNoTranscript \
  checkedCapturePacketSet \
  checkedCapturePacketSetPostCaptureWorkflow \
  checkedCapturePacketSetOcuCandidateHandoff \
  checkedCapturePacketSetContractManifest \
  checkedCapturePacketTranscriptManifest \
  checkedMakeCapturePacketTargets \
  checkedCapturePacketInputSemanticGuard \
  checkedCapturePacketPlaceholderGuard \
  checkedCapturePacketVerifyInputs \
  checkedCapturePacketImportPlaceholderGuard \
  checkedCapturePacketTranscriptPlaceholderGuard \
  checkedCapturePacketSetRootPlaceholderGuard \
  checkedCapturePacketSetRootPreflightPlaceholderGuard \
  checkedCapturePacketSetVerifyAll \
  checkedRequireReadyFailure \
  checkedMissingPluginFailure \
  checkedAllowedMissingPluginKeyboardScenario \
  checkedCoverageErrorFailure
run_json_step "OCU candidate pairing preflight smoke" "${ocu_pairing_preflight_json}" ./scripts/test-record-and-replay-ocu-candidate-pairing-preflight.py
assert_json_true_keys \
  "${ocu_pairing_preflight_json}" \
  checkedMissingOfficialPreflight \
  checkedNoCandidatePreflight \
  checkedPairedCandidatePreflight \
  checkedKeyboardRecordingRequiredScenario \
  checkedCoverageErrorReport
run_json_step "baseline audit Make targets smoke" "${baseline_audit_targets_json}" ./scripts/test-record-and-replay-baseline-audit-make-targets.py
assert_json_true_keys \
  "${baseline_audit_targets_json}" \
  checkedBaselineAuditMakeTarget \
  checkedBaselineAuditDefaultSummaryPath \
  checkedBaselineAuditCustomSummaryPath \
  checkedBaselineAuditIgnoresStrictSummaryVar \
  checkedStrictOfficialGoldenAuditMakeTarget \
  checkedStrictOfficialGoldenAuditDefaultSummaryPath \
  checkedStrictOfficialGoldenAuditCustomSummaryPath \
  checkedStrictOfficialGoldenAuditIgnoresBaselineSummaryVar \
  checkedStrictOfficialGoldenAuditSeparateSummaryPath
run_json_step "standalone Record & Replay skill repo smoke" "${standalone_json}" ./scripts/test-record-and-replay-skill-repo-scaffold.py
assert_json_contract_true_keys \
  "${standalone_json}" \
  STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS
run_json_step "npm staged Record & Replay skill repo smoke" "${npm_json}" node ./scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs
assert_json_contract_true_keys \
  "${npm_json}" \
  NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS

summary_args=(
  --standalone-json "${standalone_json}"
  --npm-json "${npm_json}"
  --official-surface-json "${official_surface_json}"
  --official-no-active-json "${official_no_active_json}"
  --official-raw-timeout-json "${official_raw_timeout_json}"
  --official-fixture-set-json "${official_fixture_set_json}"
  --official-fixture-coverage-json "${official_fixture_coverage_json}"
  --official-fixture-ingest-json "${official_fixture_ingest_json}"
  --ocu-candidate-ingest-json "${ocu_candidate_ingest_json}"
  --official-capture-preflight-json "${official_capture_preflight_json}"
  --ocu-pairing-preflight-json "${ocu_pairing_preflight_json}"
  --baseline-audit-targets-json "${baseline_audit_targets_json}"
  --baseline-contract-json "${baseline_contract_json}"
  --matrix-jsonl "${matrix_jsonl}"
  --screenshot-jsonl "${screenshot_jsonl}"
  --action-jsonl "${action_jsonl}"
)
if [[ "${require_official_golden}" == "1" ]]; then
  summary_args+=(--require-official-golden)
fi
set +e
if [[ -n "${summary_json}" ]]; then
  mkdir -p "$(dirname "${summary_json}")"
  ./scripts/build-record-and-replay-baseline-summary.py "${summary_args[@]}" | tee "${generated_summary_json}" "${summary_json}"
else
  ./scripts/build-record-and-replay-baseline-summary.py "${summary_args[@]}" | tee "${generated_summary_json}"
fi
summary_status="${PIPESTATUS[0]}"
set -e

audit_args=("${generated_summary_json}")
if [[ "${require_official_golden}" == "1" ]]; then
  audit_args+=(--require-official-golden)
fi
set +e
./scripts/check-record-and-replay-baseline-summary.py "${audit_args[@]}" >&2
audit_status="$?"
set -e

if [[ "${summary_status}" != "0" ]]; then
  exit "${summary_status}"
fi
exit "${audit_status}"
