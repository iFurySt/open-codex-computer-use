# Preserve foreground focus during SkyLight background clicks

## 目标

修正 `click_method=sky_click` 会让真实前台应用短暂失活的问题：完全遮挡的目标窗口仍能接收定向点击，同时前台应用、key window、first responder、真实鼠标和窗口层级保持不变。

## 范围

- 包含：
  - 将 SkyLight activation session 从“前台 defocus + 目标 focus + 双向恢复”收敛为只改变目标应用合成状态。
  - 为实机 Chrome 回归增加前台 AppKit active、key-window 和 first-responder 观测。
  - 让 `sky_click` 的 action-result snapshot 刷新禁止 activate / raise 恢复。
  - 同步架构、可靠性、SkyLight 参考资料和 history。
- 不包含：
  - 修改 `auto`、`app_post` 或 `global` 的公共行为。
  - 用 `NSRunningApplication.activate`、`AXRaise` 或全局 HID 补救失败的后台点击。
  - 复刻 Codex 闭源 `SyntheticAppFocusEnforcer` 的完整 event-tap 状态机。
  - 发布、提交或推送。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/RELIABILITY.md`、`docs/references/macos-skylight-background-click.md`。
- 相关代码路径：`SkyLightSPI.swift`、`SkyClickSimulation.swift`、`AccessibilitySnapshot.swift`、`ComputerUseService.click`、`SkyClickLiveTests.swift`。
- 已知约束：`SLPSPostEventRecordTo` 是私有 SPI；Chromium renderer 仍需要短暂 synthetic focus 和 off-window primer；显式模式必须 fail closed。

## 风险

- 风险：只向目标应用发送 focus record 后，Chromium 可能仍拒绝完全遮挡窗口的事件。
- 缓解方式：保留现有事件字段、primer、双通道投递和 renderer settle，用隔离 Chrome profile 做实机验证；失败时不恢复到会让前台应用失活的旧实现。
- 风险：snapshot action-result 刷新在目标 AX / CGWindow 瞬时不可见时返回错误。
- 缓解方式：只对 `sky_click` 的点击后刷新禁用恢复，首次显式 `get_app_state` 行为保持不变。
- 风险：只比较最终 AX 状态会漏掉短暂的 resign/key-loss。
- 缓解方式：让前台 fixture 记录 `applicationDidResignActive` 与 `windowDidResignKey` 累计次数，并同时检查 first responder。

## 里程碑

1. 落地 target-only synthetic focus session 和纯逻辑测试。
2. 增加非侵入 action-result refresh 与前台 focus probe。
3. 完成单元、构建、smoke 和 macOS 实机验证，更新文档并归档计划。

## 验证方式

- 命令：`swift build`。
- 命令：`swift test`。
- 命令：`./scripts/run-tool-smoke-tests.sh`。
- 命令：`OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests`。
- 手工检查：用户提供的 Chrome `sky_click` CLI 序列不再让当前应用输入焦点丢失。
- 观测检查：目标 DOM 只点击一次；前台 PID、AppKit active、key window、first responder、鼠标和 z-order 均不变；前台 fixture 的 resign/key-loss 计数不增加。

## 进度记录

- [x] 确认根因是旧实现主动向前台应用发送 `focused=false`。
- [x] 完成 target-only synthetic focus session。
- [x] 完成非侵入 snapshot refresh 和 focus probe。
- [x] 完成验证、文档与 history。

## 决策记录

- 2026-07-23：`without raise` 不再等同于“保持焦点”；新的硬约束是不得向真实前台应用发送 activation record。
- 2026-07-23：如果 target-only synthetic focus 无法满足某个目标框架，`sky_click` 应明确失败，不得静默恢复到前台 defocus 或全局 HID。
- 2026-07-23：隔离 Chrome 在完全遮挡时仍能通过 target-only synthetic focus 触发一次 DOM click；前台 fixture 的 active、key window、first responder 和 loss counters 全部保持不变。
