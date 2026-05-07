# list_apps 标记前台应用

## 用户诉求

继续对齐官方 `computer-use` 工具返回，优先收敛 `list_apps` 与官方输出的可见差异。

## 主要改动

- `ListedAppDescriptor` 增加 `isFrontmost` 状态。
- `list_apps` 输出在前台 app 上渲染 `frontmost`，并放在 `running` 前面。
- 排序时优先把前台 app 放在运行中 app 列表顶部。
- 增加单测覆盖 `frontmost` 渲染顺序和排序优先级。

## 设计动机

官方 `computer-use` 的 `list_apps` 会明确标出当前前台应用，例如 `[frontmost, running, ...]`。这个标记能帮助 host 判断当前桌面上下文，也减少后续行动工具对目标窗口状态的猜测。

## 验证

- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`
- Dev app CLI 直连确认第一行包含 `frontmost`

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
