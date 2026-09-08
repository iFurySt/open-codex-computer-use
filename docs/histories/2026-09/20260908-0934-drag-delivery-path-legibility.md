## [2026-09-08 09:34] | Task: Make the default `drag` path legible

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `macOS 26 / Swift 6.3.3 (Command Line Tools)`

### 📥 User Query
> Pick up the drag investigation and work on a fix or clearer docs for the open GitHub issue (#53: `drag` executes without error but performs no window move / text selection).

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `skills/open-computer-use`, `docs/`

**Key Actions:**
- **[Delivery path helpers]**: added `DragDeliveryPath` (`app_post` / `global`), `dragDeliveryPath(environment:)`, `dragDeliveryNote(for:)` and `appendingDragDeliveryNote(to:path:)` next to `globalPointerFallbacksEnabled`. `performDragEvent` now returns the path it used and `drag` inserts the note as a text content item after the snapshot text and before the screenshot, so `primaryText` is unchanged.
- **[Tool description]**: the `drag` MCP tool description now states that the default path posts events directly to the target app, cannot drive window-server drag sessions (window moves, text selection, Finder drag-and-drop), and that those require `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` in the server process environment. This mirrors what `click_method` already says about `global`.
- **[Tests]**: unit tests for the path decision, the note wording, and the content-item placement with and without a screenshot; the tool-definitions test now checks the `drag` description.
- **[Docs]**: new `Drag Delivery` section in `skills/open-computer-use/references/usage.md`, the drag case added to the `SKILL.md` guardrail, `docs/ARCHITECTURE.md` updated, and a feature release note row added.

### 🧠 Design Intent (Why)
The default `CGEvent.postToPid` path was chosen deliberately on 2026-04-22 so `drag` never moves the user's real pointer. Its cost is that pid-targeted events never reach the window server, so a window move, drag-select or Finder drag-and-drop returns success with no effect. Two reporters on issue #53 read that as a bug because neither the tool description nor the result said which path ran, and the rationale lived only in the Chinese architecture and security docs. This change keeps the default and the safety gate exactly as they are and makes the outcome self-describing at the two places a caller actually looks: the tool schema before the call and the result after it. A `drag_method` parameter with `click_method` parity was considered and left out to keep the change small; it can follow if wanted.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/SKILL.md`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
