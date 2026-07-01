#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys
from collections import Counter, defaultdict


SEMANTIC_SCHEMA_PATHS_BY_EVENT_TYPE = {
    "AX.focusedWindowChanged": {
        "accessibilityInspectorPayload",
        "accessibilityInspectorPayload.kind",
        "accessibilityInspectorPayload.renderedText",
        "accessibilityInspectorPayload.fullTree",
        "accessibilityInspectorPayload.fullTree[]",
        "accessibilityInspectorPayload.treeLines",
        "accessibilityInspectorPayload.treeLines[]",
        "accessibilityInspectorPayload.diffFromPrevious",
        "accessibilityInspectorPayload.cumulativeDiffFromInitial",
        "accessibilityInspectorPayload.cumulativeRenderedText",
        "accessibilityInspectorPayload.cumulativeTreeLines",
        "accessibilityInspectorPayload.cumulativeTreeLines[]",
        "accessibilityInspectorPayload.screenshotNeededForContext",
        "accessibilityInspectorPayload.screenshotPath",
    },
    "keyboard.shortcut": {
        "focusedAccessibilityElement",
        "focusedAccessibilityElement.role",
        "focusedAccessibilityElement.title",
        "focusedAccessibilityElement.label",
        "key",
        "modifiers",
    },
    "keyboard.submit": {
        "focusedAccessibilityElement",
        "focusedAccessibilityElement.role",
        "focusedAccessibilityElement.title",
        "focusedAccessibilityElement.label",
        "key",
        "modifiers",
    },
    "keyboard.text_input": {
        "focusedAccessibilityElement",
        "focusedAccessibilityElement.role",
        "focusedAccessibilityElement.title",
        "focusedAccessibilityElement.label",
        "secureInput",
        "text",
        "textLength",
    },
    "mouse.click": {
        "button",
        "location",
        "location.x",
        "location.y",
        "targetAccessibilityElement",
        "targetAccessibilityElement.role",
        "targetAccessibilityElement.title",
        "targetAccessibilityElement.label",
        "targetAccessibilityElement.actions",
        "targetAccessibilityElement.actions[]",
    },
    "mouse.context_menu": {
        "button",
        "location",
        "location.x",
        "location.y",
        "targetAccessibilityElement",
        "targetAccessibilityElement.role",
        "targetAccessibilityElement.title",
        "targetAccessibilityElement.label",
        "targetAccessibilityElement.actions",
        "targetAccessibilityElement.actions[]",
    },
    "mouse.drag": {
        "button",
        "distance",
        "durationSeconds",
        "endLocation",
        "endLocation.x",
        "endLocation.y",
        "startLocation",
        "startLocation.x",
        "startLocation.y",
        "targetAccessibilityElement",
        "targetAccessibilityElement.role",
        "targetAccessibilityElement.title",
        "targetAccessibilityElement.label",
    },
    "selection.changed": {
        "focusedAccessibilityElement",
        "focusedAccessibilityElement.role",
        "focusedAccessibilityElement.title",
        "focusedAccessibilityElement.label",
        "selectedText",
        "selectedTextLength",
        "selectionCleared",
    },
    "terminal.value_changed": {
        "focusedAccessibilityElement",
        "focusedAccessibilityElement.role",
        "focusedAccessibilityElement.title",
        "focusedAccessibilityElement.label",
        "valueHash",
        "valueLength",
    },
    "window.changed": {
        "app",
        "app.bundleIdentifier",
        "app.name",
        "window",
        "window.title",
    },
}

STABLE_METADATA_VALUE_KEYS = [
    "active",
    "endReason",
    "eventCount",
    "state",
    "suppressedEventCount",
]

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


def resolve_path(base, raw, fallback):
    if isinstance(raw, str) and raw:
        candidate = pathlib.Path(raw)
        if candidate.is_absolute():
            return candidate
        return base / candidate
    return fallback


def handoff_path_evidence(session_dir, metadata):
    evidence = {}
    for key in HANDOFF_PATH_KEYS:
        raw = metadata.get(key)
        entry = {
            "value": raw,
            "resolvedPath": None,
            "exists": None,
        }
        if isinstance(raw, str) and raw:
            path = pathlib.Path(raw)
            resolved_path = path if path.is_absolute() else session_dir / path
            entry["resolvedPath"] = str(resolved_path)
            entry["exists"] = resolved_path.exists()
        evidence[key] = entry
    return evidence


