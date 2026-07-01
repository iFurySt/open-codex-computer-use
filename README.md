# open-computer-use

[![English](https://img.shields.io/badge/English-Click-yellow)](./README.md)
[![简体中文](https://img.shields.io/badge/简体中文-点击查看-orange)](./README.zh-CN.md)
[![Release](https://img.shields.io/github/v/release/iFurySt/open-codex-computer-use)](https://github.com/iFurySt/open-codex-computer-use/releases)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/iFurySt/open-codex-computer-use)
<a href="https://llmapis.com?source=https%3A%2F%2Fgithub.com%2FiFurySt%2Fopen-codex-computer-use" target="_blank"><img src="https://llmapis.com/api/badge/iFurySt/open-codex-computer-use" alt="LLMAPIS" width="20" /></a>

> [!TIP]
> Interested in Browser Use? Check out [open-browser-use](https://github.com/iFurySt/open-codex-browser-use).

---

`open-computer-use` is an open-source `Computer Use` service wrapped as `MCP`. Any AI agent or MCP client can use it to run Computer Use on macOS, Linux, and Windows.

This project was inspired by OpenAI's [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/). It showed that non-intrusive CUA can be built on top of Accessibility, so I decided to build an open-source version.

I started this repo with my [harness template](https://github.com/iFurySt/harness-template), a template for quickly spinning up AI-first projects. It has been one of our most useful workflows lately, especially for nearly 100% AI-generated projects. I also wrote [a post](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/) about the methodology behind it.

## Demos

### Codex App and Codex CLI

[![Open Computer Use custom demo cover](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

<sub><em>`open-computer-use` used as Computer Use in Codex App and Codex CLI, matching the official experience.</em></sub>

### Gemini CLI

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI connects to `open-computer-use` through MCP and runs full Computer Use actions.</em></sub>

### Linux

https://github.com/user-attachments/assets/e036b1c8-2200-4896-abd4-19225915cf66

<sub><em>`open-computer-use` running on Linux.</em></sub>

## Quick Start

```bash
npm i -g open-computer-use
```

The npm package also exposes `ocu` as the short CLI alias.

**On macOS, run it once and grant `Accessibility` and `Screen Recording`. Windows and Linux do not need this step.**

```bash
open-computer-use
# or
ocu
```

Before using it, install it into your agent:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
```

Or add it to your own client manually:

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
```

### Skill

Install the general Computer Use skill directly:

```bash
# Install for Codex
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y
npx skills ls -g -a codex | rg 'open-computer-use'
```

Install the dedicated Record & Replay workflow skill when you only want the
macOS recording-to-skill flow:

```bash
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use-record-and-replay -y
```

Install for Claude Code:

```bash
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use -y
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use-record-and-replay -y
```

Update an existing global install, including the Codex installs created above:

```bash
npx skills update open-computer-use -g -y
npx skills update open-computer-use-record-and-replay -g -y
```

You can also manually download and install the
[`open-computer-use` skill](./skills/open-computer-use) or the
[`open-computer-use-record-and-replay` skill](./skills/open-computer-use-record-and-replay).

### Record & Replay Quick Start

Use the dedicated Record & Replay surface when you want a user to demonstrate
a macOS workflow and turn it into a reusable skill:

```bash
# Install the official-compatible 3-tool Record & Replay MCP surface into Codex
open-computer-use install-codex-record-and-replay-mcp

# Optional: install the thin workflow skill
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use-record-and-replay -y
```

The MCP surface intentionally exposes only:

```text
event_stream_start
event_stream_status
event_stream_stop
```

OCU-specific lifecycle helpers stay in the CLI layer:

```bash
# Start a recording through the OCU app agent and show local controls
open-computer-use event-stream start --json

# Wait for Done / Discard from an independent wrapper
open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'

# Validate and turn a completed session into a first-draft skill
open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>
open-computer-use event-stream summarize --json <metadataPath-or-sessionPath>
open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what it does>" \
  --output-dir <new-skill-dir>
```

To split Record & Replay into its own thin skill repo:

```bash
open-computer-use scaffold-record-and-replay-skill-repo --output-dir ./open-computer-use-rnr-skill-repo
(cd ./open-computer-use-rnr-skill-repo && ./scripts/check.sh)
```

## More

Besides the MCP JSON config above, you can also use the built-in commands:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
ocu install-codex-mcp

# Install the Record & Replay MCP surface into Codex separately
open-computer-use install-codex-record-and-replay-mcp

# Install as a Codex plugin, mainly for Codex App
open-computer-use install-codex-plugin

# Install into Claude Code by writing to ~/.claude.json
open-computer-use install-claude-mcp

# Install into Gemini CLI for the current project by writing to ./.gemini/settings.json
open-computer-use install-gemini-mcp

# Install into Gemini CLI user config instead
open-computer-use install-gemini-mcp --scope user

# Install into opencode by writing to ~/.config/opencode/opencode.json (or the active config file)
open-computer-use install-opencode-mcp

# Call a single Computer Use tool and print the MCP-style JSON result
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'

# Run a sequence in one process so element_index state can be reused
# Sequence runs sleep 1s between successful operations by default
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

# Check permissions; onboarding only opens when something is missing
open-computer-use doctor

# Record & Replay-compatible event stream
open-computer-use install-codex-record-and-replay-mcp
open-computer-use event-stream mcp
open-computer-use event-stream start --json
open-computer-use event-stream status --json
open-computer-use event-stream stop --json
open-computer-use event-stream cancel --json
open-computer-use event-stream wait --json --session-id <id> --timeout 30
# wait --json includes OCU extension fields waitTimedOut and optional notification
open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'
open-computer-use event-stream validate --json <metadataPath> --strict-ocu
open-computer-use event-stream validate --json --require-skill-draft <eventsPath>
open-computer-use event-stream summarize --json <metadataPath>
open-computer-use event-stream scaffold-skill --json <metadataPath-or-eventsPath> --skill-name <new-skill-name> --description "<what it does>" --output-dir <new-skill-dir>
scripts/validate-event-stream-recording.py <metadataPath> --strict-ocu
scripts/validate-event-stream-recording.py <eventsPath> --require-skill-draft
scripts/summarize-event-stream-recording.py <metadataPath>
scripts/scaffold-event-stream-skill.py <metadataPath-or-eventsPath> --skill-name <new-skill-name> --description "<what it does>" --output-dir <new-skill-dir>
scripts/scaffold-record-and-replay-skill-repo.py --output-dir /tmp/open-computer-use-rnr-skill-repo
# The installed standalone repo scaffold helper uses Python 3; set PYTHON=/path/to/python3 if needed
open-computer-use scaffold-record-and-replay-skill-repo --output-dir /tmp/open-computer-use-rnr-skill-repo
(cd /tmp/open-computer-use-rnr-skill-repo && ./scripts/check.sh)
scripts/import-event-stream-fixture.py <metadataPath> --name <fixture-name> --source official
# Inspect hosted official JSON first without creating a fixture.
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --mcp-transcript <mcp-transcript.json> --require-mcp-transcript-evidence --inspect-only
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --mcp-transcript <mcp-transcript.json> --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# Or generate a capture packet first; replace the placeholder hosted JSON, then run its wrappers.
make record-and-replay-official-golden-capture-packet RNR_SCENARIO=simple-action-stop RNR_PACKET_DIR=<packet-dir>
scripts/finalize-record-and-replay-official-capture-packet.py --packet-dir <packet-dir> --start-json <event_stream_start-response.json> --status-json <event_stream_status-active-response.json> --stop-json <event_stream_stop-response.json> --final-status-json <event_stream_status-final-response.json>
(cd <packet-dir> && ./verify-inputs.sh && ./inspect-only.sh && ./import-fixture.sh)
(cd <packet-dir> && ./strict-golden-gate.sh)
# Only use this while a strict gate failure is expected because required official golden is missing/not-ready.
(cd <packet-dir> && ./strict-expected-failure-audit.sh)
# Generate required + recommended capture packets and batch wrappers.
make record-and-replay-official-golden-capture-packet-set RNR_PACKET_DIR=<packet-dir>
(cd <packet-dir> && ./verify-all.sh && ./inspect-all.sh && ./import-all.sh)
# Optional calibration: imports same-scenario OCU candidates and prints pairing/fixture-set commands
(cd <packet-dir> && ./ingest-ocu-candidates.sh)
(cd <packet-dir> && ./strict-expected-failure-audit.sh)
# Or pipe a separate transcript JSON while reading the status JSON from a file
cat <mcp-transcript.json> | scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --mcp-transcript - --name <fixture-name> --scenario simple-action-stop --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# Or pipe a hosted event_stream_stop/status JSON directly; use --status-json-base-dir if it contains relative paths
cat <event_stream_stop-response.json> | scripts/ingest-official-record-and-replay-fixture.py --status-json - --status-json-base-dir <recording-parent-dir> --name <fixture-name> --scenario simple-action-stop --use-status-json-as-transcript --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# --check-coverage reports required scenario coverage and, when present, required fixture readiness.
# --require-coverage also requires the required scenario to pass readiness.
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --require-coverage
# --smoke-json can consume mcpTranscriptPath from action smoke output.
# Keep the smoke temp dir when saving stdout for later import:
#   OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_KEEP_TMP=1 make event-stream-action-smoke > /tmp/action-smoke.jsonl
# Action smoke defaults to mixed-action-stop; set OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop
# or drag-stop to sample a specific real-input candidate scenario.
# Or let the importer run action smoke and retain the evidence until import finishes:
#   scripts/ingest-ocu-record-and-replay-candidate.py --run-action-smoke --scenario drag-stop ...
scripts/ingest-ocu-record-and-replay-candidate.py --smoke-json <action-smoke-output.jsonl> --name <candidate-name> --scenario simple-action-stop --official-root <official-fixtures> --check-fixture-set
scripts/compare-event-stream-recordings.py <official-fixture> <ocu-recording> --require-same-event-sequence --require-same-schema --require-ax-diff-evidence
scripts/probe-event-stream-recording.py --target local --start-stop
scripts/probe-event-stream-recording.py --target official

# Run local validation from a source checkout
make ci
make smoke
make event-stream-surface-smoke
make event-stream-probe
make event-stream-probe-fixture-smoke
make event-stream-official-probe
make event-stream-smoke
make event-stream-smoke-matrix
make event-stream-fixture-smoke
make event-stream-official-fixture-ingest-smoke
make event-stream-official-fixture-coverage-smoke
make event-stream-ocu-candidate-ingest-smoke
make event-stream-compare-smoke
make event-stream-skill-scaffold-smoke
make record-and-replay-skill-repo-smoke
# Requires local dist/ native artifacts; verifies npm-installed repo scaffold command
make npm-record-and-replay-skill-repo-smoke
# Opt-in baseline: proves the current OCU baseline is usable and reports official golden scenario coverage
make record-and-replay-baseline-smoke
# Release / standalone evidence: writes dist/record-and-replay-baseline-summary.json
make record-and-replay-baseline-audit
# Fast fixture-only gate: requires imported official successful recordings to pass readiness
make record-and-replay-official-golden-fixture-gate
# Read-only next-step planner for same-scenario OCU candidate capture/import after official fixture import
make record-and-replay-ocu-candidate-pairing-preflight
# Strict release gate: same baseline checks, plus required official successful recording readiness
make record-and-replay-official-golden-gate
# Strict release evidence: writes dist/record-and-replay-official-golden-gate-summary.json.
# If required official golden is missing/not-ready, audit that expected failure explicitly:
make record-and-replay-official-golden-gate-audit
scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing
# Force non-interactive start approval for local automation
OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=approve make event-stream-smoke
# Verify host-side MCP elicitation approval without changing the 3-tool surface
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_MCP_ELICITATION=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_SCREENSHOTS=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_NO_ACTIVE=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TIMEOUT=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_WAIT_TIMEOUT=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL=1 make event-stream-smoke
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL=deny make event-stream-smoke
# App-agent wait smoke also verifies wait --notify-command callback delivery
OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APP_AGENT_WAIT=1 make event-stream-smoke
# Optional matrix additions
OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_SCREENSHOTS=1 make event-stream-smoke-matrix
OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_OFFICIAL=1 make event-stream-smoke-matrix
# Optional official non-recording surface drift check
./scripts/compare-event-stream-surface.py --use-default-official
# Optional official raw start/status/stop probe; currently expected to depend on host/runtime state
make event-stream-official-start-probe
OPEN_COMPUTER_USE_STRESS_LOOPS=20 make stress
make agent-smoke
make agent-smoke SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=claude,codex --command=open-computer-use
OPEN_COMPUTER_USE_HERMES_PROVIDER=anthropic OPEN_COMPUTER_USE_HERMES_MODEL=claude-opus-4-20250514 make agent-smoke AGENTS=hermes SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --hermes-max-turns=12

# Show help
open-computer-use -h
ocu -h
```

## Cursor Motion

Cursor Motion is an open-source cursor motion system for macOS, based on public information shared by members of the Software.Inc team. You can download the app from the [Releases page](https://github.com/iFurySt/open-codex-computer-use/releases).

[![Cursor Motion custom demo cover](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## Star History

<a href="https://www.star-history.com/?repos=iFurySt%2Fopen-codex-computer-use&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
    <img alt="Star History Chart for open-computer-use" src="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
  </picture>
</a>

## License

[MIT](./LICENSE)
