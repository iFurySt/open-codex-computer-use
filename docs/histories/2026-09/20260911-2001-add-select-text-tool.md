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