def handoff_path_errors(baseline_evidence, candidate_evidence):
    errors = []
    for key in HANDOFF_PATH_KEYS:
        baseline_entry = baseline_evidence.get(key, {})
        candidate_entry = candidate_evidence.get(key, {})
        baseline_value = baseline_entry.get("value")
        candidate_value = candidate_entry.get("value")
        if not isinstance(baseline_value, str) or not baseline_value:
            errors.append(f"baseline missing declared handoff path: {key}")
        elif baseline_entry.get("exists") is False:
            errors.append(f"baseline declared handoff path does not exist: {key}")
        if not isinstance(candidate_value, str) or not candidate_value:
            errors.append(f"candidate missing declared handoff path: {key}")
        elif candidate_entry.get("exists") is False:
            errors.append(f"candidate declared handoff path does not exist: {key}")
    return errors


def resolve_recording(path):
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
        transcript_path = resolve_mcp_transcript_path(path)
        suppressed_path = resolve_path(path, metadata.get("suppressedEventsPath"), path / "suppressed.jsonl")
        return {
            "sessionDir": path,
            "metadataPath": metadata_path,
            "metadata": metadata,
            "eventsPath": events_path,
            "events": read_jsonl(events_path),
            "suppressedPath": suppressed_path,
            "suppressed": read_jsonl(suppressed_path) if suppressed_path.exists() else [],
            "mcpTranscriptPath": transcript_path,
            "mcpTranscript": load_json(transcript_path) if transcript_path else None,
        }

    if not path.exists():
        raise ValueError(f"path does not exist: {path}")
    if path.name == "events.jsonl":
        return {
            "sessionDir": path.parent,
            "metadataPath": None,
            "metadata": {},
            "eventsPath": path,
            "events": read_jsonl(path),
            "suppressedPath": path.parent / "suppressed.jsonl",
            "suppressed": read_jsonl(path.parent / "suppressed.jsonl") if (path.parent / "suppressed.jsonl").exists() else [],
            "mcpTranscriptPath": None,
            "mcpTranscript": None,
        }
    if path.name not in {"metadata.json", "session.json"}:
        raise ValueError("input must be a session directory, metadata.json, session.json, or events.jsonl")
    metadata = load_json(path)
    session_dir = path.parent
    events_path = resolve_path(session_dir, metadata.get("eventsPath"), session_dir / "events.jsonl")
    suppressed_path = resolve_path(session_dir, metadata.get("suppressedEventsPath"), session_dir / "suppressed.jsonl")
    return {
        "sessionDir": session_dir,
        "metadataPath": path,
        "metadata": metadata,
        "eventsPath": events_path,
        "events": read_jsonl(events_path),
        "suppressedPath": suppressed_path,
        "suppressed": read_jsonl(suppressed_path) if suppressed_path.exists() else [],
        "mcpTranscriptPath": resolve_mcp_transcript_path(session_dir),
        "mcpTranscript": (
            load_json(resolve_mcp_transcript_path(session_dir))
            if resolve_mcp_transcript_path(session_dir)
            else None
        ),
    }


def resolve_mcp_transcript_path(session_dir):
    manifest_path = session_dir / "fixture-manifest.json"
    if manifest_path.exists():
        manifest = load_json(manifest_path)
        files = manifest.get("files")
        if isinstance(files, dict) and isinstance(files.get("mcpTranscript"), str):
            candidate = resolve_path(session_dir, files["mcpTranscript"], session_dir / "mcp-transcript.json")
            if candidate.exists():
                return candidate
    candidate = session_dir / "mcp-transcript.json"
    if candidate.exists():
        return candidate
    return None


def type_name(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int) and not isinstance(value, bool):
        return "int"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def collect_schema(value, prefix=""):
    paths = {}
    paths[prefix or "$"] = type_name(value)
    if isinstance(value, dict):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else key
            paths.update(collect_schema(child, child_prefix))
    elif isinstance(value, list):
        if value:
            item_types = sorted({type_name(item) for item in value})
            paths[f"{prefix}[]"] = "|".join(item_types)
            for item in value:
                if isinstance(item, (dict, list)):
                    paths.update(collect_schema(item, f"{prefix}[]"))
        else:
            paths[f"{prefix}[]"] = "empty"
    return paths


