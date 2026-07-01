# Open Computer Use Record & Replay

Read this reference when the user wants to demonstrate a macOS workflow and turn the captured event stream into reusable automation.

Record & Replay support is macOS-only in the current baseline. It exposes an official-compatible event-stream MCP surface plus OCU-only CLI lifecycle helpers for independent integrations.

## MCP Server

For Codex, install the separate Record & Replay MCP entry with:

```sh
open-computer-use install-codex-record-and-replay-mcp
```

For other MCP clients that support stdio servers:

```toml
[mcp_servers.record_and_replay]
command = "open-computer-use"
args = ["event-stream", "mcp"]
```

Equivalent JSON shape:

```json
{
  "mcpServers": {
    "record-and-replay": {
      "command": "open-computer-use",
      "args": ["event-stream", "mcp"]
    }
  }
}
```

This MCP server is a separate surface from `open-computer-use mcp`. It exposes only the official-compatible tools:

```text
event_stream_start
event_stream_status
event_stream_stop
```

Do not add `cancel`, `wait`, callback, or webhook arguments to this MCP surface. Those are OCU extension-layer concerns.

If the MCP host supports elicitation and should own the approval prompt, launch the server with:

```sh
OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=mcp open-computer-use event-stream mcp
```

The server will request approval with MCP `elicitation/create` only when the host declares `capabilities.elicitation` during `initialize`. Accept starts the recording; decline, cancel, or unsupported elicitation returns an approval error without creating a session. OCU sends a host-compatible `mode: "form"` request with an empty object schema; the exact official Record & Replay business message / metadata still needs golden recording calibration. This path does not change the official-compatible three-tool surface.

## Recording Workflow

1. Confirm the user is ready before starting. Starting may show a local approval UI.
2. Call `event_stream_start` once. If it reports an already active recording, do not start another one. Explain that a recording is already in progress and ask whether the user wants to use that active recording or wait until it is stopped.
3. Let the user perform the workflow. Ask the user to tell you when they are done, and tell them the recording can last up to 30 minutes. Do not poll in a loop while they are recording.
4. When the user says they are done, call `event_stream_stop`.
5. Read `eventsPath` and `metadataPath` from the returned status.
6. Treat `events.jsonl` as the primary evidence. `metadata.json` and `session.json` provide session timing, paths, counts, state, and `endReason`.

If the user says they cancelled recording, do not call `event_stream_stop` again. Read `session.json` only when needed to confirm `endReason`. OCU status JSON also includes `sessionPath` as a convenience alias path; official-compatible workflows should still treat `metadataPath` and `eventsPath` as the primary returned paths.

## Session Files

Each recording writes a session directory containing:

```text
events.jsonl
metadata.json
session.json
suppressed.jsonl
screenshots/
```

`session.json` is an alias of `metadata.json`. `suppressed.jsonl` contains events or diagnostics omitted from the main stream because of limits, privacy policy, or degraded context collection.

OCU status and metadata include `sessionPath` as a convenience field pointing at the `session.json` alias. This is an OCU integration aid, not an extra MCP tool or parameter.

The main event stream can include mouse, keyboard, window, selection, terminal, debug, and AX payload events. AX payloads may be full trees or compact diffs using `~`, `+`, and `-`.

## OCU CLI Extensions

Independent integrations can control the same app-agent recorder with:

```sh
open-computer-use event-stream start --json
open-computer-use event-stream status --json
open-computer-use event-stream stop --json
open-computer-use event-stream cancel --json
open-computer-use event-stream wait --json --session-id <id> --timeout <seconds>
open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'
open-computer-use event-stream validate --json <session-dir-or-metadata>
open-computer-use event-stream summarize --json <session-dir-or-metadata>
open-computer-use event-stream scaffold-skill --json --skill-name <name> --output-dir <dir> <session-dir-or-metadata>
```

