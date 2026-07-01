## [2026-07-01 18:25] | Task: Record & Replay official golden baseline

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `macOS local shell + Codex Record & Replay hosted MCP`

### User Query
> 复刻官方 Record & Replay，并基于官方行为推进 OCU baseline；允许调用官方录制，但完成后要确保停止，不要留下后台录制。

### Changes Overview
**Scope:** Record & Replay fixture/readiness/capture-packet/docs

**Key Actions:**
- **Official fixture**: Imported the required `simple-action-stop` official successful recording fixture after hosted capture and redaction.
- **Readiness compatibility**: Updated golden readiness and recording compare helpers to treat official top-level `ax.mode=fullTree` payloads as full AX evidence.
- **Candidate handoff**: Changed generated OCU candidate wrappers to import candidates without making same-scenario strong compare part of the required official golden gate.
- **Docs**: Updated Record & Replay design/capture docs and README commands to distinguish required official fixture readiness from optional candidate calibration.

### Design Intent (Why)
The first official hosted recording showed that official sessions may include extra host/control events compared with synthetic OCU candidate recordings. The required official golden gate should therefore prove that the official fixture exists and passes scenario readiness, while OCU candidate comparison remains a calibration tool for finding gaps.

### Files Modified
- `scripts/check-event-stream-golden-readiness.py`
- `scripts/compare-event-stream-recordings.py`
- `scripts/prepare-record-and-replay-official-golden-capture.py`
- `docs/references/codex-computer-use-reverse-engineering/fixtures/recordings/official-simple-action-stop-1.0.857/`
- `docs/design-docs/record-and-replay-official-golden-capture.md`
- `docs/design-docs/record-and-replay-replication.md`
- `README.md`
- `README.zh-CN.md`
