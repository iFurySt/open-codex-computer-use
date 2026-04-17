## [2026-04-17 15:10] | Task: 收敛非抢焦点交互

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5 / Codex`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 现在已经有官方 `computer-use` 和仓库内 `open-codex-computer-use` 两套工具，要求并行对比效果，并把两边的 tool call / 结果分别保存到同一目录下的两个子目录里；当前最明显的问题是我们的实现会抢用户鼠标和焦点，希望围绕这一点做改进。

### 🛠 Changes Overview
**Scope:** `OpenCodexComputerUseKit`, `docs/`, `artifacts/`

**Key Actions:**
- **[非侵入优先输入链路]**: 去掉 `get_app_state` 的强制 app 激活，把 `type_text` / `press_key` 改成按 PID 定向投递键盘事件。
- **[点击策略修正]**: 修复 raw AX actions 被错误过滤的问题，并为 coordinate click 增加 AX hit-test 优先路径，只有命中失败才退回全局 HID。
- **[对比样本留档]**: 新增 `artifacts/tool-comparisons/20260417-focus-behavior/`，分别保存官方 `computer-use` 和仓库实现的调用样本与前后台观测。
- **[文档同步]**: 更新架构与质量文档，补执行计划与本次 history。

### 🧠 Design Intent (Why)
“抢焦点/抢鼠标”本质上是当前实现把太多路径都建立在 `activate + cghidEventTap` 上。这个改动的目标不是假装所有鼠标路径都能彻底无副作用，而是把读状态、键盘输入和大部分可反解到 AX 元素的点击先收敛到更温和的通道，把真正需要全局 HID 的场景显式缩到最小。

### 📁 Files Modified
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/InputSimulation.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/ComputerUseService.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/AccessibilitySnapshot.swift`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/completed/20260417-nonintrusive-computer-use.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/README.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/computer-use/get_app_state-activity-monitor.json`
- `artifacts/tool-comparisons/20260417-focus-behavior/open-codex-computer-use/get_app_state-activity-monitor.json`
- `artifacts/tool-comparisons/20260417-focus-behavior/open-codex-computer-use/click-activity-monitor-coordinate.json`

### 🔁 Follow-up (2026-04-17 17:02)

同一任务在后续 MITM 调试里继续推进，新增两类收敛：

- **[全局鼠标前的 AX 提升]**: `InputSimulation` 不再把“需要全局 pointer”直接等价成 `activate()`；现在会先尝试 `AXRaise`、`kAXMainAttribute` 和 `kAXFocusedAttribute`，只有这些都失败后才回退到 `NSRunningApplication.activate`。
- **[Tool Intrusion Hints]**: 把 9 个 tools 的侵入性偏好直接写进 `ToolDefinitions` 和 plugin manifest，让模型更容易优先选择 `get_app_state` / `press_key` / `type_text` / `set_value` / `perform_secondary_action`，减少不必要的坐标点击和 drag。
- **[MITM 调试方法沉淀]**: 在 `docs/references/codex-network-capture.md` 增补 prompt 锚定差异和“宿主取消 vs MCP server 故障”的排查顺序，避免后续做 A/B 或 eval 时重复踩坑。

这次 follow-up 的重点不是再加一层复杂抽象，而是把“模型侧偏好”和“运行时兜底策略”一起往同一个方向推。仅靠运行时优化，模型仍可能频繁选到高副作用 tool；仅靠文案提示，真正退化到全局 pointer 时又仍会过早抢焦点。两边同时收口，才能更稳定地逼近官方 `computer-use` 那种“键盘优先、AX 优先、全局鼠标最后”的行为。

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-network-capture.md`