`wait --json` returns `waitTimedOut` and `waitSessionMatched`, which are OCU extension fields. `waitTimedOut=false` means the waiter was released by stop/cancel/end for the requested session. `waitSessionMatched=false` means the requested session id was not found or the current active session does not match; in that case `waitTimedOut=true` and notification callbacks are skipped.

`--notify-command` is also an OCU extension. It accepts a JSON argv array, runs only when `waitTimedOut=false`, and receives the final status JSON on stdin plus these environment variables when present:

- `OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID`
- `OPEN_COMPUTER_USE_EVENT_STREAM_STATE`
- `OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON`
- `OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH`
- `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH`

The callback is synchronous and bounded by `OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS` or 10 seconds by default. A non-zero exit or timeout marks the CLI result as an error and adds a `notification` object to the JSON response.

Use `wait` for independent plugin or skill integrations that need to resume work when the user clicks Done or Discard in OCU's recording controls. Keep `wait` out of the official-compatible MCP tools.

## Validation

Useful local checks:

```sh
make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_NO_ACTIVE=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_MCP_ELICITATION=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL=1 make event-stream-smoke
```

The official compare smoke only checks `initialize` and `tools/list`; it does not start an official recording.

To validate an existing recording directory or returned `metadataPath`:

```sh
open-computer-use event-stream validate --json <metadataPath>
open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath>
open-computer-use event-stream validate --json --require-skill-draft <eventsPath>
scripts/validate-event-stream-recording.py <session-dir-or-metadata>
scripts/validate-event-stream-recording.py <metadataPath> --strict-ocu --require-skill-draft
scripts/validate-event-stream-recording.py <eventsPath> --require-skill-draft
scripts/summarize-event-stream-recording.py <metadataPath>
open-computer-use event-stream summarize --json <metadataPath>
```

Use `--strict-ocu` for complete recordings produced by Open Computer Use. It checks metadata/session alias consistency and verifies that the declared `metadataPath`, `sessionPath`, `eventsPath`, and `suppressedEventsPath` handoff paths resolve to files. Leave it off for newly captured official golden recordings until their exact alias/index behavior has been confirmed. Non-strict validation can also take `events.jsonl` directly; in that mode it validates the event stream, confirms `session.started` appears exactly once and opens the stream, confirms `session.ended` appears exactly once and closes the stream when present, checks skill-draft evidence, infers cancellation from `session.ended.endReason=recording_controls_cancelled`, and only warns that metadata/session files are unavailable.

Use the runtime CLI as the preferred integration point for an installed OCU binary. `event-stream validate` checks session file consistency when metadata is present and returns `ok=false` as a tool-style error when required structure is missing; add `--require-skill-draft` before scaffold generation to require at least one high-level action and reject incomplete recordings, cancelled recordings, recordings where `session.started` is missing, duplicated, or not the first event, recordings where `session.ended` appears more than once or is not the final event, or recordings with blocking diagnostics such as unavailable input monitoring. `event-stream scaffold-skill` and the source Python scaffold also run this validator gate before writing files, so malformed metadata/session/events cannot be turned into a draft just because the stream can be summarized. The Python validator remains a source-checkout helper for OCU development and official golden recording calibration.

Use the summary output to quickly inspect event counts, windows, action sequence, target/focused elements, selection signals, debug errors, and redaction signals before creating a skill. It is a triage aid; `events.jsonl` remains the primary evidence. Both summary paths omit raw AX `value` and `selectedText` by default and report lengths instead; pass `--include-text` only when reviewing a deliberately sanitized recording.

Summary output can include:

