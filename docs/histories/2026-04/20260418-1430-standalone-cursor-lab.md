## [2026-04-18 14:30] | Task: 落独立 cursor motion lab

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 结合官方视频和已分析到的 cursor overlay 线索，在当前仓库里单独开一个目录，实现一版可独立开源的软件鼠标曲线，并继续推进分析与落地。

### 🛠 Changes Overview
**Scope:** `Package.swift`、`experiments/StandaloneCursorLab/`、`docs/`、`README`

**Key Actions:**
- **[新增独立 target]**: 把 `StandaloneCursorLab` 加入 Swift Package，可通过 `swift run StandaloneCursorLab` 单独运行。
- **[实现 motion demo]**: 新增参数化 cursor motion model、Bezier 路径生成、spring/timing 模拟和 SwiftUI 调参界面。
- **[补齐点击交互]**: 支持点击画布任意位置生成多条候选路径，并选中一路径驱动 cursor 动画。
- **[收敛候选曲线与显示逻辑]**: 扩展为多组 descriptor 驱动的轨迹族，并让主路径在关闭 `DEBUG` 时继续可见。
- **[修正点击坐标与死区]**: 统一 AppKit click-capture 和 SwiftUI 画布的坐标语义，去掉误导性的矩形事件排除区，避免底部区域出现“点了不动”的隐藏死区。
- **[收敛 demo 控件状态]**: 把 `DEBUG` toggle 的开启态改为明确高亮，并让顶部 controls 只占自身区域，不再靠整层透明容器遮挡画布事件。
- **[增强 turn/brake 手感]**: 把路径生成从“只看起终点连线”改成“线方向 + cursor 朝向”的混合约束，并新增 `turn` / `brake` family，让主路径更容易出现先顺头部方向、再掉头切入、末端带刹车回咬的走势。
- **[重做 timing / rotation]**: 把进度推进从 spring + `easeInOut` 改成更接近人手 pointing 的 minimum-jerk bell-shaped timing；同时让 cursor 在运动过程中持续朝向切线方向，并在到点阶段平滑回归经典朝向。
- **[移除末端多余位移]**: 删除位置层的 settle overshoot，保留连续移动和自然减速，不再在最后额外挪一下。
- **[加入 curvature-aware timing]**: 为路径建立 weighted-effort lookup，把高曲率和大 heading-change 的片段映射为更慢的时间推进，让“起步掉头”和“末端收束”阶段获得更自然的速度分配，而不是直接用 Bezier 参数 `t` 均匀走完。
- **[切到资源化 cursor asset]**: 把 standalone lab 的矢量箭头切换为 target 内置 PNG 资源，建立单独的 glyph calibration，并把静止姿态收敛到接近视频里的默认朝向。
- **[改为 tip-anchor 命中对齐]**: 不再拿整张 cursor 图的中心做定位，而是把图像 tip 对齐到 motion sample point，避免更换为朝上型 asset 后重新出现点击坐标偏移。
- **[收敛运动中朝向跟随]**: 把 motion simulator 的 rotation 统一为基于 glyph neutral heading 的绝对姿态，运动时持续追随曲线切线方向，结束时再平滑回到静止角度。
- **[补 launch/甩头候选族]**: 为 path builder 新增更强调当前 heading 惯性的 `launch` family，并在控制点生成时增加显式 launch bias，让起步阶段更像先顺着车头冲出去、再回切目标。
- **[加入 path quality 排序]**: 候选路径不再只按 family 常量排序，而是同时考虑起步朝向贴合度、早段转头力度、末段切线对齐和 terminal straightness，以便更稳定选到“既有甩头、又能干净收尾”的主路径。
- **[加强末段刹车 timing]**: 把 weighted effort lookup 从单一 edge profile 拆成 start/end 两段；前段更重掉头 effort，后段更重 braking effort，并略微拉长高加权路径的总时长，让最后一小段减速和收束更明显。
- **[重构为官方双层模型]**: 把 standalone lab 从旧的“路径 sample + 末端 rotation settle”实现，切到 recovered 的 `20` 条官方候选路径、官方风格 spring progress，以及和主运行时一致的独立 visual dynamics。
- **[移除 speculative 调参主线]**: lab 控制面板不再把 `START HANDLE` / `ARC FLOW` / `SPRING` 这类未完全确认语义的 slider 当成主入口，而是直接展示选中的 candidate id、score 和测量值。
- **[实机跑独立 app 验证]**: 实际启动 `swift run StandaloneCursorLab` 对应的 app，确认 `REPLAY` 与画布点击都会切换候选路径，并看到末段不是原地翻角，而是路径层先形成回接弧线，再由 visual dynamics 做姿态滞后和 idle sway。
- **[同步仓库知识]**: 补 motion model 逆向分析文档、active execution plan、架构说明、README 入口和 history。

