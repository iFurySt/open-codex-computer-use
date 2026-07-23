## [2026-07-22 17:18] | Task: add configurable click method

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.6`
* **Runtime**: `Codex desktop`

### 📥 User Query
> 为 `click` 增加可选实现方式，默认保持当前行为，显式选择时避免 AX 候选把坐标点击重定向到其他元素。

### 🛠 Changes Overview
**Scope:** macOS OpenComputerUseKit / app-agent proxy、Windows runtime、Linux runtime、tool schema、skill 与仓库文档

**Key Actions:**
- **[公共参数]**: 新增 `click_method=auto|accessibility|app_post|global`；未传参数继续走原有 `auto` 路由，显式模式失败时不静默 fallback。
- **[macOS 路由]**: `accessibility` 只执行 AX，`app_post` 绕过 AX 并使用 `CGEvent.postToPid`，`global` 绕过 AX 并使用 `.cghidEventTap`。
- **[安全门]**: `global` 继续要求 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`，并让 CLI / MCP proxy 把受限前缀环境变量随请求传给 app agent。
- **[跨平台映射]**: Windows 将 `app_post` 映射到 HWND `PostMessage` 并拒绝 `global`；Linux 将 `global` 映射到 AT-SPI mouse synthesis 并拒绝 `app_post`。
- **[验证]**: Swift 全量测试、Windows / Linux Go 测试、skill 打包、标准 tool smoke 和 visual cursor idle smoke 全部通过。

### 🧠 Design Intent (Why)
坐标点击的自动 AX 路径可能从命中的容器扫描到不包含原坐标的可点击后代。新增显式实现选择后，调用方可以在保留默认兼容行为的同时，用 `app_post` 严格向目标应用发送原坐标鼠标事件；高风险的全局指针路径仍需调用参数与进程环境双重授权。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `apps/OpenComputerUseLinux/runtime.py`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/exec-plans/completed/20260722-configurable-click-method.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
