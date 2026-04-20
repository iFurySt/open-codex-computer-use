## [2026-04-20 18:10] | Task: 发布 0.1.19

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 提交相关改动，bump version git tag推送

### 🛠 Changes Overview
**Scope:** `apps/`、`docs/`、`packages/`、`plugins/`、`scripts/`

**Key Actions:**
- **[Version Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version 与 CLI 文档路径统一提升到 `0.1.19`。
- **[Release Notes]**: 在用户可见发布记录中为 `0.1.19` 增加安装器运行时依赖收口说明，明确这次 patch release 的核心是去掉 `install-*` 命令对 Python 的要求。
- **[Release Trigger]**: 基于安装器修复后的 `HEAD` 收口 release 输入，准备用 `v0.1.19` tag 推送触发新的 GitHub Actions release。

### 🧠 Design Intent (Why)
安装器报错 `python3 with tomllib is required` 属于用户第一次接入就能撞到的真实发布问题，不适合只停留在本地脚本修复。把这次修正和版本源一起收口到新的 patch release，可以让 npm 包和 tag 驱动的 GitHub Release 同步反映“安装器已无 Python 运行时依赖”的新行为。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1810-bump-open-computer-use-to-0.1.19.md`
