#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

from record_and_replay_scenarios import (
    DEFAULT_RECOMMENDED_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_recipe,
)


DEFAULT_FIXTURE_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)
DEFAULT_RECOMMENDED_SCENARIO_HELP = ", ".join(DEFAULT_RECOMMENDED_SCENARIOS)


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


def display_path(path: pathlib.Path, repo: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(repo.resolve()))
    except ValueError:
        return str(path)


def candidate_dirs(root: pathlib.Path) -> list[pathlib.Path]:
    if (root / "fixture-manifest.json").exists():
        return [root]
    if not root.exists():
        return []
    return sorted(path for path in root.iterdir() if (path / "fixture-manifest.json").exists())


def run_fixture_set_readiness(
    repo: pathlib.Path,
    fixture_root: pathlib.Path,
    required_scenarios: list[str],
) -> tuple[bool, dict]:
    command = [
        sys.executable,
        str(repo / "scripts/check-event-stream-official-fixture-set.py"),
        "--official-root",
        str(fixture_root),
    ]
    for scenario in required_scenarios:
        command.extend(["--require-scenario", scenario])
    completed = subprocess.run(
        command,
        cwd=repo,
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
                f"fixture set readiness command exited {completed.returncode} and did not emit JSON",
                completed.stderr.strip() or completed.stdout.strip(),
            ],
        }
    return completed.returncode == 0, parsed


def not_ready_official_scenarios(readiness_json: dict | None, required_scenarios: list[str]) -> list[str]:
    if not isinstance(readiness_json, dict):
        return []
    results = readiness_json.get("scenarioResults")
    if not isinstance(results, list):
        return []

    not_ready = []
    for result in results:
        if not isinstance(result, dict):
            continue
        scenario = result.get("scenario")
        if not isinstance(scenario, str) or scenario not in required_scenarios:
            continue
        if not result.get("officialFixture"):
            continue
        readiness = result.get("officialReadiness")
        if not isinstance(readiness, dict) or readiness.get("ok") is not True:
            not_ready.append(scenario)
    return sorted(set(not_ready))


