## [2026-04-20 18:08] | Task: 发布 0.1.17

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 可以，bump 小版本 tag 推，然后看看结果

### 🛠 Changes Overview
**Scope:** `apps/`、`docs/`、`packages/`、`plugins/`、`scripts/`

**Key Actions:**
- **[Version Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version 与 CLI 文档路径统一提升到 `0.1.17`。
- **[Release Notes]**: 在用户可见发布记录里补充 `0.1.17`，说明这次 release 的核心是接通 `Developer ID Application` 统一签名与 `Cursor Motion` notarization / staple。
- **[Release Trigger]**: 基于当前 `HEAD`（包含 release 签名公证链与 README 中新增的 `Cursor Motion` 视频入口）收口 release 输入，准备用 `v0.1.17` tag 推送触发 GitHub Actions。

### 🧠 Design Intent (Why)
这次不是单纯的版本滚动，而是把前面已经落到 `main` 的分发链路增强真正送进外部 release。只有把 `Developer ID` 签名、`Cursor Motion` notarization，以及与之对应的版本源统一到一个新 patch release，GitHub Actions 才会在 tag 发布时按新流程构建并暴露对外产物。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1808-bump-open-computer-use-to-0.1.17.md`
