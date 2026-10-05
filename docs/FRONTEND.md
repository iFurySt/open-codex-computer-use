# 原生 GUI 协作说明

macOS GUI 由 SwiftPM 的 OpenComputerUse target 构建，不额外维护 Xcode 工程。无参数启动显示独立 SwiftUI 工作区，AppKit 管理单例窗口和应用生命周期。工具启动保持隐藏 agent 模式；GUI 与工具共享 runtime 和会话注册表。

## 本地入口

```bash
./scripts/build-open-computer-use-app.sh debug
open "dist/Open Computer Use (Dev).app"
./scripts/run-virtual-display-tests.sh --lab
```

使用原生 NavigationSplitView 会话侧栏、创建/添加应用 sheet、detail NavigationStack 内的系统 toolbar。与 HeyYo 一样，sidebar 内容使用顶部 safeAreaInset 固定单行 OpenComputerUse 品牌，New Session compose 图标声明在 sidebar toolbar（支持 Command-N），折叠按钮、位置与动画由系统原生 NavigationSplitView 管理，窗口启用 fullSizeContentView/透明标题栏，让侧栏背景延伸到窗口顶部。保留系统唯一 sidebar toggle，不移除或替换按钮、不根据 columnVisibility 重建按钮组；品牌图标和较小的 OpenComputerUse 文字放在侧栏，标题栏展示当前会话或 Virtual sessions，操作按钮在右侧。空状态仅展示图标、标题和胶囊形 Create Session 按钮（macOS 26 使用原生 glass，旧版使用 bordered）。界面提供权限引导与错误说明。桌面和 action notebook 使用 VSplitView；单元提供可编辑 JSON、播放、Run all、Stop and pause 和格式化 JSON 输出。新建 notebook 默认提供 Calculator → TextEdit 真实 case；命令/结果横向配对，UI Tree/截图横向配对。最低 macOS 14，新增系统效果须有 availability fallback。预览通过共享 `VirtualDisplayPreview` / Metal 渲染最新 CVPixelBuffer，正式 GUI 与 lab 不维护独立显示器实现。预览第一版只观看，不转发用户键鼠。

UI 状态在 MainActor 更新，显示器/AX/捕获生命周期在 worker 执行；不可在主线程等待会调用 AppKit 主线程的同步操作。暂停必须先关闭输入门。主窗口关闭不结束会话，Quit 只有安全清理完成才退出。权限未完成时禁用创建；签名 dev/release bundle 的权限分别确认。

验收包括会话创建/切换、多应用搜索、明确 PID/window 选择、暂停/继续/结束、单元编辑/运行/失败停止、原始尺寸、权限错误、窗口重开和未保存内容阻止 Quit。使用实际 AX/ScreenCaptureKit 验证，截图或事件投递本身不能证明目标状态改变。详见 [工作区设计与操作指南](design-docs/virtual-display.md)。

创建 sheet 在 worker 等待 macOS 期间显示进度；Quit 时禁用新 GUI 操作并请求 notebook 停止。退出/reply 使用可在 AppKit 嵌套循环中执行的 RunLoop 调度，避免界面能点击但新 MainActor 任务不执行的死锁。macOS 26.5.1 的签名 GUI 已确认展开/折叠均只有一个原生 toggle，展开时侧栏延伸至标题栏、品牌留在侧栏，折叠时页面标题留在左侧、操作按钮留在右侧。

创建会话的 Display scale 使用 NSViewRepresentable 封装的 NSPopUpButton，参考 HeyYo Audio/Microphone 选择器：固定控件尺寸，原生菜单覆盖内容、选中行锚定控件，切换倍率不改变 sheet 布局。

虚拟屏幕预览的 Agent cursor 直接复用 OBU 的 cursor-chat.png（23×24 points，原始 46×48 pixels），以 CALayer 显示，使用 OBU 中性姿态的 hotspot 转换。资源由 SwiftPM 管理并随签名 App 分发；不再维护预览专属手绘轮廓。系统光标仍隐藏，预览光标不写入 ScreenCaptureKit 原始帧。

侧栏内容分为 Sessions / Displays，独立可折叠；分组标题整行点击折叠，hover 显示展开方向的 chevron 与右侧 +（两处都新建会话），项目 hover 显示 trash。分组标题只控制展开状态，不改变选择，折叠不清除当前预览。Session trash 默认删除会话并保留空屏，右键可选 Delete Session and Display；Display trash 安全删除该屏与关联会话。Displays 包含活动/空闲资源，活动屏选中后查看会话；空屏展示配置与复用入口，创建精确绑定该 display ID 并锁定配置。失败展示原因并保留资源，操作期间禁用删除；独立捕获不在空闲页自动恢复。保留原生 NavigationSplitView 全高、品牌和 toolbar；空闲页复用原生 glass/bordered Create Session 按钮。

侧栏横向间距集中在 WorkspaceSidebarLayout：外侧 gutter 10 points，品牌、分组标题与项目选中框使用同一边界；组内 session/display 行内容在 8 points 内边距基础上再向右缩进 12 points，右侧删除按钮保持统一内边距，选中框不随层级缩窄。禁止分别给 Logo/分组叠加不同横向 padding。

Add application sheet 的应用选择与进程/窗口选择分开：应用列表显示 bundle ID；Launch 默认只创建验证过的新实例，保持 sheet 并转入具体 PID/window 选择。候选列表完整展示同一 App 的多个进程，不默认选择首个窗口。Move selected window 说明仅该窗口暂时移动；借用应用不会隐藏或退出。专属实例如有多个窗口，逐个加入后才整体 reveal。

侧栏项目容器使用 ScrollView + LazyVStack，固定外侧 padding，不再混用 sidebar List 自动 inset、contentMargins 和 listRowInsets。选中背景和 hover 背景由资源行绘制；选择与删除为并列原生 Button，隐藏删除图标仍保留固定占位。滚动条隐藏，避免内容溢出时产生横向 gutter。外层 NavigationSplitView、原生 toggle/toolbar/折叠动画保持不变。

Sessions/Displays 标题的上下 8 points 为按钮内部 padding，外层 HStack 使用全宽 Rectangle contentShape 接收 hover；标题/箭头/间隙/右侧 + 同属热区，+ 固定 28×38 points。分组间额外 top spacing 仅为分组间隔。新建空会话通过捕获/布局检查后直接 ready，不因创建过程的前台/Dock 变化或空会话 Space 通知要求再点开始；锁屏/睡眠、布局/捕获异常及受管实例冲突仍暂停。
