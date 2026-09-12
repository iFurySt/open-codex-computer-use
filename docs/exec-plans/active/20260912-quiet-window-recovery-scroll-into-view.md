# 静默窗口恢复与自动滚入视口（对齐 Codex Computer Use）

## 目标

在不抢用户前台焦点的前提下，让 OCU 与 Codex Computer Use 的行为对齐：

1. 快照恢复默认不再 `activate` / `unhide` / `open -b` / `AXRaise`；目标窗口最小化或不在当前 Space 时，默认 fail closed 返回官方风格 `Apple event error -10005: cgWindowNotFound` 并给出可操作提示，恢复能力改为显式 opt-in。
2. 元素级动作（click / set_value / select_text）在目标控件位于可视区之外时，先用 AX 把控件滚入视口再动作，滚动后重新解析 AX 句柄并读回 frame 校验。
3. 动作前给目标元素画一个不抢焦点的透明高亮环，300–600ms 后淡出，让审计者看得见“正在操作哪一栏”。
4. `click.method=auto` 的 AX 失败路径优先尝试 `sky_click`，失败再落 `postToPid`，且绝不因 sky 失败而回退到 global 物理指针（P3，默认关闭，见决策记录）。
5. 虚拟光标在空闲期必须绝对静止：没有显式动作时不得有任何 position / order / level 更新，所有动画定时器在节拍结束后 `invalidate()`，并在写入前取整、相等即 no-op（P6，用户实测“光标小箭头原地小幅抖动，且 AI 空闲时也在抖”）。

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
- [x] P5 光标去抖：`VisualCursorMoveCoalescer` + `OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS`（默认 400ms），同目标只重画高亮、窗口内直接落位不播 Bezier / pulse
- [x] P5 高亮环生命周期：后台 `DispatchSourceTimer` 硬 TTL + 220ms 存活看门狗 + 弹层短 TTL（300ms）+ 新动作前先清旧环
- [x] P5 单测与证据：新增 14 个单测；`swift build` Build complete、`swift test` 207 tests / 1 skipped / 0 failures、`./scripts/check-docs.sh` 通过
- [x] P6 空闲静止：`CursorIdleDriver`（单一 owner + `lastInteractionAt` 空闲守卫 + 1 秒有界节拍后自 `invalidate`）修掉 `settle`/`pulseClick` 的 idle 定时器泄漏；`CursorPanelWriteGate` 统一整点取整 / 相等 no-op / 只在显示或目标窗口变化时 `order`；idle tick 去掉 `refreshActiveOrderingIfNeeded`
- [x] P6 单测与证据：新增 7 个单测（空闲 5 秒内 frame 与 order 写入不增、同坐标不触发 setFrame / level 写入、重复 start 会 invalidate 上一个定时器、无锚点与 `window=0` 不 pump、整点取整、env 开关与计数行）；`swift build` Build complete、`swift test` 214 tests / 1 skipped / 0 failures、`./scripts/check-docs.sh` 通过
- [x] P7 光标持久可见（用户实测“系统级事件 / 切换焦点后整支光标消失”）：panel 基级改 `.floating`，普通窗口不再 `order(.above, relativeTo:)`，删除 30 秒 idle 隐藏定时器，新增前台切换重排与 `CursorOverlayPanelHosting` / `CursorOverlayEnvironment` 注入缝
- [x] P8 默认零激活：`activateClickTarget`（AXRaise / AXMain / AXFocused）收进 `allow_window_recovery` opt-in（`activationOnlyClickFallbackAllowed`），element_index 的 `.auto` / `.accessibility` 两条路径默认不再激活
- [x] P7/P8 单测与证据：新增 `CursorOverlayVisibilityTests`（7）+ `ClickActivationPolicyTests`（4）；`swift build` Build complete、`swift test` 全绿、`./scripts/check-docs.sh` 通过
- [x] P9 高亮环重做 + 渲染自证：`TargetHighlightStyle`（`codex` 默认 / `plain` 回退，env `OPEN_COMPUTER_USE_TARGET_HIGHLIGHT_STYLE`）、环 panel level 与光标同策略、`OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT=1` 诊断行、`debug-highlight [--seconds N] [--display N]` 单屏自证入口
- [x] P9 单测与证据：新增 `TargetHighlightStyleTests`（11）+ `DebugHighlightTests`（9）；`swift build` Build complete、`swift test` 245 tests / 1 skipped / 0 failures、截图证据 `tmp/ocu-highlight-21daf46/{codex-ring,plain-ring,codex-ring-v2}.png`

