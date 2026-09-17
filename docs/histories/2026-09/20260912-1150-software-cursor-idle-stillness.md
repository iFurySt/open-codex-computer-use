## [2026-09-12 11:50] | Task: 虚拟光标空闲抖动修复（idle 绝对静止）

### 🤖 Execution Context
* **Agent ID**: `session-fe09ecb5-988e-4679-aba5-333c4e21743e` (DSH subagent)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI（委派子代理会话）

### 📥 User Query
> 修 OCU「软件光标抖动」问题——用户实测：光标小箭头本身在原地小幅抖/跳，而且 AI 不动手时（空闲）也在抖。要求空闲必须绝对静止、写入前取整、相等跳过 setFrame、不要每 tick `order`、补单测，构建 / 测试 / 文档门禁通过后提交 push 并装机。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（SoftwareCursorOverlay + 新增 SoftwareCursorIdlePolicy）、单元测试、`docs/ARCHITECTURE.md`、exec-plan、history、`skills/open-computer-use/SKILL.md`。

**根因（带证据）**
1. **idle 定时器泄漏（主因）**：`SoftwareCursorOverlay.swift:678-721` 的 `startIdleAnimation()` 直接 `idleTimer = timer`，从不 invalidate 上一个定时器；而 `pulseClick`（:319）和 `settle`（:339）都只 start 不 stop。每个 animated 动作的 `settle → pulseClick` 序列都会永久漏掉一个 60 Hz writer，动作越多漏得越多。多个定时器同时推进共享静态 `idlePhase += 0.05`（:694），原本平滑的微摆变成帧间不等距的阶梯 → 观感就是“小箭头原地抖/跳”，且 `stopIdleAnimation()` 只认最新一个，泄漏的永远停不掉（面板隐藏后仍在跑）。
2. **每 tick 强制重排面板**：idle tick 第一句就是 `refreshActiveOrderingIfNeeded()`（:691）→ `configureOrdering(..., forceReorder: true)`（:630）→ `panel.order(.above, relativeTo:)`（:428）。空闲时每 16.7ms 重排一次 NSPanel，是 window server 级的抖动源。
3. **亚像素 frame 写入**：`placeCursor`（:827）无条件 `panel.setFrameOrigin(tip − tipAnchor)`，值是弹簧积分器的分数点；idle 期弹簧向 resting 点渐近收敛，每帧都写一个亚像素新值，AppKit 量化到 backing store 时在边界处整像素跳变，并且每帧 `needsDisplay = true` 全量重绘。
4. **已排除**：`TargetHighlightLifetime` 的 220ms 看门狗只碰高亮环自己的 panel（`clear() → withdrawPanel() → presenter.withdraw()`，`TargetHighlightLifetime.swift:259-274` / `TargetHighlightOverlay.swift:265`），不触碰 cursor panel；cursor 侧目标点只在动作时算一次，不存在每 tick 重读元素 frame 的路径。

**修法**
- 新增 `SoftwareCursorIdlePolicy.swift`：`CursorIdleDriver`（唯一 idle 定时器 owner；`markInteraction(at:)` 记 `lastInteractionAt`；`startIdleAnimation` 先 `stop` 再 start；tick 先过 `shouldPumpIdleAnimation` 空闲守卫，越界即自 `invalidate()` 并 return）、`CursorPanelWriteGate`（frame origin 整点取整 + 相等 no-op；level 相等不写；`order` 只在目标窗口变化或面板不可见时执行；隐藏 / reset 时清空记忆）、`CursorRunLoopIdleTimer`、`CursorOverlayDebugStats` 与 env 开关解析。
- `SoftwareCursorOverlay`：所有显式动作（move / reposition / settle / pulse）刷新 `lastInteractionAt`；idle tick 删除 `refreshActiveOrderingIfNeeded()`；`refreshActiveOrderingIfNeeded` 只处理“目标窗口已消失”，不再强制重排活着的目标窗口；`configureOrdering` 去掉 `forceReorder` 参数并改走 write gate；`placeCursor` 只在 render state 真正变化时才写 view + `needsDisplay`；`reset` / `hideOverlay` 统一走 `forgetPresentationState()` 并打印可选调试计数。
- 新增 env：`OPEN_COMPUTER_USE_VISUAL_CURSOR_IDLE_SWAY_MS`（默认 1000，`0` = 动作落定即冻结，非法值回落 1000）、`OPEN_COMPUTER_USE_VISUAL_CURSOR_DEBUG_STATS=1`（隐藏 / reset 时向 stderr 打累计计数）。

### 🧠 Design Intent (Why)
- 空闲抖动是“周期性更新驱动 overlay”，所以修的是更新源而不是结果：定时器必须收敛到零个，写入必须收敛到零次。
- 保留 1 秒有界 idle 微摆而不是删掉摆动：`runCursorIdleSmoke` 仍断言 idle 期 rotation 在变（`main.swift:348-352`），而用户主诉的“抖/跳”来自重排 + 亚像素 + 多定时器抢写，不来自摆动本身。
- frame 取整到整点而非设备像素：整点已经消除边界跳变，且 `tipAnchor` 是分数（60.35/70.3），设备像素对齐会引入设备相关分支。
- 缓存的是“已写入值”而不是元素 frame：cursor 目标本来就每动作只算一次，真正需要去重的是 panel 写入。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorIdlePolicy.swift`（新增）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`、`docs/exec-plans/active/20260912-quiet-window-recovery-scroll-into-view.md`、`skills/open-computer-use/SKILL.md`

### ✅ Verification
- `swift build`：Build complete。
- `swift test`：214 tests, 1 skipped（live sky_click 默认 skip）, 0 failures（基线 207 + 新增 7）。
- 新增单测：空闲 5 秒 300 个 60Hz tick 后 frame / order 写入数不增加且定时器已 invalidate（`idleTickCount=60`、`suppressedIdleTickCount=1`）、同整点坐标不触发第二次 frame 写入、相同 level 不重复写、重复 start 会 invalidate 上一个定时器（且失效定时器不再 fire）、无锚点 / `window=0` 不 pump、整点取整、env 开关与计数行格式。
- `./scripts/check-docs.sh`：通过。

### ⚠️ 未覆盖 / 风险
- 未做 GUI 端到端视觉验证（验收轮占用桌面），空闲静止由单测 + 可选调试计数证明。
- idle 期用户手动把别的窗口抬到目标窗口之上时，cursor 可能被盖住直到下一次动作（这是去掉每帧强制重排的既定权衡）。
- `OPEN_COMPUTER_USE_VISUAL_CURSOR_IDLE_SWAY_MS=0` 会关闭 idle 微摆，此时 `runCursorIdleSmoke` 的 rotation 断言不再成立（默认值不触发该问题）。
