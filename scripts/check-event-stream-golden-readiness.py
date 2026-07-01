#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import Counter
from typing import Any


ACTION_EVENT_TYPES = {
    "keyboard.shortcut",
    "keyboard.submit",
    "keyboard.text_input",
    "mouse.click",
    "mouse.context_menu",
    "mouse.drag",
    "terminal.value_changed",
}

FINAL_STATES = {"stopped", "cancelled"}

MCP_TOOL_EVIDENCE_DEFAULTS = {
    "requested": False,
    "responded": False,
    "hasResult": False,
    "hasError": False,
    "timedOut": False,
}

MCP_RESPONSE_SHAPES = {
    "startResponseShape": "event_stream_start",
    "repeatStartResponseShape": "event_stream_start",
    "statusResponseShape": "event_stream_status",
    "stopResponseShape": "event_stream_stop",
    "repeatStopResponseShape": "event_stream_stop",
    "finalStatusResponseShape": "event_stream_status",
}

MCP_RESPONSE_SHAPE_ALIASES = {
    "startResponse": "startResponseShape",
    "repeatStartResponse": "repeatStartResponseShape",
    "statusResponse": "statusResponseShape",
    "stopResponse": "stopResponseShape",
    "repeatStopResponse": "repeatStopResponseShape",
    "finalStatusResponse": "finalStatusResponseShape",
}

HANDOFF_PATH_KEYS = (
    "metadataPath",
    "sessionPath",
    "eventsPath",
    "suppressedEventsPath",
)


