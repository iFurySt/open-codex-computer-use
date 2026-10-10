# 软件光标：窗口移动时按实时帧重定位（v1.0.0 基线）

## 背景

在 v1.0.0 上重做此前那条跨屏光标修复。双屏环境（内建屏给 Agent、主屏给人）下，目标窗口在动作途中被拖到另一块屏时，软件光标会停在窗口原来的屏幕上。

## 根因

1. `CGWindowListCopyWindowInfo` 在窗口移动后仍返回移动前的 frame（实测连续 83 帧、约 1 秒），只有 AX 元素的位置是即时的。
2. 光标目标点是在快照时刻算出来的；窗口之后移动，落点随之失效。
3. **v1.0.0 的点击路径不经过 `visualCursorTarget(for:snapshot:)`**：它在 `ComputerUseService` 的 click 分支里直接调 `makeVisualCursorTarget(at:...)`。因此最初把锚点接在 `visualCursorTarget(for:snapshot:)` 上，单测全过而真机完全无效——诊断日志证明 `register`/`liveFrame` 一次都没被调用。

## 改动

- 新增 `CursorWindowAnchor.swift`：`CursorRestingAnchor`（元素相对窗口帧的锚点，纯函数、可单测）+ `CursorWindowFrameTracker`（AX 元素优先、窗口列表兜底，带测试注入点）。
- `VisualCursorTarget` 增加 `anchor`；点击分支用 `clickPoint` 得到的窗口内坐标构造锚点，并在构造锚点处注册快照携带的 AX 窗口元素。
- Overlay：新增 `restingAnchor`、`liveTargetPoint()`、`anchoredWindowMoved()`、`abortTravelOntoObservedWindow()`；`moveCursor` / `settle` / `pulseClick` 均按实时帧重算，行进循环逐帧检查窗口是否移动，移动即中止并落到窗口的新位置。

## 验证

- 单测：`CursorWindowAnchorTests` 7 项（含用本次复现的真实数字构造的用例）；全套 199 tests / 7 skipped / 0 failures；`make check-docs` 通过。
- 真机（双屏）：窗口在行进途中从内建屏移到主屏，**连续两次**光标跟随到主屏（光标 `x=1057`，窗口 `x=600`）。
- 帧来源日志：76–79 次读取全部走 AX 元素，窗口列表兜底 **0** 次——即不再依赖那条会滞后的路径。

## 教训

第一次把锚点接在错误的函数上，单测全绿但真机无效。是**临时诊断**（无条件写日志，先验证调用路径）定位到真实构造点。结论：**先证明代码路径会被走到，再写实现**；单测覆盖不到调用路径本身。
