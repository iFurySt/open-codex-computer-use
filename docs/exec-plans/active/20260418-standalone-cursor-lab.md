# Cursor Motion

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
- 2026-04-20：曾按用户反馈把“内部 heading”与“可见箭头角度”分离，短暂把 moving 阶段的可见箭头收紧成轻微 lean；这层假设随后已在对照官方抽帧后撤回。
- 2026-04-20：按用户反馈把左上角 5 个 slider 恢复回来，并重新接到 heading-driven 路径几何与 progress spring；当前 slider 明确只作为本地调参入口，不宣称是已完全确认的官方字段映射。
- 2026-04-20：继续按用户反馈把左上角控件区裁成纯 slider，并把 slider label / panel accent 收回当前中性灰紫主色系；不再保留 `REPLAY` / `RESET` 按钮和额外 metrics 文案，避免信息噪音和低对比白字。
- 2026-04-20：修正窗口 resize 时的状态重置 bug；`proxy.size` 变化现在只更新 canvas bounds，不再重新走 `configure + snap(to: start)`，因此调整窗口大小不会把 cursor 强行拉回起始点。
- 2026-04-20：基于 `Codex Computer Use.app` 的新一轮 timing 逆向，确认默认 move 的 wall-clock endpoint-lock 是固定的 `343 / 240 = 1.4291667s`；lab 现已移除距离驱动的 travel-duration 压缩，默认档直接按官方 spring timeline 走，`SPRING` slider 只再改变 spring 本身的 response / damping 与对应时长。
- 2026-04-20：对照用户提供的官方视频抽帧后，确认 moving 阶段的可见箭头确实会持续跟随当前 move heading，而不是只保留一个轻微 lean；lab 现已撤回那层 `displayRotation` 分离，glyph 渲染重新直接使用 visual dynamics 的主 `rotation`。
- 2026-04-20：继续对照 `official-software-cursor-window-252.png` 与独立脚本的静止朝向后，确认 lab 之前额外加的 `-26.5°` glyph 补偿会让 moving heading 固定偏掉；当前已把静止基线收敛到和主运行时一致的“零旋转即左上朝向”，也就是 y-down 画布里的 `-3π/4`。
- 2026-04-20：继续排查“屁股超前”后，确认真正的问题是 lab 的 motion/heading 运行在 SwiftUI 的 y-down 坐标，但 glyph 渲染落在 AppKit 默认 y-up `NSView`；当前已在 glyph 渲染层对 angle、body offset 和 fog offset 统一做 y-down -> y-up 转换，避免 moving 姿态被垂直镜像。
- 2026-04-20：把刚确认的 slider 语义进一步收回到 `CursorMotion` 主线上；`START HANDLE` 现在主要调起步段的 guide / reach / normal，`END HANDLE` 主要调收尾段的 guide / reach / normal，不再只是对整条曲线做对称缩放。同时移除了过紧的 corridor clipping，改用内缩 canvas bounds，避免默认样例里 `END HANDLE` 被提前裁没。
- 2026-04-20：继续按同样方法收紧 `ARC SIZE`；当前它明确表示轨迹弧度而不是 cursor 大小，并且已经同时接到局部 path 的弧高/控制点侧向偏移，以及 chooser 对 `direct` 和 `arched` family 的偏好。默认点位采样下，`arcSize=0.04 -> 0.12` 会让 `curveScale` 从约 `10.3` 提升到 `47.7`，中段 `y` 也从约 `326.8` 抬到 `345.5`。
- 2026-04-20：继续收紧 `ARC FLOW`；当前它明确表示“最宽弧段在 chord 上更靠前还是更靠后”，实现上不再只是改 start/end reach 的抽象 bias，而是改到单段 cubic 控制点的前后相位偏置。
- 2026-04-20：继续收紧 `SPRING`；当前它明确表示 progress spring 的 `response / damping` 与 endpoint-lock 时间，默认 `spring=0.5` 会精确回到官方 `.official` 配置。采样下，`spring=0.25 / 0.5 / 0.75` 分别对应约 `1.0958s / 1.4292s / 1.8750s` 的 endpoint-lock，语义已经收成稳定的“左快右慢”。
- 2026-04-20：修正 `ARC FLOW` 首轮实现引入的中段“节点感”；问题不在 `SPRING`，而在那版显式中间锚点的双段曲线把路径本身做出了 join，叠加 debug overlay 又把这个中点强调出来。当前已经收回到单段 cubic，相位控制继续保留，但几何上不再存在中间 join。
- 2026-04-20：继续修正 slider 调参状态流；当前已把“当前 cursor 位置”和“当前会话的 reference path”拆开，slider 重算时用最近一次真实 move 的 origin / startRotation + `queuedTarget` 更新整条调试曲线，同时只把 cursor snap 在当前位置，因此 settled 后调参也不会把 DEBUG 线重建成 `target -> target` 的零长度路径。
- 2026-04-20：继续收口右上角控件；当前只保留 `DEBUG` 一个 switch，`MAIL` / `CLICK` 已移除，click pulse 默认常开，同时把 switch 的 on/off 底色拉开到和左侧 slider 一致的高对比语义。
- 2026-04-20：继续收口左右 panel 的容器样式；当前左上 slider 面板和右上 `DEBUG` 面板已经统一复用同一套 card shell，不再分别维护不同的 padding / frame 包装。
- 2026-04-20：继续修正 panel 在浅背景上的识别度；当前 card fill 已收成更实的灰白底，并加强描边和阴影，减少背景渐变直接透到 panel 上导致的“看起来像不同底色”问题。
- 2026-04-20：已把独立 demo 的对外命名统一收口到 `Cursor Motion` / `CursorMotion`；Swift Package product、实验目录、README 入口和相关文档现在都以 `swift run CursorMotion` 为准，不再保留 `StandaloneCursorLab` 旧名。
- 2026-04-20：已补一条 tag 驱动的 `Cursor Motion` 分发链路；本地可以通过 `scripts/build-cursor-motion-dmg.sh` 构建 DMG，GitHub Actions 在推送 release tag 后会自动生成 `CursorMotion-<version>.dmg` 并上传到 GitHub Releases。
- 2026-04-20：继续修正“打包版和 `swift run CursorMotion` 观感不一致”的问题；当前已确认 release app 之前没把官方 `252x252` baseline cursor PNG 带进 bundle，导致退回 procedural glyph。现在 `.app` 会优先从 `Bundle.main` 读官方 cursor 图，DMG 打包脚本也会把这张图复制进 `Contents/Resources`，并显式打开 `NSHighResolutionCapable`。

