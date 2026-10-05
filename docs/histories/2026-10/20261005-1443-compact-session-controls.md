## [2026-10-05 14:43] | Task: 精简品牌与会话创建入口

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6
* **Runtime**: Codex desktop

### 📥 User Query
> 品牌缩小并使用单行 OpenComputerUse；New Session 移到顶部；空状态移除说明文字，改善 Create Session 按钮，并完成后本地提交。

### 🛠 Changes Overview
**Scope:** macOS SwiftUI workspace 与当前界面文档。

- 侧栏品牌采用较小图标和单行名称，保持原生全高度侧栏。
- New Session 改为顶部 compose 图标，支持 Command-N，折叠侧栏后入口仍可用；移除底部入口。
- 空状态保留图标和标题，使用带加号的胶囊形主按钮。两个创建入口共用名称重置与 sheet 展示逻辑。
- 同步架构、前端与虚拟显示器使用文档。

### 🧠 Design Intent (Why)
减少重复说明和侧栏空间占用，使创建入口在展开、折叠及空状态中都容易找到。

### ✅ Validation
- Release bundle 构建、helper 与外层签名及 deep/strict 签名校验通过。
- 真实 AX 与截图检查展开和折叠布局，确认单行品牌、唯一折叠按钮和顶部创建入口。
- 折叠状态下分别点击顶部 New Session 与中央 Create Session，创建 sheet 均正常打开，Cancel 正常返回。
- git diff --check 通过。本轮验证未创建虚拟显示器。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift`
- `docs/FRONTEND.md`
- `docs/ARCHITECTURE.md`
- `docs/design-docs/virtual-display.md`