- `runtimeInputs`: text-entry and selection-derived values that should become explicit runtime inputs in the final skill.
- `safetySignals`: submit/send/delete/save/upload/publish-style confirmation hints extracted from action events and semantic target titles. Treat them as a first checklist for confirmation-sensitive steps, then verify against `events.jsonl` and nearby app/window context before finalizing the skill.
- `summaryLimits`: caps, stored counts, source counts, and omitted counts for high-volume summary fields. If `summaryLimits.hasTruncatedSummary=true`, the draft may omit later replay steps or evidence; read the original `events.jsonl` before finalizing.
- `skillEvidence.recordingIncomplete`: the recording is still active or lacks `session.ended`. Stop the recording and use the completed session before creating a skill.
- `skillEvidence.sessionStartedCountInvalid`: `session.started` is missing or duplicated. Treat the recording as malformed and ask the user to re-record before creating a skill.
- `skillEvidence.sessionStartedNotFirst`: events appear before `session.started`. Treat the recording as malformed and ask the user to re-record before creating a skill.
- `skillEvidence.sessionEndedNotFinal`: events appear after `session.ended`. Treat the recording as malformed and ask the user to re-record before creating a skill.
- `skillEvidence.sessionEndedCountInvalid`: multiple `session.ended` events appear. Treat the recording as malformed and ask the user to re-record before creating a skill.
- `blockingDiagnostics`: recording failures that make the demonstration unfit for skill creation, currently including `inputMonitorsUnavailable`. If present, fix permissions or recording setup and re-record instead of generating a skill.
- `skillEvidence.hasSafetySignals`: a boolean that should make the generated or final skill preserve Confirmation Signals and pause for explicit user approval before those steps.

Summary output includes `skillReadiness.status`:

- `ready`: enough structural evidence was captured to create a reusable skill draft.
- `needsReview`: a draft can be created, but missing context, diagnostics, or redaction signals require human review before finalizing.
- `insufficient`: do not invent a workflow; ask the user to re-record or provide the missing information.

Incomplete, cancelled, and malformed recordings are always `insufficient` for skill creation. If metadata state is `recording`, `active=true`, or `session.ended` is missing, stop the recording and re-run validation on the completed session. If metadata state is `cancelled`, metadata `endReason=recording_controls_cancelled`, an events-only stream contains `session.ended.endReason=recording_controls_cancelled`, `session.started` is missing, duplicated, or not first, `session.ended` appears more than once, or `session.ended` is not the final event, summary/scaffold tooling should refuse to create a draft and the agent should ask the user to re-record.

To create a repeatable first-draft skill directory from a validated recording with an installed OCU runtime:

```sh
open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what the replay skill does>" \
  --output-dir <new-skill-dir>
```

When working in this source checkout, the Python helper is still useful as a cross-check:

```sh
scripts/scaffold-event-stream-skill.py <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what the replay skill does>" \
  --output-dir <new-skill-dir>
```

The scaffold writes a `SKILL.md` draft plus `references/recording-summary.json` only after the validator gate succeeds. The draft includes workflow readiness, inferred runtime inputs, confirmation signals, an agent replay procedure that first checks connectors/APIs/dedicated tools and then prefers `get_app_state` plus semantic `element_index` actions for UI-dependent work, observed replay steps, a verification checklist, and a finalization checklist that points back to `skill-creator`. It sanitizes local file paths and avoids raw AX text by default. Treat the result as an editable skill draft, not a standalone runbook: inspect `events.jsonl`, replace user-specific values with explicit inputs, tighten any destructive or externally visible steps, then complete the `skill-creator` workflow and validation before reporting the actual discoverable skill as created.

For automated tests, use:

```sh
swift test --filter EventStream
```

## Safety

- Do not record passwords, OTPs, API keys, financial account numbers, private medical/legal/HR content, or other unrelated sensitive information.
- Secure or protected text input may be redacted in the event stream.
- Obvious terminal buffers are treated conservatively and should not be summarized as raw user content unless the user explicitly asks.
- Ask before creating or running a reusable skill that would submit, send, delete, purchase, approve, upload, publish, save externally visible state, or otherwise act on the user's behalf; preserve any generated `safetySignals` / Confirmation Signals until the final skill has an equivalent explicit approval step.
