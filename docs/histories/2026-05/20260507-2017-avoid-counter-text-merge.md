# 避免合并计数文本 sibling

## 用户诉求

持续对比 Lark / Electron app 的 `get_app_state` 返回，修正和官方 `computer-use` 不一致的 state rendering 细节。

## 主要改动

- 调整 `mergeTextOnlySiblings` 规则：当 sibling 文本包含 `数字/数字` 计数形态时，不再把整组文本合并成一行 summary。
- 增加单元测试覆盖 `["消息", "126/126"]` 不应合并。

## 设计动机

官方 Lark 样本会把“消息”和未读/总数计数分别渲染为独立 text 节点。开源版之前输出 `text 消息 126/126`，信息仍在但结构更粗，和官方 tree 形状不一致。这个规则只针对明确的计数 sibling，避免大范围放弃短文本合并带来的节点预算压力。

## 验证

- Lark 本地回归确认输出变为独立的 `text 消息` 和 `text 126/126`。
- `swift test --filter AccessibilityRendererOnlyMergesShortTextOnlySiblingRuns`
- `./scripts/build-open-computer-use-app.sh debug`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
