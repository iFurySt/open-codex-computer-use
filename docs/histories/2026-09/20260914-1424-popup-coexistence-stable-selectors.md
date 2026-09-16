# 20260914 弹层快照共存与稳定选择器

## 用户诉求（原文压缩）

> 1. Chromium + Radix 弹层会“吞掉”整棵树：点开一个 Select/Combobox 后，Web 内容的无障碍树被整体替换成只有那个列表框（例如只剩 `16 列表框 / 17 文本 请选择 / 19 文本 OpenAPI …`），表单字段全部不可见；AI 拿不到表单元素索引，只能反复读快照，浪费大量调用且无法继续操作。目标是弹层打开时快照**同时**包含弹层节点与底层 Web 内容（或至少提供选项），一次读取即可同时操作表单与选择项。
> 2. 行首的 `element_index` 只在当次快照内有效，任何点击后索引都会漂移，AI 只能 read → act → read（真实案例里同一工具被连续调用 5–8 次而被框架判为无进展）。目标是为 `set_value` 与 `click` 增加与 `element_index` 并存、可选的**稳定选择器**，由 OCU 在动作执行的瞬间重新遍历树并解析匹配元素；匹配不到或匹配到多个时返回明确错误。

## 现象与根因

- 实测形态（人工验收期间的真实快照原文，弹层展开时）：

  ```text
  15 HTML 内容 一搜万维 · Harness 管理台, URL: http://127.0.0.1:8790/#/resources
      16 列表框 (settable, string)
          17 文本 (selected) 请选择
              18 文本 请选择
          19 文本 草稿
  …
  ```

  同一页面在弹层关闭时，`资源名称 / 用途 / 交付目标 1 / 成功标准 1 / 非目标 1 / 策略引用` 等字段都在同一棵 `AXWebArea` 下。

- 根因**不是**“快照只从某个 web area / 焦点窗口开始遍历”。弹层组件（Radix `Select`）用 `aria-hidden` 把 portal 之外的内容整体隐藏，Chromium 于是不再把这批节点放进 macOS AX 树：`AXWebArea` 下确实只剩弹层。换遍历起点（`AXApplication`）或收集 `AXPopover` / `AXSheet` / 弹层 `AXWindow` 都**取不回**这些节点——它们在 AX 层不存在，浏览器 UI 与弹层本身也不提供第二个可读副本（对照证据：Omnibox 浮层是独立的 `chrome://omnibox-popup.top-chrome/` 内容，页面内弹层不是）。
- 因此本次把问题拆成两半：**可救的一半**是弹层确实拥有自己的顶层子树（原生 popover / sheet / menu / floating·dialog window），把它们追加进快照；**不可救的一半**是背景被 app 从 AX 树隐藏，快照只能如实说明，避免上层把“页面消失”误判成需要反复重读。

## 变更

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/PopupSnapshot.swift`（新增）：`PopupSubtreeDescriptor` 与纯函数 `isOpenPopupRole` / `isTransientPopupSubtree` / `transientPopupSubtreeSelection` / `appendingTransientPopupSection` / `collapsedWebAreaPopupNote`。选择策略：没有任何打开的临时子树时返回空（输出与旧版逐字节一致）；主窗口正常 + 存在临时子树时只追加临时子树；主窗口自身就是弹层（Chromium 聚焦弹层窗口）时追加其它窗口作为背景。
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`：`SnapshotBuilder.buildAccessibilitySnapshot` 在渲染焦点窗口与菜单栏之后，从 `AXApplication` 的 `AXChildren` + `AXWindows` 收集未渲染的候选（排除菜单栏、已最小化窗口，去重），命中选择策略就用同一个 `RenderContext`、延续的索引渲染并追加到 `--- popup ---` 之后（弹层内容与主树共用节点预算）；`ElementRecord` 新增 `title` / `label` / `value` / `roleText` / `placeholder` / `parentIndex`，`TreeRenderer` 传递渲染父索引并记录 `focusedIndex`，fixture 快照同步补齐这些字段。
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ElementSelector.swift`（新增）：`ElementSelector.parse` 支持 `role[name=NAME]`、`[name=NAME]`、`[role=ROLE][name=NAME]`（含逗号 / 空格分隔）、裸名字与引号值；`selectorRoleMatches` 接受 AX 角色、去 `AX` 写法、常见别名 family（button / textfield / textbox / combobox / text / link / listbox / checkbox …）以及快照里显示的本地化 role 文本；`resolveElementSelector` 先精确 name、再唯一前缀，按渲染父子链把 Chromium 的 wrapper + 文本叶子重复上报折叠成最外层节点，多处命中 / 未命中 / 语法错误一律 fail closed 并列出候选（未命中时列出角色内最接近的候选）。
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`：`click` / `set_value` 新增可选 `selector`，与 `element_index` 二选一（同时传直接报错）；选择器路径在**动作时重新渲染**一次树再解析，`element_index` 仍使用缓存快照、语义不变。`refreshedRecord` 保留选择器所需的名字字段。
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift` / `ToolDefinitions.swift`：解析并暴露 `selector` 参数，`set_value` 的 `required` 从 `[app, element_index, value]` 改为 `[app, value]`（由服务层校验“index 或 selector 至少一个”）；`click_method=accessibility` 的报错文案改为 “requires element_index or selector”。
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`：`initialize.instructions` 增加选择器与 `--- popup ---` / `--- popup note ---` 的用法说明（`get_app_state` 的官方描述文案保持不动，仍由 `testToolDescriptionsMatchOfficialComputerUseSurface` 钉住官方 parameters surface）。
- 测试：新增 `PopupSnapshotTests`（11）与 `ElementSelectorTests`（15）；按真实快照重建了“`AXWebArea` 只剩一个打开中的 `AXListBox`、焦点在弹层内”的回归形状。
- 文档：`docs/ARCHITECTURE.md`（工具服务层两条 bullet）、`skills/open-computer-use/references/usage.md`（稳定选择器 / 弹层两节）、本分支 exec plan 的 P12 里程碑、进度与决策记录。

