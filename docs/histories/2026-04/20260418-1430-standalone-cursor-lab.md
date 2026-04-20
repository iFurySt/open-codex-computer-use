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

### 🔁 Follow-up (2026-04-20, synthesized overlay style)
**Scope:** `experiments/StandaloneCursorLab/`、`Package.swift`、`docs/`

**Key Actions:**
- **[改回脚本同款视觉]**: 对照用户给出的 `render-synthesized-software-cursor.swift` 参考图后，确认 lab 当前复用的亮白 asset 风格不对；改为优先显示仓库中的官方 `252x252` runtime baseline 图，并在缺失时退回脚本同款 procedural pointer/fog。
- **[收紧 settle 态]**: `CursorMotionSimulator` 的 idle 不再做 XY 漂移，而是保持位置固定，只保留中心固定的小幅摆角，贴近脚本默认档的“原地轻微转动”。
- **[撤回错误文档描述]**: README、架构说明和 execution plan 不再声称 lab 复用 `SoftwareCursorKit` 的共享 glyph renderer，改成明确引用脚本化 baseline/procedural renderer。

### 📁 Additional Files Modified
- `Package.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorGlyphCalibration.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/SynthesizedCursorGlyphView.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, decouple visible arrow angle)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[分离内部 heading 与可见角度]**: 保留 motion model 内部 `rotation` 给下一段选路参考，但新增单独的 `displayRotation` 给 glyph 渲染，避免箭头在移动时像车头一样持续指向轨迹方向。
- **[改成轻微 lean]**: moving 阶段的可见角度现在只根据 turn dynamics 给一个很小的偏转；idle 阶段仍然保留原地小摆角。
- **[同步文档说法]**: README、架构说明和 active plan 不再把 lab 当前表现描述成“箭头主朝向明显跟随运动方向”。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[移除起始点残留白点]**: `StandaloneCursorLab` 画布不再常驻渲染起始点白色 marker，避免 cursor 沿曲线移动后仍在起点留下误导性的白点。
- **[收紧 DEBUG 关闭态]**: `DEBUG` 关闭后不再保留选中主轨迹或目标点 marker，整层调试 overlay 会一起隐藏，避免非调试模式下仍残留轨迹线和圆点。
- **[主视觉改为中性灰紫]**: 把 lab 的背景渐变、调试高亮和控件 accent 从原先偏粉色的方案切到接近 `#E3E2E6` 的中性灰紫配色，避免画面继续带明显粉色倾向。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/README.md`

