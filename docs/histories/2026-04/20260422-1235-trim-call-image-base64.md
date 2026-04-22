## [2026-04-22 12:35] | Task: Trim CLI image base64 output

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> 运行 `swift run OpenComputerUse call --calls-file examples/textedit-overlay-seq.json` 时，不要打印巨大的 base64。

### Changes Overview
**Scope:** Swift CLI output, tests, docs

**Key Actions:**
- **[CLI print sanitizing]**: Kept the `call` command result shape intact, but summarized `image.data` base64 when rendering pretty JSON to stdout.
- **[Regression coverage]**: Added a unit test to assert CLI JSON output preserves `mimeType` while omitting the raw base64 payload.
- **[Docs sync]**: Updated README and architecture notes so the CLI/MCP boundary stays explicit.

### Design Intent (Why)
`open-computer-use call` is a human-facing debug surface. Dumping full screenshot base64 makes local runs noisy and hard to inspect, while the actual MCP/tool result still needs to keep the real image payload available internally.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
