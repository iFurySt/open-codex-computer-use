# Add macOS SkyLight background click

## 目标

为 `click` 增加显式 `click_method=sky_click`，让 macOS 能够通过 SkyLight 私有 SPI 向当前 snapshot 对应的目标进程和窗口投递 Chromium-compatible 后台左键点击，同时保持真实鼠标、前台 app、窗口层级和既有 `auto` 行为不变。

## 范围

- 包含：
  - macOS SkyLight 符号动态解析、窗口定向事件字段、off-window primer 和真实点击序列。
  - macOS `click_method` 路由、参数校验、窗口身份校验和诊断错误。
  - Windows / Linux 公共枚举同步，以及显式 unsupported 结果。
  - Swift / Go 单元测试、skill usage、架构、安全、可靠性与 history 文档。
- 不包含：
  - 修改 `auto` 路由或让现有 `app_post` 自动升级为 SkyLight。
  - `SLPSSetFrontProcessWithOptions` foreground assist、跨 Space snapshot、隐藏或最小化窗口恢复。
  - Chromium 网页右键、Canvas / Unity / Blender 等只接受全局 HID 的 surface。
  - 发布、打 tag、提交或推送远端。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/RELIABILITY.md`、`skills/open-computer-use/references/usage.md`。
- 相关代码路径：`ComputerUseService.click`、`InputSimulation.clickTargeted`、`AccessibilitySnapshot.AppSnapshot`、三平台 `click_method` parser / schema。
- 已知约束：显式方法不能静默 fallback；目标窗口必须来自当前 snapshot；私有 SPI 必须通过 `dlopen` / `dlsym` 运行时探测；第一版只承诺同一 Space 内仍为 on-screen 的遮挡窗口。

## 风险

- 风险：SkyLight 函数和 raw event field 都是未公开 ABI，可能随 macOS 更新失效或崩溃。
- 缓解方式：集中封装函数签名和字段、缺符号时 fail closed，并在 macOS 14 / 15 / 26 与签名 app 制品上验证。
- 风险：SkyLight 与公开 `postToPid` 双投递可能在某些非 Chromium surface 产生重复动作。
- 缓解方式：`sky_click` 保持显式且不进入 `auto`，用单次计数 fixture 检查重复投递；若出现重复则把内部 post policy 收敛为 SkyLight-only。
- 风险：过期 snapshot 的 window id 可能已被销毁或复用。
- 缓解方式：投递前检查 `CGWindowID` 的 owner pid 与 on-screen 状态，不匹配时要求重新执行 `get_app_state`。
- 风险：primer 坐标或不支持的鼠标类型命中意外目标。
- 缓解方式：primer 同时使用 off-window screen/local 坐标；第一版只接受左键和 1–2 次点击。

## 里程碑

1. 实现 SkyLight SPI、纯事件 recipe 与 macOS 显式路由。
2. 同步三平台协议、测试和使用文档。
3. 运行单元、跨平台、skill、smoke 与本地能力验证，完成 history 后归档计划。

## 验证方式

- 命令：`swift build`、`swift test`。
- 命令：`(cd apps/OpenComputerUseWindows && go test ./...)`。
- 命令：`(cd apps/OpenComputerUseLinux && go test ./...)`。
- 命令：`npm run package:skill`、`./scripts/run-tool-smoke-tests.sh`。
- 命令：`OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests`（隔离 Chrome profile + 本地页面）。
- 手工检查：`tools/list` 三平台均暴露 `sky_click`，Windows / Linux 在 snapshot lookup 前返回 unsupported。
- 观测检查：macOS 缺失 SkyLight capability、错误 window owner、非左键或超出双击范围时不发送事件；成功路径不调用 `.cghidEventTap` 或 app activation。
- 实机检查：Chrome 按钮在被其他窗口完全遮挡时只触发一次，前台 PID、真实 cursor position 和目标窗口 z-order 不变。

## 进度记录

- [x] 完成文章、Cua Driver、yabai 与 OCU 现有输入路径的源码调研。
- [x] 完成 SkyLight SPI 与 macOS `sky_click` 路由。
- [x] 完成跨平台协议、测试和文档。
- [x] 完成自动化验证与受控实机验证。
- [x] 完成 history 并归档 execution plan。

## 决策记录

- 2026-07-22：公共参数使用 `click_method=sky_click`，保持显式 macOS-only；Windows / Linux 返回稳定 unsupported。
- 2026-07-22：第一版不修改 `auto`，也不引入会 raise / 切 Space 的 `SLPSSetFrontProcessWithOptions`。完全遮挡 Chrome 实测证明只用 `SLEventPostToPid` 不足，因此按文章与 yabai pattern 加入可恢复的 `SLPSPostEventRecordTo` AppKit-active 切换。
- 2026-07-22：事件 recipe 以当前 Cua Driver Chromium 路径为基线，包含 window-local 坐标、PID/window 字段、move primer、off-window primer 和 click-group id。
- 2026-07-22：`CGEventSetWindowLocation` 的动态函数指针按 Cua Rust bridge 的 `(CGEventRef, double, double)` 标量 ABI 声明，并用无投递的 runtime test 验证字段写入，避免依赖 Swift `CGPoint` 聚合参数推断。
- 2026-07-22：focus-without-raise begin/restore 各自保留 40ms event-record 间隔，真实 mouse-up 后保留 100ms renderer settle；受控 Chrome 页面验证单次触发、前台 PID、真实 cursor 和 z-order 均不变。
