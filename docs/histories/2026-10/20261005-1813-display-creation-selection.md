## 2026-10-05 18:13 | Task: 拆分显示器创建与会话选择

### Execution Context
- Agent: `/root`，Codex desktop；macOS arm64。

### 用户诉求
- Displays 的 + 创建独立虚拟显示器；两种名称 placeholder 标注 optional。
- 创建会话可选择显示器；每轮完成后本地提交并重启 App。

### 改动与设计
- Displays + 使用独立名称/scale 弹窗，创建空屏并选中，不保留输入会话；Sessions + 保持创建会话。
- 会话 Display 菜单提供自动复用/创建及在线空闲屏；选择具体 ID 后沿用配置，不占用活动屏。
- 显示器名称为 GUI 工作区标签，不改变系统固定身份或 ICC 配置。
- Swift prewarm、MCP reuse_display、JS reuseDisplay 增加显式 false 创建新空屏能力，默认幂等行为保持。
- 同步架构、GUI、设计说明和协作约定，后续更新签名制品后正常清理并重启本仓库 App，不强制丢弃未保存内容。

### 验证
- swift test：193 项，1 项跳过，0 失败；包含预热参数非法类型的副作用前校验。
- Node REPL：27 项通过；验证默认预热及强制新空屏参数转发。
- release 主 App 与 VirtualDisplayHost 构建、Developer ID 签名、deep/strict 签名校验通过。
- 旧 GUI 创建弹窗先取消，再正常 terminate，确认进程退出并启动新版 GUI；agentInfo 确认同一 bundle 路径的新进程且无活动会话/显示器。
- Computer Use AX 实机确认新版会话弹窗包含 optional 名称、Display 原生菜单及 scale；取消后回到工作区。
- 未进行新一轮显示器热插拔循环；新空屏的完整 GUI 创建/精确租用实机回归仍待后续协调，ColorSync 排查计划保持未完成。

### 主要文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift
- scripts/node-repl/open-computer-use-repl.mjs
