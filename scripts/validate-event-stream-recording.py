#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys
from collections import Counter


FINAL_STATES = {"stopped", "cancelled"}
SKILL_DRAFT_ACTION_EVENT_TYPES = {
    "mouse.click",
    "mouse.context_menu",
    "mouse.drag",
    "keyboard.text_input",
    "keyboard.submit",
    "keyboard.shortcut",
    "terminal.value_changed",
    "selection.changed",
}
BLOCKING_DIAGNOSTIC_REASONS = {"inputMonitorsUnavailable"}
HANDOFF_PATH_KEYS = [
    "metadataPath",
    "sessionPath",
    "eventsPath",
    "suppressedEventsPath",
]


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


def resolve_input(path):
    if path.is_dir():
        metadata_path = path / "metadata.json"
        session_path = path / "session.json"
        if metadata_path.exists():
            return path, metadata_path, None
        if session_path.exists():
            return path, session_path, None
        raise ValueError(f"session directory has no metadata.json or session.json: {path}")
    if not path.exists():
        raise ValueError(f"path does not exist: {path}")
    if path.name == "metadata.json":
        return path.parent, path, None
    if path.name == "session.json":
        metadata_path = path.parent / "metadata.json"
        return path.parent, metadata_path if metadata_path.exists() else path, None
    if path.name == "events.jsonl":
        return path.parent, None, path
    raise ValueError("input must be a session directory, metadata.json, session.json, or events.jsonl")


def relative_path(base, raw):
    candidate = pathlib.Path(raw)
    if candidate.is_absolute():
        return candidate
    return base / candidate


def path_from_metadata(value, key, fallback, base):
    raw = value.get(key)
    if isinstance(raw, str) and raw:
        return relative_path(base, raw)
    return fallback


def optional_path_from_metadata(value, key, base):
    raw = value.get(key)
    if isinstance(raw, str) and raw:
        return relative_path(base, raw)
    return None


def declared_handoff_path_evidence(metadata, base):
    evidence = {}
    for key in HANDOFF_PATH_KEYS:
        raw = metadata.get(key)
        entry = {
            "value": raw,
            "resolvedPath": None,
            "exists": None,
        }
        if isinstance(raw, str) and raw:
            resolved = relative_path(base, raw)
            entry["resolvedPath"] = str(resolved)
            entry["exists"] = resolved.exists()
        evidence[key] = entry
    return evidence


def declared_handoff_path_errors(evidence, require_all_paths):
    errors = []
    for key in HANDOFF_PATH_KEYS:
        entry = evidence.get(key, {})
        value = entry.get("value")
        if isinstance(value, str) and value:
            if entry.get("exists") is False:
                errors.append(f"{key} does not exist: {value}")
            continue
        if value is not None and not (isinstance(value, str) and not value):
            errors.append(f"{key} must be a non-empty string")
        elif require_all_paths:
            errors.append(f"strict OCU validation requires {key}")
    return errors


def first_string(value, keys):
    for key in keys:
        candidate = value.get(key)
        if isinstance(candidate, str) and candidate:
            return candidate
    return None


def session_alias_compatible(metadata, session_alias):
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


def collect_screenshot_paths(value):
    paths = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "screenshotPath" and isinstance(child, str) and child:
                paths.append(child)
            else:
                paths.extend(collect_screenshot_paths(child))
    elif isinstance(value, list):
        for child in value:
            paths.extend(collect_screenshot_paths(child))
    return paths


def is_inside_directory(path, directory):
    candidate = path.resolve(strict=False)
    base = directory.resolve(strict=False)
    return candidate == base or base in candidate.parents


def blocking_diagnostics(events):
    diagnostics = []
    for index, event in enumerate(events, start=1):
        if event_kind(event) != "debug.error":
            continue
        if event.get("reason") not in BLOCKING_DIAGNOSTIC_REASONS:
            continue
        diagnostic = {"line": index}
        for key in ["subsystem", "reason", "errorType"]:
            if key in event:
                diagnostic[key] = event[key]
        diagnostics.append(diagnostic)
    return diagnostics


