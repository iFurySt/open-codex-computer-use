## [2026-04-17 18:16] | Task: 对齐 computer-use 的 tool schema 与结果载荷

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> 基于前面抓到的官方 `computer-use` / `open-computer-use` dump，对照两边的 MCP 调用参数和返回做优化。明确要求包括：
> 1. action 后的截图不要写磁盘，而是直接通过 BASE64 返回。
> 2. tools 的描述和参数要和官方严格对齐。
> 其他差异也根据实际 dump 继续优化。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `apps/OpenComputerUse`, `apps/OpenComputerUseSmokeSuite`, `docs`

**Key Actions:**
- **[Schema 对齐]**: 把 9 个 tools 的 description 和 input schema 文案收敛到当前官方 `computer-use` 暴露给模型的 surface。
- **[结果载荷对齐]**: 新增 MCP tool result content 封装，让 `get_app_state` 和动作类 tools 返回 `text + image/png(base64)`，不再把普通 app 截图路径塞进文本里。
- **[状态文本收口]**: 去掉开源实现自己的 `Screenshot:` 路径和 `<element_index>` 附加块，让 state 文本更接近官方 `computer-use` 的 `App=/Window=/tree` 结构。
- **[错误语义调整]**: 将 `appNotFound("...")` 这类官方常见恢复型结果按普通 tool text 返回，而不是一律作为 MCP error。
- **[Smoke 稳定性]**: 修复 fixture state 文件的非原子写入竞争，并让 smoke suite 启动前主动清理旧 fixture 进程与旧状态文件，避免残留进程互相污染。

### 🧠 Design Intent (Why)
这次优化的目标不是“做一个功能相近的开源版”，而是尽量把 host 实际看到的 tool shape、tool result shape 和恢复语义都收敛到官方 `computer-use` 当前的调用习惯上。这样后续无论是抓包对比、做 eval，还是继续优化焦点策略，都能建立在更接近真实 host 行为的兼容面上，而不是被自定义 schema、磁盘截图路径或测试夹具竞态这些非本质差异干扰。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolResult.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