## 决策记录

- 2026-04-18：先把这项工作定义为 standalone lab，而不是继续直接堆进 `OpenComputerUseKit`.
- 2026-04-18：参数命名优先采用视频 UI 与官方字符串的交集：`start/end handle`、`arc size/flow`、`spring`。
- 2026-04-18：第一版 demo 先用独立 SwiftUI target + `CVDisplayLink` 驱动模拟，优先验证参数语义和轨迹手感，再考虑与主 overlay 合流。
- 2026-04-19：在拿到更完整的 binary-backed 路径与视觉层实现后，lab 改为直接演示 recovered 结构，不再把未经确认的 slider 语义继续当成主实现。
- 2026-04-19：对 `swift_once` 恢复出的 guide 系数，当前默认采用“常量已确认、世界坐标解释不成立、局部基底投影更贴近官方视频”的实现策略；后续如果拿到更强的二进制级证据，再继续下沉这层解释。
- 2026-04-19：raw binary lift 的 `20` candidate pool 保留在 `StandaloneCursor` 这条分析线；`CursorMotion` 和主 runtime overlay 则统一切到 heading-driven 主线，实现上优先保证“朝向约束 + 单侧转弯”这个更贴近官方视频的结构行为。
- 2026-04-20：恢复 slider UI 时，继续把“调参入口”和“binary-confirmed 结构”分开表述；lab 可以暴露 `start/end handle`、`arc size/flow`、`spring` 这些测试旋钮，但文档和代码都不把它们说成官方一一字段对照。
- 2026-04-20：对 `start/end handle` 这两个旋钮，当前实验线采用“作用在局部 start/end control 几何，而不是全局统一缩放”的策略；这更接近 binary lift 里 `startControl/endControl` 与 `startExtent/endExtent` 的边界。
- 2026-04-20：对 `ARC SIZE`，当前实验线采用“作用在局部 arc height / normal bias / family chooser，而不是 cursor glyph 尺寸”的策略；这更接近 binary lift 里 `handleExtent / arcExtent / tableA / tableB` 对曲线宽度的作用边界。
- 2026-04-20：对 `ARC FLOW`，当前实验线采用“作用在单段 cubic 控制点的前后相位，而不是单纯抽象 reach bias”的策略；这更接近 reverse-engineering 里“最宽弧段被沿 guide 方向推前/推后”的边界。
- 2026-04-20：对 `SPRING`，当前实验线采用“围绕官方 `.official` 的 centered response/damping remap，而不是再叠加额外 distance-based duration 层”的策略；这更接近当前 binary-backed 证据里“主链直接吃 `1.4 / 0.9` spring config”的边界。
- 2026-04-20：调左上角 slider 时，path 重建现在统一基于当前会话里最近一次 move 的 reference origin / startRotation / `queuedTarget`，而不是外层 `@State start/end` 或 settled 后的 live endpoint；这样参数调节既不会把曲线起点误拉回初始位置，也不会把 DEBUG 反馈线消成零长度。
- 2026-04-20：对 `Cursor Motion` 的对外交付，当前采用“源码运行 + GitHub Releases 分发 ad-hoc signed DMG”的策略；先把 tag 驱动的可复现封装链路稳定下来，不在这一轮提前引入 notarization 和 Developer ID 签名复杂度。
- 2026-04-20：对 packaged `Cursor Motion` 的 glyph 资源，当前采用“bundle 内官方 baseline 图优先，仓库 reference 路径兜底”的策略；这样 release app 不再因为缺资源而静默退回低保真的 procedural glyph。
