#!/usr/bin/env python3

import argparse
import datetime
import json
import pathlib
import shutil
import sys
from collections import Counter

from record_and_replay_scenarios import scenario_recipe


DEFAULT_OUTPUT_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)

TEXT_KEYS = {
    "AXDescription",
    "AXSelectedText",
    "AXTitle",
    "AXValue",
    "characters",
    "description",
    "label",
    "rawCharacters",
    "renderedText",
    "selectedText",
    "text",
    "treeLines",
    "title",
    "value",
    "windowTitle",
    "cumulativeRenderedText",
    "cumulativeTreeLines",
    "diffRenderedText",
    "fullTree",
    "fullRenderedText",
}

APP_ATTRIBUTION_KEYS = {
    "appBundleIdentifier",
    "appName",
    "applicationName",
    "bundleId",
    "bundleIdentifier",
    "localizedName",
}

TIMESTAMP_KEYS = {
    "capturedAt",
    "createdAt",
    "endedAt",
    "startTime",
    "startedAt",
    "timestamp",
    "updatedAt",
}

SESSION_ID_KEYS = {
    "id",
    "sessionID",
    "sessionId",
}

RELATIVE_PATHS = {
    "currentSegmentEventsPath": "events.jsonl",
    "currentSegmentMetadataPath": "metadata.json",
    "eventsPath": "events.jsonl",
    "metadataPath": "metadata.json",
    "sessionPath": "session.json",
    "suppressedEventsPath": "suppressed.jsonl",
}

MCP_TRANSCRIPT_FILENAME = "mcp-transcript.json"


def should_redact_path_key(key):
    return key == "path" or key.endswith("Path")


def load_json(path):
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def read_jsonl(path):
    records = []
    if not path.exists():
        raise ValueError(f"missing JSONL file: {path}")
    for index, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSONL in {path}:{index}:{error.colno}: {error.msg}")
        if not isinstance(value, dict):
            raise ValueError(f"expected JSON object in {path}:{index}")
        records.append(value)
    return records


def event_kind(event):
    kind = event.get("kind")
    if isinstance(kind, str):
        return kind
    event_type = event.get("type")
    if isinstance(event_type, str):
        return event_type
    return None


def first_string(value, keys):
    for key in keys:
        candidate = value.get(key)
        if isinstance(candidate, str) and candidate:
            return candidate
    return None


def recording_session_id(metadata, events):
    session_id = first_string(metadata, ["sessionId", "sessionID", "id"])
    if session_id is not None:
        return session_id
    for event in events:
        session_id = first_string(event, ["sessionId", "sessionID", "id"])
        if session_id is not None:
            return session_id
    return "fixture-session"


def recording_end_reason(metadata, events):
    end_reason = metadata.get("endReason")
    if isinstance(end_reason, str) and end_reason:
        return end_reason
    ended_reasons = [
        event.get("endReason")
        for event in events
        if event_kind(event) == "session.ended" and isinstance(event.get("endReason"), str)
    ]
    return ended_reasons[-1] if ended_reasons else None


def normalized_fixture_metadata(metadata, events, suppressed):
    end_reason = recording_end_reason(metadata, events)
    ended_at = first_string(metadata, ["endedAt"])
    state = metadata.get("state") if isinstance(metadata.get("state"), str) else None
    if state is None:
        state = "cancelled" if end_reason == "recording_controls_cancelled" else "stopped"
        if ended_at is None and end_reason is None and not any(event_kind(event) == "session.ended" for event in events):
            state = "recording"

    normalized = {
        "sessionId": recording_session_id(metadata, events),
        "state": state,
        "active": state == "recording",
        "eventCount": len(events),
        "suppressedEventCount": len(suppressed),
        "eventsPath": "events.jsonl",
        "metadataPath": "metadata.json",
        "sessionPath": "session.json",
        "suppressedEventsPath": "suppressed.jsonl",
    }
    started_at = first_string(metadata, ["startedAt"])
    if started_at is not None:
        normalized["startedAt"] = started_at
    if ended_at is not None:
        normalized["endedAt"] = ended_at
    if end_reason is not None:
        normalized["endReason"] = end_reason
    return normalized


def session_handoff_from_metadata(metadata):
    handoff = {
        "id": metadata["sessionId"],
        "eventsPath": metadata["eventsPath"],
    }
    for key in ["startedAt", "endedAt", "endReason"]:
        if key in metadata:
            handoff[key] = metadata[key]
    return handoff


def resolve_path(base, raw, fallback):
    if isinstance(raw, str) and raw:
        candidate = pathlib.Path(raw)
        if candidate.is_absolute():
            return candidate
        return base / candidate
    return fallback


