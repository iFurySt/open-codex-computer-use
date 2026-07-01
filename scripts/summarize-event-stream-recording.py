#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys
from collections import Counter, OrderedDict


ACTION_EVENT_TYPES = {
    "mouse.click",
    "mouse.context_menu",
    "mouse.drag",
    "keyboard.text_input",
    "keyboard.submit",
    "keyboard.shortcut",
    "terminal.value_changed",
    "selection.changed",
}

CONTEXT_EVENT_TYPES = {
    "session.started",
    "session.ended",
    "window.changed",
    "AX.focusedWindowChanged",
    "debug.error",
    "experimentalRawEvents",
}

SAFETY_KEYWORDS = [
    ("send", "sendAction"),
    ("delete", "deleteAction"),
    ("remove", "deleteAction"),
    ("trash", "deleteAction"),
    ("archive", "archiveAction"),
    ("purchase", "purchaseAction"),
    ("buy", "purchaseAction"),
    ("pay", "paymentAction"),
    ("approve", "approvalAction"),
    ("upload", "uploadAction"),
    ("publish", "publishAction"),
    ("share", "shareAction"),
    ("invite", "inviteAction"),
    ("submit", "submitAction"),
    ("save", "saveAction"),
]

BLOCKING_DIAGNOSTIC_REASONS = {"inputMonitorsUnavailable"}

ACTION_SEQUENCE_LIMIT = 50
RUNTIME_INPUTS_LIMIT = 50
SAFETY_SIGNALS_LIMIT = 50
ELEMENT_LIST_LIMIT = 25
DIAGNOSTICS_LIMIT = 25
SCREENSHOT_PATHS_LIMIT = 25


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
        value["_line"] = index
        records.append(value)
    return records


def resolve_input(path):
    def path_from_metadata(raw, fallback):
        if not raw:
            return fallback
        candidate = pathlib.Path(raw)
        if candidate.is_absolute():
            return candidate
        return path / candidate

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
        events_path = path_from_metadata(metadata.get("eventsPath"), path / "events.jsonl")
        return path, metadata_path, metadata, events_path

    if not path.exists():
        raise ValueError(f"path does not exist: {path}")

    if path.name in {"metadata.json", "session.json"}:
        metadata = load_json(path)
        session_dir = path.parent
        raw_events_path = metadata.get("eventsPath")
        if raw_events_path:
            candidate = pathlib.Path(raw_events_path)
            events_path = candidate if candidate.is_absolute() else session_dir / candidate
        else:
            events_path = session_dir / "events.jsonl"
        return path.parent, path, metadata, events_path

    if path.name == "events.jsonl":
        return path.parent, None, {}, path

    raise ValueError("input must be a session directory, metadata.json, session.json, or events.jsonl")


def first_string(value, keys):
    if not isinstance(value, dict):
        return None
    for key in keys:
        raw = value.get(key)
        if isinstance(raw, str) and raw:
            return raw
    return None


def nested_dict(value, keys):
    if not isinstance(value, dict):
        return None
    for key in keys:
        raw = value.get(key)
        if isinstance(raw, dict):
            return raw
    return None


def window_signature(event):
    window = nested_dict(event, ["window", "windowContext", "targetWindow"])
    app = nested_dict(event, ["app", "application", "appContext"])

    app_name = first_string(event, ["appName", "applicationName", "localizedName"])
    bundle_id = first_string(event, ["bundleIdentifier", "bundleId", "appBundleIdentifier"])
    window_title = first_string(event, ["windowTitle", "title"])

    if app:
        app_name = app_name or first_string(app, ["name", "appName", "localizedName"])
        bundle_id = bundle_id or first_string(app, ["bundleIdentifier", "bundleId"])
    if window:
        window_title = window_title or first_string(window, ["title", "windowTitle"])

    if not app_name and not bundle_id and not window_title:
        return None
    return {
        "appName": app_name,
        "bundleIdentifier": bundle_id,
        "windowTitle": window_title,
    }


