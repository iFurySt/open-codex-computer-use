## [2026-07-23 16:55] | Task: 修复 sky_click 前台焦点丢失

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex desktop / macOS arm64`

### 📥 User Query
> 修复 `sky_click` 虽然不置顶目标窗口，但会让当前应用失去输入焦点的问题，并对照 Codex 的行为补强验证。

### 🛠 Changes Overview
**Scope:** macOS SkyLight click runtime、snapshot recovery、fixture focus probe、测试和文档。

**Key Actions:**
- **Target-only synthetic focus**: 移除对真实前台应用的 defocus / restore record，只让目标应用短暂进入 synthetic-active 状态，renderer settle 后只撤销目标状态。
- **Non-invasive refresh**: `sky_click` 的 action-result snapshot 使用 read-only recovery policy，禁止通过 `NSRunningApplication.activate` 或 `AXRaise` 恢复目标窗口。
- **Focus regression**: 扩展 fixture 状态，记录 AppKit active、key window、first responder、`resignActive` 和 `resignKey` 累计次数；隔离 Chrome 实机回归对这些状态建立断言。
- **Compatibility boundary**: 不改变 Chromium primer、PID/window event fields、SkyLight/public 双通道投递、`auto` 默认行为或显式 fail-closed 语义。

### 🧠 Design Intent (Why)
*旧实现把“without raise”误当成“保持焦点”：它没有改变 WindowServer frontmost PID 或 z-order，却主动向真实前台应用发送 `focused=false`，足以触发 AppKit resign/key/first-responder 副作用。新的 session 数据结构不再保存前台 PSN/window，从结构上禁止这类投递；后台目标如果需要兼容状态，只能获得独立的 target-only synthetic focus。*

### ✅ Verification
- `swift build` passes.
- `swift test` passes: 149 OpenComputerUseKit unit tests, 3 StandaloneCursorSupport tests, and 1 intentionally skipped opt-in live test.
- `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests` passes; isolated fully covered Chrome triggers exactly one DOM click.
- Foreground fixture remains frontmost, active and key; its text-field first responder and resign/key-loss counters stay unchanged.
- Real pointer position and Chrome/cover z-order remain unchanged.
- `./scripts/run-tool-smoke-tests.sh` passes the full 9-tool sequence and visual cursor idle smoke.
- `npm run package:skill` passes.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyLightSPI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyClickSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`
- `docs/` and `skills/open-computer-use/references/usage.md`
