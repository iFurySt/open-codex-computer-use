## [2026-04-22 12:34] | Task: 发布 0.1.28

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### Changes Overview
**Scope:** release version bump, release notes, local release verification

**Key Actions:**
- **[Version Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version 与 CLI 文档路径统一提升到 `0.1.28`。
- **[Release Notes]**: 在用户可见发布记录中增加 `0.1.28`，说明本次 patch release 聚焦 runtime overlay cursor 默认速度对齐官方 recovered spring timing。
- **[Release Trigger]**: 基于 runtime cursor speed 对齐提交，准备用 `v0.1.28` tag 推送触发新的 GitHub Actions release。

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1234-bump-open-computer-use-to-0.1.28.md`