def schema_by_event_type(events):
    by_type = defaultdict(dict)
    for event in events:
        event_type = event_kind(event)
        if not isinstance(event_type, str):
            event_type = "<missing-type>"
        for path, kind in collect_schema(event).items():
            kinds = by_type[event_type].setdefault(path, set())
            kinds.add(kind)
    return {
        event_type: {
            path: sorted(kinds)
            for path, kinds in sorted(paths.items())
        }
        for event_type, paths in sorted(by_type.items())
    }


def diff_schema(baseline_schema, candidate_schema):
    diff = {}
    event_types = sorted(set(baseline_schema) | set(candidate_schema))
    for event_type in event_types:
        baseline_paths = baseline_schema.get(event_type, {})
        candidate_paths = candidate_schema.get(event_type, {})
        missing_paths = sorted(set(baseline_paths) - set(candidate_paths))
        extra_paths = sorted(set(candidate_paths) - set(baseline_paths))
        changed_types = []
        for path in sorted(set(baseline_paths) & set(candidate_paths)):
            if baseline_paths[path] != candidate_paths[path]:
                changed_types.append({
                    "path": path,
                    "baseline": baseline_paths[path],
                    "candidate": candidate_paths[path],
                })
        if missing_paths or extra_paths or changed_types:
            diff[event_type] = {
                "missingPaths": missing_paths,
                "extraPaths": extra_paths,
                "changedTypes": changed_types,
            }
    return diff


def mcp_response_shape_evidence(transcript):
    evidence = {}
    if not isinstance(transcript, dict):
        return evidence
    for raw_key, tool_name in {
        **MCP_RESPONSE_SHAPES,
        **{alias: MCP_RESPONSE_SHAPES[shape] for alias, shape in MCP_RESPONSE_SHAPE_ALIASES.items()},
    }.items():
        response = transcript.get(raw_key)
        if not isinstance(response, dict):
            continue
        shape_key = MCP_RESPONSE_SHAPE_ALIASES.get(raw_key, raw_key)
        evidence[shape_key] = {
            "toolName": tool_name,
            "hasResult": "result" in response,
            "hasError": "error" in response,
            "timedOut": "timeout" in response,
            "schema": collect_schema(response),
        }
    return evidence


def mcp_response_shape_errors(baseline_evidence, candidate_evidence, require_same_schema):
    errors = []
    for shape_key in sorted(baseline_evidence):
        baseline_shape = baseline_evidence[shape_key]
        candidate_shape = candidate_evidence.get(shape_key)
        if candidate_shape is None:
            errors.append(f"candidate missing MCP response shape: {shape_key}")
            continue
        for flag in ["hasResult", "hasError", "timedOut"]:
            if baseline_shape.get(flag) != candidate_shape.get(flag):
                errors.append(
                    f"candidate MCP response shape {shape_key} {flag} differs "
                    f"(baseline={baseline_shape.get(flag)}, candidate={candidate_shape.get(flag)})"
                )
        if require_same_schema:
            baseline_schema = baseline_shape.get("schema", {})
            candidate_schema = candidate_shape.get("schema", {})
            missing_paths = sorted(set(baseline_schema) - set(candidate_schema))
            changed_types = [
                {
                    "path": path,
                    "baseline": baseline_schema[path],
                    "candidate": candidate_schema[path],
                }
                for path in sorted(set(baseline_schema) & set(candidate_schema))
                if baseline_schema[path] != candidate_schema[path]
            ]
            if missing_paths:
                errors.append(
                    f"candidate MCP response shape {shape_key} missing schema paths: {','.join(missing_paths)}"
                )
            if changed_types:
                changed_paths = ",".join(change["path"] for change in changed_types)
                errors.append(
                    f"candidate MCP response shape {shape_key} changed schema types: {changed_paths}"
                )
    return errors


def semantic_field_evidence(events):
    schemas = schema_by_event_type(events)
    evidence = {}
    for event_type, required_paths in sorted(SEMANTIC_SCHEMA_PATHS_BY_EVENT_TYPE.items()):
        event_schema = schemas.get(event_type, {})
        present_paths = sorted(set(event_schema) & required_paths)
        if present_paths or event_type in schemas:
            evidence[event_type] = {
                "eventCount": sum(1 for event in events if event_kind(event) == event_type),
                "presentPaths": present_paths,
            }
    return evidence


