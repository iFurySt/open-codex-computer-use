## [2026-04-22 16:38] | Task: 调整 visual cursor 停驻时长

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> let's optimize the cursor status, currently it will disappeared immediately once it reach the target place, but I wanna it keep float there, only vanish if there is no new move after 30s

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime、测试、架构文档

**Key Actions:**
- **[Idle timeout 调整]**: 将 visual cursor 交互后的 idle cleanup 窗口改为 `30s`，让 cursor 到达目标点后继续停驻并等待后续动作。
- **[回归测试同步]**: 更新 timeout 常量测试，避免后续把停驻时长又改回更短或更长而没有显式确认。
- **[文档同步]**: 更新 `docs/ARCHITECTURE.md`，说明当前开源 runtime 的 idle 隐藏条件已经收敛为“30 秒无新动作才清理”。

### Design Intent
这轮目标不是改 motion 曲线，而是改 overlay 的可见性生命周期。cursor 到达目标点后应该继续以 idle 姿态停在原地，给用户明确的“刚刚操作到了这里”的反馈；只有在一段时间内没有新的 move / click / set_value 时才隐藏。这里把等待窗口收敛到 30 秒，兼顾连续操作时的可跟踪性和长时间残留的干扰。

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1638-shorten-visual-cursor-idle-timeout.md`
