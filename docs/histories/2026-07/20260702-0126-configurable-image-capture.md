## [2026-07-02 01:26] | Task: configurable image capture

### Execution Context
* **Agent ID**: `Amp`
* **Base Model**: `Amp deep mode, model not exposed`
* **Runtime**: `macOS SwiftPM`

### User Query
> `get_app_state` 和动作工具返回的截图占用大量上下文，希望能按 MCP host 的预算调小图片，同时保持真实桌面操作和坐标映射安全。

### Changes Overview
**Scope:** macOS screenshot capture and app-agent proxy, README, architecture docs, release notes

**Key Actions:**
- **[Config]**: macOS 截图捕获新增 `OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT`、`OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION`、`OPEN_COMPUTER_USE_IMAGE_MAX_BYTES`、`OPEN_COMPUTER_USE_IMAGE_MIN_SCALE` 四个环境变量。
- **[Runtime]**: MCP proxy 把 host 的 `OPEN_COMPUTER_USE_*` 环境逐条转发给 app agent，并在请求期间清除 host 未设置的 image capture key、完成后恢复 agent 原环境；`WindowCapture` 每次捕获时读取当前配置，控制 ScreenCaptureKit 超时、PNG 长边上限、编码后字节预算和降采样比例下限。
- **[Scaling]**: 修复 `maxDimension / nativeSize` 小于 `minScale` 时 resize 循环不执行、从而返回原图的问题；现在显式的长边上限会优先生效，`minScale` 只限制在该长边上限基础上按字节预算继续缩小时的下限。
- **[Validation]**: 非法环境变量值会回退到默认值；返回 PNG 会遵守长边上限，按字节预算继续缩小时也会按实际返回 PNG 尺寸换算坐标。
- **[Tests]**: 补充单元测试覆盖环境变量解析、非法配置回退、`minScale` 夹取行为和缩小后 PNG 尺寸到窗口坐标的换算。
- **[Docs]**: 同步 README、中文 README、架构文档和功能发布记录。

### Design Intent (Why)
默认截图边界已经能避免一部分过大的 PNG，但不同 MCP host 对 image block 的上下文成本差异很大。把已有边界开放成环境变量可以保持默认兼容，同时让 Codex、Claude、Gemini 或其他 host 根据自己的预算调小图片。坐标类工具继续从返回 PNG 读取实际尺寸再映射回窗口坐标，因此降采样不会破坏 click / drag 的坐标语义。

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