def semantic_field_errors(baseline_evidence, candidate_evidence):
    errors = []
    for event_type in sorted(baseline_evidence):
        baseline_paths = set(baseline_evidence[event_type].get("presentPaths", []))
        if not baseline_paths:
            continue
        candidate_paths = set(candidate_evidence.get(event_type, {}).get("presentPaths", []))
        missing_paths = sorted(baseline_paths - candidate_paths)
        if missing_paths:
            errors.append(
                f"candidate missing semantic fields for {event_type}: {','.join(missing_paths)}"
            )
    return errors


def metadata_key_diff(baseline_metadata, candidate_metadata):
    baseline_keys = set(baseline_metadata.keys())
    candidate_keys = set(candidate_metadata.keys())
    return {
        "missingKeys": sorted(baseline_keys - candidate_keys),
        "extraKeys": sorted(candidate_keys - baseline_keys),
    }


def metadata_value_diff(baseline_metadata, candidate_metadata):
    changed_values = []
    missing_keys = []
    checked_keys = []
    for key in STABLE_METADATA_VALUE_KEYS:
        if key not in baseline_metadata:
            continue
        checked_keys.append(key)
        if key not in candidate_metadata:
            missing_keys.append(key)
            continue
        if baseline_metadata[key] != candidate_metadata[key]:
            changed_values.append({
                "key": key,
                "baseline": baseline_metadata[key],
                "candidate": candidate_metadata[key],
            })
    return {
        "checkedKeys": checked_keys,
        "missingKeys": missing_keys,
        "changedValues": changed_values,
    }


def lifecycle_session_evidence(events):
    started_indexes = [
        index
        for index, event in enumerate(events)
        if event_kind(event) == "session.started"
    ]
    ended_indexes = [
        index
        for index, event in enumerate(events)
        if event_kind(event) == "session.ended"
    ]
    end_reasons = sorted({
        event.get("endReason")
        for event in events
        if event_kind(event) == "session.ended"
        and isinstance(event.get("endReason"), str)
    })
    first_event_type = event_kind(events[0]) if events else None
    last_event_type = event_kind(events[-1]) if events else None
    return {
        "eventCount": len(events),
        "sessionStartedCount": len(started_indexes),
        "sessionStartedIndexes": started_indexes,
        "firstEventType": first_event_type,
        "hasInitialSessionStarted": first_event_type == "session.started",
        "sessionEndedCount": len(ended_indexes),
        "sessionEndedIndexes": ended_indexes,
        "lastEventType": last_event_type,
        "hasFinalSessionEnded": last_event_type == "session.ended",
        "endReasons": end_reasons,
    }


def lifecycle_session_evidence_errors(baseline_evidence, candidate_evidence):
    errors = []
    if baseline_evidence["sessionStartedCount"] != candidate_evidence["sessionStartedCount"]:
        errors.append(
            "session.started count differs "
            f"(baseline={baseline_evidence['sessionStartedCount']}, "
            f"candidate={candidate_evidence['sessionStartedCount']})"
        )
    if baseline_evidence["hasInitialSessionStarted"] and not candidate_evidence["hasInitialSessionStarted"]:
        errors.append("candidate first event is not session.started")
    if baseline_evidence["sessionEndedCount"] != candidate_evidence["sessionEndedCount"]:
        errors.append(
            "session.ended count differs "
            f"(baseline={baseline_evidence['sessionEndedCount']}, "
            f"candidate={candidate_evidence['sessionEndedCount']})"
        )
    if baseline_evidence["hasFinalSessionEnded"] and not candidate_evidence["hasFinalSessionEnded"]:
        errors.append("candidate final event is not session.ended")
    baseline_reasons = set(baseline_evidence["endReasons"])
    candidate_reasons = set(candidate_evidence["endReasons"])
    missing_reasons = sorted(baseline_reasons - candidate_reasons)
    extra_reasons = sorted(candidate_reasons - baseline_reasons)
    if missing_reasons:
        errors.append(f"candidate missing session.ended endReason: {','.join(missing_reasons)}")
    if extra_reasons:
        errors.append(f"candidate has extra session.ended endReason: {','.join(extra_reasons)}")
    return errors


def first_sequence_difference(baseline, candidate):
    max_len = max(len(baseline), len(candidate))
    for index in range(max_len):
        baseline_value = baseline[index] if index < len(baseline) else None
        candidate_value = candidate[index] if index < len(candidate) else None
        if baseline_value != candidate_value:
            return {
                "index": index,
                "baseline": baseline_value,
                "candidate": candidate_value,
            }
    return None


