## [2026-04-21 11:13] | Task: Fix initial visual cursor approach

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> 自己运行 direct call-seq 并用截图排查，修复 `set_value` 一开始看起来倒退过去的问题。

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime

**Key Actions:**
- **Initial cursor approach**: 将首次显示时的默认出现点从固定屏幕偏移改为基于 resting forward 的反向偏移，保证第一段 travel vector 和 cursor 朝向一致。
- **Regression coverage**: 增加默认出现点单测，锁定“从 resting forward 背后侧出现”的几何约束。
- **Documentation**: 更新架构文档里的 overlay 行为说明。

### Design Intent (Why)
固定 `target + (72, -54)` 偏移和当前 runtime resting forward 不一致，会让首次 `set_value` 的移动阶段看起来像侧向或倒退切入目标。默认出现点应由 cursor 自身的 resting forward 决定，而不是硬编码屏幕方向。

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Follow-up (2026-04-21, align runtime glyph with CursorMotion)

- **Reference glyph**: `OpenComputerUseKit` 现在和 `CursorMotion` 一样优先加载 `official-software-cursor-window-252.png`，避免程序化 fallback 在主路径上暴露锯齿。
- **Packaged app resource**: `scripts/build-open-computer-use-app.sh` 会把同一张 cursor baseline PNG 复制进 `Open Computer Use.app/Contents/Resources/`，并声明 `NSHighResolutionCapable`。
- **Fallback boundary**: 程序化 pointer/fog 继续保留为资源缺失时的 fallback，但不再是 runtime 默认视觉路径。

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `docs/ARCHITECTURE.md`
