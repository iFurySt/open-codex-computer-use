## [2026-04-22 17:20] | Task: 调整 visual cursor 等待态为轻微旋转抖动

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> when cursor is waiting for the new move, the animation is left and right horizontally shake, actually, I wanna it makes a tiny rotate shake

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime、端到端 smoke、测试、架构文档

**Key Actions:**
- **[Idle pose 收紧]**: 把 visual cursor 在等待下一次 move 时的 idle target 固定回 resting tip，不再做左右/上下位移抖动。
- **[Rotate wobble 保留]**: idle 态只保留一个很小的 angle offset，让等待态更接近“原地轻微转动”而不是水平摇摆。
- **[回归覆盖]**: 增加针对 idle pose 的单测，并为 `OpenComputerUseSmokeSuite` 新增 visual cursor idle smoke，通过 observation file 跨进程验证“tip anchored + rotation changes”。
- **[振幅上调]**: 后续根据实机反馈把 idle rotation 振幅从几乎不可感知的档位提高到仍属 tiny、但肉眼能明显察觉的档位。

### Design Intent
用户想修的不是 move path，而是 cursor 停在目标点等待下一次动作时的观感。当前 runtime 在 idle 阶段仍然给 tip 位置叠加了横向为主的细小漂移，所以更像左右抖。这里把等待态收紧成“位置固定 + 小幅旋转 wobble”，让反馈更稳定，也和仓库里对 lab/runtime 的目标描述保持一致。后续又根据实机反馈把振幅从过小的近不可见档位上调到更容易感知的范围，避免用户几乎察觉不到 rotation。

### Files Modified
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/run-tool-smoke-tests.sh`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1720-switch-visual-cursor-idle-to-rotate-shake.md`
