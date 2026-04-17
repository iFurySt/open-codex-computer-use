## [2026-04-17 22:35] | Task: 修复 CLI help 和 version 参数

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `open-computer-use -v` 会卡住。这个 CLI 需要支持 `-h`、`--help`、`-v`、`--version`，并且能看到支持的子命令和参数。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `README.md`, `docs/ARCHITECTURE.md`, `scripts/npm/build-packages.mjs`

**Key Actions:**
- **抽离 CLI 解析**：在 `OpenComputerUseKit` 新增可测试的 CLI 解析与帮助文本逻辑，统一处理全局 flag、子命令帮助和错误提示。
- **修复版本参数行为**：让 `-v` / `--version` / `version` 直接输出版本号，不再误落到默认 app 模式。
- **补文档与分发说明**：同步仓库 README、架构文档和 npm 包 README 模板，明确帮助与版本命令的用法。

### 🧠 Design Intent (Why)
之前的入口只按第一个参数匹配子命令，没有单独处理全局 flag，导致 `-v` 这种常见 CLI 用法直接触发默认 onboarding 分支。把解析逻辑收口成独立模块后，帮助文本、错误提示和版本输出可以共用一套规则，也更容易通过单测长期守住。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `scripts/npm/build-packages.mjs`
