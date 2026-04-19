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
  - 本地 demo UI、候选路径 overlay、`REPLAY` 与点击交互

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
- `REPLAY` 会从固定起点重新跑同一条选中路径，便于反复观察收尾曲线和姿态变化。
- debug overlay 会显示控制点、arc handle 和当前选中的 candidate id / score。
- lab 主线不再直接复用 raw binary lift 的 `20` 条 candidate + score；当前改为 reverse-engineering 约束下的 heading-driven chooser，把起始朝向和最终 resting pose 一起喂给路径选择器，让默认曲线更稳定收敛到单侧 C 形或近直线。
- 主路径进度不再用 speculative `easeInOut` 或 terminal settle；现在直接复用官方风格 spring progress。
- 可见 cursor 不再直接贴在 path sample 上，而是经过独立 visual dynamics 状态，再输出 `rotation + cursorBodyOffset + fogOffset + fogScale`。
- 候选路径现在显式约束“先顺车头方向掉头，再沿主轴推进，再按 resting pose 收尾”；因此大多数跨向移动会呈现单侧 C 形，需要直接切入时才会退化为近直线，而不会再出现两侧乱甩的 S 形扭曲。
- 箭头主朝向会重新明显跟随运动方向；小幅摆动单独作为额外 angle offset 叠加，而不是把整套 rotation 压成一个小角度 wiggle。
- 使用 target 自带资源里的 cursor asset 渲染指针，并用 tip-anchor 而不是整张图中心来对齐点击点。

后续实现应优先保持：

- 不要再把未验证的 slider 参数语义伪装成“官方实现”。
- 路径层、progress 层和 visible pose 层继续保持分离。
- 没有真实 target window 的场景里，要明确区分 `StandaloneCursor` 的 raw reverse-engineered pool 和 `StandaloneCursorLab` 的 heading-driven 主线实现。
- demo host 可以替换，但 motion model 和 visual dynamics 应保持可单独复用。
