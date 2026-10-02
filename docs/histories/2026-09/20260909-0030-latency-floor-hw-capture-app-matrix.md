## [2026-09-09 00:30] | Task: 把后台输入间隔压到基准下限、HW 窗口截图、多 app 扫描

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `Claude Code CLI / macOS 27.0 arm64`

### 📥 User Query
> 所有动作要最低延迟；不要机械地按 app 打补丁，从系统角度想；尽量多测不同技术栈的 app。

### 🛠 Changes Overview
**Scope:** 输入 recipe 的时间参数、窗口截图路径、AX 窗口绑定、基准与扫描 live test、文档。

**Key Actions:**
- **InputTiming knobs**: 所有固定间隔改为环境变量可调，默认值由 `BackgroundInputBenchmarkLiveTests` 扫描决定：focus record 40→10 ms，`sky_click` recipe scale 1→0.2，type_text chunk 20→0 ms，press_key 收尾 100→0 ms，`sky_key` key-window settle 300→0 ms、release 100→0 ms。结果：`sky_click` 调用返回 323→82 ms，`sky_key` 526→30 ms，50/50 成功、每轮恰好一次点击。
- **Compatibility correction (2026-09-09)**: macOS 26.6.2 的独立复验显示 `sky_key` 零 settle/release 会偶发丢键（18/20、49/50），各恢复 10 ms 后为 50/50；普通 `auto` 输入不在该后台基准覆盖范围内，因此 type_text chunk / press-key settle 恢复既有 20 / 100 ms 默认，仍可用环境变量显式调优。
- **系统事实**: 同一事件队列内不需要间隔；`SLPSPostEventRecordTo` 与 `CGEventPostToPid` 是两条通道，跨通道保留小间隔；`sky_click` 内部 down/up 间隔不能为 0（scale 0 全部失败）。
- **HW capture**: 截图主路径改为 `SLSHWCaptureWindowList`（15–45 ms，非活动全屏 Space 的窗口也能截），ScreenCaptureKit 为 fallback（它对这类窗口返回 -3811）。
- **AX↔CGWindow 绑定**: `_AXUIElementGetWindow` 直接把 AX root window 绑到 `CGWindowID`，消除 tree 与截图/坐标指向不同窗口的一类错误。
- **AppMatrixLiveTests**: 扫描运行中的全部 GUI app，read-only snapshot + 在空白文本框输入并删除标记，输出每 app 一行。

### 🧠 Design Intent (Why)
*间隔不是靠继承的数字，而是靠测量：能证明有顺序保证的地方归零，跨通道的地方留 2 倍余量，并把每个数字留成旋钮。截图与绑定改用 WindowServer / AX 的直接原语，对所有 app 一致。*

### ✅ Verification
- `swift test`：176 tests，7 个默认跳过的实机 live test，0 failures。
- 基准（50 轮，未 pin，默认参数）：`sky_click` 50/50、`sky_key` 50/50，前台不变。
- 五个实机 live test（sky_key、sky_click、keep-alive、Desktop 2、agent display）在新默认值下全部通过。
- 多 app 扫描：有窗口的 9 个 app 全部拿到 tree 与截图（含全屏 Space 的 VS Code、Blender）；System Settings 与 Slack 输入并清理成功。
- agent display 模式扫描（`OPEN_COMPUTER_USE_APP_MATRIX_PARK=1`）：8 个非全屏窗口停靠、snapshot、输入、恢复全部成功，前台与鼠标不变，显示器结束后移除。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TimingLog.swift`、`SkyLightSPI.swift`、`SkyClickSimulation.swift`、`SkyKeyboardSimulation.swift`、`InputSimulation.swift`、`AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundInputBenchmarkLiveTests.swift`、`AppMatrixLiveTests.swift`
- `docs/references/macos-window-visibility-and-spaces.md`、`docs/RELIABILITY.md`、`docs/ARCHITECTURE.md`
