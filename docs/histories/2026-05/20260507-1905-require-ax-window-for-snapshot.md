## [2026-05-07 19:05] | Task: Align unavailable window state

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `macOS local shell`

### 📥 User Query
> 对比最新版 open-computer-use 和官方 computer-use 的工具返回，继续修正差异。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **[Snapshot Guard]**: `get_app_state` now requires a real AX window before rendering an accessibility tree.
- **[Role Filtering]**: Focused-window and first-window candidates are filtered to `AXWindow`, avoiding misleading app-root-only trees when an app exposes no usable key window.

### 🧠 Design Intent (Why)
Official `computer-use` returns an unavailable-window error for the observed Lark state, while open-computer-use previously rendered only the application/menu-bar root and implied the app was actionable. Requiring a real accessibility window makes the failure explicit and prevents stale or non-actionable element indexes from reaching follow-up tools.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
