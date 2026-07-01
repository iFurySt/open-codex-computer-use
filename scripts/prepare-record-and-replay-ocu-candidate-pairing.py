#!/usr/bin/env python3

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any

from record_and_replay_scenarios import (
    ACTION_SMOKE_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_recipe,
)


DEFAULT_OFFICIAL_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)
DEFAULT_CANDIDATE_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings/ocu-candidates"
)
DEFAULT_SCENARIO = DEFAULT_REQUIRED_SCENARIOS[0]
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)


def display_path(path: pathlib.Path, repo: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(repo.resolve()))
    except (FileNotFoundError, ValueError):
        try:
            return "~/" + str(path.expanduser().resolve().relative_to(pathlib.Path.home()))
        except (FileNotFoundError, ValueError):
            return str(path)


def run_json(command: list[str], cwd: pathlib.Path) -> tuple[bool, dict[str, Any]]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    raw = completed.stdout if completed.returncode == 0 else completed.stderr
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = {
            "ok": False,
            "errors": [
                f"command exited {completed.returncode} and did not emit JSON",
                completed.stderr.strip() or completed.stdout.strip(),
            ],
        }
    return completed.returncode == 0, parsed


def shell_join(argv: list[str]) -> str:
    import shlex

    return " ".join(shlex.quote(part) for part in argv)


def candidate_name(scenario: str) -> str:
    return f"ocu-{scenario}"


def candidate_source_command(repo: pathlib.Path, args: argparse.Namespace) -> tuple[list[str], str]:
    base = [
        "python3",
        "scripts/ingest-ocu-record-and-replay-candidate.py",
    ]
    if args.recording_placeholder:
        source = ["--recording", args.recording_placeholder]
        source_kind = "recording"
    elif args.smoke_json_placeholder:
        source = ["--smoke-json", args.smoke_json_placeholder]
        source_kind = "smoke-json"
    elif args.scenario in ACTION_SMOKE_SCENARIOS:
        source = ["--run-action-smoke"]
        source_kind = "run-action-smoke"
    else:
        source = ["--recording", "<ocu-recording-or-metadata>"]
        source_kind = "recording-required"
    return [*base, *source], source_kind


def build_commands(repo: pathlib.Path, args: argparse.Namespace) -> dict[str, Any]:
    candidate_root = display_path(args.candidate_root, repo)
    official_root = display_path(args.official_root, repo)
    ingest_prefix, source_kind = candidate_source_command(repo, args)
    ingest = [
        *ingest_prefix,
        "--name",
        args.name or candidate_name(args.scenario),
        "--scenario",
        args.scenario,
        "--output-dir",
        candidate_root,
        "--official-root",
        official_root,
        "--check-fixture-set",
        "--require-mcp-transcript-evidence",
    ]
    if args.mcp_transcript_placeholder:
        ingest.extend(["--mcp-transcript", args.mcp_transcript_placeholder])
    fixture_set = [
        "python3",
        "scripts/check-event-stream-official-fixture-set.py",
        "--official-root",
        official_root,
        "--candidate-root",
        candidate_root,
        "--require-scenario",
        args.scenario,
    ]
    official_gate = [
        "python3",
        "scripts/check-event-stream-official-fixture-coverage.py",
        "--fixture-root",
        official_root,
        "--require-readiness",
    ]
    return {
        "sourceKind": source_kind,
        "officialFixtureGate": official_gate,
        "officialFixtureGateShell": shell_join(official_gate),
        "ingestCandidate": ingest,
        "ingestCandidateShell": shell_join(ingest),
        "fixtureSetGate": fixture_set,
        "fixtureSetGateShell": shell_join(fixture_set),
    }


def scenario_status(fixture_set: dict[str, Any], scenario: str) -> dict[str, Any]:
    scenario_results = fixture_set.get("scenarioResults")
    result = None
    if isinstance(scenario_results, list):
        for item in scenario_results:
            if isinstance(item, dict) and item.get("scenario") == scenario:
                result = item
                break
    official_fixture = result.get("officialFixture") if isinstance(result, dict) else None
    official_readiness = result.get("officialReadiness") if isinstance(result, dict) else None
    candidate_fixture = result.get("candidateFixture") if isinstance(result, dict) else None
    candidate_readiness = result.get("candidateReadiness") if isinstance(result, dict) else None
    candidate_compare = result.get("candidateCompare") if isinstance(result, dict) else None
    return {
        "scenario": scenario,
        "officialFixtureReady": bool(
            official_fixture
            and isinstance(official_readiness, dict)
            and official_readiness.get("ok") is True
        ),
        "candidateFixturePresent": bool(candidate_fixture),
        "candidateFixtureReady": bool(
            candidate_fixture
            and isinstance(candidate_readiness, dict)
            and candidate_readiness.get("ok") is True
        ),
        "candidateComparePassed": bool(
            candidate_compare
            and isinstance(candidate_compare, dict)
            and candidate_compare.get("ok") is True
        ),
        "officialFixture": official_fixture,
        "candidateFixture": candidate_fixture,
    }