def event_type_sequence(events):
    return [
        event_kind(event) or "<missing-type>"
        for event in events
    ]


def event_type_count_diff(baseline_sequence, candidate_sequence):
    baseline_counts = Counter(type_ for type_ in baseline_sequence if isinstance(type_, str))
    candidate_counts = Counter(type_ for type_ in candidate_sequence if isinstance(type_, str))
    return {
        event_type: {
            "baseline": baseline_counts[event_type],
            "candidate": candidate_counts[event_type],
        }
        for event_type in sorted(set(baseline_counts) | set(candidate_counts))
        if baseline_counts[event_type] != candidate_counts[event_type]
    }


def prune_extra_schema(schema_diff):
    return {
        event_type: {
            "missingPaths": details["missingPaths"],
            "extraPaths": [],
            "changedTypes": details["changedTypes"],
        }
        for event_type, details in schema_diff.items()
        if details["missingPaths"] or details["changedTypes"]
    }


def iter_dicts(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from iter_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_dicts(child)


def accessibility_payloads(events):
    payloads = []
    seen_ids = set()
    for event in events:
        for value in iter_dicts(event):
            payload = value.get("accessibilityInspectorPayload")
            if isinstance(payload, dict) and id(payload) not in seen_ids:
                payloads.append(payload)
                seen_ids.add(id(payload))
            official_ax_payload = value.get("ax")
            if isinstance(official_ax_payload, dict) and id(official_ax_payload) not in seen_ids:
                payloads.append(official_ax_payload)
                seen_ids.add(id(official_ax_payload))
        if event_kind(event) == "AX.focusedWindowChanged":
            payload = event.get("accessibilityInspectorPayload")
            if isinstance(payload, dict) and id(payload) not in seen_ids:
                payloads.append(payload)
                seen_ids.add(id(payload))
            official_ax_payload = event.get("ax")
            if isinstance(official_ax_payload, dict) and id(official_ax_payload) not in seen_ids:
                payloads.append(official_ax_payload)
                seen_ids.add(id(official_ax_payload))
    return payloads


def is_full_ax_payload(payload):
    return (
        payload.get("kind") == "full"
        or payload.get("mode") in {"full", "fullTree"}
        or payload.get("diffFromPrevious") is False
        or isinstance(payload.get("fullTree"), (list, str))
    )


def is_full_tree_payload(payload):
    return (
        isinstance(payload.get("fullTree"), (list, str)) and bool(payload.get("fullTree"))
    ) or payload.get("mode") == "fullTree"


def diff_markers(lines):
    markers = []
    for line in lines:
        if not isinstance(line, str):
            continue
        stripped = line.lstrip()
        if stripped.startswith(("+", "-", "~")):
            markers.append(stripped[0])
    return sorted(set(markers))


def ax_diff_evidence(events):
    payloads = accessibility_payloads(events)
    diff_payloads = [
        payload
        for payload in payloads
        if payload.get("kind") == "diff" or payload.get("diffFromPrevious") is True
    ]
    cumulative_payloads = [
        payload
        for payload in payloads
        if payload.get("cumulativeDiffFromInitial") is True
        or isinstance(payload.get("cumulativeRenderedText"), str)
    ]
    diff_marker_set = set()
    cumulative_marker_set = set()
    for payload in diff_payloads:
        tree_lines = payload.get("treeLines")
        if isinstance(tree_lines, list):
            diff_marker_set.update(diff_markers(tree_lines))
    for payload in cumulative_payloads:
        tree_lines = payload.get("cumulativeTreeLines")
        if isinstance(tree_lines, list):
            cumulative_marker_set.update(diff_markers(tree_lines))

    return {
        "payloadCount": len(payloads),
        "hasFullPayload": any(
            is_full_ax_payload(payload)
            for payload in payloads
        ),
        "hasFullTree": any(
            is_full_tree_payload(payload)
            for payload in payloads
        ),
        "hasDiffPayload": bool(diff_payloads),
        "hasCumulativeDiff": bool(cumulative_payloads),
        "diffMarkers": sorted(diff_marker_set),
        "cumulativeDiffMarkers": sorted(cumulative_marker_set),
    }


def ax_diff_evidence_errors(baseline_evidence, candidate_evidence, require_same_markers):
    errors = []
    if baseline_evidence["hasDiffPayload"] and not candidate_evidence["hasDiffPayload"]:
        errors.append("candidate missing AX diff payload")
    if baseline_evidence["hasCumulativeDiff"] and not candidate_evidence["hasCumulativeDiff"]:
        errors.append("candidate missing cumulative AX diff payload")

    baseline_diff_markers = set(baseline_evidence["diffMarkers"])
    candidate_diff_markers = set(candidate_evidence["diffMarkers"])
    missing_diff_markers = sorted(baseline_diff_markers - candidate_diff_markers)
    extra_diff_markers = sorted(candidate_diff_markers - baseline_diff_markers)
    if missing_diff_markers:
        errors.append(f"candidate missing AX diff markers: {','.join(missing_diff_markers)}")
    if require_same_markers and extra_diff_markers:
        errors.append(f"candidate has extra AX diff markers: {','.join(extra_diff_markers)}")

    baseline_cumulative_markers = set(baseline_evidence["cumulativeDiffMarkers"])
    candidate_cumulative_markers = set(candidate_evidence["cumulativeDiffMarkers"])
    missing_cumulative_markers = sorted(baseline_cumulative_markers - candidate_cumulative_markers)
    extra_cumulative_markers = sorted(candidate_cumulative_markers - baseline_cumulative_markers)
    if missing_cumulative_markers:
        errors.append(f"candidate missing cumulative AX diff markers: {','.join(missing_cumulative_markers)}")
    if require_same_markers and extra_cumulative_markers:
        errors.append(f"candidate has extra cumulative AX diff markers: {','.join(extra_cumulative_markers)}")

    return errors


def compare(baseline_path, candidate_path, ignore_extra_schema):
    baseline = resolve_recording(baseline_path)
    candidate = resolve_recording(candidate_path)

    baseline_sequence = event_type_sequence(baseline["events"])
    candidate_sequence = event_type_sequence(candidate["events"])
    baseline_counts = Counter(type_ for type_ in baseline_sequence if isinstance(type_, str))
    candidate_counts = Counter(type_ for type_ in candidate_sequence if isinstance(type_, str))
    baseline_suppressed_sequence = event_type_sequence(baseline["suppressed"])
    candidate_suppressed_sequence = event_type_sequence(candidate["suppressed"])

    baseline_schema = schema_by_event_type(baseline["events"])
    candidate_schema = schema_by_event_type(candidate["events"])
    baseline_suppressed_schema = schema_by_event_type(baseline["suppressed"])
    candidate_suppressed_schema = schema_by_event_type(candidate["suppressed"])
    baseline_semantic_evidence = semantic_field_evidence(baseline["events"])
    candidate_semantic_evidence = semantic_field_evidence(candidate["events"])
    schema_diff = diff_schema(baseline_schema, candidate_schema)
    suppressed_schema_diff = diff_schema(baseline_suppressed_schema, candidate_suppressed_schema)
    if ignore_extra_schema:
        schema_diff = prune_extra_schema(schema_diff)
        suppressed_schema_diff = prune_extra_schema(suppressed_schema_diff)

    missing_event_types = sorted(set(baseline_counts) - set(candidate_counts))
    extra_event_types = sorted(set(candidate_counts) - set(baseline_counts))
    count_differences = {
        event_type: {
            "baseline": baseline_counts[event_type],
            "candidate": candidate_counts[event_type],
        }
        for event_type in sorted(set(baseline_counts) | set(candidate_counts))
        if baseline_counts[event_type] != candidate_counts[event_type]
    }
    suppressed_count_differences = event_type_count_diff(
        baseline_suppressed_sequence,
        candidate_suppressed_sequence,
    )
    baseline_ax_diff_evidence = ax_diff_evidence(baseline["events"])
    candidate_ax_diff_evidence = ax_diff_evidence(candidate["events"])
    baseline_final_session_evidence = lifecycle_session_evidence(baseline["events"])
    candidate_final_session_evidence = lifecycle_session_evidence(candidate["events"])
    baseline_mcp_response_shape_evidence = mcp_response_shape_evidence(baseline["mcpTranscript"])
    candidate_mcp_response_shape_evidence = mcp_response_shape_evidence(candidate["mcpTranscript"])
    metadata_diff = metadata_key_diff(baseline["metadata"], candidate["metadata"])
    metadata_value_drift = metadata_value_diff(baseline["metadata"], candidate["metadata"])
    baseline_handoff_path_evidence = handoff_path_evidence(baseline["sessionDir"], baseline["metadata"])
    candidate_handoff_path_evidence = handoff_path_evidence(candidate["sessionDir"], candidate["metadata"])

    return {
        "baseline": {
            "sessionDir": str(baseline["sessionDir"]),
            "metadataPath": str(baseline["metadataPath"]) if baseline["metadataPath"] else None,
            "eventsPath": str(baseline["eventsPath"]),
            "suppressedPath": str(baseline["suppressedPath"]),
            "mcpTranscriptPath": str(baseline["mcpTranscriptPath"]) if baseline["mcpTranscriptPath"] else None,
            "eventCount": len(baseline["events"]),
            "suppressedEventCount": len(baseline["suppressed"]),
            "metadataKeys": sorted(baseline["metadata"].keys()),
        },
        "candidate": {
            "sessionDir": str(candidate["sessionDir"]),
            "metadataPath": str(candidate["metadataPath"]) if candidate["metadataPath"] else None,
            "eventsPath": str(candidate["eventsPath"]),
            "suppressedPath": str(candidate["suppressedPath"]),
            "mcpTranscriptPath": str(candidate["mcpTranscriptPath"]) if candidate["mcpTranscriptPath"] else None,
            "eventCount": len(candidate["events"]),
            "suppressedEventCount": len(candidate["suppressed"]),
            "metadataKeys": sorted(candidate["metadata"].keys()),
        },
        "eventSequenceEqual": baseline_sequence == candidate_sequence,
        "firstEventSequenceDifference": first_sequence_difference(baseline_sequence, candidate_sequence),
        "missingEventTypes": missing_event_types,
        "extraEventTypes": extra_event_types,
        "eventCountDifferences": count_differences,
        "suppressedEventSequenceEqual": baseline_suppressed_sequence == candidate_suppressed_sequence,
        "firstSuppressedEventSequenceDifference": first_sequence_difference(
            baseline_suppressed_sequence,
            candidate_suppressed_sequence,
        ),
        "suppressedEventCountDifferences": suppressed_count_differences,
        "metadataKeysEqual": not metadata_diff["missingKeys"] and not metadata_diff["extraKeys"],
        "metadataKeyDiff": metadata_diff,
        "metadataStableValuesEqual": (
            not metadata_value_drift["missingKeys"]
            and not metadata_value_drift["changedValues"]
        ),
        "metadataValueDiff": metadata_value_drift,
        "handoffPathEvidence": {
            "baseline": baseline_handoff_path_evidence,
            "candidate": candidate_handoff_path_evidence,
        },
        "schemaEqual": not schema_diff,
        "schemaDiff": schema_diff,
        "suppressedSchemaEqual": not suppressed_schema_diff,
        "suppressedSchemaDiff": suppressed_schema_diff,
        "semanticFieldEvidence": {
            "baseline": baseline_semantic_evidence,
            "candidate": candidate_semantic_evidence,
        },
        "axDiffEvidence": {
            "baseline": baseline_ax_diff_evidence,
            "candidate": candidate_ax_diff_evidence,
        },
        "finalSessionEvidence": {
            "baseline": baseline_final_session_evidence,
            "candidate": candidate_final_session_evidence,
        },
        "mcpResponseShapeEvidence": {
            "baseline": baseline_mcp_response_shape_evidence,
            "candidate": candidate_mcp_response_shape_evidence,
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Compare two Record & Replay recording event streams by sequence, JSON schema, and AX diff evidence."
    )
    parser.add_argument("baseline", type=pathlib.Path, help="Official/golden recording directory or metadata/events file.")
    parser.add_argument("candidate", type=pathlib.Path, help="Candidate OCU recording directory or metadata/events file.")
    parser.add_argument(
        "--require-same-event-sequence",
        action="store_true",
        help="Exit non-zero when event type sequences differ.",
    )
    parser.add_argument(
        "--require-same-schema",
        action="store_true",
        help="Exit non-zero when per-event JSON schema paths or value types differ.",
    )
    parser.add_argument(
        "--require-same-suppressed-event-sequence",
        action="store_true",
        help="Exit non-zero when suppressed.jsonl event type sequences differ.",
    )
    parser.add_argument(
        "--require-same-suppressed-schema",
        action="store_true",
        help="Exit non-zero when suppressed.jsonl JSON schema paths or value types differ.",
    )
    parser.add_argument(
        "--require-same-metadata-keys",
        action="store_true",
        help="Exit non-zero when metadata key sets differ.",
    )
    parser.add_argument(
        "--require-same-metadata-values",
        action="store_true",
        help="Exit non-zero when stable metadata values differ.",
    )
    parser.add_argument(
        "--ignore-extra-schema",
        action="store_true",
        help="Only fail/report schema paths missing from candidate or changed in type; ignore candidate-only fields.",
    )
    parser.add_argument(
        "--require-ax-diff-evidence",
        action="store_true",
        help="Fail when the baseline has AX diff/cumulative evidence that the candidate is missing.",
    )
    parser.add_argument(
        "--require-semantic-fields",
        action="store_true",
        help="Fail when the candidate is missing replay-critical semantic fields present in the baseline.",
    )
    parser.add_argument(
        "--require-final-session-evidence",
        action="store_true",
        help="Fail when candidate final session.ended evidence differs from the baseline.",
    )
    parser.add_argument(
        "--require-same-ax-diff-markers",
        action="store_true",
        help="With --require-ax-diff-evidence, also fail when candidate has extra AX diff marker types.",
    )
    parser.add_argument(
        "--require-mcp-response-shapes",
        action="store_true",
        help=(
            "Fail when baseline mcp-transcript.json has start/status/stop response shapes "
            "that the candidate transcript is missing or changes from result/error/timeout."
        ),
    )
    parser.add_argument(
        "--require-same-mcp-response-schema",
        action="store_true",
        help="With --require-mcp-response-shapes, also require candidate response shape schemas to keep baseline paths and types.",
    )
    parser.add_argument(
        "--require-handoff-paths",
        action="store_true",
        help="Fail unless both recordings declare metadataPath, sessionPath, eventsPath, and suppressedEventsPath that resolve to existing files.",
    )
    args = parser.parse_args()

    try:
        result = compare(args.baseline, args.candidate, args.ignore_extra_schema)
    except ValueError as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}, indent=2, sort_keys=True), file=sys.stderr)
        return 1

    errors = []
    if args.require_same_event_sequence and not result["eventSequenceEqual"]:
        errors.append("event type sequence differs")
    if args.require_same_schema and not result["schemaEqual"]:
        errors.append("event schema differs")
    if args.require_same_suppressed_event_sequence and not result["suppressedEventSequenceEqual"]:
        errors.append("suppressed event type sequence differs")
    if args.require_same_suppressed_schema and not result["suppressedSchemaEqual"]:
        errors.append("suppressed event schema differs")
    if args.require_same_metadata_keys and not result["metadataKeysEqual"]:
        errors.append("metadata keys differ")
    if args.require_same_metadata_values and not result["metadataStableValuesEqual"]:
        errors.append("stable metadata values differ")
    if args.require_ax_diff_evidence:
        errors.extend(
            ax_diff_evidence_errors(
                result["axDiffEvidence"]["baseline"],
                result["axDiffEvidence"]["candidate"],
                args.require_same_ax_diff_markers,
            )
        )
    if args.require_semantic_fields:
        errors.extend(
            semantic_field_errors(
                result["semanticFieldEvidence"]["baseline"],
                result["semanticFieldEvidence"]["candidate"],
            )
        )
    if args.require_final_session_evidence:
        errors.extend(
            lifecycle_session_evidence_errors(
                result["finalSessionEvidence"]["baseline"],
                result["finalSessionEvidence"]["candidate"],
            )
        )
    if args.require_mcp_response_shapes:
        errors.extend(
            mcp_response_shape_errors(
                result["mcpResponseShapeEvidence"]["baseline"],
                result["mcpResponseShapeEvidence"]["candidate"],
                args.require_same_mcp_response_schema,
            )
        )
    if args.require_handoff_paths:
        errors.extend(
            handoff_path_errors(
                result["handoffPathEvidence"]["baseline"],
                result["handoffPathEvidence"]["candidate"],
            )
        )
    result["ok"] = not errors
    result["errors"] = errors

    output = json.dumps(result, indent=2, sort_keys=True)
    if errors:
        print(output, file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
