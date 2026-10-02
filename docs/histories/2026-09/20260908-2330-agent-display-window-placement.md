## [2026-09-08 23:30] | Task: agent display：把已被隐藏的窗口停靠到 agent 专用 virtual display

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `Claude Code CLI / macOS 27.0 arm64`

### 📥 User Query
> 把 virtual display 方案做成正式功能。

### 🛠 Changes Overview
**Scope:** 新 ObjC shim target、macOS snapshot 路由、三平台工具协议、测试、文档。

**Key Actions:**
- **Shim**: 新增 `packages/OpenComputerUseVirtualDisplayShim`（ObjC，ARC），用 `NSClassFromString` 解析 `CGVirtualDisplayDescriptor` / `CGVirtualDisplay` / `CGVirtualDisplaySettings` / `CGVirtualDisplayMode`，暴露 `ocu_virtual_display_create / destroy / is_supported` 三个 C 函数；标量属性经 KVC 设置，避免猜错 C 类型。
- **AgentDisplay**: 单例管理显示器与停靠窗口：按需创建 1920×1080 显示器，用 AX `kAXPosition` 把窗口 frame 移进显示器（纯 `agentDisplayPlacement` 计算落点），记录原位置；`restore` 移回并在无窗口停靠时销毁显示器；`atexit` 兜底恢复。
- **Protocol**: `get_app_state` 新增 `window_placement`（`keep` / `agent_display` / `restore`），非 `keep` 时 snapshot 使用 read-only recovery policy；fixture 拒绝；Windows / Linux 在 snapshot 前返回 unsupported。
- **Verification**: 纯逻辑单元测试 + `AgentDisplayLiveTests`：被完全遮挡、页面 hidden 的 Chrome 经 `park` 后页面 `visible`，snapshot 含网页内容与截图，`sky_click` / `sky_key` 生效，前台与鼠标不变；`restore` 后窗口回到原位、显示器数量恢复。

### 🧠 Design Intent (Why)
*已进入 hidden 的页面没有 WindowServer 原语能在不显示的情况下改回 visible；让窗口“真的在一块屏幕上”是 macOS 自己的做法（Screen Sharing headless 会话）。所以做成显式 opt-in：它改变窗口位置这件事必须由调用方决定，并且总能恢复。*

### ✅ Verification
- `swift test`：174 tests，5 个默认跳过的实机 live test，0 failures。
- `OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST=1 swift test --filter AgentDisplayLiveTests` 通过；其他四个 live test、`./scripts/run-tool-smoke-tests.sh`、`make check-docs` 通过。
- Windows / Linux：`go vet ./...`、`go test ./...` 通过。

### 📁 Files Modified
- `Package.swift`、`packages/OpenComputerUseVirtualDisplayShim/`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AgentDisplay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`、`ComputerUseService.swift`、`ComputerUseToolDispatcher.swift`、`ToolDefinitions.swift`
- `apps/OpenComputerUseWindows/`、`apps/OpenComputerUseLinux/`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`（`AgentDisplayLiveTests` 等）
- `docs/references/macos-window-visibility-and-spaces.md`、`docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`
- `skills/open-computer-use/references/usage.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20260908-cross-space-background-state.md`
