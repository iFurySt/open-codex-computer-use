## [2026-04-22 10:55] | Task: 发布 0.1.25

### 用户诉求

> 提交相关改动，bump version 推送。

### 本次改动

- **[Version Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version 与 CLI 文档路径统一提升到 `0.1.25`。
- **[Release Notes]**: 在用户可见发布记录中增加 `0.1.25`，说明本次 patch release 聚焦 `set_value` 的 settable accessibility element 边界。
- **[Release Trigger]**: 基于 `set_value` 官方语义收敛提交，准备用 `v0.1.25` tag 推送触发新的 GitHub Actions release。

### 设计动机

`0.1.24` 解决了 `click` 的全局物理指针 fallback 问题，但 `set_value` 对 Sublime 这类可读不可写的 AX 节点仍会暴露底层 `-25200`。这次 patch release 将 `set_value` 收敛到官方的 settable-only 语义，并用独立版本发布，便于安装用户拿到清晰错误提示。

### 影响文件

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1055-bump-open-computer-use-to-0.1.25.md`
