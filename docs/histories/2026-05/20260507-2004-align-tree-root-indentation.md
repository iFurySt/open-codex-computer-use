# 对齐 AX tree 根节点缩进

## 用户诉求

继续对比 Lark / Electron app 上开源版和官方 `computer-use` 的 `get_app_state` 返回，逐步修正不一致的输出形状。

## 主要改动

- 将真实 AX tree renderer 的根节点缩进从一层 tab 改为顶格。
- 合成文本节点沿用同一缩进规则，避免 summary children 比真实 children 多缩一层。

## 设计动机

官方 Lark 返回里根节点形态是 `0 standard window ...` 顶格，子节点才从一层 tab 开始。开源版之前输出为 `\t0 standard window ...`，整棵树比官方多缩进一层，影响对比和可读性。

## 验证

- Lark 本地回归确认前三个树行变为：根节点顶格、一级子节点一层缩进、二级子节点两层缩进。
- `swift test --filter SnapshotRenderedTextStartsDirectlyWithAppHeader`
- `./scripts/build-open-computer-use-app.sh debug`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
