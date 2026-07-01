#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

from record_and_replay_scenarios import (
    ACTION_SMOKE_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_readiness_args,
)


DEFAULT_OUTPUT_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings/ocu-candidates"
)
DEFAULT_OFFICIAL_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)
DEFAULT_SCENARIO = DEFAULT_REQUIRED_SCENARIOS[0]
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)


def load_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")


def read_json_records(path: pathlib.Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        lines = path.read_text().splitlines()
    except FileNotFoundError:
        raise ValueError(f"missing smoke JSONL file: {path}")
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("{"):
            continue
        try:
            value = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            records.append(value)
    return records


def select_smoke_record(records: list[dict[str, Any]], mode: str) -> dict[str, Any]:
    matches = [record for record in records if record.get("mode") == mode]
    if not matches:
        raise ValueError(f"smoke JSONL has no record with mode={mode!r}")
    return matches[-1]


def path_from_smoke_record(record: dict[str, Any], base_dir: pathlib.Path | None = None) -> pathlib.Path:
    for key in ("metadataPath", "sessionPath"):
        raw = record.get(key)
        if isinstance(raw, str) and raw:
            path = pathlib.Path(raw)
            return path if path.is_absolute() or base_dir is None else base_dir / path

    recordings_root = record.get("recordingsRoot")
    session_id = record.get("sessionId")
    if isinstance(recordings_root, str) and recordings_root and isinstance(session_id, str) and session_id:
        root = pathlib.Path(recordings_root)
        if not root.is_absolute() and base_dir is not None:
            root = base_dir / root
        return root / session_id

    raise ValueError(
        "smoke record must include metadataPath/sessionPath or recordingsRoot plus sessionId"
    )


def optional_path_from_smoke_record(
    record: dict[str, Any],
    key: str,
    base_dir: pathlib.Path | None = None,
) -> pathlib.Path | None:
    raw = record.get(key)
    if not isinstance(raw, str) or not raw:
        return None
    path = pathlib.Path(raw)
    return path if path.is_absolute() or base_dir is None else base_dir / path


def action_smoke_scenario_for_fixture_scenario(scenario: str) -> str:
    if scenario in ACTION_SMOKE_SCENARIOS:
        return scenario
    if scenario == "keyboard-input-stop":
        raise ValueError(
            "keyboard-input-stop does not support --run-action-smoke yet; "
            "import an existing recording with --recording or a preserved smoke JSONL with --smoke-json"
        )
    return "mixed-action-stop"


def run_action_smoke(
    repo: pathlib.Path,
    output_dir: pathlib.Path,
    scenario: str,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    action_scenario = action_smoke_scenario_for_fixture_scenario(scenario)
    completed = subprocess.run(
        [
            "env",
            "OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1",
            f"OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO={action_scenario}",
            f"OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TMPDIR={output_dir}",
            "./scripts/run-event-stream-smoke-tests.sh",
        ],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    records: list[dict[str, Any]] = []
    for line in completed.stdout.splitlines():
        stripped = line.strip()
        if not stripped.startswith("{"):
            continue
        try:
            value = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            records.append(value)
    evidence = {
        "exitCode": completed.returncode,
        "stdoutLineCount": len(completed.stdout.splitlines()),
        "stderrLineCount": len(completed.stderr.splitlines()),
        "jsonRecordCount": len(records),
        "temporaryDirectory": str(output_dir),
        "actionScenario": action_scenario,
    }
    if completed.returncode != 0:
        raise ValueError(
            "action smoke failed while capturing OCU candidate "
            f"(exit={completed.returncode}): {completed.stderr.strip() or completed.stdout.strip()}"
        )
    return records, evidence


def validation_args_for_scenario(scenario: str) -> list[str]:
    args = ["--strict-ocu", "--require-event-type", "session.ended"]
    if scenario == "simple-action-stop":
        args.extend(
            [
                "--require-event-type",
                "mouse.click",
                "--require-event-type",
                "AX.focusedWindowChanged",
                "--require-skill-draft",
            ]
        )
    elif scenario == "keyboard-input-stop":
        args.extend(
            [
                "--require-event-type",
                "keyboard.text_input",
                "--require-event-type",
                "AX.focusedWindowChanged",
                "--require-skill-draft",
            ]
        )
    elif scenario == "drag-stop":
        args.extend(
            [
                "--require-event-type",
                "mouse.drag",
                "--require-event-type",
                "AX.focusedWindowChanged",
                "--require-skill-draft",
            ]
        )
    return args


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


def display_path(path: pathlib.Path, repo: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(repo.resolve()))
    except (FileNotFoundError, ValueError):
        return str(path)


def handoff_commands(repo: pathlib.Path, args: argparse.Namespace) -> dict[str, Any]:
    official_root = args.official_root or DEFAULT_OFFICIAL_ROOT
    candidate_root = args.output_dir
    pairing_preflight = [
        "python3",
        "scripts/prepare-record-and-replay-ocu-candidate-pairing.py",
        "--scenario",
        args.scenario,
        "--official-root",
        display_path(official_root, repo),
        "--candidate-root",
        display_path(candidate_root, repo),
        "--require-candidate-ready",
    ]
    fixture_set_gate = [
        "python3",
        "scripts/check-event-stream-official-fixture-set.py",
        "--official-root",
        display_path(official_root, repo),
        "--candidate-root",
        display_path(candidate_root, repo),
        "--require-scenario",
        args.scenario,
    ]
    return {
        "pairingPreflight": pairing_preflight,
        "pairingPreflightShell": shell_join(pairing_preflight),
        "fixtureSetGate": fixture_set_gate,
        "fixtureSetGateShell": shell_join(fixture_set_gate),
    }


def ingest(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    repo = pathlib.Path(__file__).resolve().parents[1]
    capture_evidence: dict[str, Any] | None = None
    smoke_record: dict[str, Any] | None = None
    capture_tmp: tempfile.TemporaryDirectory[str] | None = None

    if args.recording is not None:
        recording_input = args.recording
        mcp_transcript = args.mcp_transcript
    elif args.smoke_json is not None:
        records = read_json_records(args.smoke_json)
        smoke_record = select_smoke_record(records, args.smoke_mode)
        recording_input = path_from_smoke_record(smoke_record, args.smoke_json.parent)
        mcp_transcript = args.mcp_transcript or optional_path_from_smoke_record(
            smoke_record,
            "mcpTranscriptPath",
            args.smoke_json.parent,
        )
    elif args.run_action_smoke:
        capture_tmp = tempfile.TemporaryDirectory(prefix="ocu-rnr-", dir="/tmp")
        records, capture_evidence = run_action_smoke(repo, pathlib.Path(capture_tmp.name), args.scenario)
        smoke_record = select_smoke_record(records, args.smoke_mode)
        recording_input = path_from_smoke_record(smoke_record)
        mcp_transcript = args.mcp_transcript or optional_path_from_smoke_record(
            smoke_record,
            "mcpTranscriptPath",
        )
    else:
        raise ValueError("pass --recording, --smoke-json, or --run-action-smoke")

    validate_ok, validate_json = run_json(
        [
            sys.executable,
            str(repo / "scripts/validate-event-stream-recording.py"),
            str(recording_input),
            *validation_args_for_scenario(args.scenario),
        ],
        repo,
    )
    if not validate_ok:
        return 1, {
            "ok": False,
            "stage": "validate",
            "recordingInput": str(recording_input),
            "smokeRecord": smoke_record,
            "capture": capture_evidence,
            "validation": validate_json,
        }

    import_command = [
        sys.executable,
        str(repo / "scripts/import-event-stream-fixture.py"),
        str(recording_input),
        "--name",
        args.name,
        "--output-dir",
        str(args.output_dir),
        "--source",
        "ocu",
        "--scenario",
        args.scenario,
        "--captured-at",
        args.captured_at,
    ]
    if mcp_transcript is not None:
        import_command.extend(["--mcp-transcript", str(mcp_transcript)])
    if args.force:
        import_command.append("--force")

    import_ok, import_json = run_json(import_command, repo)
    if not import_ok:
        return 1, {
            "ok": False,
            "stage": "import",
            "recordingInput": str(recording_input),
            "smokeRecord": smoke_record,
            "capture": capture_evidence,
            "validation": validate_json,
            "importResult": import_json,
        }

    fixture_dir = pathlib.Path(import_json["fixtureDir"])
    readiness_ok, readiness_json = run_json(
        [
            sys.executable,
            str(repo / "scripts/check-event-stream-golden-readiness.py"),
            str(fixture_dir),
            *scenario_readiness_args(
                args.scenario,
                source="ocu",
                require_mcp_transcript_evidence=args.require_mcp_transcript_evidence,
            ),
        ],
        repo,
    )

    fixture_set_json = None
    fixture_set_ok = None
    if args.check_fixture_set:
        if args.official_root is None:
            raise ValueError("--check-fixture-set requires --official-root")
        fixture_set_ok, fixture_set_json = run_json(
            [
                sys.executable,
                str(repo / "scripts/check-event-stream-official-fixture-set.py"),
                "--official-root",
                str(args.official_root),
                "--candidate-root",
                str(args.output_dir),
                "--require-scenario",
                args.scenario,
            ],
            repo,
        )

    ok = readiness_ok and (fixture_set_ok is not False)
    result: dict[str, Any] = {
        "ok": ok,
        "fixtureDir": str(fixture_dir),
        "scenario": args.scenario,
        "commands": handoff_commands(repo, args),
        "recordingInput": str(recording_input),
        "smokeRecord": smoke_record,
        "capture": capture_evidence,
        "validation": validate_json,
        "importResult": import_json,
        "readiness": readiness_json,
        "requiredMcpTranscriptEvidence": args.require_mcp_transcript_evidence,
        "usedMcpTranscript": str(mcp_transcript) if mcp_transcript is not None else None,
    }
    if fixture_set_json is not None:
        result["fixtureSetGate"] = fixture_set_json

    if ok or args.allow_readiness_failure:
        return 0, result
    return 1, result


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Import an Open Computer Use Record & Replay recording as an OCU candidate fixture "
            "and optionally compare it with official same-scenario fixtures."
        )
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--recording",
        type=pathlib.Path,
        help="OCU recording directory, metadata.json, or session.json to import directly.",
    )
    source.add_argument(
        "--smoke-json",
        type=pathlib.Path,
        help="JSONL/stdout captured from OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1.",
    )
    source.add_argument(
        "--run-action-smoke",
        action="store_true",
        help="Run the opt-in real input action smoke and import its resulting recording.",
    )
    parser.add_argument("--name", required=True, help="Candidate fixture directory name to create.")
    parser.add_argument(
        "--scenario",
        default=DEFAULT_SCENARIO,
        help=(
            "Scenario tag to write into fixture-manifest.json. Defaults to "
            f"{DEFAULT_SCENARIO}. Required scenarios: {DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument(
        "--smoke-mode",
        default="actions",
        help="Smoke JSON record mode to import when using --smoke-json or --run-action-smoke.",
    )
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT_ROOT,
        help=f"Candidate fixture root directory. Defaults to {DEFAULT_OUTPUT_ROOT}.",
    )
    parser.add_argument(
        "--captured-at",
        default=datetime.date.today().isoformat(),
        help="Capture date to record in fixture-manifest.json.",
    )
    parser.add_argument(
        "--mcp-transcript",
        type=pathlib.Path,
        help=(
            "Optional local probe output or MCP transcript to sanitize into mcp-transcript.json. "
            "Provide this when comparing against official fixtures that require response-shape evidence."
        ),
    )
    parser.add_argument(
        "--require-mcp-transcript-evidence",
        action="store_true",
        help="Require mcp-transcript.json and scenario-specific response-shape evidence during readiness.",
    )
    parser.add_argument(
        "--official-root",
        type=pathlib.Path,
        help="Official fixture root used with --check-fixture-set.",
    )
    parser.add_argument(
        "--check-fixture-set",
        action="store_true",
        help="After import, run the collection-level official-vs-OCU candidate gate for this scenario.",
    )
    parser.add_argument(
        "--allow-readiness-failure",
        action="store_true",
        help="Exit 0 after import even when readiness or fixture-set checks fail; the JSON still reports failures.",
    )
    parser.add_argument("--force", action="store_true", help="Replace an existing fixture directory.")
    args = parser.parse_args()

    try:
        exit_code, result = ingest(args)
    except ValueError as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}, indent=2, sort_keys=True), file=sys.stderr)
        return 1

    output = json.dumps(result, indent=2, sort_keys=True)
    if exit_code == 0:
        print(output)
    else:
        print(output, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
