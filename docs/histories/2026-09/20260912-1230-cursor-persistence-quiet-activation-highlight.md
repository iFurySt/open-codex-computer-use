## [2026-09-12 12:30] | Task: 光标持久可见 + 默认零激活 + 高亮环重做与渲染自证

### 🤖 Execution Context
* **Agent ID**: `session-fe09ecb5-988e-4679-aba5-333c4e21743e` (DSH subagent)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI（委派子代理会话）

### 📥 User Query
> 修两个残留问题：(1) 一旦发生系统级事件（原生 NSMenu/窗口被系统接管）或用户切换焦点后，OCU 虚拟光标**整支消失**；(2) 偶发仍抢焦点，怀疑 `ClickTarget` 的 AX activation-only fallback 在 auto 的 element_index 分支默认开启。要求：光标整轮 turn 内始终可见（只在 turn-ended/reset/VISUAL_CURSOR=0 隐藏）、任何 AXRaise/AXMain/AXFocused 收进 opt-in、加回归测试。追加要求：(3) 目标高亮环样式照 Codex 光标视觉语言重做并**自证真的渲染**（现场三次没看到环），新增单屏调试入口 + 截图证据；(4) 调试入口与正常路径都不得跨屏重复显示，调试入口要确定性退出。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（Overlay / TargetHighlight / Service / CLI）、`apps/OpenComputerUse`（CLI dispatch）、单元测试、`docs/`、`skills/open-computer-use/SKILL.md`。

**根因 1（光标消失，带证据）**
1. **panel level = 目标窗口 layer（普通窗口 = 0）**：`SoftwareCursorOverlay.swift` 旧 `configureOrdering` 把 `panel.level` 设成 `effectiveTargetWindow?.layer ?? 0`。OCU 是永不 active 的 accessory app（`MCPAppRuntime.swift:17`），`.normal` 层级属于非活跃窗口组，窗口服务器会把活跃 app 的窗口排到它上面 —— 每次前台切换就把光标盖住；Apple 文档（Window Programming Guide, Window Levels）："a given window cannot be layered above other windows in a higher level"，而同一 level 内的前后关系由激活状态决定。
2. **`panel.order(.above, relativeTo: 外部 windowID)`** 是当时唯一把 level-0 panel 抬到目标窗口之上的手段，而它只在**动作开始时**执行（`configureOrdering` 的调用点：moveCursor / repositionCursor / pulseClick / settle，加移动动画里的 `refreshActiveOrderingIfNeeded`）；一旦系统级事件重排窗口列表，光标不会重新置前。仓库自带的官方逆向笔记也指出官方是“目标失效就回退普通前置排序”，并明确建议 overlay 不要只在动画开始时排一次层级（`docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md:332-340,374`）。
3. **目标窗口消失时 level 被改小**：`refreshActiveOrderingIfNeeded` → `configureOrdering(relativeTo: nil)` → `desiredLevel = 0` + `orderFront(nil)`；对一个非活跃 app 的 level-0 窗口，`orderFront` 无法抬到活跃 app 的窗口之上。
4. **30 秒 idle 隐藏**：`visualCursorPostInteractionIdleTimeout()` + `scheduleHide`（repositionCursor / pulseClick / settle 三处）会在最后一次交互 30 秒后淡出并 `orderOut`。一轮 turn 里模型思考超过 30 秒很常见，于是回合中途光标整支消失。

**修法 1**
- 新增 `cursorOverlayBaseLevel = .floating`(3) 与纯函数 `cursorPanelOrdering(targetWindow:baseLevel:)`：普通窗口下 panel 固定 `.floating` 且**不**相对外部窗口排序；只有目标窗口自身 ≥ `.floating`（菜单/popover/panel）时才继续 `order(.above, relativeTo:)`。
- 删除整套 idle hide（`scheduleHide` / `cancelPendingHide` / `hideOverlay` / `hideTimer` / `visualCursorPostInteractionIdleTimeout`）；隐藏只剩 `reset()`（`turn-ended`）与 `OPEN_COMPUTER_USE_VISUAL_CURSOR=0`。
- 新增 `NSWorkspace.didActivateApplicationNotification` 观察者 → `reassertCursorVisibility()`：只重排、不写 frame、不改 level。
- 新增注入缝 `CursorOverlayPanelHosting` + `CursorOverlayEnvironment`（`SoftwareCursorOverlay.swift`），测试用假 host 驱动目标窗口消失 / 前台切换。

**根因 2（仍抢焦点）**：`ComputerUseService.swift` 的 element_index `.auto` 与 `.accessibility` 两条路径硬编码 `allowActivationFallback: true`，落到 `activateClickTarget`（AXRaise / AXMain / AXFocused），而 `canUseActivationOnlyClickFallback(role:)` 恰好允许 `AXWindow` —— 也就是“点一个窗口元素”会真的 raise/focus 它。
**修法 2**：新增 `activationOnlyClickFallbackAllowed(allowWindowRecovery:environment:)`，与窗口恢复共用开关（`allow_window_recovery=true` 或 `OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY=1`），两条 element_index 路径改走它；坐标点击路径保持恒定 `false`。默认路径只剩 AXPress/AXConfirm/AXOpen/AXShowMenu、候选扫描、自动滚入视口、`postToPid`/`sky_click`。

