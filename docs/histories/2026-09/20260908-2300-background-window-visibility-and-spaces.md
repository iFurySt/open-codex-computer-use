## [2026-09-08 23:00] | Task: 后台与其他 Space 窗口的状态读取、点击和可见性 keep-alive

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `Claude Code CLI / macOS 27.0 arm64`

### 📥 User Query
> 完整目标：能从任何地方（包括其他 Space）拿到 AX tree、点击、输入，极其可靠且完全不抢用户焦点。要按 macOS / SkyLight 原语来设计，不要按 app 逐个打补丁。

### 🛠 Changes Overview
**Scope:** macOS snapshot / capture、SkyLight SPI、`sky_click` 校验、测试、参考文档。

**Key Actions:**
- **Root cause**: 被遮挡或在其他 Space 的 Chromium / Electron 窗口 AX tree 没有网页内容，是因为 app 收到 WindowServer occlusion 通知后把页面设为 hidden（Chromium 以 `NSWindow.occlusionState` 为准），与 Space 本身无关。
- **Occlusion keep-alive**: 新增 `WindowOcclusionKeepAlive`，在窗口未被遮挡时通过 `SLSPackagesEnableWindowOcclusionNotifications(cid, wid, false, &previous)` 固定 app 的“可见”状态，进程退出时恢复；对所有被驱动的窗口生效，不依赖 bundle id。
- **Off-screen windows**: `WindowCapture` 退到 `.optionAll`，SCK 捕获用 `onScreenWindowsOnly: false`，其他 Space 的窗口不再触发 activate / raise 恢复；`sky_click` 校验改为“窗口仍属于目标进程且 app 未隐藏”。
- **Lazy web AX tree**: Chromium 系 app（按 `Contents/Frameworks` 中的 Chromium / Electron / CEF 框架或 `AXManualAccessibility` 成功判定）第一次走 tree 若无 `AXWebArea`，窗口可见时最多重走 3 秒；被遮挡时在 tree 末尾追加说明。
- **Verification**: 新增 `OcclusionKeepAliveLiveTests` 与纯逻辑单元测试；参考文档记录 SPI 签名（lldb 反汇编）、否定方案与未解决边界。

### 🧠 Design Intent (Why)
*可见性是 WindowServer 的概念，app 只是通知的接收方；关闭一个窗口的 occlusion 通知就是在 macOS 层面告诉 app “你一直可见”，对任何 app 都成立。已经被遮挡的窗口没有原语能在不显示的情况下变可见，macOS 自己的答案是 virtual display，留到后续计划。*

### ✅ Verification
- `swift test`：171 tests，3 个默认跳过的实机 live test，0 failures。
- `OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests`：可见时的 snapshot 包含网页内容并固定窗口；被 fixture 完全遮挡后页面仍 `visible`，第二次 snapshot 仍包含网页内容与截图，Chrome 未被激活。
- `SkyKeyboardLiveTests`、`SkyClickLiveTests` 通过；`./scripts/run-tool-smoke-tests.sh` 通过完整 9-tool smoke 与 cursor idle smoke；`make check-docs` 通过。
- 一次性实验：被遮挡的 Chrome 在 `sky_click` 后截图内容变化（渲染未冻结）；全屏 Space 上的窗口 `sky_click` / `sky_key` 生效且 active Space 不切换；virtual display spike 证明已被遮挡的窗口放到 agent 显示器后页面可见、snapshot / click / type 生效。
- `OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests`（需要第二个 Desktop）：Chrome 在 Desktop 2、用户在 Desktop 1 时 snapshot 含网页内容与截图，`sky_click` / `sky_key` 生效，active Space 不变，Chrome 未被激活。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/WindowOcclusionKeepAlive.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyLightSPI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyClickSimulation.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`（`OcclusionKeepAliveLiveTests`、`CrossSpaceLiveTests`）
- `docs/references/macos-window-visibility-and-spaces.md`、`docs/references/README.md`
- `docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`
- `skills/open-computer-use/references/usage.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/active/20260908-cross-space-background-state.md`
