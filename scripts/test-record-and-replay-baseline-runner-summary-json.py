#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import shutil
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


def run(command: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def parse_last_json(stdout: str) -> dict:
    decoder = json.JSONDecoder()
    records = []
    index = 0
    while index < len(stdout):
        start = stdout.find("{", index)
        if start < 0:
            break
        try:
            payload, end = decoder.raw_decode(stdout[start:])
        except json.JSONDecodeError:
            index = start + 1
            continue
        if isinstance(payload, dict):
            records.append(payload)
        index = start + end
    assert records, stdout
    return records[-1]


def read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: pathlib.Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path: pathlib.Path, records: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(record, sort_keys=True) for record in records) + "\n")


def split_action_records(action_path: pathlib.Path, output_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    records = [
        json.loads(line)
        for line in action_path.read_text().splitlines()
        if line.strip()
    ]
    by_scenario = {
        record.get("actionScenario", "mixed-action-stop"): record
        for record in records
    }
    scenario_paths = {}
    for scenario in ("mixed-action-stop", "simple-action-stop", "drag-stop"):
        if scenario not in by_scenario:
            raise AssertionError(f"missing action fixture for {scenario}")
        scenario_path = output_dir / f"action-{scenario}.jsonl"
        write_jsonl(scenario_path, [by_scenario[scenario]])
        scenario_paths[scenario] = scenario_path
    return scenario_paths


def make_shell_stub(path: pathlib.Path, body: str) -> None:
    path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
    path.chmod(0o755)


def make_cat_stub(path: pathlib.Path, source: pathlib.Path) -> None:
    make_shell_stub(path, f"cat {str(source)!r}\n")


def build_fake_repo(repo: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    fixture_module = load_summary_fixtures(repo)
    evidence_dir = root / "evidence"
    paths = fixture_module.write_inputs(evidence_dir, has_official_golden=False)
    action_paths = split_action_records(paths["action"], evidence_dir)

    surface_payload = read_json(paths["surface"])
    surface_payload["ok"] = True
    write_json(paths["surface"], surface_payload)

    screenshot_records = [
        json.loads(line)
        for line in paths["screenshot"].read_text().splitlines()
        if line.strip()
    ]
    screenshot_records[-1]["screenshotContextChecked"] = True
    paths["screenshot"].write_text(
        "\n".join(json.dumps(record, sort_keys=True) for record in screenshot_records)
        + "\n"
    )

    fixture_set_payload = read_json(paths["fixture_set"])
    fixture_set_payload.update(
        {
            "checkedImportScenarioManifest": True,
            "checkedMissingCandidateFailure": True,
            "checkedMissingScenarioFailure": True,
        }
    )
    write_json(paths["fixture_set"], fixture_set_payload)

    fake_repo = root / "fake-repo"
    fake_scripts = fake_repo / "scripts"
    fake_scripts.mkdir(parents=True)
    shutil.copy2(
        repo / "scripts/run-record-and-replay-baseline-smoke.sh",
        fake_scripts / "run-record-and-replay-baseline-smoke.sh",
    )
    shutil.copy2(
        repo / "scripts/build-record-and-replay-baseline-summary.py",
        fake_scripts / "build-record-and-replay-baseline-summary.py",
    )
    shutil.copy2(
        repo / "scripts/check-record-and-replay-baseline-summary.py",
        fake_scripts / "check-record-and-replay-baseline-summary.py",
    )
    shutil.copy2(
        repo / "scripts/record_and_replay_baseline_contract.py",
        fake_scripts / "record_and_replay_baseline_contract.py",
    )
    shutil.copy2(
        repo / "scripts/test-record-and-replay-baseline-contract.py",
        fake_scripts / "test-record-and-replay-baseline-contract.py",
    )
    (fake_scripts / "run-record-and-replay-baseline-smoke.sh").chmod(0o755)
    (fake_scripts / "build-record-and-replay-baseline-summary.py").chmod(0o755)
    (fake_scripts / "check-record-and-replay-baseline-summary.py").chmod(0o755)
    (fake_scripts / "test-record-and-replay-baseline-contract.py").chmod(0o755)

    make_cat_stub(fake_scripts / "run-event-stream-smoke-matrix.sh", paths["matrix"])
    make_shell_stub(
        fake_scripts / "run-event-stream-smoke-tests.sh",
        "\n".join(
            [
                'if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_SCREENSHOTS:-}" == "1" ]]; then',
                f"  cat {str(paths['screenshot'])!r}",
                'elif [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS:-}" == "1" ]]; then',
                '  case "${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO:-mixed-action-stop}" in',
                '    "mixed-action-stop")',
                f"      cat {str(action_paths['mixed-action-stop'])!r}",
                "      ;;",
                '    "simple-action-stop")',
                f"      cat {str(action_paths['simple-action-stop'])!r}",
                "      ;;",
                '    "drag-stop")',
                f"      cat {str(action_paths['drag-stop'])!r}",
                "      ;;",
                "    *)",
                '      echo "unexpected action scenario: ${OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO}" >&2',
                "      exit 2",
                "      ;;",
                "  esac",
                "else",
                '  echo "unexpected event-stream smoke mode" >&2',
                "  exit 2",
                "fi",
                "",
            ]
        ),
    )
    make_cat_stub(fake_scripts / "compare-event-stream-surface.py", paths["surface"])
    make_cat_stub(fake_scripts / "compare-event-stream-no-active.py", paths["no_active"])
    make_cat_stub(fake_scripts / "test-event-stream-probe-fixtures.py", paths["raw_timeout"])
    make_cat_stub(fake_scripts / "test-event-stream-official-fixture-set.py", paths["fixture_set"])
    make_cat_stub(
        fake_scripts / "check-event-stream-official-fixture-coverage.py",
        paths["coverage"],
    )
    make_cat_stub(
        fake_scripts / "test-official-record-and-replay-fixture-ingest.py",
        paths["official_ingest"],
    )
    make_cat_stub(
        fake_scripts / "test-ocu-record-and-replay-candidate-ingest.py",
        paths["candidate_ingest"],
    )
    make_cat_stub(
        fake_scripts / "test-record-and-replay-official-golden-capture-preflight.py",
        paths["official_capture_preflight"],
    )
    make_cat_stub(
        fake_scripts / "test-record-and-replay-ocu-candidate-pairing-preflight.py",
        paths["ocu_pairing_preflight"],
    )
    make_cat_stub(
        fake_scripts / "test-record-and-replay-baseline-audit-make-targets.py",
        paths["baseline_audit_targets"],
    )
    make_cat_stub(
        fake_scripts / "test-record-and-replay-skill-repo-scaffold.py",
        paths["standalone"],
    )
    (fake_scripts / "test-npm-record-and-replay-skill-repo-scaffold.mjs").write_text(
        "import fs from 'node:fs';\n"
        f"process.stdout.write(fs.readFileSync({str(paths['npm'])!r}, 'utf8'));\n"
    )

    return fake_repo


def assert_summary_file_matches_stdout(result: subprocess.CompletedProcess[str], path: pathlib.Path) -> dict:
    assert path.exists(), result.stderr
    stdout_summary = parse_last_json(result.stdout)
    file_summary = read_json(path)
    assert file_summary == stdout_summary
    return file_summary


def main() -> None:
    repo = pathlib.Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        fake_repo = build_fake_repo(repo, root)
        runner = fake_repo / "scripts/run-record-and-replay-baseline-smoke.sh"

        default_summary_path = root / "artifacts/default-summary.json"
        default_result = run([str(runner), "--summary-json", str(default_summary_path)], fake_repo)
        assert default_result.returncode == 0, default_result.stderr
        default_summary = assert_summary_file_matches_stdout(
            default_result,
            default_summary_path,
        )
        assert default_summary["ok"] is True
        assert default_summary["status"]["usableBaseline"] is True
        assert default_summary["status"]["officialGoldenRequirementSatisfied"] is True
        assert default_summary["status"]["officialGoldenGatePassed"] is False
        assert "checkedAllowsMissingOfficialGoldenButNotEquivalence" in (
            default_result.stderr
        )

        strict_summary_path = root / "artifacts/strict-summary.json"
        strict_result = run(
            [
                str(runner),
                "--require-official-golden",
                "--summary-json",
                str(strict_summary_path),
            ],
            fake_repo,
        )
        assert strict_result.returncode == 1
        strict_summary = assert_summary_file_matches_stdout(
            strict_result,
            strict_summary_path,
        )
        assert strict_summary["ok"] is False
        assert strict_summary["status"]["usableBaseline"] is True
        assert strict_summary["status"]["strictOfficialGoldenRequired"] is True
        assert strict_summary["status"]["officialGoldenRequirementSatisfied"] is False
        assert strict_summary["status"]["officialGoldenGatePassed"] is False
        assert "missing=simple-action-stop" in strict_result.stderr
        assert "checkedOfficialGoldenGatePassed" in strict_result.stderr

        standalone_evidence_path = root / "evidence/standalone.json"
        standalone_evidence = read_json(standalone_evidence_path)
        standalone_evidence["checkedNotifyCallbackTimeoutReason"] = False
        write_json(standalone_evidence_path, standalone_evidence)
        early_gate_summary_path = root / "artifacts/early-gate-summary.json"
        early_gate_result = run(
            [str(runner), "--summary-json", str(early_gate_summary_path)],
            fake_repo,
        )
        assert early_gate_result.returncode == 1
        assert not early_gate_summary_path.exists()
        assert "expected true JSON keys missing" in early_gate_result.stderr
        assert "checkedNotifyCallbackTimeoutReason" in early_gate_result.stderr

    print(
        json.dumps(
            {
                "ok": True,
                "checkedRunnerInvokesSummaryAudit": True,
                "checkedSummaryJsonMatchesStdout": True,
                "checkedSummaryJsonDefaultExitCode": True,
                "checkedSummaryJsonStrictFailureExitCode": True,
                "checkedStandaloneEarlyEvidenceGate": True,
                "checkedActionScenarioEnvPropagation": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
