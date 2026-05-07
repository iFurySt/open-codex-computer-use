# Official Tool Alignment

## 目标

把仓库内 `open-computer-use` 暴露给 MCP host 的 9 个 tools，按当前官方 `computer-use` 的真实 `tools/list` 和 `tools/call` 返回做一轮收口：尽量对齐 description、schema、annotations、错误语义、`list_apps` 列表形态，以及 `get_app_state` / action tool 的文本输出风格。

## 范围

- 包含：
  - 用 `scripts/computer-use-cli` 实测官方 `tools/list` 与代表性 `tools/call`。
  - 收敛 9 个 tools 的 description、input schema 和 annotations。
  - 让 `list_apps` 输出更接近官方的“运行中 + 近 14 天使用过 app”视图。
  - 调整 `get_app_state` / action tool 文本渲染，减少内部实现细节，靠近官方树形输出。
  - 同步架构文档、history 和必要测试。
- 不包含：
  - 当前阶段不承诺 100% 复刻官方闭源安全策略、session approval、overlay UI 或私有 host 集成。
  - 当前阶段不把一次性本机样本抽成完整自动化 diff 平台。

## 背景

- 相关文档：
  - `docs/ARCHITECTURE.md`
  - `docs/references/codex-computer-use-cli.md`
  - `docs/references/codex-local-runtime-logs.md`
  - `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
- 相关代码路径：
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- 已知约束：
  - 官方 `computer-use` 只能稳定通过 `codex app-server` 间接调用，不能假设普通 stdio client 可直连。
  - 官方 `list_apps` 的 `uses` 数值最终确认来自系统 Spotlight metadata（`kMDItemUseCount` / `kMDItemLastUsedDate_Ranking`），而不是此前猜测的 `Knowledge/knowledgeC.db`。
  - Accessibility 树和索引分配高度依赖宿主 app 与 AX 层结构，完全一致需要做裁剪和抽象，而不是原样暴露本地 AX 全量细节。

## 风险

- 风险：只对齐 schema，不对齐结果文本，host 仍会看到明显不同的树结构和错误语义。
  - 缓解方式：同一轮内连带调整 `list_apps`、`get_app_state` 和 tool error payload。
- 风险：过度裁剪 AX 树导致现有 smoke path 或 action tool 命中能力退化。
  - 缓解方式：保留底层 element map，只收口用户可见文本；行为命中继续依赖内部全量 snapshot。
- 风险：`list_apps` 引入新的系统数据源后，在某些机器上查不到 usage 数据。
  - 缓解方式：做只读、可失败的回退；查不到时仍返回运行中 app。

## 里程碑

1. 官方 surface 与差异点实测确认。
2. schema、错误语义、`list_apps`、state rendering 收口。
3. 双链路复测、文档同步和归档。

## 验证方式

- 命令：
  - `swift test`
  - `go run . list-tools --transport app-server`
  - `go run . list-tools --transport direct --server-bin ../../.build/debug/OpenComputerUse`
  - `go run . call list_apps --transport direct --server-bin ../../.build/debug/OpenComputerUse`
- 手工检查：
  - 官方与开源 `tools/list` 的 9 个 tool surface 能一眼对齐。
  - 官方 bundled `computer-use` 的 raw app-server helper 当前只用于 `tools/list` 探测；真实 tool call 走正常 Codex agent/tool 调用链或本仓库 direct server。
  - `get_app_state` 文本不再暴露 `_NS:` 内部 identifier、frame 噪音和过量 cell 递归。
  - `appNotFound`、安全拒绝等错误形态与官方一致地回到 `content` + `isError: true`。
- 观测检查：
  - `list_apps` 输出包含 `running`、`last-used`、`uses`，且顺序接近官方。
  - 代表性 action tool 返回继续附带状态文本和截图。

## 进度记录

- [x] 里程碑 1
- [x] 里程碑 2
- [x] 里程碑 3

## 决策记录

- 2026-04-17：本轮对齐以 `computer-use-cli` 实测官方返回为准，而不是继续基于先前推测维护“近似文案”。
- 2026-04-17：`list_apps` 改为优先使用 Spotlight metadata query，按官方同源的 `kMDItemUseCount` / `kMDItemLastUsedDate_Ranking` 排序和筛选 app；运行态 app 继续由 `NSWorkspace` 合并补齐。
- 2026-04-17：对 bundle-id 直传的高风险 app 增加官方风格 safety denial，并让名称匹配路径默认不解析到这些 app，复刻官方 `appNotFound("iTerm2")` / `not allowed to use the app 'com.googlecode.iterm2'` 的边界行为。
- 2026-04-17：直接 MCP tool `content[0].text` 的当前官方基线应从 `App=<bundle-id> (pid ...)` 起头，不再把 `Computer Use state (CUA App Version: 750)` / `<app_state>` 这层旧包裹当作响应文本的一部分。
- 2026-05-07：Issue #12 暴露出 Chrome 被内置 denylist 阻止的问题。回看本计划和 reverse-engineering 样本后，只能确认官方对 iTerm2 的安全拒绝；Chrome 只出现在 `list_apps` 样本里，没有被拒绝的实测证据。随后按产品判断将内置 denylist 收缩到密码管理器，终端、Chrome / Atlas 和系统组件不再属于内置阻止目标，后续敏感 app 策略交给 session approval / policy 设计。
