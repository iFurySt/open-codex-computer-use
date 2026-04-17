## [2026-04-17 15:04] | Task: 收敛 app 模式的 Dock 暴露

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI / Swift 6.2.4 / macOS`

### 📥 User Query
> 执行过程中 Dock 里会出现 `OpenCodexComputerUse`，看起来很奇怪；除了权限弹窗页面以外，其余执行都应该静默在后台。

### 🛠 Changes Overview
**Scope:** `apps/OpenCodexComputerUse`, `scripts/`, `docs/`

**Key Actions:**
- **[收敛 app activation policy]**: 把 `PermissionOnboardingApp` 从 `.regular` 改成 `.accessory`，保留权限窗口可见性，但不再把 app 作为普通前台应用暴露到 Dock。
- **[修正 bundle 元数据]**: 在打包脚本生成的 `Info.plist` 中加入 `LSUIElement = true`，让从 `.app` bundle 启动的进程也保持 agent-style 行为。
- **[同步文档]**: 更新 README、架构文档和权限 onboarding execution plan，明确“无 Dock 图标、仅按需显示权限窗口”的产品边界。

### 🧠 Design Intent (Why)
这次改动的目标不是隐藏权限引导本身，而是让 `OpenCodexComputerUse` 的运行形态更接近后台 automation service。权限 onboarding 仍然需要显式窗口，但普通执行和 bundle 常驻不应该因为被配置成前台 `NSApplication` 而在 Dock 里露出额外图标。

### 📁 Files Modified
- `apps/OpenCodexComputerUse/Sources/OpenCodexComputerUse/PermissionOnboardingApp.swift`
- `scripts/build-open-codex-app.sh`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
