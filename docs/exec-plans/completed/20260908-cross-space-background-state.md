# Cross-Space background state: read, click and type anywhere without taking focus

## 目标

让 `get_app_state`、`click`（`sky_click`）、`type_text` / `press_key`（`sky_key`）对被遮挡的窗口和位于其他 Space 的窗口都可靠工作，全程不激活、不抬升、不切换 Space、不移动指针，并且用 macOS / SkyLight 原语实现，而不是按 app 打补丁。

## 范围

- 包含：
  - 窗口解析不再要求 on-screen；SCK 按 window id 捕获 off-screen 窗口。
  - WindowServer occlusion keep-alive（已完成）与 Chromium 系懒加载 AX tree 的重走（已完成）。
  - `sky_click` / `sky_key` 接受 off-screen 窗口（已完成）。
  - 在真实的第二个桌面 Space 上做端到端回归（待机器上存在第二个 Desktop）。
  - 已经被遮挡 / 已在其他 Space 的 Chromium 窗口：agent 专用 virtual display（`CGVirtualDisplay`）做成显式 `window_placement`（已完成）。
- 不包含：
  - 任何会显示窗口给用户、切换用户 Space 或前台 app 的 fallback。
  - Windows / Linux runtime。

## 背景

- 相关文档：`docs/references/macos-window-visibility-and-spaces.md`、`docs/references/macos-skylight-background-keyboard.md`、`docs/references/macos-skylight-background-click.md`。
- 相关代码路径：`WindowOcclusionKeepAlive`、`SnapshotBuilder`、`WindowCapture`、`SkyClickDispatcher`、`SkyKeyboardDispatcher`。
- 已知约束：app 的“可见”只来自 WindowServer 通知；已进入 hidden 的 Chromium 页面无法在不显示窗口的情况下被外部改回 visible。

## 风险

- 风险：keep-alive 让被遮挡窗口持续渲染，消耗资源。
- 缓解方式：只作用于 agent 驱动过的窗口，进程退出时恢复；后续可在 session 结束时释放。
- 风险：virtual display 会改变显示器排列，鼠标可能滑入不可见显示器，窗口会离开用户当前位置。
- 缓解方式：先做 spike 评估，明确 opt-in，结束后把窗口移回原 Space 与位置。
- 风险：私有 SPI 签名猜错会写坏内存（已在 `SLSLockWindowVisibleRegion` 上发生过）。
- 缓解方式：新增符号前用 lldb 反汇编确认参数，记录在参考文档里。

## 里程碑

1. occlusion keep-alive、off-screen 解析与捕获、`sky_click` 放宽校验（完成）。
2. 第二个桌面 Space 上的端到端回归：AX tree、截图、`sky_click`、`sky_key`。
3. virtual display spike：创建 / 销毁、把窗口移入移出、验证 Chromium 可见性，评估用户可感知副作用。

## 验证方式

- 命令：`swift test`、`OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests`。
- 手工检查：创建 Desktop 2，把 Chrome 窗口放过去，在 Desktop 1 执行 `get_app_state` / `click` / `type_text`，确认 active Space 与前台 app 不变。
- 观测检查：进程退出后目标窗口重新收到 occlusion 通知（遮挡后页面变 hidden）。

## 进度记录

- [x] 定位根因：occlusion 通知，而非 Space。
- [x] keep-alive、off-screen 捕获、懒加载重走、`sky_click` 放宽校验，单元与实机回归通过。
- [x] Desktop 2 端到端回归：`CrossSpaceLiveTests` 在真实第二个 Desktop 上通过（snapshot / 截图 / `sky_click` / `sky_key`，active Space 与前台不变）。
- [x] virtual display spike：已被遮挡的 Chrome 窗口放到 agent virtual display 后页面可见、snapshot / sky_click / sky_key 全部生效，用户 Space、前台与鼠标不变。
- [x] virtual display 产品化：`get_app_state.window_placement=agent_display / restore`，ObjC shim、`AgentDisplay`、三平台协议、`AgentDisplayLiveTests`。排列与鼠标滑入未做额外处理，记录在参考文档。

## 决策记录

- 2026-09-08：不用 bundle id 列表判断 web app；keep-alive 对所有被驱动窗口生效，懒加载重走按 bundle 内的 Chromium / Electron / CEF 框架或 `AXManualAccessibility` 判定。
- 2026-09-08：已被遮挡的窗口不做任何显示式 fallback，只在 tree 里说明；下一步评估 virtual display。
- 2026-09-08：第三方进程不能跨 Space 移动别的 app 的窗口（window-management bridge gate），运行时也不需要；测试改为在目标 Desktop 上启动目标。
- 2026-09-08：virtual display spike 证明 macOS 层面可行（细节见 `docs/references/macos-window-visibility-and-spaces.md`）；产品化作为独立后续，不混进本轮 PR。
- 2026-09-08：agent display 做成显式 `window_placement`，默认 `keep` 不移动任何窗口；`restore` 与进程退出恢复原位。计划归档。
