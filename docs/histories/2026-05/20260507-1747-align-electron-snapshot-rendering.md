## [2026-05-07 17:47] | Task: Align Electron snapshot rendering

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.5`
* **Runtime**: `Codex CLI, macOS`

### User Query
> Continue optimizing `open-computer-use` toward official `computer-use`, using Feishu/Lark or another Electron app as the comparison target and relying on reverse-engineering/observed official behavior where useful.

### Changes Overview
**Scope:** `OpenComputerUseKit` accessibility snapshot rendering.

**Key Actions:**
- **Electron tree budget**: Raised the AX render budget from 500 to 1200 nodes so long Electron/WebView content can still reach action-critical controls such as the message entry area.
- **Container rendering**: Rendered `AXGroup` as `container`, promoted useful group/WebArea descriptions into titles, and elided empty generic leaf containers.
- **Web content details**: Included `AXURL` for HTML content nodes and formatted `text entry area` values without the extra `Value:` prefix.
- **Traversal policy**: Limited `AXRows`-over-`AXChildren` preference to true row-backed controls instead of applying it to arbitrary Electron/WebView containers.
- **Official strategy parity**: Added best-effort `AXManualAccessibility` / `AXEnhancedUserInterface` enablement before taking a real app snapshot, matching strategy names observed in the official bundled service.
- **Sibling preservation**: Replaced global `CFHash(AXUIElement)` de-duplication with ancestor-cycle detection and per-parent `CFEqual` de-duplication, so long WebView traversal no longer hides sibling regions such as `SideEdgeView`.
- **Boolean tabs**: Rendered settable tab values as `boolean` with `off` / `on`, matching the observed official Feishu/Lark output.
- **Static text summaries**: Implemented a closer `mergeTextOnlySiblings`-style rule for short sibling runs, while leaving long menu/body content expanded. This keeps chat rows compact without flattening whole WebView regions.
- **Focused element formatting**: Rendered focused summaries from the same line body used in the tree, preserving WebArea titles and URLs. `AXWebArea` role descriptions now keep official-style `HTML 内容` capitalization.
- **Value separators**: Added the official comma separator between `Description:` and `Value:` for settable controls such as Feishu tabs.
- **App menu bar parity**: Appended the focused app's top-level menu bar after the focused window tree, matching the official `飞书 / 编辑 / 窗口 / 历史记录 / 帮助` tail while filtering the Apple menu and suppressing expanded menu internals.
- **Image formatting**: Promoted image descriptions into the title position and restricted URL rendering to WebArea nodes, so Electron native-resource image URLs are no longer exposed in the readable tree.

### Design Intent (Why)
The official `computer-use` Feishu/Lark result preserves deep WebView content, screenshots, URLs, message entry areas, and container-style naming. Reverse-engineering the latest bundled service exposed transformation names including `flattenIntoSelectableAncestor`, `flattenRedundantHierarchy`, `flattenRepetitiveStaticText`, `flattenLinksIntoMarkdownText`, and `mergeTextOnlySiblings`. The renderer now follows the same broad shape: preserve action-critical hierarchy, merge short text-only runs, and avoid spending the budget on generic wrappers or noisy accessibility actions.

### Verification
- `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 swift run OpenComputerUse call get_app_state --args '{"app":"com.electron.lark"}'`
  - Returned an image block.
  - Returned long Feishu/Lark WebView message content.
  - Returned `text entry area`.
  - Returned `SideEdgeView`, `ProfileButton`, search, and tab bar nodes after the long message body.
  - Rendered tabs as `(settable, boolean)` with `Description: 消息, Value: off`.
  - Returned the focused element as `HTML 内容 messenger-chat, URL: ...`, matching the official focused-summary shape.
  - Returned the top-level app menu bar after window buttons, matching the official tail (`飞书`, `编辑`, `窗口`, `历史记录`, `帮助`).
  - Rendered Electron image descriptions without leaking `native-resource://` URLs.
  - Reduced the sampled Lark menu/chat state to roughly 576 rendered lines / 571 indexed elements while retaining the message list, entry area, sidebar, and app menu bar. The official sample in the same window was roughly 648 indexed elements.
  - Returned zero `Scroll To Visible` entries in the sampled tree.
- Official comparison via `computer-use get_app_state` on `com.electron.lark` showed the same major regions: long message content, `text entry area`, `SideEdgeView`, boolean tabs, and screenshot.
- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`

### Known Follow-up
- Current Codex MCP session may still be connected to older installed app-agent processes until those processes are restarted.
- The latest sample is close in coverage and action-critical regions, but exact wrapper density and element numbering still differ from official output.

### Release Follow-up
- Prepared patch release `0.1.41` so npm-installed `open-computer-use` users can receive the Electron snapshot parity fixes instead of staying on the `0.1.40` app-agent behavior.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
