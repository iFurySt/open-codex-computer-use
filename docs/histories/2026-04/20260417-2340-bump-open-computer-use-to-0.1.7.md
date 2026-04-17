## [2026-04-17 23:40] | Task: 发布 0.1.7

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 增加个小版本，提交相关改动，git tag 后推送。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `plugins/open-computer-use`, `scripts/`, `README.md`, `docs/`

**Key Actions:**
- **统一版本号**：将插件 manifest、CLI 版本常量、MCP server version、smoke/test 示例和文档中的缓存路径统一 bump 到 `0.1.7`。
- **收口本轮功能**：将 Codex/Claude MCP 一键安装脚本、npm launcher 帮助更新，以及权限 onboarding panel 定位修复一并纳入本次 patch release。
- **同步仓库文档**：更新 README、架构文档、active exec plan 与 histories，保证发版后的使用路径和行为描述一致。

### 🧠 Design Intent (Why)
这次 patch release 的重点是把两类真实用户可见改动正式收口发布：一类是安装路径，新增了面向 Codex 和 Claude Code 的幂等 MCP 安装命令；另一类是权限 onboarding 体验，辅助 panel 重新跟随 `System Settings` 的 `+ / -` 控制行，避免在长页面里掉到屏幕最下方。版本号和文档一起提升到 `0.1.7`，可以避免 npm 包、插件缓存、CLI 自报版本和 README 示例继续错位。

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/references/codex-computer-use-cli.md`
- `scripts/install-codex-mcp.sh`
- `scripts/install-claude-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/histories/2026-04/20260417-2122-fix-permission-panel-tracking.md`
- `docs/histories/2026-04/20260417-2255-add-codex-mcp-installer.md`
- `docs/histories/2026-04/20260417-2310-add-claude-mcp-installer.md`
- `docs/histories/2026-04/20260417-2340-bump-open-computer-use-to-0.1.7.md`
