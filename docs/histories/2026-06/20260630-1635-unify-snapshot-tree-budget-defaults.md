## [2026-06-30 16:35] | Task: Unify snapshot tree budget defaults

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `macOS local CLI`

### User Query
> 先修改 默认统一为 1200/64。

### Changes Overview
**Scope:** Linux and Windows snapshot tree rendering defaults, tests, and docs.

**Key Actions:**
- Unified Linux and Windows default accessibility tree node/depth budgets with macOS at 1200 nodes and 64 levels.
- Replaced the Windows renderer's hard-coded `500/16` guard with named tree budget constants.
- Added Linux and Windows regression tests that lock the shared `1200/64` defaults.
- Updated architecture and skill troubleshooting docs so agents can distinguish text truncation from tree budget limits.

### Design Intent
The previous platform defaults had drifted: macOS used `1200/64`, Linux used `500/64`, and Windows used `500/16`. The lower Linux/Windows budgets could hide visible content on deep or long accessibility trees, while the macOS defaults had already been tuned for Electron/WebView-style apps. The shared default keeps bounded snapshots while reducing cross-platform surprise.

### Files Modified
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseLinux/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `apps/OpenComputerUseWindows/main_test.go`
- `docs/ARCHITECTURE.md`
- `skills/open-computer-use/references/troubleshooting.md`