def resolve_input(path):
    if path.is_dir():
        metadata_path = path / "metadata.json"
        session_path = path / "session.json"
        if metadata_path.exists():
            metadata = load_json(metadata_path)
        elif session_path.exists():
            metadata_path = session_path
            metadata = load_json(metadata_path)
        else:
            raise ValueError(f"session directory has no metadata.json or session.json: {path}")
        events_path = resolve_path(path, metadata.get("eventsPath"), path / "events.jsonl")
        suppressed_path = resolve_path(path, metadata.get("suppressedEventsPath"), path / "suppressed.jsonl")
        return {
            "session_dir": path,
            "metadata_path": metadata_path,
            "session_path": session_path if session_path.exists() else None,
            "metadata": metadata,
            "events_path": events_path,
            "suppressed_path": suppressed_path,
        }

    if not path.exists():
        raise ValueError(f"path does not exist: {path}")
    if path.name not in {"metadata.json", "session.json"}:
        raise ValueError("input must be a session directory, metadata.json, or session.json")
    session_dir = path.parent
    metadata = load_json(path)
    events_path = resolve_path(session_dir, metadata.get("eventsPath"), session_dir / "events.jsonl")
    suppressed_path = resolve_path(
        session_dir,
        metadata.get("suppressedEventsPath"),
        session_dir / "suppressed.jsonl",
    )
    return {
        "session_dir": session_dir,
        "metadata_path": path,
        "session_path": session_dir / "session.json" if (session_dir / "session.json").exists() else None,
        "metadata": metadata,
        "events_path": events_path,
        "suppressed_path": suppressed_path,
    }


def redacted_string(key, value):
    if key in SESSION_ID_KEYS:
        return "fixture-session"
    if key in TIMESTAMP_KEYS:
        return "<redacted-timestamp>"
    if key in APP_ATTRIBUTION_KEYS:
        return f"<redacted-{key}>"
    return f"<redacted-{key}:length={len(value)}>"


def redacted_tree_line(key, value):
    stripped = value.lstrip()
    prefix = value[: len(value) - len(stripped)]
    if stripped.startswith(("+", "-", "~")):
        return f"{prefix}{stripped[0]} <redacted-{key}:length={len(value)}>"
    return redacted_string(key, value)


def sanitize(value, parent_key=None, preserve_app_attribution=False):
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            if key in {"client", "command", "cwd", "recordingsDir"}:
                result[f"{key}Redacted"] = True
                continue
            if key in RELATIVE_PATHS:
                result[key] = RELATIVE_PATHS[key]
                continue
            if key == "screenshotPath":
                result["screenshotPathRedacted"] = True
                continue
            if isinstance(child, str) and should_redact_path_key(key):
                result[f"{key}Redacted"] = True
                result[f"{key}Length"] = len(child)
                continue
            if key == "text" and isinstance(child, str):
                decoded = decode_json_text(child)
                result["textRedacted"] = True
                if decoded is None:
                    result["textLength"] = len(child)
                else:
                    result["decodedText"] = sanitize(
                        decoded,
                        key,
                        preserve_app_attribution,
                    )
                continue
            if isinstance(child, str) and should_redact_key(key, preserve_app_attribution):
                result[key] = redacted_string(key, child)
                continue
            result[key] = sanitize(child, key, preserve_app_attribution)
        return result
    if isinstance(value, list):
        return [sanitize(child, parent_key, preserve_app_attribution) for child in value]
    if isinstance(value, str) and parent_key in {"treeLines", "cumulativeTreeLines", "fullTree"}:
        return redacted_tree_line(parent_key, value)
    if isinstance(value, str) and parent_key and should_redact_key(parent_key, preserve_app_attribution):
        return redacted_string(parent_key, value)
    return value


def decode_json_text(value):
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return None
    if isinstance(decoded, (dict, list)):
        return decoded
    return None


def should_redact_key(key, preserve_app_attribution):
    if key in TEXT_KEYS or key in TIMESTAMP_KEYS or key in SESSION_ID_KEYS:
        return True
    if not preserve_app_attribution and key in APP_ATTRIBUTION_KEYS:
        return True
    return False


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    lines = [json.dumps(record, separators=(",", ":"), ensure_ascii=False) for record in records]
    path.write_text("\n".join(lines) + ("\n" if lines else ""))


def fixture_readme(name, source, official_version):
    version_line = f"- Official plugin version: `{official_version}`\n" if official_version else ""
    return f"""# {name}

This is a sanitized Record & Replay event-stream fixture.

- Source: `{source}`
{version_line}- Screenshots are not copied.
- User text, window titles, timestamps, session ids, local paths, and app attribution are redacted by default.

Use `open-computer-use event-stream validate --json <fixture-dir>` or
`scripts/validate-event-stream-recording.py <fixture-dir>` to check structure.
"""


