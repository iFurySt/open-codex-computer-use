## [2026-09-24 17:40] | Task: 收敛 PR 65 的后台操作 session 边界

### 🤖 Execution Context
* **Agent ID**: TraeCode
* **Base Model**: GPT-5
* **Runtime**: TraeCode CLI / local macOS repository workspace

### 📥 User Query
> 评估 PR 65 后，直接在贡献者的 PR 上迭代并补充 maintainer commits。

### 🛠 Changes Overview
**Scope:** PR 与最新 main 集成、macOS 后台状态生命周期、agent display 恢复、JS REPL 参数、私有 API 防护、测试与文档。

**Key Actions:**
- 用 merge commit 同步最新 `main`，保留贡献者历史以及 derived implementation 对应的第三方许可声明。
- MCP turn-ended、stdio shutdown 与 app-agent connection close 统一清理 visual cursor、occlusion keep-alive 和 agent display；app runtime 的 distributed turn-ended 通知也执行同一 session cleanup。
- `window_placement=restore` 改为按 app PID 恢复该 runtime 停放的全部窗口，不再误用 snapshot 当前选中的 window ID。
- macOS `get_app_state` 不再声明 `readOnlyHint`，因为默认 snapshot 会维护 WindowServer occlusion 状态，显式 placement 还会移动窗口。
- JS app binding 将 `windowPlacement` 转发给 snapshot，将 `keyMethod` 转发给 `typeText` / `pressKey`，并补参数映射测试和同一 session 的用法。
- `CGVirtualDisplay` shim 捕获私有 KVC / selector 抛出的 Objective-C exception，系统 API 漂移时返回不可用结果而不是终止 host 进程。

### 🧠 Design Intent (Why)
后台能力会暂时改变进程级 WindowServer 状态，所以它的安全边界必须跟 MCP/REPL session 一致；正常 turn 或 connection 结束不能把窗口遗留在 virtual display。显式 restore 应按调用者指定的 app 恢复真实 parked set，而不是依赖移动后可能变化的 preferred-window 选择。默认 Codex 入口是 JS REPL，因此 native 新参数也必须在 code-first API 中可达。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AgentDisplay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseVirtualDisplayShim/OpenComputerUseVirtualDisplayShim.m`
- `scripts/node-repl/open-computer-use-repl.mjs`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`
- `scripts/node-repl/open-computer-use-repl.test.mjs`
- `docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`、`docs/references/js-repl.md`
- `skills/open-computer-use/references/usage.md`、`docs/releases/feature-release-notes.md`

### ✅ Verification
- `swift test`：186 tests，7 个 opt-in live tests 跳过，0 failures。
- `swift build -c release`：通过。
- 新增 JS background-option 映射测试通过；Node 全套只剩最新 `main` 已可复现的 Worker late-error timing failure。
- Linux / Windows：`go test ./...` 均通过。
- `./scripts/run-tool-smoke-tests.sh`：native tool 与 cursor idle smoke 均通过。
- `./scripts/check-docs.sh`、`./scripts/check-action-pinning.sh` 与 `git diff --check`：通过。
- 按仓库约束未运行会切换窗口 / Space 或注入真实输入的 opt-in live tests；agent-display live test 已改为覆盖按 PID 恢复入口，留待空闲桌面窗口执行。
