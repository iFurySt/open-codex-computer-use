## [2026-04-17 22:46] | Task: 发布 0.1.6

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 增加个小版本，提交相关改动，git tag 一下推送。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUseSmokeSuite`、`packages/OpenComputerUseKit`、`plugins/open-computer-use`、`scripts/computer-use-cli`、`README.md`、`docs`

**Key Actions:**
- **统一版本号**：将插件 manifest、CLI 版本常量、MCP server version 和 smoke/test 示例统一 bump 到 `0.1.6`。
- **同步文档路径**：把 `computer-use-cli` 文档中的本地插件缓存示例路径切到 `0.1.6`。
- **收口本轮功能**：把 CLI `help/version` 修复和 npm 安装后 `doctor` 引导一并纳入这次 patch release。
- **准备 tag 发布**：为后续 `git tag` / `git push origin <tag>` 保持源码与文档版本一致。

### 🧠 Design Intent (Why)
这次发布不是单独的版本号刷新，而是把两类已经完成但尚未发版的用户可见改动一起收口：CLI 基础可用性修复，以及 npm 首次安装后的权限引导。先统一源码、文档和插件缓存路径里的版本标识，再打 tag，能避免发布产物、README 和本地安装路径相互打架。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/references/codex-computer-use-cli.md`
- `README.md`
- `docs/histories/2026-04/20260417-2246-bump-open-computer-use-to-0.1.6.md`
