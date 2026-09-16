## [2026-09-12 10:59] | Task: 静默窗口恢复、自动滚入视口与目标高亮

### 🤖 Execution Context
* **Agent ID**: `session-fe09ecb5-988e-4679-aba5-333c4e21743e` (DSH subagent)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI（委派子代理会话）

### 📥 User Query
> 按 Codex 的做法优化用户 fork 的 open computer use：P2 快照恢复不再默认抢焦点、P1 新增 `ensureElementVisible`、P4 目标元素高亮环、P3 可选 `auto` 优先 `sky_click`。硬约束：不得影响正在跑的验收轮（PID 16428），不得执行 GUI 自动化，用新 feature 分支施工。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（Service / Snapshot / Overlay / ToolDefinitions / Dispatcher）、单元测试、`docs/ARCHITECTURE.md`、`skills/open-computer-use/SKILL.md`。

**Key Actions:**
- **P2 静默快照恢复**：`SnapshotBuilder.build` 与 `ComputerUseService.refreshSnapshot` 的默认 `recoveryPolicy` 由 `.allowActivation` 改为 `.readOnly`；`clickActionSnapshotRecoveryPolicy` 对除 `sky_click` 外的方法也默认只读。新增 `snapshotRecoveryPolicy(allowWindowRecovery:environment:)`，按“显式工具参数优先、否则进程 env”解析；9 个工具的 schema / dispatcher 新增可选布尔 `allow_window_recovery`。`.readOnly` 下仍返回官方风格的 `Apple event error -10005: cgWindowNotFound`，并追加“把窗口移到当前 Space / 取消最小化”和 opt-in 方式的提示。
- **P1 自动滚入视口**：新增 `elementNeedsScrollIntoView` / `windowLocalVisibleRect` / `scrollTargetIntoViewEnabled` 与 `ensureElementVisible`；先 `AXScrollToVisible`（自身 → 最多 6 层祖先），再对最近 `AXScrollArea` 祖先发 `AXScroll<Up|Down|Left|Right>ByPage`（最多 8 页、每轮读回 frame、无进展即停）。滚动后按同一 `element_index` 重新解析 AX 句柄并读回 frame 校验，读不回或仍越界时 fail closed。接入 `click(element_index)` / `set_value` / `select_text`，其 `visualCursorTarget` 使用滚动后的 record。
- **P4 目标高亮环**：新增 `TargetHighlightOverlay.swift`，复用无边框 non-activating `NSPanel` 与 screen-state → AppKit 全局坐标换算；动作前显示、450ms 后 350ms 淡出；强制 `canBecomeKey/Main = false`、`ignoresMouseEvents = true`；`localFrame` 为空或与窗口可视矩形不相交时不显示；`SoftwareCursorOverlay.reset()`（含 `turn-ended`）联动隐藏。接入 `click` / `set_value` / `select_text` / `perform_secondary_action` / `scroll`。
- **P3 `auto` 的 sky_click 灰度**：新增 `autoSkyClickEnabled` / `automaticSkyClickEligible`；`OPEN_COMPUTER_USE_AUTO_SKY_CLICK=1` 时 `.auto` 在 `postToPid` 之前先试一次 `sky_click`，失败落回 `postToPid`，绝不动态升级到 global。默认关闭。
- **测试与文档**：新增/更新 11 个单测；同步 `ARCHITECTURE.md` 与仓库 skill。

### 🧠 Design Intent (Why)
- 抢焦点的主因不是鼠标，而是快照恢复默认允许 `unhide/activate/open -b/AXRaise`；默认关闭才能让 OCU 与 Codex 一样“后台可读”。恢复能力保留为 opt-in，避免回归 Lark / Electron 场景。
- 越界元素不滚动必然点空或点到别的控件，因此 `OPEN_COMPUTER_USE_SCROLL_TARGET_INTO_VIEW` 默认开启（仅当元素 frame 中心点确实落在窗口可视矩形外才动作，可见元素是纯 no-op）。
- 高亮环只做“看得见在操作哪一栏”，任何失败路径都必须 no-op，且不能抢焦点、不能挡鼠标。
- P3 涉及私有 SkyLight SPI，半成功后再落 `postToPid` 存在重复点击风险，故默认关闭、只提供显式开关。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TargetHighlightOverlay.swift`（新增）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`、`skills/open-computer-use/SKILL.md`、`docs/exec-plans/active/20260912-quiet-window-recovery-scroll-into-view.md`

