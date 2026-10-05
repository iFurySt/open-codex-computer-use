# 原生 GUI 协作说明

macOS GUI 由 SwiftPM 的 OpenComputerUse target 构建，不额外维护 Xcode 工程。无参数启动显示独立 SwiftUI 工作区，AppKit 管理单例窗口和应用生命周期。工具启动保持隐藏 agent 模式；GUI 与工具共享 runtime 和会话注册表。

## 本地入口

```bash
./scripts/build-open-computer-use-app.sh debug
open "dist/Open Computer Use (Dev).app"
./scripts/run-virtual-display-tests.sh --lab
```

使用原生 NavigationSplitView 会话 sidebar、创建/添加应用 sheet、detail NavigationStack 内的系统 toolbar。与 HeyYo 一样，sidebar List 使用顶部 safeAreaInset 固定单行 OpenComputerUse 品牌，顶部 navigation toolbar 使用同一按钮组，左侧折叠、右侧 New Session compose 图标（支持 Command-N），展开和折叠都保留入口，窗口启用 fullSizeContentView/透明标题栏，让侧栏背景延伸到窗口顶部。移除系统自动 sidebar toggle，由同组的唯一折叠按钮控制 NavigationSplitView 的 columnVisibility；品牌图标和较小的 OpenComputerUse 文字放在侧栏，标题栏展示当前会话或 Virtual sessions，操作按钮在右侧。空状态仅展示图标、标题和胶囊形 Create Session 按钮（macOS 26 使用原生 glass，旧版使用 bordered）。界面提供权限引导与错误说明。桌面和 action notebook 使用 VSplitView；单元提供可编辑 JSON、播放、Run all、Stop and pause 和格式化 JSON 输出。新建 notebook 默认提供 Calculator → TextEdit 真实 case；命令/结果横向配对，UI Tree/截图横向配对。最低 macOS 14，新增系统效果须有 availability fallback。预览通过共享 `VirtualDisplayPreview` / Metal 渲染最新 CVPixelBuffer，正式 GUI 与 lab 不维护独立显示器实现。预览第一版只观看，不转发用户键鼠。

UI 状态在 MainActor 更新，显示器/AX/捕获生命周期在 worker 执行；不可在主线程等待会调用 AppKit 主线程的同步操作。暂停必须先关闭输入门。主窗口关闭不结束会话，Quit 只有安全清理完成才退出。权限未完成时禁用创建；签名 dev/release bundle 的权限分别确认。

验收包括会话创建/切换、多应用搜索、明确 PID/window 选择、暂停/继续/结束、单元编辑/运行/失败停止、原始尺寸、权限错误、窗口重开和未保存内容阻止 Quit。使用实际 AX/ScreenCaptureKit 验证，截图或事件投递本身不能证明目标状态改变。详见 [工作区设计与操作指南](design-docs/virtual-display.md)。

创建 sheet 在 worker 等待 macOS 期间显示进度；Quit 时禁用新 GUI 操作并请求 notebook 停止。退出/reply 使用可在 AppKit 嵌套循环中执行的 RunLoop 调度，避免界面能点击但新 MainActor 任务不执行的死锁。macOS 26.5.1 的签名 GUI 已确认展开/折叠均只有一个原生 toggle，展开时侧栏延伸至标题栏、品牌留在侧栏，折叠时页面标题留在左侧、操作按钮留在右侧。

创建会话的 Display scale 使用 NSViewRepresentable 封装的 NSPopUpButton，参考 HeyYo Audio/Microphone 选择器：固定控件尺寸，原生菜单覆盖内容、选中行锚定控件，切换倍率不改变 sheet 布局。
