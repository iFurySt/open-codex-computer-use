# 将 AXLink 渲染为 Markdown 链接

## 用户诉求

继续结合官方 `computer-use` 逆向线索优化复杂 app state，尤其是 Lark / Electron 和 browser 场景中的 AX tree 输出形状。

## 主要改动

- 对带 `AXURL` 的 `AXLink` 生成 Markdown 形态的 `[label](url)` 文本。
- 将 `AXLink` role 文案固定为英文 `link`，避免受系统语言影响输出为本地化 role。
- 对已转为 Markdown 的 link 抑制重复的 description / child text。
- 没有 URL 的 link 仍按普通 link 节点保留 description。

## 设计动机

官方 `SkyComputerUseService` 1.0.770 binary 中有 `flattenLinksIntoMarkdownText` transform。Lark / Chrome 实测也显示官方更倾向把链接语义并入可读文本，而不是输出本地化 `链接 Description: ...` 结构。这个改动让链接目标 URL 更直接出现在 state 里，同时保留元素记录用于后续点击。

## 验证

- Lark 本地回归确认链接从 `链接 Description: ...` 变为 Markdown 链接文本。
- Chrome 本地回归确认带 URL 的 link 被渲染为 Markdown，缺 URL 的 link 继续保留普通 `link Description`。
- `swift test --filter AccessibilityRenderer`
- `./scripts/build-open-computer-use-app.sh debug`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
