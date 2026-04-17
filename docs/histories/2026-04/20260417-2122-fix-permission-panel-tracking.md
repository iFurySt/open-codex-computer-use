## [2026-04-17 21:22] | Task: 修正权限引导 panel 跟随逻辑

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI / Swift 6.2.4 / macOS`

### 📥 User Query
> 打开授权页面后，点 `Allow` 时辅助窗口的跟随有问题；它会一直跟在 `System Settings` 的 `Accessibility` 窗口里 `+ / -` 下面，需要修复。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[补回控件级垂直锚点]**: 通过 `System Settings` 的 Accessibility 树扫描 `+ / -` 按钮行，优先用该控制行作为 panel 的垂直跟随目标。
- **[保留内容区水平对齐]**: panel 仍然按 `System Settings` 右侧内容区居中，只有在拿不到 `+ / -` 控件几何时才回退到窗口底边。
- **[同步文档]**: 更新架构说明和权限 onboarding execution plan，反映“优先跟随 `+ / -` 行、失败再回退”的最新行为。

### 🧠 Design Intent (Why)
这次修复的重点不是单纯继续拉大窗口级容错，而是把水平和垂直锚点拆开处理。panel 继续维持内容区居中，避免随着局部布局左右漂移；但垂直位置重新跟随 `+ / -` 控制行，这样在 `Screen & System Audio Recording` 这类长页面里也不会被错误钳到底部。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
