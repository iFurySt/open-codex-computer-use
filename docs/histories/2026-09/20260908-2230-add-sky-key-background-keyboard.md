## [2026-09-08 22:30] | Task: 添加 macOS SkyLight 后台键盘输入

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `Claude Code CLI / macOS 27.0 arm64`

### 📥 User Query
> 参考 mac-cua swift 分支里的 SkyLight keyboard 实现，判断能否给本仓库贡献；先实机验证是否真的可用，再按 `sky_click` 的约定实现。后续追加：不要把限制当作结论，要做到后台、跨 Space、不抢用户焦点的可靠键盘输入。

### 🛠 Changes Overview
**Scope:** macOS keyboard runtime、三平台工具协议、测试、skill 文档、参考资料与第三方归属。

**Key Actions:**
- **Verified first**: mac-cua 的 `deliverKeyboard`（`SLSEventAuthenticationMessage` 认证信封）在 macOS 27 实测无效且从未被调用；被遮挡 Chrome 收得到 `keydown` 但因 NSWindow 不是 key window 不插入文字。原生 AppKit 应用后台本来就接受 `postToPid` 键盘事件。
- **sky_key route**: 复用 `sky_click` 的 target-only synthetic-active record，再投递 yabai `window_manager_make_key_window` 的两条 record 让目标窗口在其进程内成为 key window，等待 300ms 后走现有 `CGEvent.postToPid` 键盘路径，最后撤销 synthetic 状态。
- **Menu chords**: 带 `cmd` 的单字符组合键在目标 AX 菜单栏按 `AXMenuItemCmdChar` / `AXMenuItemCmdModifiers` 匹配并 `AXPress`，解决后台 Chromium 不分发 NSMenu key equivalent 的问题。
- **Safety boundary**: 显式 opt-in、不进入 `auto`、不 fallback；窗口可 off-screen（其他 Space），隐藏 app 与私有符号缺失 fail closed；snapshot refresh 使用 read-only recovery policy。
- **Cross-platform contract**: `type_text` / `press_key` 新增 `key_method` 枚举，Windows / Linux 在 snapshot lookup 前返回 unsupported。
- **Verification**: 新增纯逻辑单元测试与默认跳过的隔离 Chrome 实机回归；参考文档记录被否定的方案（front-process 切换、`SetFrontmost` 连接属性、认证信封、window field 打标、AX 窗口焦点）。

### 🧠 Design Intent (Why)
*Chromium 页面焦点由 `OnWindowIsKeyChanged(isKeyWindow)` 决定，而不是由事件是否“认证”决定。yabai 的 make-key-window record 能让目标 app 在进程内把窗口设为 key window，既不改变 WindowServer frontmost、z-order 或 Space，也不需要 `SLPSSetFrontProcessWithOptions` 这类会让用户应用 resign active 的调用。菜单快捷键走 AX 菜单项则等价于用户按键触发的动作，且在后台可用。*

### ✅ Verification
- `swift build`、`swift test`：168 tests，2 个默认跳过的实机 live test，0 failures。
- `OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests`：被 fixture 完全遮挡的隔离 Chrome 收到 `hello`、`backspace`、`shift+a`、`cmd+a` + 替换文字；前台 fixture 保持 active / key / first responder，resign 计数 0，指针与 z-order 不变，投递结束后 Chrome 页面 blur。
- `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests` 仍通过。
- 一次性实验：目标窗口进入全屏 Space、桌面 Space 保持 active 时，`type_text` 与 `cmd+a` 仍生效且 Space 不切换；`cmd+c` / `cmd+v` / `cmd+x` / `cmd+z` 经菜单项生效。
- Windows / Linux：`go vet ./...`、`go test ./...` 通过。
- `./scripts/run-tool-smoke-tests.sh` 通过完整 9-tool smoke 与 cursor idle smoke；`make check-docs` 通过。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyLightSPI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyKeyboardSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`
- `apps/OpenComputerUseWindows/`、`apps/OpenComputerUseLinux/`
- `skills/open-computer-use/references/usage.md`
- `docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`
- `docs/references/macos-skylight-background-keyboard.md`、`docs/references/README.md`
- `docs/releases/feature-release-notes.md`、`THIRD_PARTY_NOTICES.md`
