# Add macOS SkyLight background keyboard (`sky_key`)

## 目标

为 `type_text` / `press_key` 增加显式 `key_method=sky_key`，让 macOS 能向被遮挡或位于其他 Space 的目标窗口（重点是 Chromium / Electron）输入文字与快捷键，同时保持真实前台应用的 active / key / first responder、指针位置、窗口层级和当前 Space 不变。

## 范围

- 包含：
  - 实机验证 mac-cua / Cua Driver 的认证键盘路径是否可用，并找出 Chromium 真正的门槛。
  - macOS `sky_key` 路由：synthetic-active record + yabai make-key-window record + 现有 `postToPid` 键盘路径 + AX 菜单快捷键。
  - Windows / Linux 公共枚举同步与 unsupported 结果。
  - Swift / Go 测试、skill usage、架构、安全、可靠性、参考资料与 history。
- 不包含：
  - 修改 `auto` 或让 `sky_click` / 快照 / 截图支持其他 Space（后续计划）。
  - `SLPSSetFrontProcessWithOptions` foreground assist、自动 unhide 隐藏 app。
  - 发布、打 tag、提交或推送远端。

## 背景

- 相关文档：`docs/references/macos-skylight-background-click.md`、`docs/references/macos-skylight-background-keyboard.md`。
- 相关代码路径：`SkyLightSPI`、`SkyKeyboardSimulation`、`ComputerUseService.typeText/pressKey`、三平台 `key_method` parser / schema。
- 已知约束：显式方法不能静默 fallback；私有 SPI 必须运行时探测；绝不向真实前台应用发送 record。

## 风险

- 风险：make-key-window record 是未公开 ABI，macOS 更新可能失效。
- 缓解方式：集中在 `SkyLightSPI.swift`，缺符号 fail closed，实机回归纳入 `docs/RELIABILITY.md`。
- 风险：AX 菜单项按下等价于用户按快捷键，`cmd+q` 之类会真的执行。
- 缓解方式：语义与用户按键一致，在 `docs/SECURITY.md` 明确说明；不做额外过滤以免与 `auto` 语义分叉。
- 风险：Chrome 变 key 的等待时间因机器不同而变化。
- 缓解方式：固定 300ms（实测 ~215ms），后续可改为 AX focused-window 轮询。

## 里程碑

1. 实机验证并找到可行序列。
2. 实现 macOS 路由、跨平台协议与测试。
3. 文档、history、归档计划。

## 验证方式

- 命令：`swift build`、`swift test`、`(cd apps/OpenComputerUseWindows && go test ./...)`、`(cd apps/OpenComputerUseLinux && go test ./...)`、`./scripts/run-tool-smoke-tests.sh`、`make check-docs`。
- 命令：`OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests`。
- 实机检查：被遮挡 Chrome 收到文字与 `cmd+a`；前台 fixture active / key / first responder 与 resign 计数不变；目标在全屏 Space 时 active Space 不切换。

## 进度记录

- [x] 验证 mac-cua 认证路径无效，定位 Chromium `isKeyWindow` 门槛。
- [x] 验证 yabai make-key-window record + synthetic-active record 可让被遮挡 Chrome 接受输入。
- [x] 验证菜单快捷键经 AX 菜单项生效，验证跨 Space 输入。
- [x] 实现 `sky_key`、三平台协议、测试与文档。

## 决策记录

- 2026-09-08：不引入 `SLSEventAuthenticationMessage` 认证信封，实测它既非必要也不充分。
- 2026-09-08：`cmd` 单字符组合键走目标 AX 菜单项；导航类组合键（`cmd+shift+left` 等）保持键盘事件。
- 2026-09-08：`sky_key` 允许 off-screen 窗口（其他 Space），但隐藏 app fail closed；不代替用户 unhide。
- 2026-09-08：否定 `SLPSSetFrontProcessWithOptions` 与 `CGSSetConnectionProperty SetFrontmost`，前者让用户应用 resign active，后者在 macOS 27 无效。
