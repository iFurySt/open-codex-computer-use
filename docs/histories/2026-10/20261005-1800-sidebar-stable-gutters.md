## 2026-10-05 | Task: 稳定侧栏横向间距

### Execution Context
- Agent: Codex /root，macOS 本地工作区。

### 用户诉求与定位
Sessions/Displays 在刷新/交互时整体横向偏移，而固定品牌基本不动；原实现叠加原生 sidebar List 自适应 inset、contentMargins 和 row insets，单纯指定 contentMargins 未可靠固定容器边界。不能从截图确定具体 AppKit 内部触发条件。

### 改动
仅侧栏项目内容改成 ScrollView + LazyVStack，一个固定 10 points 横向 gutter；保留资源层级缩进。资源行明确维护选中/hover 背景，选择与删除为并列原生按钮，opacity 不改变图标占位，隐藏滚动条避免额外 gutter。NavigationSplitView toggle、toolbar 和折叠动画保持现有实现。

### 验证
release 签名 App/helper 构建与 strict/deep 验证。没有创建/销毁显示器，也没有重启用户会话；刷新、hover 和窗口缩放的实机连续观察仍需更新版重开后确认。纯布局改动不新增镜像实现的单测。

### 主要文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- docs/FRONTEND.md
