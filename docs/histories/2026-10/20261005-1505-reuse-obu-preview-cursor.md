## [2026-10-05 15:05] | Task: 虚拟显示器直接复用 OBU cursor

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6
* **Runtime**: Codex desktop

### 📥 User Query
> 虚拟显示器中的鼠标替换为 OBU 现有 cursor 样式，直接复用。

### 🛠 Changes Overview
- 删除预览 CAShapeLayer 的手绘轮廓，改为 CALayer 显示 OBU 原始 cursor-chat.png，尺寸与中性 hotspot 使用 OBU content-cursor.js 的参数。
- 图片逐字节复用，保留来源说明及上游 MIT license；SwiftPM 管理资源，release/dev/多架构打包随主 bundle 分发资源 bundle。
- 关闭图层位置隐式动画；保留现有预览坐标转换、cursor 清理、隐藏系统鼠标及不改变捕获帧的边界。
- 补资源加载测试，同步架构与前端说明。

### 🧠 Design Intent (Why)
统一 Browser Use 与虚拟 Computer Use 的指针样式，移除独立且易失真的手绘图形。

### ✅ Validation
- OBU 源图片、本地资源及签名 App 内图片逐字节一致。
- Release bundle 构建及 deep/strict 签名校验通过。
- VirtualDisplayTests 共 15 项通过，包括 SwiftPM 资源加载、原始尺寸及透明通道检查。
- 当前 GUI 有用户活动会话，因此本轮保留会话；新预览资源在下次启动 App 时生效。本轮未重启 GUI 或新建虚拟显示器，未声明完成新版实机视频验收。

### 📁 Files Modified
- `Package.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayCapture.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Resources/`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/VirtualDisplayTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