**根因 3（高亮环“看不见”）**：结论是**触发了也画了，但视觉上等于没有**，不是没触发。(a) 旧样式 stroke 与 fill 都用 `NSColor.controlAccentColor`，与浏览器原生 focus ring 同色同形（现场描述“只有浏览器原生蓝色焦点环”就是它）；（b）重做第一版把光标白色描边（white 0.90@0.92）当环描边，浅色页面上实测几乎不可见。另外环 panel level 也跟随目标窗口 layer (=0)，存在和光标同类的被盖/被带走风险。
**修法 3**：新增 `TargetHighlightStyle`（`codex` 默认 / `plain` 逐像素回退，env `OPEN_COMPUTER_USE_TARGET_HIGHLIGHT_STYLE`）：深色描边 `0.38/0.36/0.35@0.85`（光标主体色）+ 1pt 浅色外缘 `white 0.90@0.55`（光标边缘色）+ 33pt 雾状光晕（光标 fog 半径/颜色）；环 panel level 与光标统一为 `.floating` 下限。可验证性：`open-computer-use debug-highlight [--seconds N] [--display N]` 单屏画光标+环并打印 `screencapture -R` 矩形；`OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT=1` 每次 approach 打一行 `present` / `skip` 诊断。

### 🧠 Design Intent (Why)
- 光标的“可见”必须是**层级性质**而不是“每次动作重排一次”的时序巧合：把 panel 抬到 `.floating` 后，任何前台切换都无法把它盖住，也不需要每帧重排（保持 P6 的 idle 静止契约）。
- 隐藏只允许由 turn 边界驱动：一轮 turn 的时长由模型决定，任何固定秒数的 idle 隐藏都会在长思考时误伤。
- activation-only fallback 与 window recovery 共用开关：两者都会移动用户前台焦点，语义一致，避免出现“允许恢复窗口但不允许激活”的状态组合。
- 环的样式对齐光标视觉语言而不是复刻官方：官方 binary 里没有“目标高亮”概念（`software-cursor-overlay.md:105-140,277-284`），所以参数直接取自 `SoftwareCursorGlyphRenderer`（描边 1.55pt / 雾半径 33pt / 雾色 0.43,0.41,0.40@0.28），只把“深色主体 + 浅色边缘”翻译成环可用的“深色描边 + 浅色外缘”。
- 自证优先：现场无法用工具结果判断“没触发/看不见”，所以加的是**可独立运行的单屏调试入口 + 截图**，而不是再写一段说明。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`（level 策略、去 idle hide、激活重排、注入缝）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`（activation fallback opt-in）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TargetHighlightStyle.swift`（新增）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TargetHighlightOverlay.swift`（样式绘制、level 下限、诊断行、duration override）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TargetHighlightLifetime.swift`（debug-only displayDurationOverride）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VisualCursorDebugShowcase.swift`（新增，单屏自证入口）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`、`apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`（`debug-highlight` / `--debug-highlight`）
- 测试：`CursorOverlayVisibilityTests.swift`（7）、`ClickActivationPolicyTests.swift`（4）、`TargetHighlightStyleTests.swift`（11）、`DebugHighlightTests.swift`（9）、`OpenComputerUseKitTests.swift`（1 处契约替换）
- `docs/ARCHITECTURE.md`、`docs/exec-plans/active/20260912-quiet-window-recovery-scroll-into-view.md`、`skills/open-computer-use/SKILL.md`

### ✅ Verification
- `swift build`：Build complete。
- `swift test`：**245 tests / 1 skipped（live sky_click 默认 skip）/ 0 failures**（基线 214 + 31）。
- `./scripts/check-docs.sh`：通过。
- 渲染自证：`./.build/debug/OpenComputerUse debug-highlight --seconds 2 --display 1` → 打印 `debug-highlight seconds=2.0 style=codex display=1 ring=934,548,180,56 capture=874,488,300,176 screen=0,0,2048,1152`，3.1s 内确定性退出（exit=0），`pgrep -x OpenComputerUse` 只剩安装版 mcp/app-agent，无残留 panel 或进程。
- 截图证据：`tmp/ocu-highlight-21daf46/codex-ring.png`（第一版白描边：只剩雾影，判定“看不见”）、`plain-ring.png`（旧 controlAccentColor 环：与浏览器焦点环同色）、`codex-ring-v2.png`（最终：深色描边 + 浅色外缘 + 雾状光晕，清晰可见且不像原生焦点环）。

### ⚠️ 未覆盖 / 风险
- 未做真实 GUI 端到端：不接受验收轮的桌面操作，环在真实点击路径上的观感由调试入口 + 截图 + `OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT=1` 诊断行间接证明。
- 坐标点击（`click(x,y)`）路径按设计**不画环**（`ComputerUseService.swift` 的 x/y 分支走 `moveVisualCursor`）：如果现场用的是坐标点击，日志里会**完全没有** highlight 行——这是“没触发”的判定依据，不是回归。
- 30 秒 idle 隐藏的删除由“代码路径移除 + 空闲 1.2s 内不 orderOut”的单测覆盖；没有真的等 30 秒。
- 多显示器：单进程只有一个光标 panel 与一个环 panel；磁盘上若同时有第二个 OCU 进程（例如安装版 MCP 服务验收轮），屏幕上就会出现第二个光标。
