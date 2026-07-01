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

from record_and_replay_scenarios import DEFAULT_REQUIRED_SCENARIOS, scenario_readiness_args


DEFAULT_OUTPUT_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)

DEFAULT_OFFICIAL_PLUGIN_VERSION = "record-and-replay 1.0.857"
DEFAULT_SCENARIO = DEFAULT_REQUIRED_SCENARIOS[0]
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)

PATH_KEYS = (
    "metadataPath",
    "sessionPath",
    "eventsPath",
    "suppressedEventsPath",
    "sessionDirectoryPath",
)

TRANSCRIPT_KEYS = {
    "startResponseShape",
    "repeatStartResponseShape",
    "statusResponseShape",
    "stopResponseShape",
    "repeatStopResponseShape",
    "finalStatusResponseShape",
    "transcript",
}


def load_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")


def load_json_text(raw: str, label: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {label}:{error.lineno}:{error.colno}: {error.msg}")


def decode_json_string(value: str) -> Any | None:
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def iter_json_objects(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            if isinstance(child, str):
                decoded = decode_json_string(child)
                if decoded is not None:
                    yield from iter_json_objects(decoded)
            else:
                yield from iter_json_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_json_objects(child)


def extract_handoff_paths(value: Any) -> dict[str, str]:
    paths: dict[str, str] = {}
    for obj in iter_json_objects(value):
        for key in PATH_KEYS:
            raw = obj.get(key)
            if isinstance(raw, str) and raw and key not in paths:
                paths[key] = raw
    return paths


def looks_like_mcp_transcript(value: Any) -> bool:
    return any(any(key in obj for key in TRANSCRIPT_KEYS) for obj in iter_json_objects(value))


def resolve_path(raw: str, base_dir: pathlib.Path | None) -> pathlib.Path:
    path = pathlib.Path(raw)
    if path.is_absolute() or base_dir is None:
        return path
    return base_dir / path


def recording_input_from_paths(paths: dict[str, str], base_dir: pathlib.Path | None) -> pathlib.Path:
    for key in ("metadataPath", "sessionPath"):
        raw = paths.get(key)
        if raw:
            return resolve_path(raw, base_dir)
    events_path = paths.get("eventsPath")
    if events_path:
        return resolve_path(events_path, base_dir).parent
    session_directory_path = paths.get("sessionDirectoryPath")
    if session_directory_path:
        return resolve_path(session_directory_path, base_dir)
    raise ValueError(
        "could not find metadataPath, sessionPath, eventsPath, or sessionDirectoryPath in official status JSON; "
        "pass --recording instead"
    )


def describe_path(path: pathlib.Path) -> dict[str, Any]:
    resolved = path
    exists = resolved.exists()
    return {
        "path": str(path),
        "exists": exists,
        "isDirectory": exists and resolved.is_dir(),
        "isFile": exists and resolved.is_file(),
        "name": resolved.name,
    }


def inspect_recording_input(recording_input: pathlib.Path) -> dict[str, Any]:
    info = describe_path(recording_input)
    if recording_input.is_dir():
        metadata_path = recording_input / "metadata.json"
        session_path = recording_input / "session.json"
        events_path = recording_input / "events.jsonl"
        suppressed_path = recording_input / "suppressed.jsonl"
    else:
        session_dir = recording_input.parent
        metadata_path = recording_input if recording_input.name == "metadata.json" else session_dir / "metadata.json"
        session_path = recording_input if recording_input.name == "session.json" else session_dir / "session.json"
        events_path = session_dir / "events.jsonl"
        suppressed_path = session_dir / "suppressed.jsonl"
    info.update(
        {
            "metadataPath": describe_path(metadata_path),
            "sessionPath": describe_path(session_path),
            "eventsPath": describe_path(events_path),
            "suppressedEventsPath": describe_path(suppressed_path),
        }
    )
    return info


def inspect_mcp_transcript(path: pathlib.Path | None, status_json: Any | None) -> dict[str, Any]:
    status_json_looks_like_transcript = (
        looks_like_mcp_transcript(status_json) if status_json is not None else False
    )
    if path is None:
        return {
            "path": None,
            "exists": False,
            "looksLikeMcpTranscript": False,
            "statusJsonLooksLikeMcpTranscript": status_json_looks_like_transcript,
        }
    info = describe_path(path)
    parsed: Any | None = None
    if path.exists() and path.is_file():
        parsed = load_json(path)
    info["looksLikeMcpTranscript"] = looks_like_mcp_transcript(parsed)
    info["statusJsonLooksLikeMcpTranscript"] = status_json_looks_like_transcript
    return info


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


def ingest(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    repo = pathlib.Path(__file__).resolve().parents[1]
    if args.status_json_base_dir is not None and args.status_json is None:
        raise ValueError("--status-json-base-dir requires --status-json")

    status_json: Any | None = None
    status_json_base: pathlib.Path | None = args.status_json_base_dir
    status_json_transcript_tmp: tempfile.TemporaryDirectory[str] | None = None
    status_json_stdin_transcript: pathlib.Path | None = None
    mcp_transcript_tmp: tempfile.TemporaryDirectory[str] | None = None
    mcp_transcript_stdin_path: pathlib.Path | None = None

    def cleanup_tempdirs() -> None:
        if mcp_transcript_tmp is not None:
            mcp_transcript_tmp.cleanup()
        if status_json_transcript_tmp is not None:
            status_json_transcript_tmp.cleanup()

    if args.status_json is not None:
        if str(args.status_json) == "-":
            if args.mcp_transcript is not None and str(args.mcp_transcript) == "-":
                raise ValueError(
                    "cannot read both --status-json and --mcp-transcript from stdin; "
                    "use --use-status-json-as-transcript when one JSON contains both"
                )
            raw_status_json = sys.stdin.read()
            status_json = load_json_text(raw_status_json, "<stdin>")
            if args.use_status_json_as_transcript:
                status_json_transcript_tmp = tempfile.TemporaryDirectory()
                status_json_stdin_transcript = (
                    pathlib.Path(status_json_transcript_tmp.name) / "status-json-transcript.json"
                )
                status_json_stdin_transcript.write_text(raw_status_json)
        else:
            status_json = load_json(args.status_json)
            if status_json_base is None:
                status_json_base = args.status_json.parent

    if args.recording is not None:
        recording_input = args.recording
        extracted_paths: dict[str, str] = {}
    elif status_json is not None:
        extracted_paths = extract_handoff_paths(status_json)
        recording_input = recording_input_from_paths(extracted_paths, status_json_base)
    else:
        raise ValueError("pass --recording or --status-json")

    mcp_transcript = args.mcp_transcript
    if mcp_transcript is not None and str(mcp_transcript) == "-":
        raw_mcp_transcript = sys.stdin.read()
        load_json_text(raw_mcp_transcript, "<stdin mcp transcript>")
        mcp_transcript_tmp = tempfile.TemporaryDirectory()
        mcp_transcript_stdin_path = pathlib.Path(mcp_transcript_tmp.name) / "mcp-transcript.json"
        mcp_transcript_stdin_path.write_text(raw_mcp_transcript)
        mcp_transcript = mcp_transcript_stdin_path

    if mcp_transcript is None and args.use_status_json_as_transcript:
        if status_json is None:
            raise ValueError("--use-status-json-as-transcript requires --status-json")
        if not looks_like_mcp_transcript(status_json):
            raise ValueError("--status-json does not look like an MCP transcript")
        mcp_transcript = status_json_stdin_transcript if status_json_stdin_transcript is not None else args.status_json

    used_mcp_transcript = (
        "<stdin>"
        if (
            (status_json_stdin_transcript is not None and mcp_transcript == status_json_stdin_transcript)
            or (mcp_transcript_stdin_path is not None and mcp_transcript == mcp_transcript_stdin_path)
        )
        else str(mcp_transcript)
        if mcp_transcript is not None
        else None
    )

    if args.inspect_only:
        recording_inspection = inspect_recording_input(recording_input)
        transcript_inspection = inspect_mcp_transcript(mcp_transcript, status_json)
        ok = recording_inspection["exists"] and (
            not args.require_mcp_transcript_evidence
            or transcript_inspection["looksLikeMcpTranscript"]
        )
        cleanup_tempdirs()
        return (
            0 if ok else 1,
            {
                "ok": ok,
                "stage": "inspect",
                "wouldImport": False,
                "scenario": args.scenario,
                "recordingInput": str(recording_input),
                "recordingInputInspection": recording_inspection,
                "extractedPaths": extracted_paths,
                "statusJsonBaseDir": str(status_json_base) if status_json_base is not None else None,
                "requiredMcpTranscriptEvidence": args.require_mcp_transcript_evidence,
                "usedMcpTranscript": used_mcp_transcript,
                "mcpTranscriptInspection": transcript_inspection,
            },
        )

    import_command = [
        sys.executable,
        str(repo / "scripts/import-event-stream-fixture.py"),
        str(recording_input),
        "--name",
        args.name,
        "--output-dir",
        str(args.output_dir),
        "--source",
        "official",
        "--scenario",
        args.scenario,
        "--official-plugin-version",
        args.official_plugin_version,
        "--captured-at",
        args.captured_at,
    ]
    if mcp_transcript is not None:
        import_command.extend(["--mcp-transcript", str(mcp_transcript)])
    if args.force:
        import_command.append("--force")

    import_ok, import_json = run_json(import_command, repo)
    if not import_ok:
        cleanup_tempdirs()
        return 1, {
            "ok": False,
            "stage": "import",
            "recordingInput": str(recording_input),
            "extractedPaths": extracted_paths,
            "importResult": import_json,
        }

    fixture_dir = pathlib.Path(import_json["fixtureDir"])
    readiness_command = [
        sys.executable,
        str(repo / "scripts/check-event-stream-golden-readiness.py"),
        str(fixture_dir),
        *scenario_readiness_args(
            args.scenario,
            source="official",
            require_mcp_transcript_evidence=args.require_mcp_transcript_evidence,
        ),
    ]
    readiness_ok, readiness_json = run_json(readiness_command, repo)

    fixture_set_json = None
    fixture_set_ok = None
    if args.check_fixture_set:
        fixture_set_ok, fixture_set_json = run_json(
            [
                sys.executable,
                str(repo / "scripts/check-event-stream-official-fixture-set.py"),
                "--official-root",
                str(args.output_dir),
                "--require-scenario",
                args.scenario,
            ],
            repo,
        )

    coverage_json = None
    coverage_ok = None
    if args.check_coverage or args.require_coverage:
        coverage_command = [
            sys.executable,
            str(repo / "scripts/check-event-stream-official-fixture-coverage.py"),
            "--fixture-root",
            str(args.output_dir),
        ]
        if args.require_coverage:
            coverage_command.append("--require-readiness")
        else:
            coverage_command.extend(["--allow-missing", "--check-readiness"])
        coverage_ok, coverage_json = run_json(coverage_command, repo)

    ok = (
        readiness_ok
        and (fixture_set_ok is not False)
        and (coverage_ok is not False)
    )
    result: dict[str, Any] = {
        "ok": ok,
        "fixtureDir": str(fixture_dir),
        "scenario": args.scenario,
        "recordingInput": str(recording_input),
        "extractedPaths": extracted_paths,
        "statusJsonBaseDir": str(status_json_base) if status_json_base is not None else None,
        "importResult": import_json,
        "readiness": readiness_json,
        "requiredMcpTranscriptEvidence": args.require_mcp_transcript_evidence,
        "usedMcpTranscript": used_mcp_transcript,
    }
    if fixture_set_json is not None:
        result["fixtureSetGate"] = fixture_set_json
    if coverage_json is not None:
        result["coverage"] = coverage_json

    if ok or args.allow_readiness_failure:
        cleanup_tempdirs()
        return 0, result
    cleanup_tempdirs()
    return 1, result


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Import an official Codex Record & Replay recording from hosted tool paths, "
            "sanitize it as a fixture, and run golden readiness checks."
        )
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--status-json",
        type=pathlib.Path,
        help=(
            "JSON captured from event_stream_stop/status or a JSON-RPC response. "
            "The script extracts metadataPath/sessionPath/eventsPath recursively. "
            "Use '-' to read the JSON from stdin."
        ),
    )
    source.add_argument(
        "--recording",
        type=pathlib.Path,
        help="Official recording directory, metadata.json, or session.json to import directly.",
    )
    parser.add_argument(
        "--status-json-base-dir",
        type=pathlib.Path,
        help=(
            "Resolve relative metadataPath/sessionPath/eventsPath values from --status-json against this directory. "
            "Defaults to the JSON file's parent; required for relative paths when --status-json is '-'."
        ),
    )
    parser.add_argument("--name", required=True, help="Fixture directory name to create.")
    parser.add_argument(
        "--scenario",
        default=DEFAULT_SCENARIO,
        help=(
            "Scenario tag to write into fixture-manifest.json. Defaults to "
            f"{DEFAULT_SCENARIO}. Required scenarios: {DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT_ROOT,
        help=f"Fixture root directory. Defaults to {DEFAULT_OUTPUT_ROOT}.",
    )
    parser.add_argument(
        "--official-plugin-version",
        default=DEFAULT_OFFICIAL_PLUGIN_VERSION,
        help=f"Official plugin version string. Defaults to {DEFAULT_OFFICIAL_PLUGIN_VERSION!r}.",
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
            "Optional raw probe output or MCP transcript to sanitize into mcp-transcript.json. "
            "Use '-' to read the transcript JSON from stdin when --status-json is a file."
        ),
    )
    parser.add_argument(
        "--use-status-json-as-transcript",
        action="store_true",
        help="Treat --status-json as the MCP transcript too, when it contains transcript/response-shape keys.",
    )
    parser.add_argument(
        "--require-mcp-transcript-evidence",
        action="store_true",
        help=(
            "Require mcp-transcript.json and scenario-specific MCP response-shape evidence during readiness. "
            "Use this for official golden fixtures intended to pass the collection-level gate."
        ),
    )
    parser.add_argument(
        "--check-fixture-set",
        action="store_true",
        help="After import, run the collection-level official fixture set gate for this scenario.",
    )
    parser.add_argument(
        "--check-coverage",
        action="store_true",
        help=(
            "After import, report official successful recording scenario coverage for the output root. "
            "Missing required scenarios are reported but do not fail the command."
        ),
    )
    parser.add_argument(
        "--require-coverage",
        action="store_true",
        help=(
            "After import, require the output root to cover required official successful recording scenarios. "
            "This implies --check-coverage and returns non-zero when coverage is incomplete."
        ),
    )
    parser.add_argument(
        "--allow-readiness-failure",
        action="store_true",
        help="Exit 0 after import even when readiness or fixture-set checks fail; the JSON still reports failures.",
    )
    parser.add_argument(
        "--inspect-only",
        action="store_true",
        help=(
            "Parse inputs and report recording/transcript readiness without creating a fixture. "
            "Use this immediately after copying hosted Codex Record & Replay JSON."
        ),
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
