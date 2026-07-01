#!/usr/bin/env python3

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import re
import shutil
import subprocess
import sys
from typing import Any


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SUMMARY_SCRIPT = REPO_ROOT / "scripts/summarize-event-stream-recording.py"
VALIDATION_SCRIPT = REPO_ROOT / "scripts/validate-event-stream-recording.py"
SKILL_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$")
PATH_KEYS = {
    "sessionDir",
    "metadataPath",
    "eventsPath",
}


def load_validation_module():
    spec = importlib.util.spec_from_file_location(
        "event_stream_recording_validator",
        VALIDATION_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise ValueError(f"could not load validator script: {VALIDATION_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a reusable skill draft from a Record & Replay event-stream recording."
    )
    parser.add_argument(
        "recording",
        type=pathlib.Path,
        help="Session directory, metadata.json, session.json, or events.jsonl.",
    )
    parser.add_argument(
        "--skill-name",
        required=True,
        help="Generated skill name, using lowercase letters, numbers, and hyphens.",
    )
    parser.add_argument(
        "--description",
        help="Skill description. Defaults to a generic Record & Replay replay description.",
    )
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        required=True,
        help="Directory to create. The directory must not exist unless --overwrite is set.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing output directory.",
    )
    parser.add_argument(
        "--include-text",
        action="store_true",
        help=(
            "Include raw AX value/selectedText summary fields. Use only with deliberately "
            "sanitized recordings."
        ),
    )
    return parser.parse_args()


