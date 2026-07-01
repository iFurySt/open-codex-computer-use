#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess


def run_make(repo: pathlib.Path, *args: str) -> str:
    env = os.environ.copy()
    env.pop("RNR_BASELINE_SUMMARY_JSON", None)
    env.pop("RNR_OFFICIAL_GOLDEN_SUMMARY_JSON", None)
    result = subprocess.run(
        ["make", "-n", *args],
        cwd=repo,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            "make dry-run failed\n"
            + "stdout:\n"
            + result.stdout
            + "\nstderr:\n"
            + result.stderr
        )
    return result.stdout


def assert_contains(output: str, expected: str) -> None:
    if expected not in output:
        raise AssertionError(f"missing {expected!r} in make dry-run output:\n{output}")


def main() -> None:
    repo = pathlib.Path(__file__).resolve().parents[1]

    default_output = run_make(repo, "record-and-replay-baseline-audit")
    assert_contains(default_output, "dist/record-and-replay-baseline-summary.json")
    assert_contains(
        default_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --summary-json "dist/record-and-replay-baseline-summary.json"',
    )

    custom_baseline_output = run_make(
        repo,
        "record-and-replay-baseline-audit",
        "RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-baseline-summary.json",
    )
    assert_contains(custom_baseline_output, "/tmp/ocu-rnr-baseline-summary.json")
    assert_contains(
        custom_baseline_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --summary-json "/tmp/ocu-rnr-baseline-summary.json"',
    )

    baseline_ignores_strict_var_output = run_make(
        repo,
        "record-and-replay-baseline-audit",
        "RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=/tmp/should-not-affect-baseline-summary.json",
    )
    assert_contains(
        baseline_ignores_strict_var_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --summary-json "dist/record-and-replay-baseline-summary.json"',
    )
    if "/tmp/should-not-affect-baseline-summary.json" in baseline_ignores_strict_var_output:
        raise AssertionError(
            "baseline audit must ignore the strict official golden summary variable:\n"
            + baseline_ignores_strict_var_output
        )

    strict_default_output = run_make(
        repo,
        "record-and-replay-official-golden-gate-audit",
    )
    assert_contains(
        strict_default_output,
        "dist/record-and-replay-official-golden-gate-summary.json",
    )
    assert_contains(
        strict_default_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden --summary-json "dist/record-and-replay-official-golden-gate-summary.json"',
    )
    if "dist/record-and-replay-baseline-summary.json" in strict_default_output:
        raise AssertionError(
            "strict official golden audit must not use the baseline summary path by default:\n"
            + strict_default_output
        )

    strict_ignores_baseline_var_output = run_make(
        repo,
        "record-and-replay-official-golden-gate-audit",
        "RNR_BASELINE_SUMMARY_JSON=/tmp/should-not-affect-strict-summary.json",
    )
    assert_contains(
        strict_ignores_baseline_var_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden --summary-json "dist/record-and-replay-official-golden-gate-summary.json"',
    )
    if "/tmp/should-not-affect-strict-summary.json" in strict_ignores_baseline_var_output:
        raise AssertionError(
            "strict official golden audit must ignore the baseline summary variable:\n"
            + strict_ignores_baseline_var_output
        )

    strict_custom_output = run_make(
        repo,
        "record-and-replay-official-golden-gate-audit",
        "RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=/tmp/ocu-rnr-official-golden-summary.json",
    )
    assert_contains(strict_custom_output, "/tmp/ocu-rnr-official-golden-summary.json")
    assert_contains(
        strict_custom_output,
        './scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden --summary-json "/tmp/ocu-rnr-official-golden-summary.json"',
    )

    print(
        json.dumps(
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
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
