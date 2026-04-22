## [2026-04-22 10:50] | Task: 对齐官方 `set_value` 的 settable 边界

### 用户诉求

> 按照官方姿势处理 Sublime 这类 `set_value` 失败路径。

### 本次改动

- **收敛 `set_value` 边界**: 真实 app 的 `set_value` 现在先检查 `AXUIElementIsAttributeSettable(kAXValueAttribute)`，只有目标确认为 settable 才调用 `AXUIElementSetAttributeValue`。
- **官方风格错误**: 对 Sublime 这类可读 `AXValue` 但不可设置的元素，返回 `Cannot set a value for an element that is not settable`，不再裸露 `AXUIElementSetAttributeValue failed with -25200`。
- **避免语义漂移**: 没有在 `set_value` 内部 fallback 到 `type_text`、剪贴板或未公开的 `AXReplaceRangeWithText`，保持它是“设置 settable accessibility element”的语义。
- **补充回归测试和架构说明**: 新增 settable gate 的单元测试，并同步 `docs/ARCHITECTURE.md` 的 action tool 边界。

### 设计动机

官方 bundled app 的 tool 描述和二进制错误文案都显示 `set_value` 面向 settable accessibility element。Sublime 的正文节点虽然能读到 `AXValue`，但 `AXUIElementIsAttributeSettable(kAXValueAttribute)` 返回 success + false；此时继续强行 `AXUIElementSetAttributeValue` 只会得到底层 `kAXErrorFailure(-25200)`。先做 settable gate 能把失败解释为能力边界，而不是伪装成输入模拟失败。

### 影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