### 🔁 Follow-up (2026-04-20, align glyph baseline heading with official cursor artwork)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[回收多余的局部旋转补偿]**: 对照独立 `render-synthesized-software-cursor.swift` 脚本和官方 `252x252` runtime baseline 图后，确认 lab 里额外的 `restingRotation = -26.5°` 会把 moving 期间的可见 heading 固定偏开。
- **[静止朝向改为左上基线]**: `CursorGlyphCalibration` 现在直接把零旋转基线定义成官方箭头的天然静止朝向；在 lab 的 y-down 坐标里用 `neutralHeading = -3π/4`，`restingRotation = 0`，让 path heading 和 glyph 朝向共用同一套基准。
- **[对齐主运行时语义]**: 这次调整也把 `StandaloneCursorLab` 的 heading 标定方式收回到和 `SoftwareCursorOverlay` 一致的思路，不再额外维护一层实验性局部偏角。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorGlyphCalibration.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, fix y-axis mismatch in glyph rendering)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[定位到渲染坐标系不一致]**: 继续对照用户反馈的“屁股超前”现象后，确认 `StandaloneCursorLab` 的 path / heading 在 SwiftUI y-down 坐标里推进，但 `SynthesizedCursorGlyphView` 实际使用的是 AppKit 默认 y-up 绘制坐标。
- **[统一翻转 angle 与 offset]**: 在 glyph 渲染层新增显式转换，把 screen-space 的 `rotation`、`cursorBodyOffset`、`fogOffset` 统一映射到 AppKit drawing space，避免 moving 期间可见姿态被垂直镜像。
- **[保持 motion model 不动]**: 这次没有继续改候选路径或 spring，只修复显示层坐标映射，让 heading-driven 选路和 visual dynamics 仍维持原来的 y-down 几何语义。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/SynthesizedCursorGlyphView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, restore visible heading during moves)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[按官方抽帧撤回轻微 lean 假设]**: 对照用户提供的官方 1-9 帧后，确认 moving 阶段箭头主朝向会持续跟随当前 move heading，而不是只保留一个很小的 turn lean。
- **[移除多余的 displayRotation 分层]**: `StandaloneCursorLab` 的 glyph 渲染重新直接使用 visual dynamics 主 `rotation`；之前额外加的 `displayRotation / visibleRotationOffset` 已移除，避免把主 heading 丢掉。
- **[保留小幅 idle wobble]**: idle 阶段仍沿用 `_animatedAngleOffsetDegrees` 对应的小摆角近似，但这层 offset 重新回到主 heading 之上，而不是替代 moving 期间的可见朝向。
- **[同步当前文档口径]**: README、架构说明和 active execution plan 统一改回“moving 阶段箭头跟随 heading，停住后再回 resting pose”的表述。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, restore slider tuning surface)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[恢复左上角 slider 面板]**: 把用户指出被删掉的 `START HANDLE`、`END HANDLE`、`ARC SIZE`、`ARC FLOW`、`SPRING` 五个滑块重新加回 `StandaloneCursorLab` 左上角，并保留 `REPLAY` / candidate metrics 作为辅助观察面板。
- **[重新接回参数语义]**: `CursorMotionParameters` 不再只是空壳默认值；现在这些 slider 会直接驱动 heading-driven path builder 的 start/end handle、arc size/flow，以及 progress spring 配置和 travel duration。
- **[补自定义滑块样式]**: 用更接近用户截图的细轨道 + 白色圆形 thumb 实现本地调参控件，避免直接退回系统默认控件风格。
- **[同步文档边界]**: `StandaloneCursorLab` README 和 active execution plan 都改成显式说明“slider 是本地调参入口，不等于已 binary-confirmed 的官方字段映射”。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, align default move speed with official endpoint-lock timing)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[移除距离驱动时长压缩]**: `StandaloneCursorLab` 的默认 move 不再用本地经验公式根据路径长度压缩 wall-clock 时长，避免中长距离移动明显快于官方。
- **[默认档对齐官方 1.429s timeline]**: 基于最新逆向确认的 `343 / 240 = 1.4291667s` endpoint-lock 时间，把默认 `response=1.4 / damping=0.9` 档位直接对齐到官方 spring timeline。
- **[保留 spring slider 但收紧语义]**: `SPRING` slider 继续只改变 progress spring 的 response / damping 与对应 settle 时间，不再叠加独立的 distance-based duration fudge factor。
- **[同步文档口径]**: README 和 active plan 现在都明确写出默认档的官方 endpoint-lock 时长，避免继续把 move 速度表述成不稳定的本地校准结果。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorMotionModel.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, simplify slider panel styling)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[移除左上角多余文案]**: 把 slider 面板里的 `REPLAY`、`RESET`、heading-driven 标题和 candidate metrics 全部移除，只保留 5 个调参 slider。
- **[收回当前色系]**: 面板文字从低对比的白色改回深色，slider accent 也从偏粉高亮切回当前 lab 的中性灰紫主色系。
- **[同步说明文档]**: README 和 active plan 不再把左上角 panel 描述成带 `REPLAY` 的观察面板，而是明确为纯 slider 调参入口。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `experiments/StandaloneCursorLab/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, preserve cursor state on resize)
**Scope:** `experiments/StandaloneCursorLab/`、`docs/`

**Key Actions:**
- **[修正 resize 回跳]**: 窗口尺寸变化时不再重新调用 `configure(...)+snap(to: start)`；现在只更新 canvas bounds，避免 cursor 因为 resize 被强制拉回起始点。
- **[移除错误的 resize clamp]**: 左上角 slider 面板和 canvas 的 resize 流程不再顺手重写 `start/end` 坐标，避免窗口变化意外改写当前会话状态。
- **[同步记录]**: active plan 补充这次 resize bugfix，明确“调窗口大小不应改变当前 cursor 位置”已经收口。

### 📁 Additional Files Modified
- `experiments/StandaloneCursorLab/Sources/StandaloneCursorLab/CursorLabRootView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