def element_summary(event, include_text):
    element = nested_dict(event, ["targetAccessibilityElement", "focusedAccessibilityElement"])
    if not element:
        return None

    summary = OrderedDict()
    for key in ["role", "subrole", "title", "label", "description"]:
        raw = element.get(key)
        if isinstance(raw, str) and raw:
            summary[key] = raw
        elif isinstance(raw, bool):
            summary[key] = raw
    for key in ["value", "selectedText"]:
        raw = element.get(key)
        if isinstance(raw, str) and raw:
            if include_text:
                summary[key] = raw
            summary[f"{key}Length"] = len(raw)
        elif isinstance(raw, bool):
            summary[key] = raw
    actions = element.get("actions")
    if isinstance(actions, list) and actions:
        summary["actions"] = [action for action in actions if isinstance(action, str)][:8]
    if element.get("secureInput") is True:
        summary["secureInput"] = True
    return summary or None


def append_unique(mapping, key, value):
    if not key:
        return
    if key not in mapping:
        mapping[key] = value


def event_kind(event):
    kind = event.get("kind")
    if isinstance(kind, str):
        return kind
    event_type = event.get("type")
    if isinstance(event_type, str):
        return event_type
    return None


def summarize(path, require_action, include_text):
    session_dir, metadata_path, metadata, events_path = resolve_input(path)
    events = read_jsonl(events_path)

    event_types = Counter(kind for event in events if (kind := event_kind(event)))
    action_events = [event for event in events if event_kind(event) in ACTION_EVENT_TYPES]
    context_events = [event for event in events if event_kind(event) in CONTEXT_EVENT_TYPES]

    windows = OrderedDict()
    target_elements = []
    focused_elements = []
    selected_text_events = []
    debug_errors = []
    blocking_diagnostics = []
    redaction_events = []
    screenshot_paths = []
    action_sequence = []
    runtime_inputs = []
    safety_signals = []

    for event in events:
        event_type = event_kind(event)
        signature = window_signature(event)
        if signature:
            key = "|".join(
                [
                    signature.get("bundleIdentifier") or "",
                    signature.get("appName") or "",
                    signature.get("windowTitle") or "",
                ]
            )
            append_unique(windows, key, signature)

        action_type = action_type_for_event(event)
        if action_type:
            action = OrderedDict()
            action["line"] = event.get("_line")
            action["type"] = action_type
            if isinstance(event.get("timestamp"), str):
                action["timestamp"] = event["timestamp"]
            if signature:
                action["window"] = signature
            for key in ["location", "startLocation", "endLocation", "key", "modifiers", "selectionCleared", "reason"]:
                if key in event:
                    action[key] = event[key]
            raw_events = event.get("experimentalRawEvents")
            if isinstance(raw_events, list):
                raw_event_types = [
                    raw.get("eventType")
                    for raw in raw_events
                    if isinstance(raw, dict) and isinstance(raw.get("eventType"), str)
                ]
                if raw_event_types:
                    action["rawEventTypes"] = raw_event_types[:8]
                scroll = next(
                    (
                        raw
                        for raw in raw_events
                        if isinstance(raw, dict) and raw.get("eventType") == "scrollWheel"
                    ),
                    None,
                )
                if scroll:
                    for key in ["scrollingDeltaX", "scrollingDeltaY", "hasPreciseScrollingDeltas"]:
                        if key in scroll:
                            action[key] = scroll[key]
            if "text" in event:
                text = event["text"]
                if isinstance(text, str):
                    action["textLength"] = len(text)
                else:
                    action["text"] = text
            if "textLength" in event:
                action["textLength"] = event["textLength"]
            element = element_summary(event, include_text=include_text)
            if element:
                action["element"] = element
            runtime_input = runtime_input_summary(event, action)
            if runtime_input and len(runtime_inputs) < RUNTIME_INPUTS_LIMIT:
                runtime_inputs.append(runtime_input)
            safety_signal = safety_signal_summary(event, action)
            if safety_signal and len(safety_signals) < SAFETY_SIGNALS_LIMIT:
                safety_signals.append(safety_signal)
            action_sequence.append(action)

        target = nested_dict(event, ["targetAccessibilityElement"])
        if target:
            target_elements.append(element_summary({"targetAccessibilityElement": target}, include_text=include_text) or {})
        focused = nested_dict(event, ["focusedAccessibilityElement"])
        if focused:
            focused_elements.append(element_summary({"focusedAccessibilityElement": focused}, include_text=include_text) or {})

        if event_type == "selection.changed":
            selected_text_events.append({
                "line": event.get("_line"),
                "selectedTextLength": len(event.get("selectedText") or ""),
                "selectionCleared": event.get("selectionCleared") is True,
            })

        if event_type == "debug.error":
            if is_blocking_diagnostic(event):
                blocking_diagnostics.append({
                    "line": event.get("_line"),
                    "subsystem": event.get("subsystem"),
                    "reason": event.get("reason"),
                    "errorType": event.get("errorType"),
                })
            debug_errors.append({
                "line": event.get("_line"),
                "subsystem": event.get("subsystem"),
                "reason": event.get("reason"),
                "errorType": event.get("errorType"),
            })

        if event.get("secureInput") is True or event.get("redacted") is True:
            redaction_events.append({
                "line": event.get("_line"),
                "type": event_type,
                "secureInput": event.get("secureInput") is True,
                "redacted": event.get("redacted") is True,
            })

        payload = event.get("accessibilityInspectorPayload")
        if isinstance(payload, dict):
            screenshot_path = payload.get("screenshotPath")
            if isinstance(screenshot_path, str) and screenshot_path:
                screenshot_paths.append(screenshot_path)

    ended_reasons = {
        event.get("endReason")
        for event in events
        if event_kind(event) == "session.ended" and isinstance(event.get("endReason"), str)
    }
    inferred_end_reason = metadata.get("endReason") or (
        next(iter(ended_reasons)) if len(ended_reasons) == 1 else None
    )
    final_event_type = event_kind(events[-1]) if events else None
    first_event_type = event_kind(events[0]) if events else None
    session_started_is_first = first_event_type == "session.started"
    session_started_not_first = event_types["session.started"] > 0 and not session_started_is_first
    session_started_count_invalid = event_types["session.started"] != 1
    session_ended_is_final = final_event_type == "session.ended"
    session_ended_not_final = event_types["session.ended"] > 0 and not session_ended_is_final
    session_ended_count_invalid = event_types["session.ended"] > 1
    warnings = []
    recording_was_cancelled = (
        metadata.get("state") == "cancelled"
        or inferred_end_reason == "recording_controls_cancelled"
    )
    incomplete = recording_incomplete(metadata, event_types)
    if not action_events:
        warnings.append("recording has no high-level user action events")
    if recording_was_cancelled:
        warnings.append("recording was cancelled; do not create or update a skill from this event stream")
    if incomplete:
        warnings.append("recording is not complete; stop the recording before creating a skill")
    if session_started_count_invalid:
        warnings.append("recording must contain exactly one session.started event before creating a skill")
    if session_started_not_first:
        warnings.append("recording has events before session.started; start must be the first event before creating a skill")
    if session_ended_not_final:
        warnings.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    if session_ended_count_invalid:
        warnings.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    if event_types["AX.focusedWindowChanged"] == 0:
        warnings.append("recording has no AX focused window context")
    if debug_errors:
        warnings.append("recording includes debug.error events; inspect diagnostics before creating a skill")
    if blocking_diagnostics:
        warnings.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    if redaction_events:
        warnings.append("recording includes redaction or secureInput signals; avoid copying sensitive values")
    if safety_signals:
        warnings.append("recording includes actions that may require explicit user confirmation")

    summary_limits = summary_limit_report(
        action_event_count=len(action_events),
        action_sequence_stored=min(len(action_sequence), ACTION_SEQUENCE_LIMIT),
        runtime_input_count=sum(
            1 for event in events if runtime_input_summary(event, {"type": event_kind(event)})
        ),
        runtime_inputs_stored=len(runtime_inputs),
        safety_signal_count=sum(
            1
            for event in events
            if safety_signal_summary(
                event,
                {
                    "line": event.get("_line"),
                    "type": event_kind(event),
                    "element": element_summary(event, include_text=include_text) or {},
                },
            )
        ),
        safety_signals_stored=len(safety_signals),
        target_element_count=len(target_elements),
        target_elements_stored=min(len(target_elements), ELEMENT_LIST_LIMIT),
        focused_element_count=len(focused_elements),
        focused_elements_stored=min(len(focused_elements), ELEMENT_LIST_LIMIT),
        selection_event_count=len(selected_text_events),
        selection_events_stored=min(len(selected_text_events), ELEMENT_LIST_LIMIT),
        debug_error_count=len(debug_errors),
        debug_errors_stored=min(len(debug_errors), DIAGNOSTICS_LIMIT),
        redaction_event_count=len(redaction_events),
        redaction_events_stored=min(len(redaction_events), DIAGNOSTICS_LIMIT),
        screenshot_path_count=len(screenshot_paths),
        screenshot_paths_stored=min(len(screenshot_paths), SCREENSHOT_PATHS_LIMIT),
    )
    if summary_limits["hasTruncatedSummary"]:
        warnings.append("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill")

    skill_evidence = {
        "hasActionEvents": bool(action_events),
        "hasInputEvents": any(
            (kind := event_kind(event)) is not None and kind.startswith("keyboard.")
            for event in events
        ),
        "hasPointerEvents": any(
            (kind := event_kind(event)) is not None and kind.startswith("mouse.")
            for event in events
        ),
        "hasAXContext": event_types["AX.focusedWindowChanged"] > 0,
        "hasTargetElements": bool(target_elements),
        "hasFocusedElements": bool(focused_elements),
        "hasSelectionSignals": bool(selected_text_events),
        "hasTerminalSignals": event_types["terminal.value_changed"] > 0,
        "hasScreenshots": bool(screenshot_paths),
        "hasDebugErrors": bool(debug_errors),
        "hasBlockingDiagnostics": bool(blocking_diagnostics),
        "recordingIncomplete": incomplete,
        "sessionStartedNotFirst": session_started_not_first,
        "sessionStartedCountInvalid": session_started_count_invalid,
        "sessionEndedNotFinal": session_ended_not_final,
        "sessionEndedCountInvalid": session_ended_count_invalid,
        "hasRedactionSignals": bool(redaction_events),
        "hasSafetySignals": bool(safety_signals),
        "hasTruncatedSummary": summary_limits["hasTruncatedSummary"],
    }
    skill_readiness = skill_readiness_from_evidence(
        skill_evidence,
        has_window_context=bool(windows),
        recording_was_cancelled=recording_was_cancelled,
        recording_incomplete=incomplete,
        session_started_not_first=session_started_not_first,
        session_started_count_invalid=session_started_count_invalid,
        session_ended_not_final=session_ended_not_final,
        session_ended_count_invalid=session_ended_count_invalid,
    )

    ok = True
    errors = []
    if require_action and not action_events:
        ok = False
        errors.append("required at least one high-level user action event")
    if require_action and recording_was_cancelled:
        ok = False
        errors.append("recording was cancelled; do not create or update a skill from this event stream")
    if require_action and incomplete:
        ok = False
        errors.append("recording is not complete; stop the recording before creating a skill")
    if require_action and session_started_count_invalid:
        ok = False
        errors.append("recording must contain exactly one session.started event before creating a skill")
    if require_action and session_started_not_first:
        ok = False
        errors.append("recording has events before session.started; start must be the first event before creating a skill")
    if require_action and session_ended_not_final:
        ok = False
        errors.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    if require_action and session_ended_count_invalid:
        ok = False
        errors.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    if require_action and blocking_diagnostics:
        ok = False
        errors.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")

    result = {
        "ok": ok,
        "sessionDir": str(session_dir),
        "eventsPath": str(events_path),
        "sessionId": metadata.get("sessionId") or metadata.get("sessionID"),
        "state": metadata.get("state"),
        "endReason": inferred_end_reason,
        "eventCount": len(events),
        "eventTypes": dict(sorted(event_types.items())),
        "sessionStartedCount": event_types["session.started"],
        "firstEventType": first_event_type,
        "sessionStartedIsFirst": session_started_is_first if first_event_type is not None else None,
        "sessionEndedCount": event_types["session.ended"],
        "finalEventType": final_event_type,
        "sessionEndedIsFinal": session_ended_is_final if final_event_type is not None else None,
        "actionEventCount": len(action_events),
        "contextEventCount": len(context_events),
        "windows": list(windows.values()),
        "skillEvidence": skill_evidence,
        "skillReadiness": skill_readiness,
        "summaryLimits": summary_limits,
        "runtimeInputs": runtime_inputs,
        "safetySignals": safety_signals,
        "actionSequence": action_sequence[:ACTION_SEQUENCE_LIMIT],
        "targetElements": target_elements[:ELEMENT_LIST_LIMIT],
        "focusedElements": focused_elements[:ELEMENT_LIST_LIMIT],
        "selectionEvents": selected_text_events[:ELEMENT_LIST_LIMIT],
        "debugErrors": debug_errors[:DIAGNOSTICS_LIMIT],
        "blockingDiagnostics": blocking_diagnostics,
        "redactionEvents": redaction_events[:DIAGNOSTICS_LIMIT],
        "screenshotPaths": screenshot_paths[:SCREENSHOT_PATHS_LIMIT],
        "includesRawText": include_text,
        "warnings": warnings,
        "errors": errors,
    }
    if metadata_path:
        result["metadataPath"] = str(metadata_path)
    return result


