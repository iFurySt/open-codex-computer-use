---
name: open-computer-use-record-and-replay
description: Record a user's macOS workflow with Open Computer Use Record & Replay and turn the captured event stream into a reusable skill or automation. Use when the user wants to demonstrate steps, capture a workflow, replay a process, or create a skill from recorded desktop actions without depending on Codex.app-specific UI.
---

# Open Computer Use Record & Replay

## Overview

Use this skill to record a user's macOS workflow through Open Computer Use and convert the captured event stream into reusable automation. This workflow is independent of Codex.app-specific plugin UI; Open Computer Use owns the start approval, recording controls, session files, wait listener, and notification handoff.

Current scope is macOS only.

## Required MCP Server

Configure the Record & Replay MCP surface separately from the normal Computer Use MCP server. For Codex, prefer the installer:

```sh
open-computer-use install-codex-record-and-replay-mcp
```

Equivalent manual config:

```toml
[mcp_servers.record_and_replay]
command = "open-computer-use"
args = ["event-stream", "mcp"]
```

This server exposes only the official-compatible tools:

```text
event_stream_start
event_stream_status
event_stream_stop
```

Do not add cancel, wait, callback, webhook, or extra arguments to this MCP surface. Those are Open Computer Use extension-layer CLI features.

## Recording Workflow

1. Confirm the user is ready to record. Starting may show an Open Computer Use approval dialog and recording control bar.
2. Call `event_stream_start` once. If it reports an already active recording, do not start another one. Explain that a recording is already in progress and ask whether the user wants to use that active recording or wait until it is stopped.
3. End the turn and let the user perform the workflow. Ask the user to tell you when they are done, and tell them the recording can last up to 30 minutes. Do not poll while the user is recording.
4. Use `event_stream_status` only when the user asks for status or returns after recording; do not use it to wait for completion.
5. When the user says they are done, call `event_stream_stop`.
6. Parse the returned text JSON and read `eventsPath`, `metadataPath`, and, when present, `sessionPath`. The MCP server does not expose event-stream contents directly.
7. Treat `events.jsonl` as the primary evidence. Use `metadata.json` or `session.json` only for session timing, state, counts, paths, and `endReason`.
8. Validate and summarize the recording before generating any reusable asset:

```sh
open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>
open-computer-use event-stream validate --json --require-skill-draft <eventsPath>
open-computer-use event-stream summarize --json <metadataPath-or-sessionPath>
```

Use the strict validation command for complete OCU session output. It proves metadata/session alias consistency and that the declared `metadataPath`, `sessionPath`, `eventsPath`, and `suppressedEventsPath` handoff paths resolve to files. If only `eventsPath` is available, run the non-strict events-only validator; it can still check JSONL readability, completion, whether `session.started` appears exactly once and is the first event, whether `session.ended` appears exactly once and is the final event, high-level action evidence, cancellation from `session.ended.endReason=recording_controls_cancelled`, and blocking diagnostics, but it cannot prove metadata/session alias consistency or declared handoff paths.

For a repeatable first draft, use the installed runtime CLI:

```sh
open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what the replay skill does>" \
  --output-dir <new-skill-dir>
```

When developing inside this source checkout, the Python scaffold helper should
produce the same draft shape and can be used as a cross-check:

```sh
scripts/scaffold-event-stream-skill.py <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what the replay skill does>" \
  --output-dir <new-skill-dir>
```

The scaffold runs the same skill-draft validator gate before writing files, then writes `SKILL.md` and `references/recording-summary.json`. The generated `SKILL.md` includes inferred runtime inputs, an agent replay procedure that prefers `get_app_state` and semantic `element_index` actions, observed replay steps, and a verification checklist. It intentionally produces a draft, not a fully verified automation: review the original `events.jsonl`, replace user-specific values with inputs, and tighten the replay instructions before packaging or installing the generated skill.

The summary and generated draft include `skillReadiness` with `ready`, `needsReview`, or `insufficient` status. Treat `needsReview` as a signal to inspect `events.jsonl`, replace placeholders, and verify missing context before finalizing. Treat `insufficient` as a failed or incomplete demonstration: stop the recording if it is still active, or ask the user to re-record or provide the missing workflow information instead of inventing steps. Cancelled, incomplete, and malformed recordings are always insufficient for skill creation; scaffold commands should reject them instead of writing a draft, including events-only streams whose `session.ended.endReason` is `recording_controls_cancelled`, whose `session.started` is missing, duplicated, or not the first event, whose `session.ended` appears more than once, or whose `session.ended` is not the final event.

The summary and generated draft can also include `runtimeInputs`, `safetySignals`, `summaryLimits`, and `blockingDiagnostics`:

