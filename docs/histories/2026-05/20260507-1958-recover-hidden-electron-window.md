# 恢复隐藏的 Electron 窗口后再采集状态

## 用户诉求

继续对比开源版 `open-computer-use` 和官方 `computer-use` 在 Lark / Electron app 上的工具返回，没达到官方行为的地方继续优化。

## 主要改动

- 在 `get_app_state` 找到 AX window 但找不到 on-screen CGWindow，或暂时找不到可用 focused window 时，增加 best-effort 窗口恢复流程。
- 恢复流程会尝试 unhide、activate、`open -b <bundle-id>`、取消最小化、`AXRaise`、设置 main/focused，然后短暂等待并重试窗口匹配。
- 保留恢复失败后的官方形态错误文本：`Apple event error -10005: cgWindowNotFound`。
- 更新架构文档，说明隐藏 / 不可见 Electron 窗口会先恢复再采集。

## 验证

- 对比观察：开源版第一次请求隐藏的 Feishu 时返回 `cgWindowNotFound`，官方 `computer-use` 会拉起窗口并返回完整状态。
- 本地回归：隐藏 Feishu 后，使用新构建的 Dev app 直接调用 `get_app_state`，返回 `isError=false`，且包含截图内容块。
- `swift test --filter NoWindowErrorMessageMatchesOfficialShape`
- `./scripts/build-open-computer-use-app.sh debug`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `docs/ARCHITECTURE.md`
