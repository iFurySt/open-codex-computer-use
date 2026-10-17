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

## 2026-10-17：基于当前 main 复查 #95

用户要求在当前 main 上重新检查和测试，修复之前仍有问题的跟随行为，并补充提交到原 PR。先保留原提交，再合入 main 的 1.1.1 基线。

### 补充修复

- 原实现的 idle timer 和 click pulse 保存旧落点，窗口移动后仍在旧位置绘制。现在行进、settle、pulse 和 idle 共用最新缓存帧，并能处理连续移动和返回原位置。
- 行进中止原本只更新 spring 目标，旧速度仍让可见 tip 留在旧位置。现在同时重置 dynamics 并直接绘制新位置；窗口在行进开始前已移动时，仍保留正常行进动画。
- 新的无锚点目标会清掉旧窗口追踪。开始 idle / pulse 前停止旧计时器，避免重复 timer 在 reset 后继续绘制。
- AX 查询改为后台串行读取：最多 30 Hz、同时一个请求，渲染只读缓存。慢窗口不阻塞主线程，也不会堆积请求。
- 只保留当前窗口的 AX 引用；切换窗口和清理后丢弃在途旧结果。短暂读取失败保留最后有效帧，不回退到旧快照或滞后的窗口列表。非法 / 无限 frame 被拒绝。
- 同步架构、skill 使用说明和功能记录。冒烟脚本的旧 9-tool 数量断言不兼容 main 新增的 query，改为检查完整的 10 个工具名称；现有 fixture 动作覆盖仍为原 9 个工具。

### 验证与边界

- 修复前在原 overlay 上跑新增回归，4 项中的 3 项失败、共 16 个断言失败，复现 idle / pulse 和可见 tip 问题。
- 完整 Swift：351 项，8 项跳过，0 失败；原基线为 341 项、7 项跳过、0 失败。
- Node REPL / CLI / 配置：36 项通过。完整 fixture 动作 smoke 和 cursor idle smoke 通过；文档检查与 diff whitespace 检查通过。
- 新测试直接驱动生产 overlay，覆盖连续移动、返回原位置、双击期间移动、行进中止、无锚点目标、reset 和行进前已经移动；后台读取测试覆盖慢响应、请求不堆积、旧结果丢弃和读取失败保留缓存。
- 真实独立 NSWindow 的 AX 测试通过，包含行进、双击反馈、idle 和当前所有显示器。当前测试机仅一块显示器，未重做物理双屏拖动；上文双屏实测属于原贡献者的验证。
- 新增完整 ComputerUseService.click 集成测试，但本机 XCTest 宿主未通过已有 Locked Use 身份校验，明确跳过；没有绕过保护。这项跳过与 fixture smoke、真实窗口 AX / overlay 测试区分记录。
- 该修改调整软件光标显示位置，不改变输入路由，也不处理窗口内部控件重新排版后的定位。
