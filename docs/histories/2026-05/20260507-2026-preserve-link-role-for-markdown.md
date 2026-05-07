# Markdown 链接保留 link role

## 用户诉求

继续对齐官方 `computer-use` 的 state renderer，让 Lark / Electron app 的返回既可读又保留可操作元素语义。

## 主要改动

- 修正 `AXLink` 在 suppress children 后被泛化成 `container` 的问题。
- Markdown 链接行现在保留 `link [label](url)` 形态，而不是 `container [label](url)`。
- 补充单测覆盖 `AXLink` 压平后仍保留 `link` role 的边界。

## 设计动机

上一轮将带 URL 的链接压平成 Markdown 文本后，Lark 回归显示行头变成了 `container`。这提升了可读性，但弱化了元素语义。官方 renderer 逆向中同时存在 `flattenLinksIntoMarkdownText` 和 `role` / `roleDescription` 字段，因此更合理的形态是保留 link role 并压平文本。

## 验证

- Lark 本地回归确认链接行输出为 `link [label](url)`。
- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
