# 原生 GUI 协作说明

macOS GUI 由 SwiftPM 的 OpenComputerUse target 构建，不额外维护 Xcode 工程。无参数启动显示独立 SwiftUI 工作区，AppKit 管理单例窗口和应用生命周期。工具启动保持隐藏 agent 模式；GUI 与工具共享 runtime 和会话注册表。

## 本地入口

```bash
./scripts/build-open-computer-use-app.sh debug
open "dist/Open Computer Use (Dev).app"
./scripts/run-virtual-display-tests.sh --lab
```

使用原生 NavigationSplitView、sidebar、系统 toolbar、权限引导与错误说明。最低 macOS 14，新增系统效果须有 availability fallback。预览通过共享 `VirtualDisplayPreview` / Metal 渲染最新 CVPixelBuffer，正式 GUI 与 lab 不维护独立显示器实现。预览第一版只观看，不转发用户键鼠。

UI 状态在 MainActor 更新，显示器/AX/捕获生命周期在 worker 执行；不可在主线程等待会调用 AppKit 主线程的同步操作。暂停必须先关闭输入门。主窗口关闭不结束会话，Quit 只有安全清理完成才退出。权限未完成时禁用 Start；签名 dev/release bundle 的权限分别确认。

验收包括应用搜索、明确 PID/window 选择、开始/暂停/继续/结束、原始尺寸、权限错误、窗口重开和未保存内容阻止 Quit。使用实际 AX/ScreenCaptureKit 验证，截图或事件投递本身不能证明目标状态改变。详见 [工作区设计与操作指南](design-docs/virtual-display.md)。