def recording_incomplete(state, active, ended_events):
    if state == "recording" or active is True:
        return True
    return not ended_events


def skill_draft_blocking_reasons(
    event_type_counts,
    state,
    end_reason,
    incomplete,
    blocking_diagnostics,
    session_started_not_first,
    session_started_count_invalid,
    session_ended_not_final,
    session_ended_count_invalid,
):
    has_action = any(event_type_counts[event_type] > 0 for event_type in SKILL_DRAFT_ACTION_EVENT_TYPES)
    recording_was_cancelled = state == "cancelled" or end_reason == "recording_controls_cancelled"
    reasons = []
    if not has_action:
        reasons.append("recording has no high-level user action events")
    if recording_was_cancelled:
        reasons.append("recording was cancelled; do not create or update a skill from this event stream")
    if incomplete:
        reasons.append("recording is not complete; stop the recording before creating a skill")
    if blocking_diagnostics:
        reasons.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    if session_started_count_invalid:
        reasons.append("recording must contain exactly one session.started event before creating a skill")
    if session_started_not_first:
        reasons.append("recording has events before session.started; start must be the first event before creating a skill")
    if session_ended_not_final:
        reasons.append(
            "recording has events after session.ended; stop or cancel must be the final event before creating a skill"
        )
    if session_ended_count_invalid:
        reasons.append(
            "recording has multiple session.ended events; stop or cancel must close the event stream exactly once"
        )
    return reasons


