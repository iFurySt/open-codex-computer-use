# Fix macOS Unicode type_text Ordering

### Request

排查 OCU 在飞书等输入框里用 `type_text` 输入中文时出现乱序或字符错误的问题；先定位原因，再修复并验证。

### Changes

- 将 macOS `type_text` 从逐个 UTF-16 code unit 发送键盘事件，改为按 Unicode extended grapheme cluster 聚合成小批量 `keyboardSetUnicodeString` 事件。
- 为 accessibility snapshot 记录当前 focused element；`type_text` 在 focused element 的 `AXValue` 可设置时，优先追加并写回 `AXValue`，作为 Electron 富文本输入框不可靠接收后台键盘事件时的非前台兜底。
- `AXValue` 兜底会从可编辑子文本推导已有草稿，并过滤 Feishu 输入框占位提示，避免把 placeholder 一起拼进消息内容。
- 当前 focused element 不是可编辑文本目标时，`type_text` 现在会明确报错要求先 click 文本输入区或使用 `set_value`，不再把无效果的后台键盘投递当成成功。
- 新增单元测试覆盖中文全角括号、emoji 代理对、ZWJ 序列、组合字符和 CJK 扩展字符，确保 chunking 后能无损还原且不拆分 grapheme cluster。
- 同步更新架构文档，记录 `type_text` 的 Unicode 输入边界。

### Motivation

历史会话里 `type_text` 的参数是正确的，但飞书输入框最终出现中文括号方向、顺序和文本残留问题。代码排查显示一部分问题位于 macOS 输入注入层：原实现把文本拆成单个 UTF-16 code unit 逐次发送，复杂 Unicode 文本在 Electron 富文本控件中容易被异步处理成乱序或错误字符。批量发送完整 Unicode 文本块可以减少事件重排。

真实飞书验证还发现，聚焦输入框后后台 `CGEvent.postToPid` 键盘事件仍可能不进入 Electron 富文本编辑器，而同一元素的 `set_value` 路径可以稳定写入完整 Unicode。因此 `type_text` 增加 focused settable `AXValue` 兜底，在不抢前台、不使用剪贴板的前提下复用同一条可设置值能力。后续测试还暴露了另一个假阳性：当前 focus 停在 WebArea 时 `type_text` 会返回成功但没有写入内容。现在这类状态会直接报错，要求先用 OCU click 聚焦输入框。

### Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Validation

- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- 本地 fixture 窗口手工验证：聚焦 `fixture-input` 后用 batched `CGEvent.keyboardSetUnicodeString` 投递 `（ocu发的）👩🏽‍💻é𠀀`，导出的 fixture state 精确显示同一字符串。
- 使用 dev app 对飞书做真实验证：同一进程里先点击输入框，再执行 `type_text` 输入 `（ocu发的测试）👩🏽‍💻é𠀀`，后续 snapshot 中实际草稿子文本完整包含中文括号、ZWJ emoji、组合音和 CJK 扩展字符；测试后用 `Command+A` / `BackSpace` 清空草稿。
- 真实发送链路中复测 `type_text`：未聚焦输入框时不再把 WebArea 当成可编辑目标；先用 OCU `click` 聚焦 text entry area 后，`type_text` + `press_key Return` 成功把完整中文测试消息发送到飞书会话。
