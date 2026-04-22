## [2026-04-22 17:05] | Task: 清理 app 打包构建告警

### 🤖 Execution Context
* **Agent ID**: `codex-main`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `./scripts/build-open-computer-use-app.sh debug` 运行时有很多 warning。

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`, `docs`

**Key Actions:**
- **[Modernize app launch path]**: 去掉 `AppDiscovery` 里已废弃的 `NSWorkspace.launchApplication(...)` 和 `fullPath(forApplication:)`，改成标准应用目录解析 + 现代 `openApplication(at:configuration:)`。
- **[Modernize window capture path]**: 去掉 `AccessibilitySnapshot` 里已废弃的 `CGWindowListCreateImage`，改成基于 `ScreenCaptureKit` 的单窗口截图。
- **[Trim test-only warning]**: 去掉 `CursorMotion` 实验 target 里已无效果的 `activateIgnoringOtherApps` 选项，避免 `swift test` 额外报废弃告警。
- **[Sync docs]**: 更新架构文档里的截图实现说明。

### 🧠 Design Intent (Why)
这次任务的目标不是压掉 warning，而是把已经有替代方案的系统 API 真正迁移掉，确保 `./scripts/build-open-computer-use-app.sh debug` 在当前 Xcode / Swift 组合下保持干净，并减少后续 SDK 升级带来的噪音。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1705-build-warning-cleanup.md`