def action_type_for_event(event):
    event_type = event_kind(event)
    if event_type in ACTION_EVENT_TYPES:
        return event_type
    if event_type == "experimentalRawEvents" and event.get("reason") == "scrollWheel":
        return event_type
    return None


def runtime_input_summary(event, action):
    event_type = action.get("type")
    result = OrderedDict()
    result["line"] = action.get("line")
    result["sourceEventType"] = event_type
    result["requiresUserValue"] = True
    if isinstance(action.get("element"), dict) and action["element"]:
        result["target"] = action["element"]

    if event_type == "keyboard.text_input":
        result["kind"] = "text"
        result["description"] = "Runtime text to enter into the observed target."
        if "textLength" in action:
            result["textLength"] = action["textLength"]
        if event.get("secureInput") is True or event.get("redacted") is True:
            result["sensitive"] = True
        return result

    if event_type == "selection.changed":
        result["kind"] = "selection"
        result["description"] = (
            "Current selection or selected-content semantics if the workflow depends on it."
        )
        selected_text = event.get("selectedText")
        if isinstance(selected_text, str):
            result["selectedTextLength"] = len(selected_text)
        if "selectionCleared" in action:
            result["selectionCleared"] = action["selectionCleared"]
        return result

    return None


def summary_limit_report(**counts):
    source_counts = {
        "actionSequence": counts["action_event_count"],
        "runtimeInputs": counts["runtime_input_count"],
        "safetySignals": counts["safety_signal_count"],
        "targetElements": counts["target_element_count"],
        "focusedElements": counts["focused_element_count"],
        "selectionEvents": counts["selection_event_count"],
        "debugErrors": counts["debug_error_count"],
        "redactionEvents": counts["redaction_event_count"],
        "screenshotPaths": counts["screenshot_path_count"],
    }
    stored_counts = {
        "actionSequence": counts["action_sequence_stored"],
        "runtimeInputs": counts["runtime_inputs_stored"],
        "safetySignals": counts["safety_signals_stored"],
        "targetElements": counts["target_elements_stored"],
        "focusedElements": counts["focused_elements_stored"],
        "selectionEvents": counts["selection_events_stored"],
        "debugErrors": counts["debug_errors_stored"],
        "redactionEvents": counts["redaction_events_stored"],
        "screenshotPaths": counts["screenshot_paths_stored"],
    }
    omitted_counts = {
        key: max(0, source_counts[key] - stored_counts[key])
        for key in source_counts
    }
    return {
        "hasTruncatedSummary": any(value > 0 for value in omitted_counts.values()),
        "limits": {
            "actionSequence": ACTION_SEQUENCE_LIMIT,
            "runtimeInputs": RUNTIME_INPUTS_LIMIT,
            "safetySignals": SAFETY_SIGNALS_LIMIT,
            "targetElements": ELEMENT_LIST_LIMIT,
            "focusedElements": ELEMENT_LIST_LIMIT,
            "selectionEvents": ELEMENT_LIST_LIMIT,
            "debugErrors": DIAGNOSTICS_LIMIT,
            "redactionEvents": DIAGNOSTICS_LIMIT,
            "screenshotPaths": SCREENSHOT_PATHS_LIMIT,
        },
        "storedCounts": stored_counts,
        "sourceCounts": source_counts,
        "omittedCounts": omitted_counts,
    }


