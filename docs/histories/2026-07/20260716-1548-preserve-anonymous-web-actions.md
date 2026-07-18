## [2026-07-16 15:48] | Task: 保留匿名 Web 图标按钮

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-5
* **Runtime**: Codex desktop

### 📥 User Query
> 修复 Chrome 页面中一列只有图标和悬浮提示的按钮无法出现在 snapshot、因而无法使用 `element_index` 点击的问题。

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` macOS Accessibility snapshot renderer

**Key Actions:**
- **[保留主点击节点]**: 匿名 `AXGroup` / `AXUnknown` 如果暴露 `AXPress`、`AXConfirm` 或 `AXOpen`，不再仅因主动作被隐藏于文本输出而直接裁掉。
- **[限制噪音]**: 只保留具备有效紧凑 frame 的匿名动作节点，继续过滤零尺寸节点和覆盖大面积页面的通用点击容器。
- **[可操作输出]**: 将这些 icon-only 控件渲染为带窗口相对 `Frame` 的 `button`，使每个控件获得可区分的 `element_index`。
- **[验证]**: 补充主点击动作识别、匿名按钮判定、尺寸边界测试，并在 Chrome 实际页面确认右侧连续图标按钮进入 snapshot。

### 🧠 Design Intent (Why)
Web 页面经常用无文本的 iconfont 或 SVG 容器实现按钮。Chrome 可能只为这类节点暴露通用 AX role、frame 和主点击动作；旧 renderer 会先隐藏 `AXPress` 等隐式主动作，再把节点当作无语义 wrapper 裁掉。修复在不恢复所有空 wrapper 的前提下保留紧凑可点击节点，让 Agent 能通过 frame 和 `element_index` 操作它们。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-07/20260716-1548-preserve-anonymous-web-actions.md`
