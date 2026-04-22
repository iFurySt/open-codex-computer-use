## [2026-04-22 12:46] | Task: Add Windows Computer Use Runtime

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Extend the project beyond macOS Accessibility to Windows, avoid coupling to Swift `.app`, consider Go-generated `.exe`, and prioritize functional implementation of the 9 Computer Use tools for background computer use. Use the UTM Windows host over SSH for testing where practical, and leave TODOs if the full scope is too large.

### 🛠 Changes Overview
**Scope:** Windows runtime, build scripts, CI, docs

**Key Actions:**
- **[Runtime]**: Added `apps/OpenComputerUseWindows`, a Go CLI/MCP runtime exposing the same 9 Computer Use tools, `call --calls`, MCP initialize/tools list, and per-process snapshot cache.
- **[Bridge]**: Embedded a Windows PowerShell UI Automation bridge for app/window discovery, accessibility tree snapshots, screenshots, UIA pattern actions, ValuePattern, ScrollPattern, and Win32 window-message fallback input.
- **[Build/CI]**: Added `scripts/build-open-computer-use-windows.sh` for arm64/amd64 `.exe` builds and wired Go tests into `scripts/ci.sh`.
- **[Docs]**: Updated README, architecture, quality score, and added an active Windows runtime execution plan with the remaining TODOs.
- **[Follow-up Fix]**: Used Windows Codex App session history to identify `get_app_state` failures after `list_apps` succeeded, then hardened process matching and UIA tree rendering against `Argument types do not match`.
- **[Interactive Validation]**: Verified through an interactive Windows scheduled task that `get_app_state -> type_text -> get_app_state` writes `hello windows mcp` into Notepad and returns the updated UIA value.
- **[Background Policy]**: Removed the default app-launch fallback and disabled `SetFocus` by default so Windows tools do not intentionally steal foreground focus; both behaviors remain available through explicit environment variables.
- **[Type Text Focus Fix]**: Changed `type_text` to prefer child-window `EM_SETSEL` / `EM_REPLACESEL` messages and made the UIA `ValuePattern.SetValue` text fallback opt-in because Notepad can foreground itself from that UIA path.
- **[Focus Validation]**: Re-ran an interactive Windows scheduled task against Notepad; `get_app_state -> type_text -> get_app_state` returned three non-error results, wrote a `bgmsg-*` marker, and left the foreground window title as `Codex` before and after the call.

### 🧠 Design Intent (Why)
Windows should have its own executable boundary instead of inheriting macOS `.app` and Swift/AppKit assumptions. The first slice keeps the public tool protocol stable and makes the runtime buildable/testable as a `.exe`; the bridge can be replaced with more native Go UIA internals later without changing MCP or CLI callers.

Windows UI Automation can often operate on background windows through control patterns such as `ValuePattern`, `InvokePattern`, and `ScrollPattern`, but Windows does not provide one universal macOS-AX-equivalent background keyboard/mouse model for every GUI toolkit. The runtime therefore avoids the known foreground-taking paths by default and treats launch, focus, and UIA text fallback as explicit opt-in behavior.

### 📁 Files Modified
- `apps/OpenComputerUseWindows/go.mod`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `scripts/build-open-computer-use-windows.sh`
- `scripts/ci.sh`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260422-windows-computer-use-runtime.md`