def safety_keyword_reason(element):
    parts = []
    if isinstance(element, dict):
        for key in ["role", "title", "label", "description", "subrole"]:
            raw = element.get(key)
            if isinstance(raw, str) and raw:
                parts.append(raw)
    text = " ".join(parts).lower()
    if not text:
        return None
    for keyword, reason in SAFETY_KEYWORDS:
        if keyword in text:
            return reason
    return None


def is_blocking_diagnostic(event):
    return (
        event_kind(event) == "debug.error"
        and event.get("reason") in BLOCKING_DIAGNOSTIC_REASONS
    )


def recording_incomplete(metadata, event_types):
    if metadata.get("state") == "recording" or metadata.get("active") is True:
        return True
    return event_types["session.ended"] == 0


def safety_signal_summary(event, action):
    event_type = action.get("type")
    reason = None
    if event_type == "keyboard.submit":
        reason = "submitAction"
    element = action.get("element") if isinstance(action.get("element"), dict) else {}
    if reason is None:
        reason = safety_keyword_reason(element)
    if reason is None:
        return None

    result = OrderedDict()
    result["line"] = action.get("line")
    result["sourceEventType"] = event_type
    result["reason"] = reason
    result["confirmationRequired"] = True
    if isinstance(event.get("timestamp"), str):
        result["timestamp"] = event["timestamp"]
    if isinstance(action.get("window"), dict) and action["window"]:
        result["window"] = action["window"]
    if element:
        result["target"] = element
    return result


