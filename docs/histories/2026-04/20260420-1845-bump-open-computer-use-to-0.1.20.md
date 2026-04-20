## [2026-04-20 18:45] | Task: 发布 0.1.20

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> bump version git tag推送

### 🛠 Changes Overview
**Scope:** `apps/`、`docs/`、`packages/`、`plugins/`、`scripts/`

**Key Actions:**
- **[Version Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version 与 CLI 文档路径统一提升到 `0.1.20`。
- **[Release Notes]**: 在用户可见发布记录中增加 `0.1.20`，说明这次 patch release 的核心是去掉 plugin installer 对 `rsync` 的宿主命令依赖。
- **[Release Trigger]**: 基于 `rsync -> cpSync` 修复后的 `HEAD` 收口 release 输入，准备用 `v0.1.20` tag 推送触发新的 GitHub Actions release。

### 🧠 Design Intent (Why)
`rsync` 在 `install-codex-plugin` 里只是递归复制目录的实现手段，不是业务必需能力。既然前一版已经把安装器的 Python 依赖去掉了，就应该继续把这类非必要外部命令前提收口到 npm/Node 自身，确保用户通过 npm 安装后的接入路径更稳定、也更容易预期。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1845-bump-open-computer-use-to-0.1.20.md`
