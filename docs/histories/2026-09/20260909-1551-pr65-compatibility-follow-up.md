## [2026-09-09 15:51] | Task: 收紧 PR 65 的跨版本输入与窗口状态恢复

### 🤖 Execution Context
* **Agent ID**: TraeCode
* **Base Model**: GPT-5
* **Runtime**: TraeCode CLI / macOS 26.6.2 arm64

### 📥 User Query
> 审查 PR 65 后直接补充修订并提交到该 PR。

### 🛠 Changes Overview
**Scope:** PR 与 main 集成、macOS 输入时序、occlusion / agent display 生命周期、测试与文档。

**Key Actions:**
- 合入当前 `main`，保留已经发布的 drag 投递修复与文档。
- 普通 `auto` 输入恢复 20 ms type chunk 和 100 ms press-key settle；`sky_key` settle / release 改为跨版本实测稳定的 10 / 10 ms。
- occlusion cleanup 保存并恢复 SPI 返回的原始通知状态，正常 server shutdown 时主动清理，失败项保留供重试。
- agent display 只在确认窗口恢复后删除记录；失败时保留原坐标和显示器供重试，窗口已经关闭时安全清除。
- 补默认时序与恢复坐标单元测试，并更新 benchmark、架构、安全和发布说明。

### 🧠 Design Intent (Why)
*新能力可以允许旧系统兼容性继续增量完善，但不能把只在一个系统版本验证过的零延迟结论扩散到普通默认输入，也不能在恢复失败时丢失用户窗口的恢复信息。*

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TimingLog.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyKeyboardSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/WindowOcclusionKeepAlive.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AgentDisplay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`
- `docs/references/background-input-benchmarks.md`、`docs/references/macos-window-visibility-and-spaces.md`
- `docs/releases/feature-release-notes.md`

### ✅ Verification
- `swift test`：185 tests，7 个 opt-in live tests 默认跳过，0 failures。
- `swift build -c release`：通过（仅有仓库既存 warning）。
- Linux / Windows：`go test ./... && go vet ./...` 均通过。
- `make check-docs`、action pinning、shell syntax、tool smoke、cursor idle smoke 与 `git diff --check` 均通过。
- macOS 26.6.2 后台输入基准：零 settle/release 为 49/50；10 / 10 ms 为 50/50。
- occlusion 与 agent-display 的 opt-in live fixture 在双显示器机器上无法满足其固定窗口布局前置条件，因此未把 setup failure 当成实现失败，也没有放宽断言；agent display 的创建、停靠、操作和恢复路径在现场均实际执行。独立 `sky_click` 偶发失败也可在当前 main 复现，不属于本 PR 引入的回归。