def preflight(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    repo = pathlib.Path(__file__).resolve().parents[1]
    commands = build_commands(repo, args)
    coverage_command = [
        sys.executable,
        str(repo / "scripts/check-event-stream-official-fixture-coverage.py"),
        "--fixture-root",
        str(args.official_root),
        "--allow-missing",
        "--check-readiness",
        "--require-scenario",
        args.scenario,
    ]
    coverage_ok, coverage = run_json(coverage_command, repo)
    coverage_errors = coverage.get("errors")
    if not isinstance(coverage_errors, list):
        coverage_errors = []
    fixture_set_command = [
        sys.executable,
        str(repo / "scripts/check-event-stream-official-fixture-set.py"),
        "--official-root",
        str(args.official_root),
        "--require-scenario",
        args.scenario,
    ]
    if args.candidate_root.exists():
        fixture_set_command.extend(["--candidate-root", str(args.candidate_root)])
    fixture_set_ok, fixture_set = run_json(fixture_set_command, repo)
    status = scenario_status(fixture_set, args.scenario)
    next_actions: list[str] = []
    if not status["officialFixtureReady"]:
        next_actions.append(
            f"Import a ready official fixture for scenario {args.scenario!r} before pairing an OCU candidate."
        )
    elif not status["candidateFixturePresent"]:
        next_actions.append("Run commands.ingestCandidate to create the same-scenario OCU candidate fixture.")
    elif not status["candidateFixtureReady"]:
        next_actions.append("Repair or re-import the OCU candidate; it does not pass scenario readiness.")
    elif not status["candidateComparePassed"]:
        next_actions.append("Use commands.fixtureSetGate output to inspect official-vs-OCU drift.")
    else:
        next_actions.append("Official fixture and OCU candidate are paired and pass the fixture set gate.")

    if commands["sourceKind"] == "recording-required":
        next_actions.append(
            "This scenario cannot use synthetic --run-action-smoke; provide --recording-placeholder or --smoke-json-placeholder."
        )
    if coverage_errors:
        next_actions.insert(
            0,
            "Fix official fixture coverage errors before pairing an OCU candidate: "
            + " | ".join(str(error) for error in coverage_errors),
        )

    ok = coverage_ok and fixture_set_ok and status["officialFixtureReady"] and (
        not args.require_candidate_ready
        or (status["candidateFixtureReady"] and status["candidateComparePassed"])
    )
    result: dict[str, Any] = {
        "ok": ok,
        "stage": "candidate-pairing-preflight",
        "scenario": args.scenario,
        "officialRoot": display_path(args.official_root, repo),
        "candidateRoot": display_path(args.candidate_root, repo),
        "scenarioRecipe": scenario_recipe(args.scenario),
        "scenarioStatus": status,
        "officialCoverage": coverage,
        "officialCoverageErrors": coverage_errors,
        "fixtureSetGate": fixture_set,
        "commands": commands,
        "nextActions": next_actions,
        "requireCandidateReady": args.require_candidate_ready,
    }
    exit_code = 1 if args.require_candidate_ready and not ok else 0
    return exit_code, result


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare same-scenario OCU candidate capture/import commands after an official "
            "Record & Replay golden fixture is available. This command is read-only."
        )
    )
    parser.add_argument(
        "--scenario",
        default=DEFAULT_SCENARIO,
        help=(
            f"Scenario to pair. Defaults to {DEFAULT_SCENARIO}. "
            f"Required scenarios: {DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument("--name", help="Candidate fixture name for generated ingest command.")
    parser.add_argument(
        "--official-root",
        type=pathlib.Path,
        default=DEFAULT_OFFICIAL_ROOT,
        help=f"Official fixture root. Defaults to {DEFAULT_OFFICIAL_ROOT}.",
    )
    parser.add_argument(
        "--candidate-root",
        type=pathlib.Path,
        default=DEFAULT_CANDIDATE_ROOT,
        help=f"OCU candidate fixture root. Defaults to {DEFAULT_CANDIDATE_ROOT}.",
    )
    parser.add_argument(
        "--recording-placeholder",
        default=None,
        help="Use this placeholder/path as --recording in generated candidate ingest command.",
    )
    parser.add_argument(
        "--smoke-json-placeholder",
        default=None,
        help="Use this placeholder/path as --smoke-json in generated candidate ingest command.",
    )
    parser.add_argument(
        "--mcp-transcript-placeholder",
        default=None,
        help="Optional placeholder/path for --mcp-transcript in generated candidate ingest command.",
    )
    parser.add_argument(
        "--require-candidate-ready",
        action="store_true",
        help="Fail unless a same-scenario OCU candidate exists, passes readiness, and compares successfully.",
    )
    args = parser.parse_args()
    exit_code, result = preflight(args)
    output = json.dumps(result, indent=2, sort_keys=True)
    if exit_code == 0:
        print(output)
    else:
        print(output, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