## 决策记录

- 2026-09-12：`OPEN_COMPUTER_USE_SCROLL_TARGET_INTO_VIEW` 默认 **开启**（以 `0/false/no/off` 关闭）。理由：该路径只在元素 frame 的中心点落在窗口可视矩形之外时才动作，正常可见元素是纯 no-op；而越界时不滚动必然点空，风险高于滚动本身。
- 2026-09-12：P3 的 `.auto` sky_click 灰度默认 **关闭**。理由：SkyLight 是私有 SPI，`SkyClickDispatcher` 在部分步骤失败时可能已经投递了事件，随后再落 `postToPid` 会重复点击；在无法用 GUI 验证的前提下，默认保持现状、只提供显式开关。
- 2026-09-12：显式 `click_method=global` 与既有 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` 语义不变；P3 只保证“sky 失败不会动态升级到 global”。
- 2026-09-12：分支日志按本仓库自身约定落在 `docs/exec-plans/active/`（仓库无 `docs/branches/` 约定），history 在收尾时补 `docs/histories/2026-09/`。
- 2026-09-12：P5 合并窗口内采用“立即落位但不播 Bezier / pulse”，而不是跳过移动。理由：P4 已确立“高亮环必须跟在光标到位之后”的顺序约束，跳过移动会让环落在光标不在的元素上；直接落位同时保持该约束，并让一轮 burst 最多只播一次移动动画。
- 2026-09-12：P5 合并窗口锚定“上一次真正播动画”的时刻；同目标（≤2pt）时不移动也不重新锚定，避免亚像素漂移把光标慢慢带走。
- 2026-09-12：P5 高亮环 TTL 改用后台 `DispatchSourceTimer`。理由：主 RunLoop default-mode `Timer` 在原生菜单 event-tracking 模式下会停摆，是“弹层关闭后高亮仍挂着”的诱因之一；`orderOut` 另设无条件的硬截止，不再依赖 CA 淡出动画的 completion handler。
- 2026-09-12：P5 菜单/弹层（`AXMenuItem` / `AXMenu` / `AXMenuBar` / `AXMenuBarItem`，或目标窗口 layer > 0）TTL 缩短到 300ms，并在窗口消失时由看门狗立即隐藏。
- 2026-09-12：P6 空闲静止采用“有界 idle 节拍”而不是彻底删掉 idle 摆动。理由：(a) `runCursorIdleSmoke` 明确断言 idle 期 tip 锚定但 rotation 仍在变（`main.swift:348-352`），删掉摆动会直接破坏既有 smoke 契约；(b) 用户主诉是“抖/跳”而不是“微摆”，而抖的机制是每帧重排 + 亚像素写入 + 多个泄漏定时器互相抢写，不是摆动本身。默认窗口 1 秒（`OPEN_COMPUTER_USE_VISUAL_CURSOR_IDLE_SWAY_MS`，`0` 同分钟级冻结），节拍结束后定时器自毁、tick 直接 return。
- 2026-09-12：P6 不缓存元素 frame。证据：cursor 侧目标点只在每次动作时由 `visualCursorTarget` / `makeVisualCursorTarget` 从 snapshot 的 `ElementRecord.localFrame` 算一次（`ComputerUseService.swift:2219-2226`），idle tick 只复用 `restingTipPosition` 这个缓存值，不存在“每 tick 重读 frame 导致 1pt 漂移”的路径；需要缓存的其实是**写入值**，由 `CursorPanelWriteGate` 承担。
- 2026-09-12：P6 保留 `order(.above, relativeTo:)` 的展示语义（显示 / 目标窗口变化时重排），只去掉 idle 期每帧强制重排。代价：idle 期间若用户把别的窗口抬到目标窗口之上，cursor 可能被盖住直到下一次动作；这是消除“每 16.7ms 重排一次”的直接权衡。
- 2026-09-12：P7 光标 panel 基级从“目标窗口 layer（普通窗口 = 0）”改为固定 `.floating`(3)。理由：OCU 是永不 active 的 accessory app，`.normal` 层级属于非活跃窗口组，任何一次前台切换都会让活跃 app 的窗口盖住光标；而 `order(.above, relativeTo:)` 绑定的外部窗口一旦被系统 orderOut（原生菜单 tracking、app 被隐藏、目标窗口关闭），光标会跟着一起从屏幕上消失——这正是用户看到的“整支消失”而不是“被盖住”。只有目标窗口自身在 `.floating` 及以上（原生菜单 / popover / panel）时才保留相对排序，否则只 `orderFront`。
- 2026-09-12：P7 删除 `visualCursorPostInteractionIdleTimeout`（30 秒无动作隐藏）与整套 hide timer。理由：需求是“整轮 turn 内始终可见”，而 30 秒短于一轮常见的模型思考间隔，会导致回合中途消失；隐藏只保留 turn-ended / reset / `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` 三条路径。
- 2026-09-12：P7 增加 `NSWorkspace.didActivateApplicationNotification` 触发的无条件“重新置前”。理由：把“前台切换后光标仍在屏幕上”变成显式处理而不是依赖层级副作用；该路径只重排、不写 frame、不改 level，因此不会重新引入 P6 修掉的 idle 抖动。
- 2026-09-12：P7 把窗口交互面抽成 `CursorOverlayPanelHosting` / `CursorOverlayEnvironment` 注入缝。理由：用户要求“模拟目标窗口失活 / 目标窗口不再 on-screen → 光标仍 visible 且 frame 不变”的回归测试，而原来的静态 `NSPanel` 无法在无 window server 的单测里驱动。
- 2026-09-12：P9 高亮环“看不见”的结论是**触发了也画了，但视觉上等于没有**，不是没触发。(a) 旧样式 stroke/fill 都用 `NSColor.controlAccentColor`，与浏览器原生 focus ring 同色同形，现场被判定成“只有浏览器原生焦点环”；（b）新 codex 样式第一版把光标的白色描边（white 0.90@0.92）直接当环描边，在浅色页面上实测几乎不可见（截图 `codex-ring.png` 只剩一圈雾影）。修法：把光标的“深色主体 + 浅色边缘”翻译成“深色描边 + 1pt 浅色外缘 + 33pt 雾状光晕”（截图 `codex-ring-v2.png` 清晰可见）。证据：Assets/scripts 无 macOS GUI 依赖的 `debug-highlight` 单屏自证入口 + `screencapture -R`。
- 2026-09-12：P9 环 panel level 与光标统一为 `.floating` 下限。理由与 P7 相同；环是 450ms 级 overlay，若前台 app 窗口盖住它，观感就是“环没出现”。
- 2026-09-12：P9 官方确认没有“目标高亮”概念（只有 `Software Cursor` 运行时 overlay，见 `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md:105-140,277-284`），因此环不冒充官方行为，只对齐光标视觉语言；参数取自 `SoftwareCursorGlyphRenderer` 而不是臆造。
- 2026-09-12：P9 调试入口只允许**单屏**并强制确定性收尾。理由：现场曾出现“光标同时出现在两块屏幕上”；核查结论是**单进程只有一个 panel**（`SoftwareCursorOverlay.swift:430/434/995`、`TargetHighlightOverlay.swift:326`），双光标来自两个进程（调试进程 + 验收轮正在跑的 installed OCU）各画一个，而不是遍历屏幕建 panel（`NSScreen.screens` 的用法只有坐标映射、可用性判断与 `screen(containing:)` 夹取）。为杜绝歧义，入口新增 `--display N`（1-based，默认主屏）且永不遍历建 panel，`--seconds` 上限 60s，`run()` 用 `defer` 收尾。
- 2026-09-12：P8 activation-only fallback 与 window recovery 共用同一个开关，而不是新增独立开关。理由：两者都会移动用户前台焦点，语义完全一致；共用开关可以避免出现“允许恢复窗口但不允许激活”的额外状态组合。默认路径只保留 `AXPress` / `AXConfirm` / `AXOpen` / `AXShowMenu`、候选扫描、自动滚入视口、`postToPid` / `sky_click`。
- 2026-09-12：P4 高亮环顺序修正为“光标先到位、再高亮、最后动作”。依据官方同线程日志顺序 `Move cursor to ...` / `Start Bezier cursor animation ...` / `Signal cursor movement completion ...` 先于 `Moving mouse to ...` / `Clicking at ...`（`docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md:192-196,243`），且 `scroll` / `perform_secondary_action` 在官方 tool 矩阵里同样命中 `Move cursor to ...`；到达后只加 `120ms` settle，不改变工具调用语义。
