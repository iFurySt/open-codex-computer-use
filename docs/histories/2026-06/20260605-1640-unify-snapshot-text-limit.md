## [2026-06-05 16:40] | Task: Unify snapshot text limit

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex desktop`

### User Query
> Unify the default snapshot text truncation across macOS, Linux, and Windows to 500 characters, append `...` when truncated, and add an explicit full-text parameter for `get_app_state` and `snapshot`.

### Changes Overview
**Scope:** macOS Swift renderer, Linux runtime, Windows runtime, CLI/tool schema, tests.

**Key Actions:**
- Added optional `show_full_text` / `--show-full-text` support for full accessibility text output.
- Changed macOS snapshot text truncation from 160 to the shared 500 character default.
- Unified Linux and Windows truncation markers so truncated text appends `...`.
- Kept node count, tree depth, image, and action-result refresh protections unchanged.

### Design Intent (Why)
Default truncation protects snapshot size and preserves upstream-compatible behavior, while the explicit full-text option lets users inspect long semantic text such as chat messages without adding URL- or page-specific rendering rules.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseWindows/runtime.ps1`

### Follow-up 2026-06-18

**Scope:** Agent-facing Open Computer Use skill docs.

**Key Actions:**
- Documented when agents should request full text with `show_full_text: true`.
- Added CLI examples for `get_app_state` full-text mode and `snapshot --show-full-text`.
- Added troubleshooting guidance for visible text ending in `...`, clarifying that full-text mode only removes the text character limit and does not relax other snapshot protections.

**Files Modified:**
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/references/troubleshooting.md`

### Follow-up 2026-06-30

**Scope:** Snapshot text-limit public API and agent-facing docs.

**Key Actions:**
- Replaced `show_full_text` / `--show-full-text` with the unified breaking API `text_limit` / `--text-limit`.
- Kept the default text limit at 500 characters and preserved `...` when truncation happens.
- Added support for `text_limit: "max"` and `--text-limit max` to request full accessibility text without project-level text truncation.
- Kept action-tool refreshed state on the default 500 character text limit; custom `text_limit` applies only to explicit `get_app_state` and `snapshot`.
- Updated skill docs and troubleshooting guidance so agents use `text_limit: 1000` for longer text or `text_limit: "max"` only when full text is required.

**Files Modified:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/references/troubleshooting.md`
