## [2026-04-17 23:50] | Task: 发布 0.1.8

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 增加一个小版本，提交相关改动，git tag后推送

### 🛠 Changes Overview
**Scope:** `plugins/open-computer-use`, `packages/OpenComputerUseKit`, `apps/OpenComputerUseSmokeSuite`, `scripts/computer-use-cli`, `README.md`, `docs/`

**Key Actions:**
- **统一版本号**：将插件 manifest、Swift/Go 侧版本常量、smoke suite 初始化版本和测试示例统一 bump 到 `0.1.8`。
- **同步发布文档**：更新 README、`computer-use-cli` 示例路径和 release notes，保证 tag 发布示例与当前版本一致。
- **记录本次发布**：新增 history，收口本轮权限引导 panel 跟随修复对应的 patch release。

### 🧠 Design Intent (Why)
这次 patch release 的重点是把刚修好的权限引导 panel 跟随问题正式纳入一个可发布版本，同时保证插件 manifest、CLI 自报版本、smoke/test 样例和文档里的版本引用重新对齐，避免用户安装到旧缓存路径或看到错位的版本号。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `scripts/computer-use-cli/main.go`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/README.md`
- `README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260417-2350-bump-open-computer-use-to-0.1.8.md`
