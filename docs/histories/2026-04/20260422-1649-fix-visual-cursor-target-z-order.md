## [2026-04-22 16:49] | Task: Fix visual cursor target z-order

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> the virtual cursor current z index is above the target app, but under the current active app, but if I invoke the target app manually, the virtual cursor will behind the target app, fix this, make the virtual cursor always on top of target app

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor overlay ordering、测试、架构文档

**Key Actions:**
- **[Ordering refresh]**: 调整 `SoftwareCursorOverlay` 的排序逻辑，让 overlay 在可见期间持续重申自己应排在目标 window 之上，而不是只在目标窗口变化时排序一次。
- **[Regression coverage]**: 新增针对“强制重排”和“稳定窗口不重复重排”两类判断的单测，避免后续又退回成一次性排序。
- **[Docs sync]**: 更新 `docs/ARCHITECTURE.md`，把“用户手动激活目标 app 后仍保持压在目标 window 上面”的行为写回架构说明。

### Design Intent
这次不是调整 cursor 的视觉效果，而是修复 overlay 和目标窗口之间的持久层级关系。问题根因是当前实现只在 `activeTargetWindow` 变化时调用一次 `order(.above, relativeTo:)`；当用户随后手动激活目标 app，系统会重排该 app 的窗口顺序，但 overlay 没有重新声明自己的排序位置，结果就会掉到目标窗口后面。修复后，overlay 只要还可见，就会持续重申相对目标窗口的排序，从而保持“始终盖在目标 app 之上”。

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1649-fix-visual-cursor-target-z-order.md`
