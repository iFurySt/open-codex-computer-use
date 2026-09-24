# macOS SkyLight 后台键盘参考

## 用途

这份笔记记录 `key_method=sky_key` 的机制、实机验证结论和被否定的方案。所有结论来自 2026-09-08 在 macOS 27.0（build 26A5425a）上对被完全遮挡的隔离 Chrome `--app` 窗口和本仓库 fixture app 的受控测试；测试代码是 `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/SkyKeyboardLiveTests.swift`。

## 问题

- 普通 AppKit 应用在后台就能接受 `CGEvent.postToPid` 键盘事件（fixture 在 inactive、非 key 状态下照常收到文字）。
- Chromium / Electron 不行：页面能收到 `keydown` / `keyup`，但 `document.hasFocus()` 为 false，不会触发 `input`，文字不会插入。原因在 Chromium 源码 `content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm`：页面焦点由 `OnWindowIsKeyChanged(keyTrackingWindow.isKeyWindow)` 驱动，只要 NSWindow 不是 AppKit 意义上的 key window，渲染进程就把页面当作未聚焦。

## `sky_key` 采用的序列

1. 复用 `sky_click` 的 target-only synthetic-active record（`[0x08]=0x0D`、`[0x8a]=0x01`），只发给目标 PSN，不碰真实前台应用。
2. 向目标 PSN 投递 yabai `window_manager_make_key_window` 的两条 record：`[0x04]=0xF8`、`[0x3a]=0x10`、`[0x20..0x30)=0xFF`、window id 在 `0x3c..0x3f`，`[0x08]` 先 `0x01` 再 `0x02`。目标 app 在进程内把该窗口设为 key window，不改变 WindowServer frontmost、z-order 或 Space。
3. 等待 300ms（Chrome 实测约 215ms 后 `document.hasFocus()` 变 true）。
4. 通过现有的公开 `CGEvent.postToPid` 路径发送键盘事件（`InputSimulation.typeText` / `pressKey`）。带 `cmd` 的单字符组合键改为在目标 app 的 AX 菜单栏里按 `AXMenuItemCmdChar` + `AXMenuItemCmdModifiers` 找到对应菜单项并 `AXPress`。
5. 再发 `[0x8a]=0x02` 的 deactivate record 撤销 synthetic 状态；Chrome 页面随即 blur。

## 实机验证结论

- 只发 synthetic-active record 不会让 Chrome 变 key；record 顺序必须是先 activation 后 key-window，反过来无效。
- 变 key 之后，公开 `postToPid` 就能输入；Cua Driver 的 `SLSEventAuthenticationMessage` 认证信封不是必要条件，窗口不是 key 时带认证也同样无效，所以本仓库没有引入它。
- 菜单栏快捷键（`cmd+a` / `cmd+c` / `cmd+v` / `cmd+x` / `cmd+z`）以键盘事件形式发到后台 Chromium 不会生效，因为 AppKit 只为 active app 分发 NSMenu key equivalent；但目标的 Edit 菜单项在后台是 enabled 的，`AXPress` 可以正确执行。`cmd+shift+left` 这类 key-binding 组合键仍走键盘事件。
- 目标窗口在另一个 Space（实测用全屏 Space）时同样可用：active Space 不切换，frontmost 不变。
- 前台 fixture 在整个过程中保持 active、key、first responder，`resignActive` / `resignKey` 计数为 0，真实指针不动，目标窗口 z-order 不变。
- 被 `cmd+h` 隐藏的 app 不接受 key-window record，`sky_key` 对隐藏 app fail closed，不代替用户 unhide。

## 明确否定的方案

- `SLPSSetFrontProcessWithOptions`（Cua `with_foreground_assist` / `with_menu_shortcut_activation`）：会让真实前台应用 resign active，被前台 fixture 计数器捕获。
- `CGSSetConnectionProperty(cid, targetCid, "SetFrontmost", true)`（mac-cua Python 的 micro-activate）：macOS 27 返回 1000，对 Chrome 无效。
- 只靠 `SLSEventAuthenticationMessage` + `SLEventPostToPid`、给键盘事件打 window field 40/51/91/92、先 `sky_click` 再输入、AX `AXFocused` / `AXMain` 设到窗口上：都无法让 Chrome 页面聚焦。

## 参考来源

- yabai：[asmvik/yabai](https://github.com/asmvik/yabai/tree/dd845723416f5fe92af49fad5ebab00369e07edd) `src/window_manager.c` 的 `window_manager_make_key_window`。
- Cua Driver：[trycua/cua](https://github.com/trycua/cua/tree/b8a0f32a06c75225ba24ebb5ab14f6507fa90d15) `libs/cua-driver/rust/crates/platform-macos/src/input/keyboard.rs`、`skylight.rs`。
- Chromium：`content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm`（`isKeyTrackingWindowKey`、`OnWindowIsKeyChanged`、`performKeyEquivalent:`）。

## 兼容性检查

`sky_key` 复用 `sky_click` 的五个私有符号，缺任一个都 fail closed。macOS 更新后重新跑 `OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests`。