### ✅ Verification
- `swift build`：Build complete。
- `swift test`：189 tests, 1 skipped (live `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST` 默认 skip), 0 failures。
- 未做：真实 GUI 端到端验证（验收轮正在使用桌面，本轮禁止 GUI 自动化）。

### ⚠️ 未覆盖 / 风险
- 已安装产物 `~/Applications/Open Computer Use (Dev).app` 未被重建；运行中的验收轮不受影响。
- P3 未在真实 Chromium 上验证。
- `ensureElementVisible` 的 AX 滚动路径未在真实 App 上验证，只验证了越界判定与开关语义。

### 🔁 2026-09-12 补记 | P4 高亮环顺序修正
- 用户诉求（压缩）：新版“目标元素高亮环”先高亮、后移动虚拟光标，观感别扭；对照 Codex 改成正确先后顺序。本轮只改代码 + 测试 + 本地提交，不重建 `.app`、不 push。
- 文档依据：`docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md:192-196,243`——官方先 `Move cursor to ...` / `Start Bezier cursor animation ...` / `Signal cursor movement completion ...`，之后才 `Moving mouse to ...` / `Clicking at ...`；`scroll` / `perform_secondary_action` 在官方 tool 矩阵里同样命中移动阶段。
- 改动：新增 `VisualInteractionChoreographer`（`move → settle(120ms) → highlight → action`），元素级 5 个调用点统一走它；`perform_secondary_action` / `scroll` 补上移动阶段；`SoftwareCursorOverlay.waitForArrivalSettle` + `visualCursorArrivalSettleDuration()` 提供到达节拍。
- 验证：`swift build` Build complete；`swift test` 193 tests / 1 skipped / 0 failures（新增 4 个顺序与开关单测）；`./scripts/check-docs.sh` 通过。
- 未做：未重建 / 未替换 `~/Applications/Open Computer Use (Dev).app`，未 push；等用户确认后再装机。

### 🔁 2026-09-12 补记（第二轮）| 光标去抖合并与高亮环硬生命周期
- 用户诉求（压缩）：新版每次动作都 `move → settle(120ms) → highlight`，填 33 字段大表单时“光标到处飘”；且目标元素消失后（尤其原生下拉菜单/弹层关闭）高亮环仍挂在屏幕上。
- 改动：新增 `VisualCursorMoveCoalescer` 与 `OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS`（默认 400ms，0 关闭）：目标与上次落点相差 ≤2pt 只重画高亮、目标变化但在窗口内时由新的 `SoftwareCursorOverlay.repositionCursor` 直接落位（不播 Bezier、不播 pulse、不等待到达节拍），合并窗口锚定上一次真正播动画的时刻；`ComputerUseService` 的坐标点击与 fixture 路径也共用同一个 coalescer，并在 `.repositioned` 时跳过 click pulse。新增 `TargetHighlightLifetime.swift`：后台 `DispatchSourceTimer` 硬 TTL（常规 450ms / 弹层 300ms，`TTL + 350ms fade + 50ms` 处无条件 `orderOut`）、220ms 存活看门狗（AX 元素失效 / frame 变化超 8pt / 目标窗口消失即隐藏）、新 approach 先清旧环；`TargetHighlightOverlay` 拆成 facade + 注入式 lifetime controller + AppKit presenter，便于无窗口服务器单测。
- 验证：`swift build` Build complete；`swift test` 207 tests / 1 skipped / 0 failures（新增 14 个单测，覆盖同目标只移动一次、窗口内至多一次动画、窗口外再次动画、`COALESCE_MS=0` 恢复逐次、`VISUAL_CURSOR=0` 全跳过、硬 TTL 不依赖主 RunLoop、看门狗失效隐藏、弹层短 TTL、新动作替换旧环）；`./scripts/check-docs.sh` 通过。
- 未做：本轮仍不做 GUI 自动化验证（桌面正在跑验收轮）。