def validate(path, strict_ocu, required_event_types, require_skill_draft=False):
    session_dir, metadata_path, input_events_path = resolve_input(path)
    metadata = load_json(metadata_path) if metadata_path is not None else {}
    warnings = []
    errors = []

    metadata_json_path = session_dir / "metadata.json"
    session_alias_path = session_dir / "session.json"
    if metadata_path is None:
        if strict_ocu:
            errors.append("strict OCU validation requires metadata.json or session.json")
        else:
            warnings.append("metadata/session files not available; validating events.jsonl only")
    elif metadata_json_path.exists() and session_alias_path.exists():
        try:
            metadata_json = load_json(metadata_json_path)
            session_json = load_json(session_alias_path)
            if not session_alias_compatible(metadata_json, session_json):
                errors.append("metadata.json and session.json differ")
        except ValueError as error:
            errors.append(str(error))
    elif strict_ocu:
        errors.append("strict OCU validation requires both metadata.json and session.json")
    else:
        warnings.append("metadata/session alias pair is incomplete")

    declared_paths = declared_handoff_path_evidence(metadata, session_dir)
    errors.extend(declared_handoff_path_errors(declared_paths, strict_ocu))

    state = metadata.get("state")
    current_segment_events_path = optional_path_from_metadata(
        metadata,
        "currentSegmentEventsPath",
        session_dir,
    )
    current_segment_metadata_path = optional_path_from_metadata(
        metadata,
        "currentSegmentMetadataPath",
        session_dir,
    )
    if current_segment_events_path is not None and not current_segment_events_path.exists():
        errors.append(f"currentSegmentEventsPath does not exist: {metadata['currentSegmentEventsPath']}")
    if current_segment_metadata_path is not None and not current_segment_metadata_path.exists():
        errors.append(f"currentSegmentMetadataPath does not exist: {metadata['currentSegmentMetadataPath']}")
    if strict_ocu:
        if state == "recording":
            if current_segment_events_path is None:
                errors.append("recording state requires currentSegmentEventsPath")
            if current_segment_metadata_path is None:
                errors.append("recording state requires currentSegmentMetadataPath")
        elif state in FINAL_STATES:
            if current_segment_events_path is not None:
                errors.append("final state must not include currentSegmentEventsPath")
            if current_segment_metadata_path is not None:
                errors.append("final state must not include currentSegmentMetadataPath")

    events_path = input_events_path or path_from_metadata(metadata, "eventsPath", session_dir / "events.jsonl", session_dir)
    suppressed_path = path_from_metadata(
        metadata,
        "suppressedEventsPath",
        session_dir / "suppressed.jsonl",
        session_dir,
    )

    try:
        events = read_jsonl(events_path)
    except ValueError as error:
        errors.append(str(error))
        events = []

    suppressed_events = []
    if suppressed_path.exists():
        try:
            suppressed_events = read_jsonl(suppressed_path)
        except ValueError as error:
            errors.append(str(error))
    elif strict_ocu or metadata.get("suppressedEventsPath"):
        errors.append(f"suppressedEventsPath does not exist: {suppressed_path}")
    else:
        warnings.append(f"suppressed events file not found: {suppressed_path}")

    event_count = metadata.get("eventCount")
    if isinstance(event_count, int) and event_count != len(events):
        errors.append(f"eventCount={event_count} does not match events.jsonl lines={len(events)}")
    elif event_count is None:
        warnings.append("metadata has no eventCount")

    suppressed_count = metadata.get("suppressedEventCount")
    if isinstance(suppressed_count, int) and suppressed_count != len(suppressed_events):
        errors.append(
            f"suppressedEventCount={suppressed_count} does not match suppressed.jsonl lines={len(suppressed_events)}"
        )
    elif suppressed_count is None:
        warnings.append("metadata has no suppressedEventCount")

    event_types = [kind for event in events if (kind := event_kind(event))]
    event_type_counts = Counter(event_types)
    for event_type in required_event_types:
        if event_type_counts[event_type] == 0:
            errors.append(f"missing required event type: {event_type}")

    end_reason = metadata.get("endReason")
    started_events = [event for event in events if event_kind(event) == "session.started"]
    session_started_count_invalid = len(started_events) != 1
    first_event_type = event_kind(events[0]) if events else None
    session_started_is_first = first_event_type == "session.started"
    session_started_not_first = bool(started_events) and not session_started_is_first
    ended_events = [event for event in events if event_kind(event) == "session.ended"]
    ended_reasons = {
        event.get("endReason")
        for event in ended_events
        if isinstance(event.get("endReason"), str)
    }
    session_ended_count_invalid = len(ended_events) > 1
    final_event_type = event_kind(events[-1]) if events else None
    session_ended_is_final = final_event_type == "session.ended"
    session_ended_not_final = bool(ended_events) and not session_ended_is_final
    inferred_end_reason = end_reason or (next(iter(ended_reasons)) if len(ended_reasons) == 1 else None)
    incomplete = recording_incomplete(state, metadata.get("active"), ended_events)
    blocking_diagnostic_events = blocking_diagnostics(events)
    skill_draft_reasons = skill_draft_blocking_reasons(
        event_type_counts,
        state,
        inferred_end_reason,
        incomplete,
        blocking_diagnostic_events,
        session_started_not_first,
        session_started_count_invalid,
        session_ended_not_final,
        session_ended_count_invalid,
    )
    if require_skill_draft:
        errors.extend(skill_draft_reasons)

    if session_started_count_invalid:
        message = "recording has no session.started event" if not started_events else "recording has multiple session.started events"
        if strict_ocu:
            errors.append(message)
        elif not require_skill_draft:
            warnings.append(message)

    if session_started_not_first:
        message = "session.started is not the first event"
        if strict_ocu:
            errors.append(message)
        elif not require_skill_draft:
            warnings.append(message)

    if session_ended_count_invalid:
        message = "recording has multiple session.ended events"
        if strict_ocu:
            errors.append(message)
        elif not require_skill_draft:
            warnings.append(message)

    if session_ended_not_final:
        message = "session.ended is not the final event"
        if strict_ocu:
            errors.append(message)
        elif not require_skill_draft:
            warnings.append(message)

    if state in FINAL_STATES:
        if not ended_events:
            message = f"final state {state} has no session.ended event"
            if strict_ocu:
                errors.append(message)
            else:
                warnings.append(message)
        if end_reason:
            if ended_reasons and end_reason not in ended_reasons:
                errors.append(
                    f"metadata endReason={end_reason} not present in session.ended events: {sorted(ended_reasons)}"
                )

    session_id = metadata.get("sessionId") or metadata.get("sessionID")
    if isinstance(session_id, str) and session_id:
        mismatched_events = [
            index
            for index, event in enumerate(events, start=1)
            if isinstance(event.get("sessionId"), str) and event.get("sessionId") != session_id
        ]
        if mismatched_events:
            errors.append(f"event sessionId mismatch at JSONL lines: {mismatched_events[:10]}")

    for event_index, event in enumerate(events, start=1):
        for screenshot_path in collect_screenshot_paths(event):
            candidate = pathlib.Path(screenshot_path)
            if not candidate.is_absolute():
                candidate = session_dir / candidate
            if not is_inside_directory(candidate, session_dir):
                errors.append(
                    f"screenshotPath from event line {event_index} must stay inside session directory: {screenshot_path}"
                )
                continue
            if not candidate.exists():
                errors.append(f"screenshotPath from event line {event_index} does not exist: {screenshot_path}")

    if strict_ocu:
        if metadata.get("active") is not (state == "recording"):
            errors.append("metadata active flag does not match state")
        if state != "recording" and (session_dir.parent / "active-session.json").exists():
            errors.append("active-session.json exists after final session state")

    return {
        "ok": not errors,
        "sessionDir": str(session_dir),
        "metadataPath": str(metadata_path) if metadata_path is not None else None,
        "sessionPath": str(session_alias_path),
        "eventsPath": str(events_path),
        "suppressedEventsPath": str(suppressed_path),
        "currentSegmentEventsPath": str(current_segment_events_path) if current_segment_events_path else None,
        "currentSegmentMetadataPath": str(current_segment_metadata_path) if current_segment_metadata_path else None,
        "declaredPaths": declared_paths,
        "state": state,
        "active": metadata.get("active"),
        "endReason": inferred_end_reason,
        "sessionId": session_id,
        "eventCount": len(events),
        "metadataEventCount": event_count,
        "suppressedEventCount": len(suppressed_events),
        "metadataSuppressedEventCount": suppressed_count,
        "eventTypes": dict(sorted(event_type_counts.items())),
        "sessionStartedCount": len(started_events),
        "sessionStartedCountInvalid": session_started_count_invalid,
        "firstEventType": first_event_type,
        "sessionStartedIsFirst": session_started_is_first if first_event_type is not None else None,
        "sessionEndedCount": len(ended_events),
        "sessionEndedCountInvalid": session_ended_count_invalid,
        "finalEventType": final_event_type,
        "sessionEndedIsFinal": session_ended_is_final if final_event_type is not None else None,
        "requireSkillDraft": require_skill_draft,
        "skillDraftReady": not skill_draft_reasons,
        "skillDraftReasons": skill_draft_reasons,
        "recordingIncomplete": incomplete,
        "blockingDiagnostics": blocking_diagnostic_events,
        "warnings": warnings,
        "errors": errors,
    }


def main():
    parser = argparse.ArgumentParser(description="Validate a Record & Replay event-stream recording directory.")
    parser.add_argument("path", type=pathlib.Path, help="Session directory, metadata.json, session.json, or events.jsonl")
    parser.add_argument(
        "--strict-ocu",
        action="store_true",
        help="Require OCU baseline files and final-state invariants.",
    )
    parser.add_argument(
        "--require-event-type",
        action="append",
        default=[],
        help="Require at least one event of this type. May be passed multiple times.",
    )
    parser.add_argument(
        "--require-skill-draft",
        action="store_true",
        help="Require enough evidence to create a first-draft skill: at least one high-level action and no cancelled end state.",
    )
    args = parser.parse_args()

    try:
        result = validate(args.path, args.strict_ocu, args.require_event_type, args.require_skill_draft)
    except ValueError as error:
        result = {
            "ok": False,
            "errors": [str(error)],
            "warnings": [],
        }

    output = json.dumps(result, indent=2, sort_keys=True)
    if result["ok"]:
        print(output)
        return 0
    print(output, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
