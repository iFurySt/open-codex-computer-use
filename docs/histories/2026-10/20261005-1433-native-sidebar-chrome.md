## [2026-10-05 14:33] | Task: 按 HeyYo 原生方案修正全高侧栏

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6 (Codex)
* **Runtime**: Codex desktop, macOS 26.5.1 / arm64

### 📥 User Query
> 侧栏应顶到窗口顶部，和 HeyYo 采用相同方案；删除重复折叠图标；Open Computer Use 品牌放在侧栏上方，不与折叠按钮组成一组。完成后本地提交。

### 🛠 Changes Overview
**Scope:** standalone SwiftUI/AppKit workspace GUI

- 核对 HeyYo 的 sidebar List + top/bottom safeAreaInset 和 AppKit window chrome，替换旧 sidebar VStack 结构。品牌图标/文字固定在顶部，New session 固定在底部；会话 List 独立滚动。
- 窗口启用 fullSizeContentView 与透明标题栏，让原生侧栏背景延伸到窗口顶部；保留可见原生页面标题，使当前会话或 Virtual sessions 位于 detail 标题栏左侧，操作按钮保持右侧。
- 删除自定义 navigation item 的折叠按钮和品牌文本，以及 sidebarToggle 移除规则；只保留系统折叠按钮，展开/折叠由原生 NavigationSplitView 管理。
- 使用 OCU 已有 app icon，未复制 HeyYo 品牌素材或业务代码。同步架构/GUI/质量文档，完成并归档之前的 example/layout execution plan；桌面隔离计划仍 active。

### 🧠 Design Intent (Why)
解决窗口结构差异，使用系统布局来管理全高侧栏和折叠行为，避免继续叠加按钮或手动重排 toolbar。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/QUALITY_SCORE.md`
- `docs/design-docs/virtual-display.md`
- `docs/exec-plans/completed/20261005-ready-example-layout.md`

### Verification

Swift debug build 和 Release bundle 构建通过，helper/主 bundle 复用既有签名，codesign --verify --deep --strict 通过。真实 GUI AX 与截图确认：展开时侧栏包含窗口控制区并顶到窗口顶部、OCU 品牌在侧栏、仅一个 Hide Sidebar；折叠后仅一个 Show Sidebar、页面标题靠左、操作按钮靠右；再次展开保持一致。侧栏 New session 正常打开创建 sheet，Cancel 正常返回。此次未创建额外虚拟显示器或操作第三方应用，未将已有 Dock/启动闪现验收问题算作通过。

本地提交，不推送。