def load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def read_jsonl(path: pathlib.Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
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


def event_kind(event: dict[str, Any]) -> str | None:
    kind = event.get("kind")
    if isinstance(kind, str):
        return kind
    event_type = event.get("type")
    if isinstance(event_type, str):
        return event_type
    return None


def resolve_path(base: pathlib.Path, raw: Any, fallback: pathlib.Path) -> pathlib.Path:
    if isinstance(raw, str) and raw:
        candidate = pathlib.Path(raw)
        if candidate.is_absolute():
            return candidate
        return base / candidate
    return fallback


def handoff_path_evidence(session_dir: pathlib.Path, metadata: dict[str, Any], key: str) -> dict[str, Any]:
    raw = metadata.get(key)
    evidence: dict[str, Any] = {
        "value": raw,
        "resolvedPath": None,
        "exists": None,
    }
    if isinstance(raw, str) and raw:
        path = pathlib.Path(raw)
        resolved_path = path if path.is_absolute() else session_dir / path
        evidence["resolvedPath"] = str(resolved_path)
        evidence["exists"] = resolved_path.exists()
    return evidence


def first_string(value: dict[str, Any], keys: list[str]) -> str | None:
    for key in keys:
        candidate = value.get(key)
        if isinstance(candidate, str) and candidate:
            return candidate
    return None


def session_alias_compatible(metadata: dict[str, Any], session_alias: dict[str, Any]) -> bool:
    if metadata == session_alias:
        return True

    metadata_session_id = first_string(metadata, ["sessionId", "sessionID", "id"])
    session_id = first_string(session_alias, ["id", "sessionId", "sessionID"])
    if metadata_session_id is None or session_id is None or metadata_session_id != session_id:
        return False

    metadata_started_at = metadata.get("startedAt")
    if isinstance(metadata_started_at, str) and metadata_started_at != session_alias.get("startedAt"):
        return False

    for key in ["endedAt", "endReason"]:
        session_value = session_alias.get(key)
        if isinstance(session_value, str) and session_value != metadata.get(key):
            return False

    session_events_path = session_alias.get("eventsPath")
    metadata_events_path = metadata.get("eventsPath")
    if not isinstance(session_events_path, str) or not session_events_path:
        return False
    if not isinstance(metadata_events_path, str) or not metadata_events_path:
        return False
    if (
        session_events_path != metadata_events_path
        and pathlib.Path(session_events_path).name != pathlib.Path(metadata_events_path).name
    ):
        return False

    return True


def resolve_recording(path: pathlib.Path) -> dict[str, Any]:
    if path.is_dir():
        metadata_json_path = path / "metadata.json"
        session_alias_path = path / "session.json"
        metadata_json = load_json(metadata_json_path) if metadata_json_path.exists() else None
        session_alias = load_json(session_alias_path) if session_alias_path.exists() else None
        if metadata_json is not None:
            metadata_path = metadata_json_path
            metadata = metadata_json
        elif session_alias is not None:
            metadata_path = session_alias_path
            metadata = session_alias
        else:
            raise ValueError(f"recording directory has no metadata.json or session.json: {path}")
        session_dir = path
    else:
        if not path.exists():
            raise ValueError(f"path does not exist: {path}")
        if path.name not in {"metadata.json", "session.json"}:
            raise ValueError("input must be a recording directory, metadata.json, or session.json")
        session_dir = path.parent
        metadata_json_path = session_dir / "metadata.json"
        session_alias_path = session_dir / "session.json"
        metadata_json = load_json(metadata_json_path) if metadata_json_path.exists() else None
        session_alias = load_json(session_alias_path) if session_alias_path.exists() else None
        if path.name == "session.json" and metadata_json is not None:
            metadata_path = metadata_json_path
            metadata = metadata_json
        else:
            metadata_path = path
            metadata = load_json(path)

    events_path = resolve_path(session_dir, metadata.get("eventsPath"), session_dir / "events.jsonl")
    suppressed_path = resolve_path(
        session_dir,
        metadata.get("suppressedEventsPath"),
        session_dir / "suppressed.jsonl",
    )
    manifest_path = session_dir / "fixture-manifest.json"
    manifest = load_json(manifest_path) if manifest_path.exists() else None
    mcp_transcript_path = None
    if isinstance(manifest, dict):
        files = manifest.get("files")
        if isinstance(files, dict) and isinstance(files.get("mcpTranscript"), str):
            mcp_transcript_path = resolve_path(session_dir, files["mcpTranscript"], session_dir / "mcp-transcript.json")
    if mcp_transcript_path is None and (session_dir / "mcp-transcript.json").exists():
        mcp_transcript_path = session_dir / "mcp-transcript.json"

    try:
        events = read_jsonl(events_path)
        events_error = None
    except ValueError as error:
        events = []
        events_error = str(error)

    return {
        "sessionDir": session_dir,
        "metadataPath": metadata_path,
        "metadataJsonPath": metadata_json_path if metadata_json_path.exists() else None,
        "sessionAliasPath": session_alias_path if session_alias_path.exists() else None,
        "metadata": metadata,
        "metadataJson": metadata_json,
        "sessionAlias": session_alias,
        "eventsPath": events_path,
        "events": events,
        "eventsReadError": events_error,
        "suppressedPath": suppressed_path,
        "suppressed": read_jsonl(suppressed_path) if suppressed_path.exists() else [],
        "manifestPath": manifest_path if manifest_path.exists() else None,
        "manifest": manifest,
        "mcpTranscriptPath": mcp_transcript_path,
        "mcpTranscript": load_json(mcp_transcript_path) if mcp_transcript_path else None,
    }


def iter_dicts(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from iter_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_dicts(child)


def accessibility_payloads(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    payloads: list[dict[str, Any]] = []
    for event in events:
        for value in iter_dicts(event):
            payload = value.get("accessibilityInspectorPayload")
            if isinstance(payload, dict):
                payloads.append(payload)
            official_ax_payload = value.get("ax")
            if isinstance(official_ax_payload, dict):
                payloads.append(official_ax_payload)
        if event_kind(event) == "AX.focusedWindowChanged":
            payload = event.get("accessibilityInspectorPayload")
            if isinstance(payload, dict) and payload not in payloads:
                payloads.append(payload)
            official_ax_payload = event.get("ax")
            if isinstance(official_ax_payload, dict) and official_ax_payload not in payloads:
                payloads.append(official_ax_payload)
    return payloads


def is_full_ax_payload(payload: dict[str, Any]) -> bool:
    return (
        payload.get("kind") == "full"
        or payload.get("mode") in {"full", "fullTree"}
        or payload.get("diffFromPrevious") is False
        or isinstance(payload.get("fullTree"), (list, str))
    )


def is_full_tree_payload(payload: dict[str, Any]) -> bool:
    return (
        isinstance(payload.get("fullTree"), (list, str)) and bool(payload.get("fullTree"))
    ) or payload.get("mode") == "fullTree"


def response_evidence(response: dict[str, Any], requested: bool = True) -> dict[str, bool]:
    return {
        "requested": requested,
        "responded": True,
        "hasResult": "result" in response,
        "hasError": "error" in response,
        "timedOut": "timeout" in response,
    }


def merge_tool_evidence(entry: dict[str, bool], response: dict[str, Any]) -> None:
    entry["responded"] = True
    entry["hasResult"] = bool(entry.get("hasResult")) or "result" in response
    entry["hasError"] = bool(entry.get("hasError")) or "error" in response
    saw_timeout = bool(entry.get("timedOut")) or "timeout" in response
    entry["timedOut"] = saw_timeout and not (entry["hasResult"] or entry["hasError"])


def mcp_response_evidence(transcript: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    evidence: dict[str, dict[str, bool]] = {}
    shape_evidence: dict[str, dict[str, Any]] = {}
    if not isinstance(transcript, dict):
        return evidence, shape_evidence

    response_keys: dict[str, str] = dict(MCP_RESPONSE_SHAPES)
    response_keys.update(
        {raw_key: MCP_RESPONSE_SHAPES[shape_key] for raw_key, shape_key in MCP_RESPONSE_SHAPE_ALIASES.items()}
    )
    for response_key, tool_name in response_keys.items():
        response = transcript.get(response_key)
        if isinstance(response, dict):
            entry = evidence.setdefault(
                tool_name,
                dict(MCP_TOOL_EVIDENCE_DEFAULTS),
            )
            entry["requested"] = True
            merge_tool_evidence(entry, response)
            shape_key = MCP_RESPONSE_SHAPE_ALIASES.get(response_key, response_key)
            if shape_key in MCP_RESPONSE_SHAPES:
                shape_evidence[shape_key] = {
                    **response_evidence(response),
                    "toolName": tool_name,
                }

    request_id_to_tool: dict[Any, str] = {}
    for event in transcript.get("transcript", []):
        if not isinstance(event, dict):
            continue
        message = event.get("message")
        if not isinstance(message, dict):
            continue
        if event.get("direction") == "send" and message.get("method") == "tools/call":
            params = message.get("params")
            tool_name = params.get("name") if isinstance(params, dict) else None
            if isinstance(tool_name, str):
                request_id_to_tool[message.get("id")] = tool_name
                entry = evidence.setdefault(tool_name, dict(MCP_TOOL_EVIDENCE_DEFAULTS))
                entry["requested"] = True
        elif event.get("direction") == "receive" and message.get("id") in request_id_to_tool:
            tool_name = request_id_to_tool[message.get("id")]
            entry = evidence.setdefault(tool_name, dict(MCP_TOOL_EVIDENCE_DEFAULTS))
            entry["requested"] = True
            merge_tool_evidence(entry, message)

    for event in transcript.get("transcriptShape", []):
        if not isinstance(event, dict):
            continue
        method = event.get("method")
        if method == "tools/call":
            continue
        # Shape-only probe fixtures cannot recover the tool name from method alone.

    return evidence, shape_evidence


def check_recording(path: pathlib.Path, args: argparse.Namespace) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    try:
        recording = resolve_recording(path)
    except ValueError as error:
        return {
            "ok": False,
            "path": str(path),
            "errors": [str(error)],
            "warnings": [],
        }

    metadata = recording["metadata"]
    metadata_json = recording["metadataJson"]
    session_alias = recording["sessionAlias"]
    events = recording["events"]
    suppressed_events = recording["suppressed"]
    manifest = recording["manifest"]
    mcp_transcript = recording["mcpTranscript"]
    event_types = [kind for event in events if (kind := event_kind(event))]
    event_type_counts = Counter(event_types)
    suppressed_event_types = [
        event_kind(event)
        for event in suppressed_events
        if event_kind(event) is not None
    ]
    suppressed_event_type_counts = Counter(suppressed_event_types)
    action_event_count = sum(event_type_counts[event_type] for event_type in ACTION_EVENT_TYPES)
    payloads = accessibility_payloads(events)
    has_metadata_json = metadata_json is not None
    has_session_alias = session_alias is not None
    metadata_session_alias_complete = has_metadata_json and has_session_alias
    metadata_session_alias_matches = (
        session_alias_compatible(metadata_json, session_alias)
        if metadata_session_alias_complete
        else None
    )
    if metadata_session_alias_matches is False:
        errors.append("metadata.json and session.json differ")
    if args.require_session_alias:
        if not has_metadata_json:
            errors.append("missing metadata.json")
        if not has_session_alias:
            errors.append("missing session.json alias")
    metadata_event_count = metadata.get("eventCount")
    metadata_suppressed_event_count = metadata.get("suppressedEventCount")
    metadata_event_count_matches = (
        metadata_event_count == len(events)
        if isinstance(metadata_event_count, int)
        else None
    )
    metadata_suppressed_event_count_matches = (
        metadata_suppressed_event_count == len(suppressed_events)
        if isinstance(metadata_suppressed_event_count, int)
        else None
    )
    if metadata_event_count_matches is False:
        errors.append(f"eventCount={metadata_event_count} does not match events.jsonl lines={len(events)}")
    if metadata_suppressed_event_count_matches is False:
        errors.append(
            "suppressedEventCount="
            f"{metadata_suppressed_event_count} does not match suppressed.jsonl lines={len(suppressed_events)}"
        )
    if args.require_metadata_counts:
        if not isinstance(metadata_event_count, int):
            errors.append("missing metadata eventCount")
        if not isinstance(metadata_suppressed_event_count, int):
            errors.append("missing metadata suppressedEventCount")

    declared_paths = {
        key: handoff_path_evidence(recording["sessionDir"], metadata, key)
        for key in HANDOFF_PATH_KEYS
    }
    for key, evidence in declared_paths.items():
        raw_value = evidence["value"]
        if raw_value is None:
            continue
        if not isinstance(raw_value, str) or not raw_value:
            errors.append(f"{key} is not a non-empty string")
        elif evidence["exists"] is False:
            errors.append(f"{key} does not exist: {raw_value}")
    if args.require_handoff_paths:
        for key, evidence in declared_paths.items():
            if not isinstance(evidence["value"], str) or not evidence["value"]:
                errors.append(f"missing {key}")
    if recording["eventsReadError"] is not None:
        errors.append(recording["eventsReadError"])

    state = metadata.get("state")
    started_events = [event for event in events if event_kind(event) == "session.started"]
    first_event_type = event_kind(events[0]) if events else None
    last_event_type = event_kind(events[-1]) if events else None
    ended_events = [event for event in events if event_kind(event) == "session.ended"]
    end_reasons = [
        event.get("endReason")
        for event in ended_events
        if isinstance(event.get("endReason"), str)
    ]
    if isinstance(metadata.get("endReason"), str):
        end_reasons.append(metadata["endReason"])
    end_reason_counts = Counter(end_reasons)
    if state not in FINAL_STATES:
        errors.append(f"metadata state is not final: {state}")
    if not started_events:
        errors.append("missing session.started event")
    elif len(started_events) > 1:
        errors.append("multiple session.started events")
    if started_events and first_event_type != "session.started":
        errors.append("session.started is not the first event")
    if not ended_events and not args.allow_no_session_ended:
        errors.append("missing session.ended event")
    elif len(ended_events) > 1:
        errors.append("multiple session.ended events")
    if ended_events and last_event_type != "session.ended":
        errors.append("session.ended is not the final event")
    if not args.allow_no_action and action_event_count == 0:
        errors.append("missing action event; pass --allow-no-action only for lifecycle/status fixtures")
    if not args.allow_no_ax_payload and not payloads:
        errors.append("missing accessibilityInspectorPayload; pass --allow-no-ax-payload only for non-action fixtures")

    for required_type in args.require_event_type:
        if event_type_counts[required_type] == 0:
            errors.append(f"missing required event type: {required_type}")
    if args.require_suppressed_events and not suppressed_events:
        errors.append("missing suppressed events")
    for required_type in args.require_suppressed_event_type:
        if suppressed_event_type_counts[required_type] == 0:
            errors.append(f"missing required suppressed event type: {required_type}")
    for required_reason in args.require_end_reason:
        if end_reason_counts[required_reason] == 0:
            errors.append(f"missing required endReason: {required_reason}")

    has_full_tree_payload = any(
        is_full_tree_payload(payload)
        for payload in payloads
    )
    has_full_ax_payload = any(
        is_full_ax_payload(payload)
        for payload in payloads
    )
    has_diff_ax_payload = any(payload.get("kind") == "diff" or payload.get("diffFromPrevious") is True for payload in payloads)
    has_cumulative_ax_diff = any(
        payload.get("cumulativeDiffFromInitial") is True
        or isinstance(payload.get("cumulativeRenderedText"), str)
        for payload in payloads
    )
    if args.require_full_ax_payload and not has_full_ax_payload:
        errors.append("missing full AX payload")
    if args.require_diff_payload and not has_diff_ax_payload:
        errors.append("missing AX diff payload")
    if args.require_cumulative_diff and not has_cumulative_ax_diff:
        errors.append("missing cumulative AX diff payload")

    if args.require_fixture_manifest and manifest is None:
        errors.append("missing fixture-manifest.json")
    if args.require_source:
        if manifest is None:
            errors.append("cannot verify source without fixture-manifest.json")
        elif manifest.get("source") != args.require_source:
            errors.append(f"fixture source={manifest.get('source')} does not match required source={args.require_source}")
    if args.require_official_plugin_version:
        if manifest is None:
            errors.append("cannot verify official plugin version without fixture-manifest.json")
        elif manifest.get("officialPluginVersion") != args.require_official_plugin_version:
            errors.append(
                "fixture officialPluginVersion="
                f"{manifest.get('officialPluginVersion')} does not match required "
                f"{args.require_official_plugin_version}"
            )

    if manifest is not None:
        redaction = manifest.get("redaction")
        if not isinstance(redaction, dict):
            warnings.append("fixture manifest has no redaction block")
        elif redaction.get("screenshotsCopied") is not False:
            errors.append("fixture manifest must record screenshotsCopied=false for repository fixtures")
        manifest_event_count = manifest.get("eventCount")
        if isinstance(manifest_event_count, int) and manifest_event_count != len(events):
            errors.append(
                f"fixture manifest eventCount={manifest_event_count} does not match events.jsonl lines={len(events)}"
            )
        manifest_suppressed_event_count = manifest.get("suppressedEventCount")
        if isinstance(manifest_suppressed_event_count, int) and manifest_suppressed_event_count != len(suppressed_events):
            errors.append(
                "fixture manifest suppressedEventCount="
                f"{manifest_suppressed_event_count} does not match suppressed.jsonl lines={len(suppressed_events)}"
            )

    mcp_evidence, mcp_shape_evidence = mcp_response_evidence(mcp_transcript)
    if args.require_mcp_transcript and mcp_transcript is None:
        errors.append("missing mcp-transcript.json")
    for tool_name in args.require_mcp_tool_response:
        tool_evidence = mcp_evidence.get(tool_name)
        if not tool_evidence:
            errors.append(f"missing MCP response evidence for {tool_name}")
            continue
        if tool_evidence.get("timedOut"):
            errors.append(f"MCP tool timed out: {tool_name}")
        elif not tool_evidence.get("responded"):
            errors.append(f"MCP tool did not respond: {tool_name}")
        elif not (tool_evidence.get("hasResult") or tool_evidence.get("hasError")):
            errors.append(f"MCP response has no result or error: {tool_name}")
    for response_shape in args.require_mcp_response_shape:
        shape_evidence = mcp_shape_evidence.get(response_shape)
        if not shape_evidence:
            errors.append(f"missing MCP response shape evidence: {response_shape}")
            continue
        if shape_evidence.get("timedOut"):
            errors.append(f"MCP response shape timed out: {response_shape}")
        elif not shape_evidence.get("responded"):
            errors.append(f"MCP response shape did not respond: {response_shape}")
        elif not (shape_evidence.get("hasResult") or shape_evidence.get("hasError")):
            errors.append(f"MCP response shape has no result or error: {response_shape}")

    recommendation = "ready for golden comparison"
    if errors:
        recommendation = "capture or import a richer recording before using this as a golden baseline"
    elif warnings:
        recommendation = "usable, but review warnings before treating as authoritative"

    return {
        "ok": not errors,
        "path": str(path),
        "sessionDir": str(recording["sessionDir"]),
        "metadataPath": str(recording["metadataPath"]),
        "metadataJsonPath": str(recording["metadataJsonPath"]) if recording["metadataJsonPath"] else None,
        "sessionPath": str(recording["sessionAliasPath"]) if recording["sessionAliasPath"] else None,
        "metadataSessionAliasComplete": metadata_session_alias_complete,
        "metadataSessionAliasMatches": metadata_session_alias_matches,
        "declaredPaths": declared_paths,
        "eventsPath": str(recording["eventsPath"]),
        "fixtureManifestPath": str(recording["manifestPath"]) if recording["manifestPath"] else None,
        "mcpTranscriptPath": str(recording["mcpTranscriptPath"]) if recording["mcpTranscriptPath"] else None,
        "source": manifest.get("source") if isinstance(manifest, dict) else None,
        "officialPluginVersion": manifest.get("officialPluginVersion") if isinstance(manifest, dict) else None,
        "state": state,
        "endReason": metadata.get("endReason"),
        "endReasons": dict(sorted(end_reason_counts.items())),
        "eventCount": len(events),
        "metadataEventCount": metadata_event_count,
        "metadataEventCountMatches": metadata_event_count_matches,
        "firstEventType": first_event_type,
        "lastEventType": last_event_type,
        "sessionStartedCount": len(started_events),
        "sessionStartedIsFirst": first_event_type == "session.started" if first_event_type is not None else None,
        "sessionEndedCount": len(ended_events),
        "sessionEndedIsFinal": last_event_type == "session.ended" if last_event_type is not None else None,
        "eventTypes": dict(sorted(event_type_counts.items())),
        "actionEventCount": action_event_count,
        "hasAccessibilityPayload": bool(payloads),
        "hasFullAXPayload": has_full_ax_payload,
        "hasFullTreePayload": has_full_tree_payload,
        "hasDiffAXPayload": has_diff_ax_payload,
        "hasCumulativeAXDiff": has_cumulative_ax_diff,
        "mcpToolResponses": mcp_evidence,
        "mcpResponseShapes": mcp_shape_evidence,
        "suppressedEventCount": len(recording["suppressed"]),
        "metadataSuppressedEventCount": metadata_suppressed_event_count,
        "metadataSuppressedEventCountMatches": metadata_suppressed_event_count_matches,
        "suppressedEventTypes": dict(sorted(suppressed_event_type_counts.items())),
        "warnings": warnings,
        "errors": errors,
        "recommendation": recommendation,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check whether Record & Replay recordings are rich enough to use as golden baselines."
    )
    parser.add_argument("paths", nargs="+", type=pathlib.Path, help="Recording directories, metadata.json, or session.json files")
    parser.add_argument("--require-fixture-manifest", action="store_true", help="Require fixture-manifest.json next to the recording files.")
    parser.add_argument("--require-source", choices=["official", "ocu"], help="Require fixture-manifest.json source to match.")
    parser.add_argument("--require-official-plugin-version", help="Require an exact fixture-manifest officialPluginVersion value.")
    parser.add_argument("--require-event-type", action="append", default=[], help="Require at least one event of this type. May be repeated.")
    parser.add_argument(
        "--require-session-alias",
        action="store_true",
        help="Require both metadata.json and session.json, and require them to be compatible.",
    )
    parser.add_argument(
        "--require-metadata-counts",
        action="store_true",
        help="Require metadata eventCount and suppressedEventCount fields to be present and match file line counts.",
    )
    parser.add_argument(
        "--require-handoff-paths",
        action="store_true",
        help="Require metadataPath, eventsPath, sessionPath, and suppressedEventsPath to resolve to existing files.",
    )
    parser.add_argument(
        "--require-end-reason",
        action="append",
        default=[],
        help="Require an endReason value in metadata.json/session.json or session.ended. May be repeated.",
    )
    parser.add_argument("--require-suppressed-events", action="store_true", help="Require at least one suppressed event in suppressed.jsonl.")
    parser.add_argument("--require-suppressed-event-type", action="append", default=[], help="Require at least one suppressed event of this type. May be repeated.")
    parser.add_argument("--require-mcp-transcript", action="store_true", help="Require mcp-transcript.json next to the fixture files.")
    parser.add_argument(
        "--require-mcp-tool-response",
        action="append",
        default=[],
        choices=["event_stream_start", "event_stream_status", "event_stream_stop"],
        help="Require result/error response evidence for a Record & Replay MCP tool. May be repeated.",
    )
    parser.add_argument(
        "--require-mcp-response-shape",
        action="append",
        default=[],
        choices=sorted(MCP_RESPONSE_SHAPES),
        help=(
            "Require result/error evidence for a specific probe response shape, such as "
            "repeatStartResponseShape or finalStatusResponseShape. May be repeated."
        ),
    )
    parser.add_argument("--allow-no-action", action="store_true", help="Allow lifecycle/status fixtures without user action events.")
    parser.add_argument("--allow-no-ax-payload", action="store_true", help="Allow fixtures without AX payloads.")
    parser.add_argument("--allow-no-session-ended", action="store_true", help="Allow final-state samples without a session.ended event.")
    parser.add_argument("--require-full-ax-payload", action="store_true", help="Require at least one full AX payload.")
    parser.add_argument("--require-diff-payload", action="store_true", help="Require at least one diff AX payload.")
    parser.add_argument("--require-cumulative-diff", action="store_true", help="Require at least one cumulative AX diff payload.")
    args = parser.parse_args()

    recordings = [check_recording(path, args) for path in args.paths]
    result = {
        "ok": all(recording["ok"] for recording in recordings),
        "recordings": recordings,
    }
    output = json.dumps(result, indent=2, sort_keys=True)
    if result["ok"]:
        print(output)
        return 0
    print(output, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
