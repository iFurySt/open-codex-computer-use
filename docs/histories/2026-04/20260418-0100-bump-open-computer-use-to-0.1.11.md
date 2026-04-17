## [2026-04-18 01:00] | Task: 发布 0.1.11

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 加个小版本，提交所有改动，git tag推送

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: 把插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本和单测中的 client version 统一提升到 `0.1.11`。
- **[Release Scope]**: 把首次冷启动 `System Settings` 时权限浮窗不出现的修复，以及根目录新增中文 README 入口，一并纳入 patch release。
- **[Release Notes]**: 更新功能发布记录，为 `0.1.11` 补充用户价值与变更摘要。

### 🧠 Design Intent (Why)
这轮剩余改动虽然不大，但都直接影响首次授权体验和仓库入口文档。单独补一个 patch release，可以把“首次冷启动可见性修复”和“中文 README 恢复”从 `0.1.10` 的权限身份收口里切开，避免后续 tag 和实际用户可见行为继续混在一起。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260418-0100-bump-open-computer-use-to-0.1.11.md`
