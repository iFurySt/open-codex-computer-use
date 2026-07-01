from __future__ import annotations

from copy import deepcopy
from typing import Any


DEFAULT_REQUIRED_SCENARIOS = ("simple-action-stop",)
DEFAULT_RECOMMENDED_SCENARIOS = (
    "simple-action-stop",
    "keyboard-input-stop",
    "drag-stop",
    "cancel",
    "timeout",
)

ACTION_SMOKE_SCENARIOS = {"simple-action-stop", "drag-stop"}

BASE_GOLDEN_READINESS_ARGS = (
    "--require-fixture-manifest",
    "--require-session-alias",
    "--require-metadata-counts",
    "--require-handoff-paths",
)

COMPLETED_MCP_RESPONSE_SHAPES = (
    "startResponseShape",
    "statusResponseShape",
    "stopResponseShape",
    "finalStatusResponseShape",
)

_SCENARIO_RECIPES: dict[str, dict[str, Any]] = {
    "simple-action-stop": {
        "scenario": "simple-action-stop",
        "priority": "required",
        "captureGoal": "Record one low-risk left click and finish with the Record & Replay Done control.",
        "userAction": "Click a stable, harmless UI target once, then click Done in the official recording controls.",
        "expectedActionEvents": ["mouse.click"],
        "expectedEndReason": "recording_controls_stopped",
        "expectedEvidence": [
            "event_stream_start/status/stop hosted MCP response shape",
            "metadata/session/events/suppressed handoff paths",
            "one session.started as the first event",
            "one session.ended as the final event",
            "mouse.click action event",
            "AX payload for the clicked target/window",
        ],
        "ocuCandidateSourceKind": "run-action-smoke",
        "notes": [
            "Use this as the minimum official successful recording golden fixture.",
            "Keep the clicked target harmless and easy to describe after redaction.",
        ],
    },
    "keyboard-input-stop": {
        "scenario": "keyboard-input-stop",
        "priority": "recommended",
        "captureGoal": "Record a small text input and finish with the Record & Replay Done control.",
        "userAction": "Type a short non-sensitive string into a harmless text field, then click Done.",
        "expectedActionEvents": ["keyboard.text_input"],
        "expectedEndReason": "recording_controls_stopped",
        "expectedEvidence": [
            "keyboard.text_input action event",
            "focusedAccessibilityElement or equivalent keyboard target evidence",
            "AX payload for the edited field/window",
            "completed hosted MCP response shape",
        ],
        "ocuCandidateSourceKind": "recording-required",
        "notes": [
            "Do not use synthetic --run-action-smoke for this scenario; macOS may filter synthetic keyboard events.",
            "Use non-sensitive placeholder text only.",
        ],
    },
    "drag-stop": {
        "scenario": "drag-stop",
        "priority": "recommended",
        "captureGoal": "Record one low-risk drag gesture and finish with the Record & Replay Done control.",
        "userAction": "Drag a harmless target a short distance, release it, then click Done.",
        "expectedActionEvents": ["mouse.drag"],
        "expectedEndReason": "recording_controls_stopped",
        "expectedEvidence": [
            "mouse.drag action event",
            "start/end location evidence",
            "targetAccessibilityElement or equivalent drag target evidence",
            "AX payload for the affected window",
            "completed hosted MCP response shape",
        ],
        "ocuCandidateSourceKind": "run-action-smoke",
        "notes": [
            "Use a fixture or harmless UI target where drag has no external side effects.",
        ],
    },
    "cancel": {
        "scenario": "cancel",
        "priority": "recommended",
        "captureGoal": "Record the official cancellation path.",
        "userAction": "Start recording, optionally perform no action, then click Discard/Cancel in the recording controls.",
        "expectedActionEvents": [],
        "expectedEndReason": "recording_controls_cancelled",
        "expectedEvidence": [
            "session.ended endReason=recording_controls_cancelled",
            "cancelled hosted MCP/status response shape when available",
            "no skill creation from the cancelled recording",
        ],
        "ocuCandidateSourceKind": "recording-required",
        "notes": [
            "Cancelled recordings are evidence for lifecycle semantics only and must not be used to scaffold a skill.",
        ],
    },
    "timeout": {
        "scenario": "timeout",
        "priority": "recommended",
        "captureGoal": "Record the official maximum-duration timeout path.",
        "userAction": "Start recording and let the official time limit expire without using Done or Discard.",
        "expectedActionEvents": [],
        "expectedEndReason": None,
        "expectedEvidence": [
            "one session.started as the first event",
            "one session.ended as the final event",
            "official timeout endReason once observed",
            "completed or timeout hosted MCP/status response shape",
        ],
        "ocuCandidateSourceKind": "recording-required",
        "notes": [
            "OCU currently uses recording_time_limit_reached as a baseline; official timeout endReason still needs calibration.",
            "This sample may be slow because the official limit is expected to be long.",
        ],
    },
}


def scenario_recipe(scenario: str) -> dict[str, Any]:
    recipe = _SCENARIO_RECIPES.get(scenario)
    if recipe is None:
        return {
            "scenario": scenario,
            "priority": "custom",
            "captureGoal": "Capture and document this custom Record & Replay scenario before importing it.",
            "userAction": "Use a minimal, low-risk demonstration and finish through the official recording controls.",
            "expectedActionEvents": [],
            "expectedEndReason": None,
            "expectedEvidence": [
                "hosted MCP response shape",
                "metadata/session/events/suppressed handoff paths",
                "session.started and session.ended lifecycle evidence",
                "AX payload when the scenario includes UI interaction",
            ],
            "ocuCandidateSourceKind": "recording-required",
            "notes": [
                "No scenario-specific readiness policy is encoded for this custom scenario.",
            ],
        }
    return deepcopy(recipe)


def scenario_readiness_args(
    scenario: str,
    *,
    source: str,
    require_mcp_transcript_evidence: bool = False,
) -> list[str]:
    recipe = scenario_recipe(scenario)
    args = [
        *BASE_GOLDEN_READINESS_ARGS,
        "--require-source",
        source,
    ]

    expected_action_events = recipe.get("expectedActionEvents")
    if isinstance(expected_action_events, list):
        for event_type in expected_action_events:
            if isinstance(event_type, str) and event_type:
                args.extend(["--require-event-type", event_type])

    expected_end_reason = recipe.get("expectedEndReason")
    if isinstance(expected_end_reason, str) and expected_end_reason:
        args.extend(["--require-end-reason", expected_end_reason])

    scenario_name = recipe.get("scenario")
    if scenario_name in {"simple-action-stop", "keyboard-input-stop", "drag-stop"}:
        args.append("--require-full-ax-payload")
    elif scenario_name in {"cancel", "timeout"}:
        args.extend(["--allow-no-action", "--allow-no-ax-payload"])

    if require_mcp_transcript_evidence:
        args.append("--require-mcp-transcript")
        if scenario_name in {"simple-action-stop", "keyboard-input-stop", "drag-stop"}:
            for response_shape in COMPLETED_MCP_RESPONSE_SHAPES:
                args.extend(["--require-mcp-response-shape", response_shape])

    return args
