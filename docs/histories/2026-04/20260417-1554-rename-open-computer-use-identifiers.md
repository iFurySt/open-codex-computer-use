## [2026-04-17 15:54] | Task: 统一 open-computer-use 命名

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 除了 repo 名继续保留 `open-codex-computer-use` 以外，其余对外命名统一改成 `open-computer-use`，至少先把 plugin 已经采用的新命名和 MCP name 对齐。

### 🛠 Changes Overview
**Scope:** `Package.swift`, `apps/`, `packages/`, `scripts/`, `plugins/open-computer-use`, `README.md`, `docs/`, `artifacts/`

**Key Actions:**
- **[Runtime Identity]**: 把 Swift package / executable / fixture / smoke suite 的当前命名统一收敛到 `OpenComputerUse*`，并把 MCP `serverInfo.name` 改为 `open-computer-use`。
- **[Packaging and Install]**: 把 `.app` 打包产物、插件 launcher、安装脚本和 Makefile 入口切到 `OpenComputerUse.app` / `OpenComputerUse`，同步更新 bundle display name 与 bundle identifier。
- **[Docs and Samples]**: 更新 README、架构/安全/稳定性/质量文档和 active exec plan；对历史样本保留旧目录名，但在说明文字里显式标出当前产品名已切换到 `open-computer-use`。

### 🧠 Design Intent (Why)
这轮改动的目标不是只改某一个字符串，而是把“产品名、MCP 名、可执行名、打包名、插件入口、文档说明”收敛成一套一致的当前态，避免用户在仓库里同时看到 `open-codex-computer-use` 和 `open-computer-use` 两套并行命名。保留 repo 名、历史记录和旧配置清理逻辑，是为了兼顾迁移成本和可追溯性。

### 📁 Files Modified
- `Package.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/README.md`
- `docs/histories/2026-04/20260417-1554-rename-open-computer-use-identifiers.md`
