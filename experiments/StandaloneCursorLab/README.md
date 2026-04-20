# Standalone Cursor Lab

这个目录用于实现一个可独立演进、后续可单独开源的软件 cursor motion demo。

当前目标不是替换仓库主线的 `SoftwareCursorOverlay`，而是先把“轨迹几何 + 时序弹性 + 候选路径可视化”从主产品代码里拆出来，做成一个更适合试验和对比的视频 lab。

## 为什么单独放这里

- 主线 `packages/OpenComputerUseKit/.../SoftwareCursorOverlay.swift` 已经承担产品行为，不适合继续塞大量实验代码。
- 用户提供的视频和官方字符串都说明 cursor motion 有独立参数模型，适合先做一个 lab。
- 这块后续可能单独开源，先在目录边界上收口更干净。

## 当前模块边界

- `Sources/CursorMotionModel.swift`
  - heading-driven 的 `direct` / `turn` / `brake` / `orbit` candidate 族
  - 官方风格 `VelocityVerlet` spring progress
  - 独立 visual dynamics，用 visible tip/velocity/angle/fog 来驱动姿态
- `Sources/CursorLabRootView.swift`
  - 本地 demo UI、slider 调参面板、候选路径 overlay 与点击交互
- `Sources/SynthesizedCursorGlyphView.swift`
  - 参考 `scripts/render-synthesized-software-cursor.swift` 的 baseline/procedural cursor renderer

## 当前参考

- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

## 当前状态

当前已经有一个可运行的 SwiftUI demo target：

```bash
swift run StandaloneCursorLab
```

现阶段支持：

- 点击画布任意位置，先预览当前 heading-driven candidate 族，再自动选一路径并驱动 cursor 过去。
- 左上角保留 `START HANDLE`、`END HANDLE`、`ARC SIZE`、`ARC FLOW`、`SPRING` 5 个 slider，面板本身不再附带 `REPLAY` / `RESET` 按钮或额外指标文案，便于直接对照当前轨迹和画面观感。
- debug overlay 会显示控制点、arc handle 和当前选中的 candidate id / score。
- 关闭 `DEBUG` 后不会展示任何轨迹线或目标点，只保留 cursor 本体，便于单独观察最终运动观感。
- lab 主线不再直接复用 raw binary lift 的 `20` 条 candidate + score；当前改为 reverse-engineering 约束下的 heading-driven chooser，把起始朝向和最终 resting pose 一起喂给路径选择器，让默认曲线更稳定收敛到单侧 C 形或近直线。
- 主路径进度不再用 speculative `easeInOut` 或 terminal settle；现在直接复用官方风格 spring progress。
- 默认档的 wall-clock move 时长现在直接对齐 reverse-engineered 官方 endpoint-lock 时间 `343 / 240 = 1.4291667s`；不再额外按路径距离压缩时长。
- 可见 cursor 不再直接贴在 path sample 上，而是经过独立 visual dynamics 状态，再输出 `rotation + cursorBodyOffset + fogOffset + fogScale`。
- 候选路径现在显式约束“先顺车头方向掉头，再沿主轴推进，再按 resting pose 收尾”；因此大多数跨向移动会呈现单侧 C 形，需要直接切入时才会退化为近直线，而不会再出现两侧乱甩的 S 形扭曲。
- 箭头的可见角度现在重新对齐官方抽帧与逆向证据：moving 阶段持续跟随当前 move heading，接近停住后再平滑回到默认 resting pose，并继续做原地小摆角。
- cursor glyph 不再走之前那套亮白 asset；当前优先直接显示仓库里的官方 `252x252` runtime baseline 图，缺失时才退回脚本同款 procedural pointer/fog。
- settle 态不再做 XY 漂移；现在改成和参考脚本一致的中心固定小摆角，让“停住以后原地轻微转动”的观感先对齐。

后续实现应优先保持：

- 不要再把未验证的 slider 参数语义伪装成“官方实现”。
- slider 可以作为本地调参入口保留，但要明确它们是 heading-driven lab 的测试旋钮，不是已经 binary-confirmed 的一一字段映射。
- `SPRING` slider 可以改变 spring 本身的 response / damping 与对应 settle 时间，但默认档应继续保持官方 `1.4291667s` endpoint-lock 节奏。
- 路径层、progress 层和 visible pose 层继续保持分离。
- 没有真实 target window 的场景里，要明确区分 `StandaloneCursor` 的 raw reverse-engineered pool 和 `StandaloneCursorLab` 的 heading-driven 主线实现。
- demo host 可以替换，但 motion model 和 visual dynamics 应保持可单独复用。