def skill_readiness_from_evidence(
    skill_evidence,
    has_window_context,
    recording_was_cancelled=False,
    recording_incomplete=False,
    session_started_not_first=False,
    session_started_count_invalid=False,
    session_ended_not_final=False,
    session_ended_count_invalid=False,
):
    has_action_events = skill_evidence.get("hasActionEvents") is True
    has_ax_context = skill_evidence.get("hasAXContext") is True
    has_target_elements = skill_evidence.get("hasTargetElements") is True
    has_focused_elements = skill_evidence.get("hasFocusedElements") is True
    has_selection_signals = skill_evidence.get("hasSelectionSignals") is True
    has_debug_errors = skill_evidence.get("hasDebugErrors") is True
    has_blocking_diagnostics = skill_evidence.get("hasBlockingDiagnostics") is True
    recording_incomplete = recording_incomplete or skill_evidence.get("recordingIncomplete") is True
    session_started_not_first = session_started_not_first or skill_evidence.get("sessionStartedNotFirst") is True
    session_started_count_invalid = (
        session_started_count_invalid or skill_evidence.get("sessionStartedCountInvalid") is True
    )
    session_ended_not_final = session_ended_not_final or skill_evidence.get("sessionEndedNotFinal") is True
    session_ended_count_invalid = (
        session_ended_count_invalid or skill_evidence.get("sessionEndedCountInvalid") is True
    )
    has_redaction_signals = skill_evidence.get("hasRedactionSignals") is True
    has_safety_signals = skill_evidence.get("hasSafetySignals") is True
    has_truncated_summary = skill_evidence.get("hasTruncatedSummary") is True

    reasons = []
    if recording_was_cancelled:
        reasons.append("recording was cancelled; do not create or update a skill from this event stream")
    if recording_incomplete:
        reasons.append("recording is not complete; stop the recording before creating a skill")
    if session_started_count_invalid:
        reasons.append("recording must contain exactly one session.started event before creating a skill")
    if session_started_not_first:
        reasons.append("recording has events before session.started; start must be the first event before creating a skill")
    if session_ended_not_final:
        reasons.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    if session_ended_count_invalid:
        reasons.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    if not has_action_events:
        reasons.append("recording has no high-level user action events")
    if not has_window_context:
        reasons.append("recording has no stable app/window context")
    if not has_ax_context:
        reasons.append("recording has no AX focused window context")
    if not (has_target_elements or has_focused_elements or has_selection_signals):
        reasons.append("recording has no semantic target, focused element, or selection evidence")
    if has_debug_errors:
        reasons.append("recording includes debug.error diagnostics")
    if has_blocking_diagnostics:
        reasons.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    if has_redaction_signals:
        reasons.append("recording includes redaction or secureInput signals")
    if has_safety_signals:
        reasons.append("recording includes actions that may require explicit user confirmation")
    if has_truncated_summary:
        reasons.append("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill")

    if recording_was_cancelled:
        status = "insufficient"
        recommended_next_step = (
            "Acknowledge the cancellation and ask the user to re-record when they want to "
            "create a skill."
        )
    elif recording_incomplete:
        status = "insufficient"
        recommended_next_step = (
            "Stop the recording, then inspect the completed events before creating a skill."
        )
    elif session_started_count_invalid:
        status = "insufficient"
        recommended_next_step = (
            "Discard this malformed recording and re-record so exactly one start event opens "
            "the event stream."
        )
    elif session_started_not_first:
        status = "insufficient"
        recommended_next_step = "Discard this malformed recording and re-record so session.started is the first event."
    elif session_ended_not_final:
        status = "insufficient"
        recommended_next_step = (
            "Discard this malformed recording and re-record so the stop or cancel event closes "
            "the event stream."
        )
    elif session_ended_count_invalid:
        status = "insufficient"
        recommended_next_step = (
            "Discard this malformed recording and re-record so the stop or cancel event closes "
            "the event stream exactly once."
        )
    elif has_blocking_diagnostics:
        status = "insufficient"
        recommended_next_step = (
            "Fix the recording permissions or input monitoring issue, then ask the user to "
            "re-record the workflow."
        )
    elif not has_action_events:
        status = "insufficient"
        recommended_next_step = (
            "Ask the user to re-record after confirming permissions and demonstrating at least "
            "one workflow action."
        )
    elif reasons:
        status = "needsReview"
        recommended_next_step = (
            "Inspect events.jsonl, replace user-specific values with inputs, and refine the "
            "generated skill before packaging."
        )
    else:
        status = "ready"
        recommended_next_step = (
            "Create or refine a reusable skill from the recording, then validate the final "
            "skill package."
        )

    return {
        "status": status,
        "canCreateSkillDraft": (
            has_action_events
            and not recording_was_cancelled
            and not recording_incomplete
            and not session_started_count_invalid
            and not session_started_not_first
            and not session_ended_not_final
            and not session_ended_count_invalid
            and not has_blocking_diagnostics
        ),
        "requiresHumanReview": status != "ready",
        "reasons": reasons,
        "recommendedNextStep": recommended_next_step,
    }


def main():
    parser = argparse.ArgumentParser(description="Summarize a Record & Replay event stream for replay/skill creation.")
    parser.add_argument("path", type=pathlib.Path, help="Session directory, metadata.json, session.json, or events.jsonl")
    parser.add_argument(
        "--require-action",
        action="store_true",
        help="Exit non-zero when no high-level user action events are present.",
    )
    parser.add_argument(
        "--include-text",
        action="store_true",
        help="Include raw AX value/selectedText fields in summaries. By default only lengths are emitted.",
    )
    args = parser.parse_args()

    try:
        result = summarize(args.path, args.require_action, args.include_text)
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
