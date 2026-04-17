# Permission Onboarding App

## 目标

为 `OpenCodexComputerUse` 增加一套真正可用的 macOS 权限引导体验：把当前纯 CLI 入口扩成可运行的 app 模式，提供权限状态窗口、System Settings 深链和可拖拽的 app 代理视图，让用户更轻松地把 `OpenCodexComputerUse` 加入 `Accessibility` 与 `Screen & System Audio Recording`。

## 范围

- 包含：
  - 为 `OpenCodexComputerUse` 增加 app 模式入口。
  - 实现权限状态窗口、轮询更新和按钮状态。
  - 实现 `Accessibility`、`Screen & System Audio Recording` 的 System Settings 深链。
  - 实现拖拽 app bundle 的辅助浮窗 / draggable app tile。
  - 增加 `.app` 打包脚本与本地验证路径。
  - 同步架构、README、质量评分、history。
- 不包含：
  - 当前阶段不复刻官方的所有转场动画、模糊 overlay 和多窗口 choreography。
  - 当前阶段不接入 notarization、code signing 或发布渠道分发。

## 背景

- 相关文档：
  - `docs/references/codex-computer-use-reverse-engineering/permission-onboarding.md`
  - `docs/ARCHITECTURE.md`
  - `docs/SECURITY.md`
- 相关代码路径：
  - `apps/OpenCodexComputerUse/`
  - `packages/OpenCodexComputerUseKit/Permissions.swift`
  - `scripts/`
- 已知约束：
  - 只有真正的 `.app` bundle 才能让用户以“拖进列表”的方式授予权限。
  - 这轮仍然保留 CLI / MCP 模式，不能把现有 `mcp` 入口打断。
  - `Screen Recording` 的授权状态在某些场景下需要重启 app 后才能稳定生效。

## 风险

- 风险：只做窗口 UI，不做 `.app` 打包，最终无法真的拖进系统设置列表。
  - 缓解方式：同一轮内补齐最小 `.app` 打包脚本，并以 bundle 模式验证。
- 风险：System Settings URL 写错或系统版本差异导致跳错页。
  - 缓解方式：在本机直接验证跳到 `Accessibility` 和 `Screen & System Audio Recording` 两页。
- 风险：拖拽 pasteboard 内容不对，用户看得到 tile 但拖不进去。
  - 缓解方式：drag source 直接使用 app bundle `fileURL`，而不是只做视觉复制。

## 里程碑

1. 入口和包装方案收敛。
2. 权限窗口与拖拽辅助浮窗实现。
3. `.app` 打包、本地验证、文档同步。

## 验证方式

- 命令：
  - `swift build`
  - `swift test`
  - `scripts/build-open-codex-app.sh debug`
  - `open dist/OpenCodexComputerUse.app`
- 手工检查：
  - app 模式可正常显示权限窗口。
  - `Allow` 按钮分别跳到 `Accessibility`、`Screen & System Audio Recording`。
  - 辅助浮窗可展示并可开始拖拽 app tile。
  - 主窗口在权限已授予后会收敛到 `Done`。
- 观测检查：
  - `doctor` 和 app 窗口的权限状态一致。
  - 授权后窗口状态能自动收敛到 `Done` 或明确提示需要 relaunch。

## 进度记录

- [x] 里程碑 1
- [x] 里程碑 2
- [x] 里程碑 3

## 决策记录

- 2026-04-17：权限 onboarding 直接做进 `OpenCodexComputerUse` 主 target，而不是另起一个完全独立的 helper app。这样 `mcp` CLI 和 app bundle 可复用同一个可执行文件与 bundle 身份。
- 2026-04-17：权限状态判定加入对 TCC 持久授权记录的读取，避免 dev 环境里 CLI 子进程与 GUI app 对同一 bundle 权限状态看到不一致的结果。
- 2026-04-17：drag panel 当前收敛到“只在 `System Settings` 前台时显示，并锚到 `Add` / `Remove` 控制区”的近似方案；更接近官方嵌入式 choreography 的视觉行为后续再补。
- 2026-04-17：app 模式改成 `LSUIElement` + `.accessory` agent-style 运行，保证权限窗口可见，但执行过程中不再额外在 Dock 暴露前台 app 图标。

## 当前结论

- app 模式、System Settings 深链、drag tile、`.app` 打包和主窗口 `Done` 状态已经可用。
- `swift test`、`./scripts/run-tool-smoke-tests.sh`、`doctor` 和真实 `System Settings snapshot` 都已通过。
- 官方那种“像嵌入在 `System Settings` 里的 accessory UI” 仍然是后续 UI 收敛项，不作为这轮功能验证阻塞。