## 设计动机

- 选择器在动作时重新解析，而不是“把快照里的 record 按名字查出来”：前者才真正与快照无关，也不会把已经失效的 AX 句柄当成目标；`element_index` 的既有契约（当次快照内有效）保持不变，避免破坏所有现存调用方。
- 不做“把上一份快照的背景行搬进当前快照”：`aria-hidden` 会让 Chromium 删除对应 platform node，旧 `AXUIElement` 已经失效，把旧 `element_index` 端给上层等于埋一个必然失败的陷阱。
- 弹层追加默认开启、不加开关：没有临时子树时选择为空，输出与旧版一致；开关只会多一个“忘了打开就没有弹层”的失败模式。
- 匹配必须 fail closed：Chromium 同屏经常出现同名节点（wrapper + 文本叶子、同名按钮），猜一个的代价是点错目标；折叠“同一目标重复上报”之后，真正同名的不相关元素仍然报错并列出候选。

## 验证

- `swift build`：Build complete。
- `swift test`：**257 tests, 1 skipped, 0 failures**（231 → 257，新增 26 个单测）。
- 覆盖点：弹层分类与选择策略（有弹层追加 / 无弹层为空 / 主窗口即弹层时追加背景窗口）、段落拼接（主树逐字节保留 + `--- popup ---` + 弹层选项同时存在）、真实 Chromium 塌缩树形状的 `--- popup note ---`（焦点在弹层内才触发、页面仍有内容或焦点在外时不触发）、选择器解析（各种写法与非法写法）、角色别名与本地化角色文本、精确 / 前缀 / 歧义 / 未命中候选列表、Chromium wrapper + 叶子折叠、`element_index` 与 `selector` 互斥及 `set_value` 参数校验。
- 未做真机复验：本轮硬约束是“不重装 / 不重启正在运行的验收产物”（不执行 app 打包、不替换二进制、不 codesign、不 `pkill`），因此没有在真实 Chrome 会话上跑一遍；验收路径留待下一次装机。

## 备注与残余风险

- 背景被 app 隐藏（Radix / aria-hidden）时，快照**无法**同时给出背景与选项：AX 层没有这些节点。本次给的是 `--- popup note ---` 与“用 selector 继续”的指引；如果上层忽略该 note 仍然反复 `get_app_state`，问题会以另一种形式复现（产品侧缓解是 MCP instructions 与 skill 文档）。
- 弹层类型覆盖：原生 `AXPopover` / `AXSheet` / `AXMenu` / `AXListBox` / `AXDialog` 与 floating / dialog / system dialog / system floating 子角色的 `AXWindow` 会被追加；未分类的形态（例如 subrole 为空或 `AXUnknown` 的弹层窗口、macOS Chrome 用 NSMenu 呈现的原生 `<select>` 下拉）保持既有行为——它们在主窗口子树里时本来就可见，不在时不会被追加。
- `collapsedWebAreaPopupNote` 的触发条件是“`AXWebArea` 唯一渲染子节点是 popup 角色 + 焦点在该弹层内”。一个页面如果本来就只由一个取得焦点的 listbox 组成，会多出这条 note（只加说明、不影响元素索引）。
- 选择器路径每次动作多渲染一次树（代价换正确性）；`selector` 目前只在 macOS 主线实现，Windows / Linux runtime 的 tool schema 未同步（与 `select_text` 的现状一致）。
