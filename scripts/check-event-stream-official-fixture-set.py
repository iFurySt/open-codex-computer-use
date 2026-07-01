#!/usr/bin/env python3

import argparse
import json
import pathlib
import subprocess
import sys

from record_and_replay_scenarios import (
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_readiness_args,
    scenario_recipe,
)


DEFAULT_FIXTURE_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)

BASE_COMPARE_ARGS = (
    "--require-same-event-sequence",
    "--require-same-schema",
    "--require-same-metadata-keys",
    "--require-same-metadata-values",
    "--require-handoff-paths",
    "--require-final-session-evidence",
    "--require-semantic-fields",
    "--require-mcp-response-shapes",
    "--require-same-mcp-response-schema",
    "--require-ax-diff-evidence",
    "--require-same-ax-diff-markers",
    "--require-same-suppressed-event-sequence",
    "--require-same-suppressed-schema",
    "--ignore-extra-schema",
)


def load_json(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def discover_fixtures(root: pathlib.Path, expected_source: str) -> tuple[dict[str, pathlib.Path], list[str]]:
    if (root / "fixture-manifest.json").exists():
        candidates = [root]
    elif root.exists():
        candidates = sorted(path for path in root.iterdir() if (path / "fixture-manifest.json").exists())
    else:
        candidates = []

    by_scenario: dict[str, pathlib.Path] = {}
    errors: list[str] = []
    for fixture_dir in candidates:
        try:
            manifest = load_json(fixture_dir / "fixture-manifest.json")
        except ValueError as error:
            errors.append(str(error))
            continue

        source = manifest.get("source")
        if source != expected_source:
            errors.append(f"{fixture_dir}: expected source={expected_source}, got {source!r}")
        scenario = manifest.get("scenario")
        if not isinstance(scenario, str) or not scenario:
            errors.append(f"{fixture_dir}: fixture-manifest.json missing scenario")
            continue
        actual_recipe = manifest.get("scenarioRecipe")
        expected_recipe = scenario_recipe(scenario)
        if actual_recipe != expected_recipe:
            errors.append(f"{fixture_dir}: fixture-manifest.json scenarioRecipe does not match scenario {scenario!r}")
        if scenario in by_scenario:
            errors.append(f"duplicate scenario {scenario!r}: {by_scenario[scenario]} and {fixture_dir}")
            continue
        by_scenario[scenario] = fixture_dir
    return by_scenario, errors


def run_json(command: list[str], cwd: pathlib.Path) -> tuple[bool, dict]:
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


def check_fixture_set(args: argparse.Namespace) -> dict:
    repo = pathlib.Path(__file__).resolve().parents[1]
    official, official_errors = discover_fixtures(args.official_root, "official")
    candidate: dict[str, pathlib.Path] = {}
    candidate_errors: list[str] = []
    if args.candidate_root is not None:
        candidate, candidate_errors = discover_fixtures(args.candidate_root, "ocu")

    required_scenarios = args.require_scenario or list(DEFAULT_REQUIRED_SCENARIOS)
    errors = [*official_errors, *candidate_errors]
    scenario_results = []

    for scenario in required_scenarios:
        official_path = official.get(scenario)
        scenario_result = {
            "scenario": scenario,
            "officialFixture": str(official_path) if official_path else None,
            "officialReadiness": None,
            "candidateFixture": None,
            "candidateReadiness": None,
            "candidateCompare": None,
        }
        if official_path is None:
            errors.append(f"missing official fixture scenario: {scenario}")
            scenario_results.append(scenario_result)
            continue

        readiness_command = [
            sys.executable,
            str(repo / "scripts/check-event-stream-golden-readiness.py"),
            str(official_path),
            *scenario_readiness_args(
                scenario,
                source="official",
                require_mcp_transcript_evidence=True,
            ),
        ]
        readiness_ok, readiness_json = run_json(readiness_command, repo)
        scenario_result["officialReadiness"] = readiness_json
        if not readiness_ok:
            errors.append(f"official fixture scenario failed readiness: {scenario}")

        if args.candidate_root is not None:
            candidate_path = candidate.get(scenario)
            scenario_result["candidateFixture"] = str(candidate_path) if candidate_path else None
            if candidate_path is None:
                errors.append(f"missing OCU candidate fixture scenario: {scenario}")
            else:
                candidate_readiness_command = [
                    sys.executable,
                    str(repo / "scripts/check-event-stream-golden-readiness.py"),
                    str(candidate_path),
                    *scenario_readiness_args(
                        scenario,
                        source="ocu",
                        require_mcp_transcript_evidence=True,
                    ),
                ]
                candidate_readiness_ok, candidate_readiness_json = run_json(
                    candidate_readiness_command,
                    repo,
                )
                scenario_result["candidateReadiness"] = candidate_readiness_json
                if not candidate_readiness_ok:
                    errors.append(f"OCU candidate scenario failed readiness: {scenario}")

                compare_command = [
                    sys.executable,
                    str(repo / "scripts/compare-event-stream-recordings.py"),
                    str(official_path),
                    str(candidate_path),
                    *BASE_COMPARE_ARGS,
                ]
                compare_ok, compare_json = run_json(compare_command, repo)
                scenario_result["candidateCompare"] = compare_json
                if not compare_ok:
                    errors.append(f"OCU candidate scenario failed official comparison: {scenario}")

        scenario_results.append(scenario_result)

    return {
        "ok": not errors,
        "officialRoot": str(args.official_root),
        "candidateRoot": str(args.candidate_root) if args.candidate_root is not None else None,
        "requiredScenarios": required_scenarios,
        "availableOfficialScenarios": sorted(official),
        "availableCandidateScenarios": sorted(candidate),
        "scenarioResults": scenario_results,
        "comparePolicy": {
            "requiresAxDiffEvidence": "--require-ax-diff-evidence" in BASE_COMPARE_ARGS,
            "requiresSameAxDiffMarkers": "--require-same-ax-diff-markers" in BASE_COMPARE_ARGS,
            "requiresSuppressedEventSequence": "--require-same-suppressed-event-sequence" in BASE_COMPARE_ARGS,
            "requiresSuppressedSchema": "--require-same-suppressed-schema" in BASE_COMPARE_ARGS,
        },
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate an official Record & Replay golden fixture set and optionally compare "
            "same-scenario OCU candidate fixtures against it."
        )
    )
    parser.add_argument(
        "--official-root",
        type=pathlib.Path,
        default=DEFAULT_FIXTURE_ROOT,
        help=f"Directory containing official fixture subdirectories. Defaults to {DEFAULT_FIXTURE_ROOT}.",
    )
    parser.add_argument(
        "--candidate-root",
        type=pathlib.Path,
        help="Optional directory containing OCU candidate fixture subdirectories with matching scenario tags.",
    )
    parser.add_argument(
        "--require-scenario",
        action="append",
        default=[],
        help=(
            "Required scenario tag. May be repeated. Defaults to "
            f"{DEFAULT_REQUIRED_SCENARIO_HELP}, "
            "the minimum official successful recording baseline."
        ),
    )
    args = parser.parse_args()

    result = check_fixture_set(args)
    output = json.dumps(result, indent=2, sort_keys=True)
    if result["ok"]:
        print(output)
        return 0
    print(output, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