def run_summary(recording: pathlib.Path, include_text: bool) -> dict[str, Any]:
    command = [
        sys.executable,
        str(SUMMARY_SCRIPT),
        "--require-action",
    ]
    if include_text:
        command.append("--include-text")
    command.append(str(recording))
    completed = subprocess.run(
        command,
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    payload = completed.stdout if completed.returncode == 0 else completed.stderr
    try:
        summary = json.loads(payload)
    except json.JSONDecodeError as error:
        raise ValueError(f"summary command did not return JSON: {error}") from error
    if not isinstance(summary, dict):
        raise ValueError("summary command returned non-object JSON")
    if not summary.get("ok"):
        errors = summary.get("errors") if isinstance(summary.get("errors"), list) else []
        raise ValueError("; ".join(str(error) for error in errors) or "recording summary failed")
    return summary


def run_validation(recording: pathlib.Path) -> dict[str, Any]:
    module = load_validation_module()
    result = module.validate(
        recording,
        strict_ocu=False,
        required_event_types=[],
        require_skill_draft=True,
    )
    if not isinstance(result, dict):
        raise ValueError("validation command returned non-object JSON")
    if not result.get("ok"):
        errors = result.get("errors") if isinstance(result.get("errors"), list) else []
        reasons = (
            result.get("skillDraftReasons")
            if isinstance(result.get("skillDraftReasons"), list)
            else []
        )
        message_parts = [str(item) for item in [*errors, *reasons] if str(item)]
        raise ValueError("; ".join(dict.fromkeys(message_parts)) or "recording validation failed")
    return result


def sanitize_summary(value: Any) -> Any:
    if isinstance(value, dict):
        sanitized: dict[str, Any] = {}
        for key, child in value.items():
            if key in PATH_KEYS:
                sanitized[key] = f"<recording-{key}>"
                continue
            if key == "screenshotPaths" and isinstance(child, list):
                sanitized[key] = [
                    pathlib.Path(item).name if isinstance(item, str) else item
                    for item in child
                ]
                continue
            sanitized[key] = sanitize_summary(child)
        return sanitized
    if isinstance(value, list):
        return [sanitize_summary(child) for child in value]
    return value


def frontmatter_value(value: str) -> str:
    return value.replace("\n", " ").strip()


def title_from_skill_name(skill_name: str) -> str:
    return " ".join(part.capitalize() for part in skill_name.split("-"))


def target_description(element: dict[str, Any]) -> str:
    target_bits = []
    for key in ["role", "title", "label", "description"]:
        raw = element.get(key)
        if isinstance(raw, str) and raw:
            target_bits.append(f"{key}={raw!r}")
    return ", ".join(target_bits) if target_bits else "the observed target"


def action_description(action: dict[str, Any]) -> str:
    action_type = action.get("type")
    line = action.get("line")
    prefix = f"Line {line}: " if isinstance(line, int) else ""
    element = action.get("element") if isinstance(action.get("element"), dict) else {}
    window = action.get("window") if isinstance(action.get("window"), dict) else {}
    target = target_description(element)
    app = window.get("appName") or window.get("bundleIdentifier") or "the recorded app"

    if action_type == "mouse.click":
        return f"{prefix}Click {target} in {app}."
    if action_type == "mouse.context_menu":
        return f"{prefix}Open the context menu on {target} in {app}."
    if action_type == "mouse.drag":
        return f"{prefix}Drag from the recorded start location to end location in {app}."
    if action_type == "keyboard.text_input":
        text_length = action.get("textLength")
        if isinstance(text_length, int):
            return f"{prefix}Enter user-provided text into {target} ({text_length} recorded characters)."
        return f"{prefix}Enter user-provided text into {target}."
    if action_type == "keyboard.submit":
        return f"{prefix}Submit the current focused control in {app}."
    if action_type == "keyboard.shortcut":
        key = action.get("key")
        modifiers = action.get("modifiers")
        chord = "+".join([*(modifiers if isinstance(modifiers, list) else []), str(key)])
        return f"{prefix}Press shortcut `{chord}` in {app}."
    if action_type == "terminal.value_changed":
        return f"{prefix}Observe terminal output/state change; keep command/output values sanitized."
    if action_type == "selection.changed":
        return f"{prefix}Use the recorded selection change as context, but do not rely on stale selected text."
    if action_type == "experimentalRawEvents":
        if action.get("reason") == "scrollWheel":
            return f"{prefix}Scroll in {app} using the recorded wheel direction; re-check the visible state after scrolling."
        return f"{prefix}Replay raw input evidence in {app} only after inspecting the original `events.jsonl`."
    return f"{prefix}Replay `{action_type}` using the recorded context."


def input_description(action: dict[str, Any]) -> str | None:
    action_type = action.get("type")
    element = action.get("element") if isinstance(action.get("element"), dict) else {}
    target = target_description(element)

    if action_type == "keyboard.text_input":
        text_length = action.get("textLength")
        if isinstance(text_length, int):
            return (
                f"Runtime text for {target} ({text_length} recorded characters; "
                "recorded literal text is omitted by default)."
            )
        return f"Runtime text for {target}; recorded literal text is omitted by default."
    if action_type == "selection.changed":
        return "Current selection or selected content semantics if the workflow depends on the recorded selection."
    return None


def runtime_input_description(runtime_input: dict[str, Any]) -> str:
    kind = str(runtime_input.get("kind") or "value")
    target = target_description(
        runtime_input.get("target") if isinstance(runtime_input.get("target"), dict) else {}
    )
    if isinstance(runtime_input.get("textLength"), int):
        suffix = f" ({runtime_input['textLength']} recorded characters; use a fresh runtime value)."
    elif isinstance(runtime_input.get("selectedTextLength"), int):
        suffix = (
            f" ({runtime_input['selectedTextLength']} recorded selected characters; "
            "confirm current semantics)."
        )
    else:
        suffix = "."
    sensitivity = " Treat this as sensitive input." if runtime_input.get("sensitive") is True else ""

    if kind == "text":
        return f"Runtime text for {target}{suffix}{sensitivity}"
    if kind == "selection":
        return f"Runtime selection or selected-content meaning for {target}{suffix}"
    return f"Runtime {kind} for {target}{suffix}"


def safety_signal_description(signal: dict[str, Any]) -> str:
    source_event_type = signal.get("sourceEventType") or "recorded action"
    reason = signal.get("reason") or "confirmationRequired"
    target = target_description(signal.get("target") if isinstance(signal.get("target"), dict) else {})
    line = signal.get("line")
    prefix = f"Line {line}: " if isinstance(line, int) else ""
    return (
        f"{prefix}`{source_event_type}` matched {reason} on {target}; "
        "ask for explicit confirmation before replaying this step."
    )


def summary_limit_descriptions(summary_limits: dict[str, Any]) -> list[str]:
    if summary_limits.get("hasTruncatedSummary") is not True:
        return []
    omitted_counts = (
        summary_limits.get("omittedCounts")
        if isinstance(summary_limits.get("omittedCounts"), dict)
        else {}
    )
    items = []
    for key, value in sorted(omitted_counts.items()):
        if isinstance(value, int) and value > 0:
            items.append(
                f"{value} {key} item(s) were omitted from `references/recording-summary.json`; "
                "inspect the original `events.jsonl` before finalizing replay steps."
            )
    return items


def markdown_list(items: list[str], fallback: str) -> str:
    if not items:
        return f"- {fallback}"
    return "\n".join(f"- {item}" for item in items)


def render_skill(skill_name: str, description: str, summary: dict[str, Any]) -> str:
    windows = summary.get("windows") if isinstance(summary.get("windows"), list) else []
    window_items = []
    for window in windows[:10]:
        if not isinstance(window, dict):
            continue
        app = window.get("appName") or window.get("bundleIdentifier") or "Unknown app"
        title = window.get("windowTitle")
        window_items.append(f"{app}" + (f" / {title}" if title else ""))

    actions = summary.get("actionSequence") if isinstance(summary.get("actionSequence"), list) else []
    action_items = [
        action_description(action)
        for action in actions[:30]
        if isinstance(action, dict)
    ]
    runtime_inputs = summary.get("runtimeInputs") if isinstance(summary.get("runtimeInputs"), list) else []
    input_items = [
        runtime_input_description(runtime_input)
        for runtime_input in runtime_inputs[:30]
        if isinstance(runtime_input, dict)
    ]
    if not input_items:
        input_items = [
            item
            for action in actions[:30]
            if isinstance(action, dict)
            for item in [input_description(action)]
            if item is not None
        ]
    warnings = summary.get("warnings") if isinstance(summary.get("warnings"), list) else []
    evidence = summary.get("skillEvidence") if isinstance(summary.get("skillEvidence"), dict) else {}
    readiness = summary.get("skillReadiness") if isinstance(summary.get("skillReadiness"), dict) else {}
    readiness_reasons = readiness.get("reasons") if isinstance(readiness.get("reasons"), list) else []
    safety_signals = summary.get("safetySignals") if isinstance(summary.get("safetySignals"), list) else []
    safety_items = [
        safety_signal_description(signal)
        for signal in safety_signals[:20]
        if isinstance(signal, dict)
    ]
    summary_limits = summary.get("summaryLimits") if isinstance(summary.get("summaryLimits"), dict) else {}
    summary_limit_items = summary_limit_descriptions(summary_limits)

    return f"""---
name: {frontmatter_value(skill_name)}
description: {frontmatter_value(description)}
---

# {title_from_skill_name(skill_name)}

## Purpose

Replay or adapt the workflow captured with Open Computer Use Record & Replay. This is a generated draft: preserve the observed sequence, but replace user-specific values with explicit inputs before using it on real data.

## Inputs To Confirm

- The user's concrete goal for this replay.
- Required app/account/login state.
- Any names, paths, message text, dates, or account-specific values that were redacted or should be parameterized.
- Whether any step sends, deletes, purchases, uploads, approves, or otherwise changes external state.

## Runtime Inputs

{markdown_list(input_items, "No text or selection inputs were inferred. Still ask the user for any values that should vary between replays.")}

## Workflow Readiness

- Status: {readiness.get("status") or "unknown"}
- Can create skill draft: {str(readiness.get("canCreateSkillDraft")).lower()}
- Requires human review: {str(readiness.get("requiresHumanReview")).lower()}
- Recommended next step: {readiness.get("recommendedNextStep") or "Inspect `events.jsonl` before finalizing this skill."}

{markdown_list([str(reason) for reason in readiness_reasons], "No readiness issues were detected by the summary helper.")}

## Summary Limits

{markdown_list(summary_limit_items, "No high-volume summary fields were truncated.")}

## Recorded Context

{markdown_list(window_items, "No stable app/window context was captured; inspect `references/recording-summary.json`.")}

## Agent Replay Procedure

- Before replaying UI actions, check whether a connector, API, or dedicated tool can perform the stable semantic operation more reliably than desktop automation; use Computer Use for visually dependent verification, unsupported UI interactions, or when manipulating the interface is itself the workflow.
- Start by calling `get_app_state` for the recorded app or the app the user names; verify the expected window or equivalent screen is present.
- For each observed step, resolve the current target by visible label, role, title, or neighboring text from `references/recording-summary.json`; use `element_index` actions when a semantic element is available.
- Use coordinate clicks or drags only as a last resort after refreshing the screenshot and confirming the coordinate system still matches the current window.
- For text entry, collect the runtime value from the user or task context, focus the observed input target, then use `type_text` or `set_value` according to the current app state.
- Pause and ask for explicit confirmation before sends, deletes, purchases, approvals, uploads, or other externally visible changes.

## Replay Steps

{markdown_list(action_items, "No high-level action sequence was captured; ask the user to re-record after fixing permissions.")}

## Evidence

- Event count: {summary.get("eventCount")}
- Action event count: {summary.get("actionEventCount")}
- End reason: {summary.get("endReason") or "unknown"}
- Has AX context: {str(evidence.get("hasAXContext")).lower()}
- Has target elements: {str(evidence.get("hasTargetElements")).lower()}
- Has redaction signals: {str(evidence.get("hasRedactionSignals")).lower()}
- Has safety signals: {str(evidence.get("hasSafetySignals")).lower()}

## Warnings

{markdown_list([str(warning) for warning in warnings], "No summary warnings were reported.")}

## Safety

- Do not reconstruct passwords, OTPs, API keys, terminal buffers, or other redacted values.
- Ask for confirmation before externally visible or destructive actions.
- Prefer semantic targets, labels, app names, and keyboard shortcuts over raw coordinates.
- Re-check the current app state before executing each step; recorded UI positions may drift.

### Confirmation Signals

{markdown_list(safety_items, "No specific confirmation-sensitive actions were detected by the summary helper. Still ask before externally visible changes.")}

## Verification

- Before packaging this skill, rerun `open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadata-or-session>` on the source recording.
- Compare the final app state with the user's requested outcome, not just the recorded event sequence.
- If replay behavior depends on missing AX targets, screenshots, or redacted text, refine this draft against `events.jsonl` before installing it.
- If `summaryLimits.hasTruncatedSummary` is true, inspect the original `events.jsonl` for omitted steps before finalizing this skill.

## Finalizing The Skill

- Treat this directory as a skill draft, not a standalone runbook or replay plan.
- Read and follow the `skill-creator` skill before packaging or installing the skill.
- Complete the `skill-creator` workflow, including validation, before reporting that this skill was created.
- Keep reusable workflow intent, prerequisites, runtime inputs, safety confirmations, and verification steps in the skill; omit raw event logs and user-specific values.
- The final deliverable should be an actual discoverable skill directory, not only this generated Markdown draft.

## Source

The generated summary is stored in `references/recording-summary.json`. Treat `events.jsonl` from the original recording as the primary evidence when refining this draft.
"""


def write_skill(output_dir: pathlib.Path, skill_name: str, description: str, summary: dict[str, Any], overwrite: bool) -> None:
    readiness = summary.get("skillReadiness") if isinstance(summary.get("skillReadiness"), dict) else {}
    if readiness.get("canCreateSkillDraft") is not True:
        message = readiness.get("recommendedNextStep") or (
            "Recording does not contain enough usable evidence to create a skill draft."
        )
        raise ValueError(str(message))

    if output_dir.exists():
        if not overwrite:
            raise ValueError(f"output directory already exists: {output_dir}")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)
    references_dir = output_dir / "references"
    references_dir.mkdir()

    sanitized = sanitize_summary(summary)
    (output_dir / "SKILL.md").write_text(
        render_skill(skill_name, description, sanitized),
        encoding="utf-8",
    )
    (references_dir / "recording-summary.json").write_text(
        json.dumps(sanitized, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    skill_name = args.skill_name.strip()
    if not SKILL_NAME_PATTERN.fullmatch(skill_name):
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "invalidSkillName",
                    "message": "skill name must use lowercase letters, numbers, and hyphens",
                }
            ),
            file=sys.stderr,
        )
        return 1

    description = args.description or (
        f"Replay a workflow captured by Open Computer Use Record & Replay for {skill_name}."
    )

    try:
        run_validation(args.recording)
        summary = run_summary(args.recording, include_text=args.include_text)
        write_skill(args.output_dir, skill_name, description, summary, overwrite=args.overwrite)
    except ValueError as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "ok": True,
                "skillName": skill_name,
                "outputDir": str(args.output_dir),
                "skillPath": str(args.output_dir / "SKILL.md"),
                "summaryPath": str(args.output_dir / "references/recording-summary.json"),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
