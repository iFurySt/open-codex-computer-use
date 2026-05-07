## [2026-05-07 15:34] | Task: 收缩内置阻止列表

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> 查看 GitHub Issue #12，溯源为什么之前加入了一个 list；用户认为这个阻止应该去掉。随后明确要求除密码管理器以外都从内置 denylist 删除。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs`

**Key Actions:**
- **[Denylist scope]**: 将 macOS `AppSafetyPolicy` 内置 denylist 收缩到密码管理器：1Password、Bitwarden、Dashlane、LastPass、NordPass 和 Proton Pass。
- **[Non-password unblock]**: 移除终端类 app、Chrome / Atlas 和系统组件的内置阻止，避免常规 app 自动化路径被硬编码策略拦住。
- **[Regression coverage]**: 新增单测确认 Chrome、iTerm2、Atlas 和 SecurityAgent 不属于内置阻止目标，同时保留密码管理器阻止覆盖。
- **[Docs sync]**: 更新安全、架构、质量评分和官方对齐计划，记录 Chrome 进入 denylist 的历史来源、缺少官方拒绝样本支撑的判断，以及当前只阻止密码管理器的产品决策。

### 🧠 Design Intent (Why)
原 denylist 的提交目标是复刻官方安全边界，但仓库留档样本只证明了 iTerm2 的拒绝行为；Chrome 只出现在 `list_apps` 输出中。继续把终端、浏览器和系统组件写死在内置阻止列表里，会让常规 app 自动化路径不可用。当前先只保留密码管理器这类明确高敏感目标，其余敏感 app 策略留给后续 session approval / policy 设计。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260417-official-tool-alignment.md`
