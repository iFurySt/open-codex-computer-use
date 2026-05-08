# Bound screenshot result size

## 用户诉求

用户发现 `open-computer-use` 的部分 tool call 在 Codex 历史记录里变成 `text` 下的 JSON 字符串，怀疑最近几次 commit 引入了额外包装，并提供了历史 session id 辅助定位。

## 本次改动

- **[Root cause]**: 确认 MCP server 原始 `tools/call` 响应是标准 `content: [text, image]`，嵌套只出现在 Codex 为了持久化超大 MCP result 而做的事件日志降级路径里。
- **[Screenshot bound]**: macOS `ScreenCaptureKit` 窗口截图在编码为 PNG 前按最大尺寸和目标字节数自适应缩小，减少复杂页面触发 host 侧大结果降级的概率。
- **[Regression tests]**: 增加截图压缩边界测试，覆盖大图会缩小、小图保持原尺寸。
- **[Docs]**: 更新架构文档，说明截图仍以 MCP image block 返回，但会做尺寸/字节上限控制，coordinate tools 继续按实际返回的 screenshot pixel 尺寸映射。

## 设计动机

问题不是协议层重复包了一层，而是截图 PNG 过大时，Codex 会把整个 `CallToolResult` 序列化成一个 text preview 来保护 rollout storage。直接改 MCP shape 会破坏兼容性；更稳妥的修复是控制截图结果大小，让正常 `get_app_state` / action tool 返回保持扁平的 `text + image` 结构。

## 影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
