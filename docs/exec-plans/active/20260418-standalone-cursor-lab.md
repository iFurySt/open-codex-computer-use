# Standalone Cursor Lab

## 目标

在当前仓库内落一个与主 `OpenComputerUseKit` 解耦的独立目录，用 Swift 实现一版可调参的软件 cursor motion demo，用来逼近官方视频里的手感，并为后续单独开源做准备。

## 范围

- 包含：
- 新建独立目录承载 cursor motion 实验，不直接污染主 MCP runtime。
- 把 motion model 拆成参数层、路径层、时间模拟层、渲染层。
- 做一个本地可运行的 demo，至少支持起点/终点、轨迹预览、参数滑杆和点击触发。
- 把本轮逆向分析沉淀到 `docs/references/`。
- 不包含：
- 本轮不要求接入真实 `click` tool。
- 本轮不要求完全复刻官方闭源素材。
- 本轮不要求把 demo 立即发布成独立仓库。

## 背景

- 用户提供了 X 视频样本，明确出现 `START HANDLE`、`END HANDLE`、`ARC SIZE`、`ARC FLOW`、`SPRING` 调参项。
- `SkyComputerUseService` 字符串已出现 `BezierParameters`、`SpringParameters`、`arcHeight`、`arcIn`、`arcOut`、`cursorMotionProgressAnimation` 等证据。
- 当前仓库已有 `SoftwareCursorOverlay.swift`，但它更像产品内近似实现，不适合继续承载大量调参与实验 UI。

## 风险

- 风险：过早把实验代码下沉到主包，导致主线 overlay 行为反复波动。
- 缓解方式：先放独立目录，稳定后再抽公共模块。
- 风险：只凭视频调参，可能把“视觉像”误当成“结构对”。
- 缓解方式：优先围绕已确认字段名建模，不做纯拍脑袋参数命名。
- 风险：demo UI 和未来独立开源边界不清。
- 缓解方式：第一阶段只做最小可运行 lab，避免提前引入和 MCP/tool 相关的耦合。

## 里程碑

1. 建立独立目录与 README，明确模块边界。
2. 实现纯参数化路径生成与可视化。
3. 补 spring/timing 模拟。
4. 在独立 lab 中完成一版按最新逆向结果重构的官方风格路径/姿态模型。

## 验证方式

- 能独立运行本地 demo。
- 能通过 slider 实时改变轨迹几何和停驻手感。
- 仓库文档能说明该目录与主产品代码的边界。

## 进度记录

- [x] 里程碑 1
- [x] 里程碑 2
- [x] 里程碑 3
- [x] 里程碑 4

## 最新进展

- 2026-04-18：已补齐点击任意位置触发候选路径预览，不再局限于 replay。
- 2026-04-18：已修正 click capture 的坐标系和事件覆盖问题，底部区域不再因为额外矩形排除区而出现隐藏死区。
- 2026-04-18：已把 `DEBUG` toggle 的开启态改成明显高亮，并把 controls 改成最小 overlay 布局，避免透明容器阻挡画布点击。
- 2026-04-18：已把路径模型升级为“line direction + cursor heading”混合约束，并新增 `turn` / `brake` 候选族，选中的主路径开始具备更明显的先顺头部方向、再回咬目标的走势。
- 2026-04-18：已把 timing 从 spring + `easeInOut` 改为 minimum-jerk bell-shaped profile，并移除位置层末端 overshoot；cursor 在运动中持续跟随切线朝向，到点阶段再平滑回正。
- 2026-04-19：已为路径建立 curvature / heading-change 加权的 effort lookup，进度推进不再直接绑定 Bezier 参数 `t`，从而让高曲率转向段更慢、直线段更快。
- 2026-04-19：已把 standalone lab 的 cursor 切到资源化 PNG asset，并改成 tip-anchor 驱动的命中点对齐；静止姿态与运动姿态共用一套 heading calibration，运动中持续朝向当前切线方向。
- 2026-04-19：已新增更偏“launch/甩头”的候选路径族，并引入 path quality 评分，显式衡量起步朝向贴合度、早段转头力度、末段切线对齐和 terminal straightness。
- 2026-04-19：已把 timing edge weighting 拆成 start/end 两侧，分别加重起步掉头和末段刹车阶段，从而让速度分配更接近官方视频里“先甩头、后收束”的节奏。
- 2026-04-19：已把 lab 从 speculative slider 驱动的曲线/收尾模型，重构为 recovered 的 `20` candidate path + 官方风格 spring progress + 独立 visual dynamics；收尾不再靠 endpoint 锁住后原地翻角。
- 2026-04-19：在对照官方视频后发现 guide/arc 相关常量不能直接按屏幕坐标向量使用；当前已改成先投到 start→end 的局部基底，再生成候选路径，默认样例和反向斜移都不再出现起点附近打结式的扭曲回环。
- 2026-04-19：继续对照官方视频后，确认 lab 主线不能直接拿 raw reverse-engineered `20` candidates 当 chooser；当前已改成 heading-driven 选路，把当前可见朝向和最终 resting pose 一起参与选路，主路径重新收敛到“需要掉头时走单侧 C 形，不需要掉头时近直线”的分布。
- 2026-04-20：在对照 `scripts/render-synthesized-software-cursor.swift` 与用户截图后，确认共享 glyph renderer 的亮白 asset 风格并不对；当前已把 lab 改成优先显示仓库里的官方 `252x252` runtime baseline 图，fallback 才走脚本同款 procedural pointer/fog，同时把 idle 从 XY 漂移收紧为中心固定的小幅摆角。
- 2026-04-20：继续按用户反馈收紧姿态后，lab 现在把“内部 heading”与“可见箭头角度”分离；选路仍可参考当前 heading，但屏幕上看到的箭头不再像车头一样沿切线持续转向，只在转弯时轻微 lean。

## 决策记录

- 2026-04-18：先把这项工作定义为 standalone lab，而不是继续直接堆进 `OpenComputerUseKit`.
- 2026-04-18：参数命名优先采用视频 UI 与官方字符串的交集：`start/end handle`、`arc size/flow`、`spring`。
- 2026-04-18：第一版 demo 先用独立 SwiftUI target + `CVDisplayLink` 驱动模拟，优先验证参数语义和轨迹手感，再考虑与主 overlay 合流。
- 2026-04-19：在拿到更完整的 binary-backed 路径与视觉层实现后，lab 改为直接演示 recovered 结构，不再把未经确认的 slider 语义继续当成主实现。
- 2026-04-19：对 `swift_once` 恢复出的 guide 系数，当前默认采用“常量已确认、世界坐标解释不成立、局部基底投影更贴近官方视频”的实现策略；后续如果拿到更强的二进制级证据，再继续下沉这层解释。
- 2026-04-19：raw binary lift 的 `20` candidate pool 保留在 `StandaloneCursor` 这条分析线；`StandaloneCursorLab` 和主 runtime overlay 则统一切到 heading-driven 主线，实现上优先保证“朝向约束 + 单侧转弯”这个更贴近官方视频的结构行为。
