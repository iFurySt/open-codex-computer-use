## [2026-10-05 16:13] | Task: 默认复用虚拟显示器并开放生命周期控制

### 🤖 Execution Context
- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop，macOS 26.5.1 arm64

### 📥 User Query
> 优先采用显示器复用；先搜索开源/官方文档确认有没有更好的 Dock 保持方案，否则实施复用，允许调用方控制预热和复用。完成后本地提交。

### 🛠 Changes Overview
- registry 按 width/height/scale 租用自有空屏；默认结束恢复借用窗口、处理专属应用、清理恢复标记/捕获/光标后保留 display/helper。新租用拥有新 session/capture 身份；失效 helper 不复用。
- Swift、macOS MCP/CLI/JS 增加 prewarm/release，create/destroy 增加显式 reuse/retain 参数；状态区分 sessions/idle_displays 和 display_reused。GUI 使用默认复用；Quit 串行完整清理，失败不强制退出用户应用。
- 自有空屏从物理布局/恢复目标排除；切换构建时空屏也阻止 runtime 自动替换。旧 hotplug runner 显式使用严格移除，保持回归含义。
- 新增真实签名复用 smoke 和独立 App 打包输出目录；同步架构、使用、安全、稳定性、质量及执行计划。

### 🧠 Design Intent
DockKeeper 上游实测没有提供符合无鼠标干扰边界的可靠底部 Dock host setter；Apple 回调是通知 API。复用减少重复 WindowServer 热插拔，不改变 Dock/Spaces 偏好，不重启 Dock、不移动系统鼠标。首次接入、配置不匹配/强制新建、最终 release/Quit 仍可能重置 Dock；不能宣称完全解决所有 Dock 转移。

### 验证与限制
- Swift 184 tests（1 opt-in skip）、Node 25 contracts、现有工具与 cursor idle smoke 通过。
- 真实签名 production runtime 1×/2× 各 20 次复用循环通过：同 display/helper、新 session、真实 SCK 帧，预热后主屏/物理布局/Dock 归属保持。配置隔离、强制新建、活动屏释放拒绝、旧 ID 失效、helper 异常退出/替换、release 与 Quit 通过。
- release bundle/helper 签名验证通过。打包遇到一次签名拒绝后改用独立目录验证并恢复 dist；没有终止用户当前 GUI，旧 GUI 正常重启后生效。
- 一次复测观察到用户桌面 Chrome/ChatGPT 前台变化；runner 记录变化并断言测试 OCU 不被激活，不把这些观测当并行 first-responder 验收。未测首次上屏 Dock 保持、完整并行输入、可辨识图案串源以及其他系统/架构；已有 TextEdit 启动闪现仍开放。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `scripts/node-repl/open-computer-use-repl.mjs`
- `scripts/run-virtual-display-reuse-smoke.mjs`
- `scripts/build-open-computer-use-app.sh`
- `docs/exec-plans/completed/20261005-display-reuse.md`
