## [2026-04-22 17:05] | Task: fix targeted mouse coordinate space

### 🤖 Execution Context
* **Agent ID**: `unknown`
* **Base Model**: `GPT-5 Codex`
* **Runtime**: `Codex CLI`

### 📥 User Query
> if mcp click with x,y like `click({"app":"Calendar","x":1060,"y":790})`, it will trigger the "About Mac" page, why? fix this

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`, `docs/ARCHITECTURE.md`, `docs/histories/`

**Key Actions:**
- **[Retina pixel mapping fix]**: 把 `click` / `drag` 的 screenshot `x/y` 先按截图像素坐标映射回 window points，再拼到 Quartz 全局坐标，避免把 Retina 2x 截图像素直接当成 window point。
- **[Regression coverage]**: 增加针对 screenshot pixel -> window point 转换的单测，覆盖真实 Calendar 样本里的 `2048x1266` screenshot 对 `1024x633` window bounds 的 2x 场景。
- **[Behavior docs]**: 更新架构文档，明确 coordinate tools 会先按 screenshot pixel 坐标解释，再依据截图尺寸和 window bounds 做比例换算。

### 🧠 Design Intent (Why)
`get_app_state` 暴露给工具的是 screenshot 像素坐标。真实窗口 bounds 和 AX frame 则是 point 单位；在 Retina 屏上两者常常正好差一个 `2x`。本地 live 诊断里，Calendar screenshot 是 `2048x1266`，但窗口 bounds 只有 `1024x633`。之前直接把 screenshot 像素当成 window point 去点击，目标点会偏到窗口外，表现成点 Calendar 却触发了别的系统 UI。修复的关键不是再翻一层 y，而是先把 screenshot pixel 坐标按截图尺寸和 window bounds 的比例还原成 point。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1705-fix-targeted-mouse-coordinate-space.md`
