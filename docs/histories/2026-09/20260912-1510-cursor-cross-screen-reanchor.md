## [2026-09-12 15:10] | Task: 窗口跨屏/移动后重定位虚拟光标（坐标陈旧修复）

### 🤖 Execution Context
* **Agent ID**: `session-fe09ecb5-988e-4679-aba5-333c4e21743e` (DSH subagent)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI（委派子代理会话）

### 📥 User Query
> 用户实测：目标 App（Chrome for Testing）开在外接屏；把窗口移到内建屏后，OCU 的虚拟光标仍留在原来那块屏上（位置没跟着窗口走）；期间还抢了他的焦点；稍后光标又“正常回到内建屏”。要求给出 file:line 根因、修复、单测、`swift build` / `swift test` / `check-docs.sh` 与文档同步、本地原子提交（不 push）+ 装机（同证书重签、doctor 双 granted、记录新 PID）与回退命令。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（`ComputerUseService`、`AccessibilitySnapshot`、新增 `SnapshotWindowGeometry` / `CursorWindowMotionWatch`、`SoftwareCursorOverlay`、`VisualInteractionChoreographer`）、单元测试、`docs/`、`skills/open-computer-use/SKILL.md`。

**根因（坐标陈旧）**：`ComputerUseService.currentSnapshot`（`ComputerUseService.swift:1159-1165`）把 `snapshotsByApp` 缓存直接交给 8 个动作入口（`653/857/902/946/968/989/1006/1062`）。缓存里的 `windowBounds` / `targetWindowID` 停在 `get_app_state` 时刻，用户在两次动作之间拖动窗口（含跨屏）后：`windowPointToGlobalPoint`（`2205-2211`）与 `makeVisualCursorTarget`（`184-220`）仍按旧 frame 算全局点 → overlay 画在旧屏、坐标点击与截图映射同样偏移；动作收尾的 `refreshSnapshot`（`688` 等）才刷新缓存，于是观感是“先留在旧屏、稍后又正常”。overlay 侧没有任何窗口移动观察者（只有 `workspaceDidActivateApplication` 与“窗口消失”时的重排），`clampTipPosition`（`927-942`）还会按旧点所在屏继续夹取，加固旧屏。

**根因（抢焦点，不同源）**：全部会改变前台焦点的 API 已收敛在 opt-in 之后——`AccessibilitySnapshot.recoverVisibleWindow`（`AccessibilitySnapshot.swift:300-324`，仅 `.allowActivation`）、`activateClickTarget`（`ComputerUseService.swift:1436-1452`，由 `activationOnlyClickFallbackAllowed` 门控）、`InputSimulation.prepareAppForGlobalPointerInput`（`InputSimulation.swift:48-56`，仅 global 指针路径）。默认路径零激活，本次修复不新增任何激活 API。

**Key Actions:**
- **动作前重读窗口几何**：新增 `SnapshotWindowGeometry` / `snapshotWindowReanchorAction` / `AppSnapshot.reanchored(to:)`；`currentSnapshot` 每次动作前用 `CGWindowListCopyWindowInfo(.optionIncludingWindow)` 重读目标窗口。同窗口同尺寸仅移动 → 只 patch `windowBounds`（元素 frame 是窗口相对坐标，不需要重取）；尺寸变化或换了窗口 → 整份 `refreshSnapshot`；解析不到 → 保持原快照（AX 动作路径本来就不需要 frame）。
- **overlay 跟随窗口**：`VisualCursorTarget` 增加 screen-state 点与当时的窗口 frame，派生 `CursorRestingAnchor`（窗口局部偏移 + frame）；`SoftwareCursorOverlay` 保存该锚点，窗口移动/换屏后由 live frame 重推 tip。
- **事件式跟随**：新增 `AXWindowMotionObserver`（`kAXWindowMovedNotification` / `kAXWindowResizedNotification`，只读注册；`OPEN_COMPUTER_USE_WINDOW_MOVE_WATCH=0` 关闭），`SoftwareCursorOverlay.observeTargetWindow` 由 `currentSnapshot` 在每次动作时投递，面板出现后挂载，`reset()` / turn-ended 摘除。
- **动作前兜底校验**：`refreshTargetWindowAnchorIfScreenChanged` 在每次落位前比较“光标所在屏 == 目标窗口所在屏”，不一致就用 live frame 重算并 `repositionCursor` 重画；两条路径都不隐藏光标（`orderOutCount == 0`）。

### 🧠 Design Intent (Why)
* 坐标陈旧属缓存问题，修在“动作取快照”这一层比在 overlay 里打补丁更彻底：所有派生量（光标 tip、坐标点击、截图像素映射、滚入视口判定）都从 `windowBounds` 出发，frame 一刷新就同时正确。
* 只 patch“同尺寸移动”，resize 走整份重取：元素 frame 是窗口相对坐标，纯移动不改变它们；resize 会同时改变布局与截图缩放比，patch 只会制造更难查的错误坐标。
* 跟随用只读 AX 通知 + 动作前兜底两层，而不是轮询 window server：轮询会破坏此前建立的“空闲绝对静止、只读不写”契约；App 不保证都发 `AXWindowMoved`，所以才需要动作前的屏一致性兜底。
* 跟随用立即落位（`repositionCursor`）而不是 Bezier 飞行：用户自己在拖窗口，光标跟着窗口瞬移才读作“跟着走”。

### 📁 Files Modified
- 新增：`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SnapshotWindowGeometry.swift`
- 新增：`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorWindowMotionWatch.swift`
- 新增：`packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/CursorCrossScreenTests.swift`（9 个用例）
- 修改：`ComputerUseService.swift`、`AccessibilitySnapshot.swift`、`SoftwareCursorOverlay.swift`、`VisualInteractionChoreographer.swift`、`OpenComputerUseKitTests.swift`（`AppSnapshot` 新字段与 `VisualCursorTarget` 新锚点断言）
- 文档：`skills/open-computer-use/SKILL.md`（平台中立段）、`docs/ARCHITECTURE.md`、`docs/exec-plans/active/20260912-quiet-window-recovery-scroll-into-view.md`（P11 进度与决策）

### ✅ Verification
- `swift build`：Build complete（0 error）。
- `swift test`：**231 tests / 1 skipped / 0 failures**（基线 222/1/0，本次 +9）。
- `./scripts/check-docs.sh`：通过。
- 现场探针：`CGWindowListCopyWindowInfo([.optionIncludingWindow], id)` 对真实窗口返回 bounds（`optionIncludingWindow_count=1 bounds=(0.0, 31.0, 2048.0, 1058.0)`）。

### ⚠️ 未覆盖 / 风险
- 真实跨屏拖动未做 GUI 端到端（验收屏正被其它子代理使用）：跨屏跟随由注入假 panel host / 假屏映射 / 假观察者的单测覆盖，`AXWindowMoved` 在 Chromium 上的实际投递未现场验证（动作前兜底不依赖它）。
- 抢焦点与坐标陈旧是否同源未能现场证实；本次只做 API 审计与默认值回归测试，未新增激活路径。