- Use `runtimeInputs` to identify text values, selected-content semantics, paths, names, dates, or other values that must become explicit runtime inputs instead of copied from the recording.
- Use `safetySignals` to find recorded submit/send/delete/save/upload/publish-style actions that require explicit user confirmation before replay. These signals are hints from the summary helper, not a replacement for reading `events.jsonl`; still inspect neighboring events and app/window context before finalizing safety instructions.
- If `skillEvidence.hasSafetySignals=true`, keep the generated Confirmation Signals or equivalent wording in the final skill and make the replay procedure pause before those steps.
- If `summaryLimits.hasTruncatedSummary=true`, the summary omitted some high-volume fields such as later replay steps, targets, runtime inputs, or diagnostics. Do not finalize the skill from the draft alone; inspect the original `events.jsonl` for omitted steps and update the final skill accordingly.
- If `skillEvidence.recordingIncomplete=true`, do not create or update a skill from that recording. Stop the active recording first, then validate and summarize the completed session.
- If `skillEvidence.sessionStartedCountInvalid=true` or `sessionStartedCount` is not 1, do not create or update a skill from that recording. Ask the user to re-record so the start event is written exactly once.
- If `skillEvidence.sessionStartedNotFirst=true` or `sessionStartedIsFirst=false`, do not create or update a skill from that recording. Ask the user to re-record so the start event opens the stream.
- If `skillEvidence.sessionEndedNotFinal=true` or `sessionEndedIsFinal=false`, do not create or update a skill from that recording. Ask the user to re-record so the stop/cancel event closes the event stream.
- If `skillEvidence.sessionEndedCountInvalid=true` or `sessionEndedCount` is greater than 1, do not create or update a skill from that recording. Ask the user to re-record so the stop/cancel event is written exactly once.
- If `skillEvidence.hasBlockingDiagnostics=true` or `blockingDiagnostics` is non-empty, do not create or update a skill from that recording. Fix the reported recording permission or input monitoring issue, then ask the user to re-record.

If the recording contains enough information to identify a reusable workflow, do not stop at a summary, runbook, or replay plan. Use the scaffold as the starting artifact, then follow the `skill-creator` workflow to refine, validate, package, or install an actual discoverable skill.

If the user says they clicked Discard or cancelled recording, do not call `event_stream_stop` again. Read `sessionPath` or `session.json` only if you need to confirm `endReason=recording_controls_cancelled`, then acknowledge the cancellation and ask the user to re-record before creating or updating a skill.

## Creating The Reusable Skill

After validation, inspect the summary first, then inspect `events.jsonl` for the action details that matter. Build a reusable skill from the observed workflow rather than only summarizing the recording.

Before finalizing the skill, read and follow the `skill-creator` skill. Complete the `skill-creator` workflow, including validation, before reporting that the skill was created. The generated scaffold is a first draft; the final deliverable should be a usable, discoverable skill directory with clear triggers, prerequisites, runtime inputs, safety confirmations, replay instructions, and verification steps.

When creating the skill:

- Preserve the user's goal and decision points, not every raw mouse coordinate.
- Check whether an available connector, API, or dedicated tool can perform stable semantic operations more reliably than UI replay; use Computer Use for unsupported UI interactions, visually dependent verification, or when manipulating the interface is itself the task.
- Prefer app names, visible labels, element roles, text entry targets, and keyboard shortcuts over brittle coordinates.
- Use placeholders for user-specific values such as names, emails, paths, account ids, message text, or dates.
- Include prerequisites such as required apps, login state, permissions, or files.
- Call out destructive or externally visible steps that require confirmation before execution, using `safetySignals` as the first checklist and `events.jsonl` as the final evidence.
- Keep the resulting skill independent of Codex.app; reference `open-computer-use` CLI and MCP commands instead.

If the recording is too sparse, mostly empty, or contains only diagnostics such as `inputMonitorsUnavailable`, ask the user to retry after fixing permissions instead of inventing workflow steps.

## Independent Wait / Notify Integration

For a plugin or wrapper that needs to resume automatically after the user clicks Done or Discard, use the Open Computer Use CLI extension layer:

```sh
open-computer-use event-stream start --json
open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'
```

`wait --json` adds `waitTimedOut` and `waitSessionMatched`. `waitTimedOut=false` means the waiter was released by stop, cancel, or automatic end for the requested session. `waitSessionMatched=false` means the requested session id was not found or the current active session does not match; in that case `waitTimedOut=true` and notification callbacks are skipped.

`--notify-command` receives the final status JSON on stdin and these environment variables when present:

- `OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID`
- `OPEN_COMPUTER_USE_EVENT_STREAM_STATE`
- `OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON`
- `OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH`

Keep this listener path outside the official-compatible MCP tool surface.

## Safety

- Do not record passwords, OTPs, API keys, financial account numbers, private medical/legal/HR content, or unrelated private content.
- Ask before creating automation that sends, deletes, purchases, approves, uploads, or changes external state.
- Secure input and obvious terminal buffers may be redacted; do not reconstruct redacted secrets from context.
- If screenshots are present, treat them as sensitive evidence and avoid copying their content into the generated skill unless it is essential and sanitized.
