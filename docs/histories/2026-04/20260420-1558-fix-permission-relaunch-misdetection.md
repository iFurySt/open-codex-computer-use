## [2026-04-20 15:58] | Task: 修复权限授权后重开 app 仍误弹 onboarding

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> allow 授权都完成后，重新打开 app 还会弹出两个都要 `Allow` 的授权窗口；但关掉窗口后再跑 `open-computer-use` 或 `open-computer-use doctor` 又显示两个权限都已经 granted。这个回归是后来引入的，需要修掉。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs/histories`

**Key Actions:**
- **[Stable Permission Target]**: 把权限目标 bundle 的选择逻辑改成真正优先 npm 全局安装后的稳定 `.app`，不再让当前运行的临时/源码 app copy 抢在前面。
- **[Permission Client Ordering]**: 重新整理 TCC 查询候选，先认稳定 bundle identifier，再认稳定 app 路径，最后再兼容当前运行中的 app 路径，减少开发态路径误导授权状态。
- **[Grant Aggregation Fix]**: TCC 查询不再被第一条命中的 `false` 提前短路；现在会遍历所有候选，只要任一匹配记录已 `granted` 就视为已授权，避免旧路径记录把真实授权盖掉。
- **[Regression Tests]**: 新增单测覆盖“源码/临时 app 重开时仍应沿用稳定安装身份”和“多条候选里任一 granted 即视为 granted”这两个回归点。

### 🧠 Design Intent (Why)
这次回归的根因不是权限真的丢了，而是权限状态读取在 app 重开时又回到了“当前运行 copy 的路径优先 + 第一条命中即返回”的旧行为，导致某些临时路径或旧记录把真正稳定的授权身份遮住。修复目标是让 app mode、`open-computer-use` 和 `doctor` 对同一份稳定授权身份给出一致结论，不再出现“窗口说缺权限，CLI 说已授权”的分叉。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/histories/2026-04/20260420-1558-fix-permission-relaunch-misdetection.md`
