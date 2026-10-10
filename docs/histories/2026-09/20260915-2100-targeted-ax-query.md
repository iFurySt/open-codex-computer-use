## [2026-09-15 21:00] | Task: macOS 新增定向 AX 查找 tool `query`

### 🤖 Execution Context
* **Agent ID**: `claude-code`
* **Base Model**: `Claude Opus 5`
* **Runtime**: `Claude Code CLI / macOS`

### 📥 User Query
> 把 fork 里已经验证过的定向 AX 查找整理成上游 PR。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`、`skills/open-computer-use`

**Key Actions:**
- **[TargetedAX]**: 新增 `TargetedAX`（`Criteria` / `WindowContext` / `SearchResult`）与 `SnapshotBuilder.resolveTargetWindow`、`targetedSearch`、`currentGeometry`。窗口解析是只读的：不激活、不抬升、不截图。
- **[查找策略]**: 优先调用应用自带的 `AXUIElementsForSearchPredicate`；应用不支持时退回广度优先遍历——边遍历边匹配、凑够 `limit` 立即停止、按窗口自身 AX frame 做几何裁剪、对 table/outline/list 这类大容器只走 `AXVisibleChildren`，每个节点的属性用一次 `AXUIElementCopyMultipleAttributeValues` 批量读取。
- **[index 注册表]**: `query` 命中的控件登记在 `ComputerUseService` 的定向注册表里，index 从 `1_000_000` 起单调递增、永不复用，因此后续快照不会把同一个 index 重新指到别的控件；上限 5000 条，超出后按先进先出淘汰。
- **[action 复用]**: `click`、`set_value`、`scroll`、`perform_secondary_action` 改为经 `snapshotForAction` 取快照——遇到定向 index 时用该控件自己的窗口上下文构造 lite snapshot（无树、无截图），其余情况仍走原来的当前快照。
- **[精确匹配兜底]**: `exact` 未命中且遍历没有被节点上限截断时，自动以子串重试一次，命中的记录标记 `match: "contains"`。
- **[支撑改动]**: `ElementRecord` 增加带默认值的 `title` / `value`；`WindowCapture` 增加按 `exactWindowID` 的精确绑定与 `capture: false` 的纯几何读取；`SkyLightSPI` 绑定 `_AXUIElementGetWindow`。
- **[测试]**: 新增 `TargetedAXTests`（纯匹配逻辑，无需真实桌面）；tool 数量断言 9 → 10。

### 🧠 Design Intent (Why)
点一个按钮不该先付一棵完整 AX 树加一张截图的代价。已经知道控件文案时，定向查找只返回匹配项，成本和窗口复杂度基本无关。

只读是这里的硬约束：查找绝不能把前台抢过去，否则“看一眼”本身就改变了被观察的状态。

`index` 单调且不复用，是因为复用是这类注册表最危险的失效方式——一个后台快照把旧 index 指到新控件上，action 会安静地点错东西。

**对上游 tool surface 的影响**：这是在官方 `computer-use` 9 个 tool 之外新增的第 10 个 tool，与 `docs/ARCHITECTURE.md` 里“尽量减少 tool surface 偏差”的取向有冲突，已在该文档中明确记下这处偏离及其理由。Windows / Linux 运行时不受影响，仍是对齐的 9 个。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyLightSPI.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/TargetedAXTests.swift`
- `docs/ARCHITECTURE.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`

## 2026-10-10：PR #73 评审后的补充提交

用户要求按当前主线统一处理评审问题，补充 commits 到原 PR。保留作者原提交，合入 main 的截图配置、hardware/SCK 捕获、后台输入和 agent-display 行为。

- 查询改为单一有界 BFS，限制节点、队列、子节点分页、字符串和 AX 等待时间。返回结构化完整性元数据；精确匹配不再自动改成子串。长字段保留额外边界字符，避免截断制造假精确匹配。
- 严格验证 query 参数，非法 window_id 返回工具错误，避免浮点转 UInt32 崩溃。只解析已运行应用。
- 索引绑定进程身份和窗口，增加 120 秒有效期和会话结束清理。操作前验证控件归属、查询条件和最新位置，拒绝失效目标与旧坐标。
- JS 增加 `app.query()` 与 `getApp(..., { initialState: false })`，默认绑定行为不变。补齐中英文查询文档、README 入口、skill 使用说明及架构和发布记录。
- 新增 registry、预算、循环、错误、超时、参数校验和持久 JS 查询后操作回归。Swift 207 项测试通过（7 项跳过）；Node 测试及文档检查见完成计划。没有安装或重启 app，也未执行真实桌面交互；实际 AX 延迟仍需在真实应用中验证。

主要新增文件为 `TargetedQuery.swift`、`TargetedQuerySafetyTests.swift`、`docs/targeted-query.md` 和 `docs/targeted-query.zh-CN.md`。原记录中的 native predicate 优先路径和 exact 自动兜底描述为初始实现，已由本节方案替代。