### 🧠 Design Intent (Why)
主线 `SoftwareCursorOverlay` 更适合承载产品行为，不适合继续堆调参与实验 UI。这次把 cursor 曲线实验拆成独立 lab，是为了先稳定参数模型和视觉手感，再决定哪些部分适合回灌主 MCP 实现或单独开源。

### 📁 Files Modified
- `Package.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `experiments/StandaloneCursorLab/README.md`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/StandaloneCursorLabApp.swift`

### 🔁 Follow-up (2026-04-19)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[同步主运行时的 recovered motion model]**: standalone lab 现在直接使用 recovered 的 base/arched candidate 生成策略、`VelocityVerlet` progress spring 和独立 visual dynamics。
- **[重做 lab UI 的语义]**: 控制面板改成展示选中候选路径与 measurement，而不是继续暴露容易误导为“已确认官方语义”的 slider。
- **[补充独立验证]**: 实际拉起 app，并通过桌面交互验证 `REPLAY` 和新目标点击会切换 candidate，界面也能实时反映 `BASE-SCALED-GUIDE` / `ARCHED` 等选择结果。
- **[恢复箭头的 heading 跟随]**: 基于 bundled `SkyComputerUseService` 里 `SoftwareCursorStyle.velocityX / velocityY / angle` 与 `CursorView._animatedAngleOffsetDegrees` 的分层证据，把 lab 的姿态从“单一受限小角度偏移”修回“主 heading 跟随速度方向 + 额外小幅 wiggle offset”。
- **[补 lab chooser 约束]**: 用户指出默认样例会选到过于夸张的大回环后，明确区分“recovered candidate pool”和“真实环境下还有 target-window chooser”两层；lab 现在新增 synthetic corridor hit-count，避免在整块画布上把一些过于离谱但平滑的 arched candidate 当成官方必选结果。
- **[修正 candidate 坐标系解释]**: 对照官方视频后，确认之前把 recovered guide/arc 常量直接当成固定屏幕坐标向量会在某些象限下生成扭曲回环；现在改成先投到 start→end 的局部基底，再生成候选路径，候选族重新收敛到围绕主轴的 C/椭圆形分布。
- **[主线切到 heading-driven chooser]**: 继续对照官方视频后，确认 standalone lab 不能把 raw reverse-engineered `20` candidate pool 直接拿来做默认选路；当前已改成把当前可见朝向和最终 resting pose 一起喂给 chooser，让“需要掉头时是单侧 C 形、无需掉头时接近直线”重新成为默认分布。
- **[同步 runtime overlay 选路]**: 主 `SoftwareCursorOverlay` 现在也改为同一套 heading-driven candidate 族；raw reverse-engineered `20` candidates 仍然保留在 `StandaloneCursor` / Python 重建脚本里做分析对照，但不再直接作为 runtime 主 chooser。
- **[补方向约束回归测试]**: 新增测试，显式验证“朝向已对齐时优先近直线”和“起步朝向反向时优先掉头大弧”两类行为，避免后续再次回到怪异扭曲曲线。
