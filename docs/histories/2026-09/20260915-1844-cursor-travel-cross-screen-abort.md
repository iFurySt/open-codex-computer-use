## [2026-09-15 18:44] | Task: 修复跨屏拖动时光标沿旧路径继续飞行

### 🤖 Execution Context
* **Agent ID**: `session-66aa166d-ee60-437e-a52e-940a311c8c76` (DSH)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI

### 📥 User Query
> 这个 ocu 还是有问题，我主屏幕打开 chrome，移到了内建屏上，ocu 显示软件光标居然在主屏幕，并且看到光标在控制移动，随后才回到了内建屏上，到底是 skill 问题还是代码问题呢？

这是 `20260912-1510-cursor-cross-screen-reanchor` 修过的同一症状再次出现。先确认运行副本确实包含那次修复（用只存在于最新提交的 `display note` 字符串验证），排除了"没装上新版"，再定位剩余路径。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（`SoftwareCursorOverlay`、`SnapshotWindowGeometry`）、单元测试、`skills/open-computer-use/references/usage.md`。

**根因**：`SoftwareCursorOverlay.animateMove` 是同步忙循环——每帧按预先采样的路径写光标位置，直到整段行进结束。窗口在行进中被拖到另一块屏时：

- AX 移动通知确实触发了 `targetWindowDidMove()` → `applyLiveWindowAnchor` → `repositionCursor`（瞬移，并重播种视觉动力学）；
- 但循环的**下一帧**又按旧路径采样写回光标，把瞬移覆盖掉；
- 于是观感是"光标一直在主屏被控制着移动，直到整段动画跑完才回到内建屏"。

**修复**：行进开始前记录目标窗口 frame，循环每帧重读实时 frame，一旦变化立即中止行进、落到新 frame 并返回（不再执行收尾的旧目标落点）。

- `SnapshotWindowGeometry.swift` 新增纯决策 `cursorTravelMustAbort(startFrame:liveFrame:)`：frame 变化即中止；**读不到 frame 不算变化**（与 `snapshotWindowReanchorAction` 对"窗口消失"的处理一致）。
- `SoftwareCursorOverlay.animateMove` 每帧调用该决策；命中则 `applyLiveWindowAnchor` + `refreshTargetWindowAnchorIfScreenChanged` 后 `return`。

### 🧠 Design Intent (Why)
- **为什么不在通知回调里取消动画**：行进是主线程上的同步循环，回调无法中断它；只有循环自己检查才生效。这也是"通知已经瞬移、光标却继续飞"的原因。
- **为什么判据是"frame 变化"而不是"屏幕不匹配"**：拖动过程中窗口可能仍与旧屏相交，屏幕级判据会漏；frame 变化是最早、最可靠的信号。
- **为什么读不到 frame 不中止**：AX 动作路径本就不需要 frame，窗口最小化或换 Space 时中止会让原本可用的动作凭空失败。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SnapshotWindowGeometry.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/CursorCrossScreenTests.swift`
- `skills/open-computer-use/references/usage.md`

### ✅ Verification
- 新增 2 个用例：纯决策边界（含读不到 frame 的两种情况）；以及**跑真实行进循环**的端到端用例（窗口 frame 在起始帧与首帧之间变化）。
- **反向证明**：临时禁用修复后该用例失败，落点 `(140, 370)` 说明光标仍在旧路径上；恢复后通过，落点 `(840, 370)`（由实时 frame 推导）。
- `swift test`：264 tests / 1 skipped / 0 failures；`make check-docs` 通过。
- **未做真机双屏复现**：本机探测窗口（TextEdit / Finder）落在 OCU 驱动的 Space 之外，动作路径报 `cgWindowNotFound`，无法在不干扰用户桌面的前提下复现该场景。

### 🔁 2026-09-15 补记 | 真机实测确认 + choreographer 层落点修复

用户提示"刚才有其他任务对话在使用 ocu"后重测，最终修好并验证：

1. **中止行进只是第一步**。真机插桩证明两件事：
   - 通知在行进途中就送达，且此刻 AX frame 已是新的（`ax=(600,200,…)`），而窗口列表仍是旧值（`list=(-1400,200,…)`）——印证"窗口列表滞后约 1 秒、AX 位置即时"；
   - 但光标最终仍停在旧屏，因为 `VisualInteractionChoreographer.approach` 是 `moveCursor(target)` → `settleCursorArrival(target)`，`settle` 用**同一个移动前算出的 target** 再落位一次，覆盖了中止结果。
2. **补齐 choreographer 层**：`SoftwareCursorOverlay.settle` / `pulseClick` 落位前经 `liveTargetPoint(...)` 按实时 frame 重算（元素 frame 是窗口相对的，保留 window-local 偏移、只换原点）。中止落点同样优先用 AX frame。
3. **验证**：
   - 新增 3 个用例（通知中止行进、settle 与 pulseClick 用实时 frame）；全套 267 tests / 1 skipped / 0 failures；
   - 反向证明：去掉 settle 的实时重算后用例失败，落点 `140,370`（即旧屏）；
   - **真机连续三次实测通过**：窗口拖到主屏后光标停在主屏 `x=1023`（处于窗口范围 600–1118 内）；对照组（仅窗口列表兜底的版本）在同一场景下光标停在旧屏 `-977`。
4. **教训**：中途一次"修复无效"是**别的会话同时驱动 OCU** 造成的假阴性；重测前先用 10 秒被动采样确认 overlay 位置无变化，再下结论。

### ⚠️ 未覆盖 / 风险
- 真实拖动（鼠标按住移动）期间的行为未现场验证，单测用注入的 frame 序列覆盖。
- 中止后若 `applyLiveWindowAnchor` 因 anchor 不匹配而跳过，光标会停在行进中途，需要下一次动作纠正（比继续飞向旧屏可接受，但不是最优）。
- 同类竞态的另一半仍在：动作**刚开始**的瞬间窗口服务器尚未更新 frame 时，该动作仍可能瞄准旧点。本次只覆盖"行进途中变化"。
