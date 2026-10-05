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

### 后续修正：顶部按钮顺序
用户要求折叠在左、新会话在右并作为一组。将两者放入 detail navigation ToolbarItemGroup，移除系统自动折叠按钮；唯一折叠按钮直接控制 NavigationSplitView.columnVisibility，保持全高度原生侧栏。Release 构建及签名校验通过，真实 AX/截图验证展开和折叠顺序，New Session sheet 打开/取消正常。

### 后续修正：倍率菜单与原生玻璃按钮
用户要求 Display scale 参考 HeyYo Audio/Microphone 选择器，覆盖内容且布局稳定；Create Session 去除亮蓝色。新增本地 DisplayScalePopUp，以 NSPopUpButton 与 Binding<Int> 同步倍率，固定尺寸，菜单只初始化一次，busy 时禁用。参考 HeyYo 原生控件组织方式，无音频依赖。Create Session 使用 macOS 26 glass 样式，macOS 14–25 回退 bordered。

Release 构建、deep/strict 签名校验和 diff check 通过。真实 AX 与截图验证 1× → 2× → 1×、两种选中状态下的菜单覆盖与选中行锚定、sheet 布局未变，以及 glass 按钮外观。取消后恢复空状态，本轮未创建虚拟显示器。

### 后续修正：展开时按钮留在侧栏顶部
用户明确展开时折叠与新会话图标应留在左侧栏顶部，只有折叠后才在主区域组成一组。根据 columnVisibility 条件选择 sidebar toolbar 或 detail navigation toolbar，共用 sidebarControls，保持左折叠、右新会话且只出现一套入口。Release 构建、签名及 diff check 通过；真实截图与 AX 检查展开与折叠两种布局，折叠后的创建入口正常打开 sheet；随后用户在 App 内继续操作会话，本轮不再打断操作。