def import_fixture(args):
    resolved = resolve_input(args.input)
    events = read_jsonl(resolved["events_path"])
    suppressed = []
    suppressed_exists = resolved["suppressed_path"].exists()
    if suppressed_exists:
        suppressed = read_jsonl(resolved["suppressed_path"])

    target = args.output_dir / args.name
    if target.exists():
        if not args.force:
            raise ValueError(f"fixture already exists: {target}; pass --force to replace it")
        shutil.rmtree(target)
    target.mkdir(parents=True)

    fixture_metadata = normalized_fixture_metadata(resolved["metadata"], events, suppressed)
    sanitized_metadata = sanitize(
        fixture_metadata,
        preserve_app_attribution=args.preserve_app_attribution,
    )
    sanitized_events = [
        sanitize(event, preserve_app_attribution=args.preserve_app_attribution)
        for event in events
    ]
    sanitized_suppressed = [
        sanitize(event, preserve_app_attribution=args.preserve_app_attribution)
        for event in suppressed
    ]

    write_json(target / "metadata.json", sanitized_metadata)
    if resolved["session_path"] is not None:
        session_json = load_json(resolved["session_path"])
        write_json(
            target / "session.json",
            sanitize(session_json, preserve_app_attribution=args.preserve_app_attribution),
        )
    else:
        write_json(
            target / "session.json",
            sanitize(
                session_handoff_from_metadata(fixture_metadata),
                preserve_app_attribution=args.preserve_app_attribution,
            ),
        )
    write_jsonl(target / "events.jsonl", sanitized_events)
    write_jsonl(target / "suppressed.jsonl", sanitized_suppressed)

    sanitized_mcp_transcript = None
    if args.mcp_transcript:
        mcp_transcript = load_json(args.mcp_transcript)
        sanitized_mcp_transcript = sanitize(
            mcp_transcript,
            preserve_app_attribution=args.preserve_app_attribution,
        )
        write_json(target / MCP_TRANSCRIPT_FILENAME, sanitized_mcp_transcript)

    event_types = Counter(kind for event in events if (kind := event_kind(event)))
    manifest = {
        "fixtureFormatVersion": 1,
        "name": args.name,
        "scenario": args.scenario,
        "scenarioRecipe": scenario_recipe(args.scenario) if args.scenario else None,
        "source": args.source,
        "officialPluginVersion": args.official_plugin_version,
        "capturedAt": args.captured_at,
        "importedAt": datetime.date.today().isoformat(),
        "eventCount": len(events),
        "suppressedEventCount": len(suppressed),
        "eventTypes": dict(sorted(event_types.items())),
        "files": {
            "metadata": "metadata.json",
            "session": "session.json",
            "events": "events.jsonl",
            "suppressed": "suppressed.jsonl",
            "mcpTranscript": MCP_TRANSCRIPT_FILENAME if sanitized_mcp_transcript is not None else None,
        },
        "redaction": {
            "screenshotsCopied": False,
            "mcpTranscriptSanitized": sanitized_mcp_transcript is not None,
            "preserveAppAttribution": args.preserve_app_attribution,
            "textKeys": sorted(TEXT_KEYS),
            "timestampKeys": sorted(TIMESTAMP_KEYS),
            "sessionIdKeys": sorted(SESSION_ID_KEYS),
            "pathKeysRewrittenRelative": sorted(RELATIVE_PATHS),
            "pathKeysRedacted": ["path", "*Path"],
        },
    }
    write_json(target / "fixture-manifest.json", manifest)
    (target / "README.md").write_text(
        fixture_readme(args.name, args.source, args.official_plugin_version)
    )
    return {
        "ok": True,
        "fixtureDir": str(target),
        "eventCount": len(events),
        "eventTypes": dict(sorted(event_types.items())),
        "mcpTranscript": MCP_TRANSCRIPT_FILENAME if sanitized_mcp_transcript is not None else None,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Import and sanitize a Record & Replay recording as a repository fixture."
    )
    parser.add_argument("input", type=pathlib.Path, help="Session directory, metadata.json, or session.json")
    parser.add_argument("--name", required=True, help="Fixture directory name to create.")
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT_ROOT,
        help=f"Fixture root directory. Defaults to {DEFAULT_OUTPUT_ROOT}.",
    )
    parser.add_argument("--source", choices=["official", "ocu"], default="official")
    parser.add_argument(
        "--scenario",
        help=(
            "Machine-readable scenario tag, for example simple-action-stop. "
            "Official fixture set gates use this to pair baseline and candidate recordings."
        ),
    )
    parser.add_argument("--official-plugin-version", help="Official Record & Replay plugin version, when known.")
    parser.add_argument(
        "--captured-at",
        default=datetime.date.today().isoformat(),
        help="Capture date to record in fixture-manifest.json.",
    )
    parser.add_argument(
        "--preserve-app-attribution",
        action="store_true",
        help="Keep app names and bundle identifiers when the fixture is already safe to publish.",
    )
    parser.add_argument(
        "--mcp-transcript",
        type=pathlib.Path,
        help=(
            "Optional JSON probe output or MCP transcript to sanitize into mcp-transcript.json. "
            "Use this for official golden fixtures that need event_stream_start/status/stop response evidence."
        ),
    )
    parser.add_argument("--force", action="store_true", help="Replace an existing fixture directory.")
    args = parser.parse_args()

    try:
        result = import_fixture(args)
    except ValueError as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
