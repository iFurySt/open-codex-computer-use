## [2026-09-11 20:01] | Task: 补齐官方 `select_text` 工具

### 🤖 Execution Context
* **Agent ID**: DeepSeek Harness agent session (`dsh web`)
* **Base Model**: deepseek-flash
* **Runtime**: DSH `run_code` + bash；macOS 26.1 (arm64)，Swift 6.2 (swiftlang-6.2.0.19.9)

### 📥 User Query
> 我把 ocu 的仓库 fork 下来了（`github.com/wicgee/open-codex-computer-use`），请你在这上面改，并补齐缺少的与官方 codex computer use。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`、`apps/OpenComputerUseFixture`、`apps/OpenComputerUseSmokeSuite`、`docs/`、`skills/`

**Key Actions:**
- **[新增工具]**: 实现官方 10 个 Computer Use tool 中唯一缺失的 `select_text`，description / 参数名 / 参数说明 / `enum` 与官方 `computer-use` 逐字对齐。
- **[解析层]**: 新增纯函数 `TextSelectionResolver`，把「目标文本 + prefix/suffix 消歧」解析成 UTF-16 偏移选区，歧义时 fail closed。
- **[执行层]**: `ComputerUseService.selectText` 通过 `kAXSelectedTextRangeAttribute` 落地选区，并在写后读回真实 range。
- **[验证能力]**: fixture 支持 `select_text` 并导出当前选区；smoke suite 增加第 8 步，断言 snapshot 中出现 `Selected text: [value-ok]`。
- **[文档同步]**: `docs/ARCHITECTURE.md`、`docs/QUALITY_SCORE.md`、`skills/open-computer-use/SKILL.md`、`references/usage.md`、MCP server instructions 的工具面描述一并更新。

### 🧠 Design Intent (Why)
* 官方 surface 是 10 个 tool，本仓库此前只覆盖 9 个；`select_text` 是唯一的协议缺口，补上后 macOS 主线与官方完全对齐。
* 选区单位必须是 UTF-16 偏移（`CFRange` 语义），不能用 Swift `Character` 计数，否则 CJK / emoji 会错位——单测专门锁住这点。
* 文本命中不唯一时 fail closed 并提示用 `prefix` / `suffix` 消歧，而不是静默选第一个匹配；这与仓库既有的 `sky_click` / `drag`「失败即停、不静默 fallback」策略一致。
* 设置选区后读回真实 range：目标 app 未接受时在 result 里附 verification note，不把未生效的选区伪装成成功。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TextSelectionResolver.swift`（新增）
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/TextSelectionResolverTests.swift`（新增）
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/ARCHITECTURE.md`、`docs/QUALITY_SCORE.md`
- `skills/open-computer-use/SKILL.md`、`skills/open-computer-use/references/usage.md`

### ✅ Verification
- `swift build`：Build complete。
- `swift test`：**179 tests / 0 failures**（1 skipped：需 `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1` 的 Chrome live 测试）。新增 `TextSelectionResolverTests` 11 个用例 + 官方 surface 文案/schema 断言 + 非法 `selection` 用例。
- `make smoke`：通过，输出包含新增的 `8. select_text`。
- 回归口径：改动前该 suite 的 `testToolDefinitionCount` 锁定 9 个 tool、smoke runner 锁定 `Expected 9 tools`，均随本次行为变化同步为 10（属预期更新，非新引入失败）。

### 📌 Notes / 未覆盖
- Windows（Go + PowerShell UIA）与 Linux（Go + AT-SPI2）runtime 仍是 9 个 tool，`select_text` 未实现；已在 `docs/ARCHITECTURE.md` / `docs/QUALITY_SCORE.md` 明确标注平台差异。
- 未做版本 bump 与 release notes：本次是能力补齐，按仓库发版流程需要单独走 `docs/releases/RELEASE_GUIDE.md`。


### 2026-10-17：基于当前 main 补齐 JS 入口

用户要求同步最新 main、解决冲突、补齐 JS 调用、检查测试并推送原 PR。保留原贡献提交，合并最新主线并修正 query / select_text 的工具清单、测试及 skill 冲突。macOS 当前为 11 个 native tools，Linux / Windows 仍为 9 个。

- 新增 `app.selectText(elementIndex, text, {prefix?, suffix?, selection?})`，校验索引、文本、选项及模式；支持快照和 query 索引，原生失败通过两种 JS 会话的异常返回。
- 原 selectText 直接查旧 snapshot，无法使用 query 索引；改为现有 snapshotForAction 路径。定向索引解析前检查会话，原生读取、实际写入前及验证后继续检查会话 / 租约，取消不能继续写入或报告成功。
- 写入前检查 AX range 可设置，使用只读 recovery 刷新结果；不激活 app、不增加键盘或真实指针 fallback。
- 修复不可验证结果被当成成功：缺失或不匹配的实际 range 明确返回错误。即使关闭完整回读也验证文本未变和实际 range；JS 不再吞掉非错误的提示。测试覆盖写前 / 写后文本变化、租约撤销、缺失及拒绝选区。
- 原 NSString 搜索会按规范等价字符匹配，但按请求字符串的 UTF-16 长度计算范围。实测原实现把两单元的分解字符匹配成长度 1；改为字面匹配，拒绝不同 Unicode 拼写。重叠匹配仍完整计数，扫描不再保存所有匹配范围。
- fixture 导出实际 range，验证选区 / caret 后才返回；JS/native smoke 使用 UUID 隔离状态及通知，支持并行测试清理。同步 API、平台范围和功能说明。

验证：

- `swift test`：374 项、8 项跳过、0 失败；新增选择相关 22 项均通过，包含独立 AppKit NSTextView 的真实 AX UTF-16 选区及两种 caret 模式。
- Node REPL / CLI / 配置：42 项通过，包含 Persistent 和 Worker 两种会话的参数转发、错误传播和无快照调用。
- 原有工具 smoke（含 select_text）及 cursor idle smoke 通过。
- Worker JS → native MCP → 独立 fixture 全链通过：重复 / 不存在文本报错、前缀消歧、中文选区、两种 caret 模式、只返回 ok 的 no-read-back，以及显式读取选区。
- 首次临时 native probe 返回 Locked Use 观察连接的 Broken pipe；后续只读核对准入配置，确认开发版 signing identifier 未登记。改用仓库正常打包、签名的正式版后，真实服务链路通过，未修改系统准入配置或绕过保护。
- 补测 Worker JS → native MCP → 真实 AX query 索引 → selectText，分别覆盖独立 AppKit 文本框的可编辑与只读模式。独立读取控件导出状态，确认中文选区 UTF-16 location/length 为 3/2，前后 caret 为 6/0、8/0；文本不变、歧义 / 缺失报错、no-read-back 只返回 ok。测试窗口禁止成为 key/main window，避免键盘输入干扰。此前完整真实服务链未验证的限制已消除，未发现新增功能问题。
- 文档与 diff whitespace 检查通过。无版本 bump。

交付前再次合入 `0daece0` 的 Trusted Publishing 文档更新；该同步仅涉及文档，文档与 whitespace 检查通过。

补测交付时同步主线 `531c9d4`（上游 1.1.2 版本及发布文档更新），初始化协议相关 2 项测试通过；本任务未额外 bump 版本。
