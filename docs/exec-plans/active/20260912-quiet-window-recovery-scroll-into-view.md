# 静默窗口恢复与自动滚入视口（对齐 Codex Computer Use）

## 目标

在不抢用户前台焦点的前提下，让 OCU 与 Codex Computer Use 的行为对齐：

1. 快照恢复默认不再 `activate` / `unhide` / `open -b` / `AXRaise`；目标窗口最小化或不在当前 Space 时，默认 fail closed 返回官方风格 `Apple event error -10005: cgWindowNotFound` 并给出可操作提示，恢复能力改为显式 opt-in。
2. 元素级动作（click / set_value / select_text）在目标控件位于可视区之外时，先用 AX 把控件滚入视口再动作，滚动后重新解析 AX 句柄并读回 frame 校验。
3. 动作前给目标元素画一个不抢焦点的透明高亮环，300–600ms 后淡出，让审计者看得见“正在操作哪一栏”。
4. `click.method=auto` 的 AX 失败路径优先尝试 `sky_click`，失败再落 `postToPid`，且绝不因 sky 失败而回退到 global 物理指针（P3，默认关闭，见决策记录）。

## 范围

- 包含：`packages/OpenComputerUseKit`（Service / Snapshot / Overlay / ToolDefinitions / Dispatcher）、单元测试、`docs/ARCHITECTURE.md` 与 history。
- 不包含：Windows / Linux runtime、`.app` 打包与安装、真实 GUI 端到端验证、运行中验收轮所用的已安装产物。

## 背景

- 对照分析：`repos/platform-testkit/test-results/manual-acceptance/611342aa-9b46-4af4-bf96-770886a25518/ocu-vs-codex-computer-use.md`。
- 主诉：OCU 会抢走另一块屏幕上正在使用的前台焦点；诱因是 `SnapshotBuilder.recoverVisibleWindow` 默认启用（`AccessibilitySnapshot.swift:260-284`）以及 `refreshSnapshot` 默认 `.allowActivation`（`ComputerUseService.swift:970`）。
- 次诉：目标控件在视口外时动作落空，用户只能手工 `perform_secondary_action(AXScrollToVisible)`。
- 缺视觉指示：virtual cursor 已默认开启，但没有元素级高亮。
- 验证命令事实源：`swift build` / `swift test`（SwiftPM，`swift-tools-version: 6.2`）；live GUI 测试由 `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1` 显式开启，默认 skip。

## 风险

- 风险：默认关掉恢复会回归 Lark / Electron “隐藏窗口自动拉回”能力（`docs/histories/2026-05/...feishu...`）。缓解：保留恢复实现，只把它收进 `allow_window_recovery` 工具参数或 `OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY=1`。
- 风险：滚动会改变页面滚动位置，并与用户当前观看的一屏冲突。缓解：只有目标元素确实越界才滚动；`OPEN_COMPUTER_USE_SCROLL_TARGET_INTO_VIEW=0` 可整条关闭。
- 风险：滚动后 Chromium AX 句柄失效，复用旧句柄会点错元素。缓解：滚动后重新解析 record 并读回 frame 校验；无法校验时不做破坏性兜底。
- 风险：高亮环抢焦点。缓解：`NSPanel` 子类强制 `canBecomeKey/Main = false`，`ignoresMouseEvents = true`，`localFrame` 为空或与窗口不相交时不显示。
- 风险：私有 SkyLight SPI 半成功导致重复投递。缓解：P3 默认关闭，需显式 `OPEN_COMPUTER_USE_AUTO_SKY_CLICK=1`。
- 硬约束：运行中的验收轮（PID 16428）加载的是 `~/Applications/Open Computer Use (Dev).app`（与 `dist/` 副本不同 inode 的独立拷贝）；本计划只改源码与 `.build/`，不执行 `build-open-computer-use-app.sh`、不覆盖 `~/Applications`。

## 里程碑

1. P2：默认 `.readOnly` + 显式 opt-in + 错误提示。
2. P1：`ensureElementVisible` 与动作调用点接入。
3. P4：`TargetHighlightOverlay`。
4. P3：`.auto` 的 sky_click 优先路径（env 灰度）。
5. 单元测试、`swift build` / `swift test`、文档与 history。

## 验证方式

- 命令（cwd = 本仓库根）：`swift build`。
- 命令：`swift test`（live GUI 测试默认 skip，不产生 GUI 操作）。
- 预期证据：新增单测覆盖 recoveryPolicy 默认值、opt-in 打开后的行为、`ensureElementVisible` 越界判定、overlay `canBecomeKey == false`；`swift test` 全绿。
- 不做：任何 GUI 自动化、任何对 `~/Applications` 产物的重写。

## 进度记录

- [x] P2：recoveryPolicy 默认值翻转 + opt-in 开关 + `-10005` 提示
- [x] P1：`ensureElementVisible` + 三个动作调用点
- [x] P4：`TargetHighlightOverlay` + reset 联动
- [x] P3：`.auto` sky_click 灰度路径
- [x] 单测与 `swift build` / `swift test` 证据（189 tests / 0 failures）
- [x] `docs/ARCHITECTURE.md` 与 history 同步
- [x] P4 顺序修正：advisory overlay 统一走 `move → settle → highlight`，`scroll` / `perform_secondary_action` 补移动阶段，新增顺序单测

## 决策记录

- 2026-09-12：`OPEN_COMPUTER_USE_SCROLL_TARGET_INTO_VIEW` 默认 **开启**（以 `0/false/no/off` 关闭）。理由：该路径只在元素 frame 的中心点落在窗口可视矩形之外时才动作，正常可见元素是纯 no-op；而越界时不滚动必然点空，风险高于滚动本身。
- 2026-09-12：P3 的 `.auto` sky_click 灰度默认 **关闭**。理由：SkyLight 是私有 SPI，`SkyClickDispatcher` 在部分步骤失败时可能已经投递了事件，随后再落 `postToPid` 会重复点击；在无法用 GUI 验证的前提下，默认保持现状、只提供显式开关。
- 2026-09-12：显式 `click_method=global` 与既有 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` 语义不变；P3 只保证“sky 失败不会动态升级到 global”。
- 2026-09-12：分支日志按本仓库自身约定落在 `docs/exec-plans/active/`（仓库无 `docs/branches/` 约定），history 在收尾时补 `docs/histories/2026-09/`。
- 2026-09-12：P4 高亮环顺序修正为“光标先到位、再高亮、最后动作”。依据官方同线程日志顺序 `Move cursor to ...` / `Start Bezier cursor animation ...` / `Signal cursor movement completion ...` 先于 `Moving mouse to ...` / `Clicking at ...`（`docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md:192-196,243`），且 `scroll` / `perform_secondary_action` 在官方 tool 矩阵里同样命中 `Move cursor to ...`；到达后只加 `120ms` settle，不改变工具调用语义。