def inspect_fixture_coverage(args: argparse.Namespace) -> dict:
    repo = pathlib.Path(__file__).resolve().parents[1]
    root = args.fixture_root
    required_scenarios = args.require_scenario or list(DEFAULT_REQUIRED_SCENARIOS)
    recommended_scenarios = args.recommended_scenario or list(DEFAULT_RECOMMENDED_SCENARIOS)
    official_fixtures = []
    scenarios = {}
    errors = []

    for fixture_dir in candidate_dirs(root):
        try:
            manifest = load_json(fixture_dir / "fixture-manifest.json")
        except ValueError as error:
            errors.append(str(error))
            continue
        if manifest.get("source") != "official":
            continue
        scenario = manifest.get("scenario")
        fixture_info = {
            "path": display_path(fixture_dir, repo),
            "name": manifest.get("name"),
            "scenario": scenario if isinstance(scenario, str) else None,
            "scenarioRecipeMatches": None,
            "eventCount": manifest.get("eventCount"),
            "officialPluginVersion": manifest.get("officialPluginVersion"),
        }
        official_fixtures.append(fixture_info)
        if not isinstance(scenario, str) or not scenario:
            errors.append(f"{fixture_info['path']}: official fixture missing scenario")
            continue
        actual_recipe = manifest.get("scenarioRecipe")
        expected_recipe = scenario_recipe(scenario)
        recipe_matches = actual_recipe == expected_recipe
        fixture_info["scenarioRecipeMatches"] = recipe_matches
        if not recipe_matches:
            errors.append(
                f"{fixture_info['path']}: fixture-manifest.json scenarioRecipe "
                f"does not match scenario {scenario!r}"
            )
        scenarios.setdefault(scenario, []).append(fixture_info["path"])

    duplicate_scenarios = {
        scenario: paths for scenario, paths in scenarios.items() if len(paths) > 1
    }
    for scenario, paths in sorted(duplicate_scenarios.items()):
        errors.append(f"duplicate official scenario {scenario!r}: {', '.join(paths)}")

    available_scenarios = sorted(scenarios)
    missing_scenarios = sorted(set(required_scenarios) - set(available_scenarios))
    missing_recommended_scenarios = sorted(set(recommended_scenarios) - set(available_scenarios))
    scenario_coverage_ok = not missing_scenarios and not duplicate_scenarios and not errors
    readiness_checked = args.check_readiness or args.require_readiness
    readiness_ok: bool | None = None
    readiness_json: dict | None = None
    readiness_errors: list[str] = []
    not_ready_scenarios: list[str] = []

    if readiness_checked:
        if scenario_coverage_ok:
            readiness_ok, readiness_json = run_fixture_set_readiness(
                repo,
                root,
                required_scenarios,
            )
            if not readiness_ok:
                readiness_errors.append("required official fixture set failed readiness")
            not_ready_scenarios = not_ready_official_scenarios(
                readiness_json,
                required_scenarios,
            )
            if not readiness_ok and not not_ready_scenarios:
                not_ready_scenarios = sorted(set(required_scenarios))
        else:
            readiness_ok = False
            readiness_json = {
                "ok": False,
                "errors": [
                    "required official fixture set readiness skipped because scenario coverage is incomplete"
                ],
            }

    coverage_ok = scenario_coverage_ok and (not readiness_checked or readiness_ok is True)
    errors.extend(readiness_errors)
    ok = coverage_ok or (
        args.allow_missing
        and not errors
        and not duplicate_scenarios
        and bool(missing_scenarios)
    )
    return {
        "ok": ok,
        "coverageOk": coverage_ok,
        "scenarioCoverageOk": scenario_coverage_ok,
        "allowMissing": args.allow_missing,
        "fixtureRoot": display_path(root, repo),
        "requiredOfficialScenarios": required_scenarios,
        "recommendedOfficialScenarios": recommended_scenarios,
        "availableOfficialScenarios": available_scenarios,
        "missingOfficialScenarios": missing_scenarios,
        "missingRecommendedOfficialScenarios": missing_recommended_scenarios,
        "notReadyOfficialScenarios": not_ready_scenarios,
        "hasRequiredOfficialScenarioCoverage": scenario_coverage_ok,
        "hasRequiredOfficialSuccessfulFixture": coverage_ok,
        "hasRecommendedOfficialScenarioCoverage": not missing_recommended_scenarios,
        "requiredOfficialReadinessChecked": readiness_checked,
        "requiredOfficialReadinessOk": readiness_ok,
        "officialFixtureSetReadiness": readiness_json,
        "officialFixtures": official_fixtures,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Report whether the repository has the required official Record & Replay "
            "successful recording fixture scenarios."
        )
    )
    parser.add_argument(
        "--fixture-root",
        type=pathlib.Path,
        default=DEFAULT_FIXTURE_ROOT,
        help=f"Directory containing recording fixture subdirectories. Defaults to {DEFAULT_FIXTURE_ROOT}.",
    )
    parser.add_argument(
        "--require-scenario",
        action="append",
        default=[],
        help=(
            "Required official scenario tag. May be repeated. Defaults to "
            f"{DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument(
        "--recommended-scenario",
        action="append",
        default=[],
        help=(
            "Recommended official scenario tag to report. May be repeated. Defaults to "
            f"{DEFAULT_RECOMMENDED_SCENARIO_HELP}. "
            "Recommended coverage is informational and does not affect the exit code."
        ),
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Exit successfully when required scenarios are missing, while still reporting coverageOk=false.",
    )
    parser.add_argument(
        "--check-readiness",
        action="store_true",
        help=(
            "When required scenarios are present, also run the official fixture set readiness gate. "
            "Missing scenarios are reported as coverageOk=false."
        ),
    )
    parser.add_argument(
        "--require-readiness",
        action="store_true",
        help=(
            "Require the official fixture set readiness gate for required scenarios. "
            "This implies --check-readiness."
        ),
    )
    args = parser.parse_args()
    if args.require_readiness:
        args.check_readiness = True
    result = inspect_fixture_coverage(args)
    output = json.dumps(result, indent=2, sort_keys=True)
    if result["ok"]:
        print(output)
        return 0
    print(output, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
