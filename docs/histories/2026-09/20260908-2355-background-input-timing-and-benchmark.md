## [2026-09-08 23:55] | Task: 后台输入耗时观测、轮询替代固定等待、基准测试

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Fable 5.1`
* **Runtime**: `Claude Code CLI / macOS 27.0 arm64`

### 📥 User Query
> 后台点击 / 键盘到底多可靠？把所有环节都加上观测，把耗时压到毫秒级。

### 🛠 Changes Overview
**Scope:** SkyLight SPI 观测符号、`AgentDisplay` 轮询、`sky_key` / `sky_click` / snapshot 耗时日志、基准 live test、文档。

**Key Actions:**
- **TimingLog**: `OPEN_COMPUTER_USE_DEBUG_TIMING=1` 时向 stderr 输出各阶段毫秒耗时；`waitUntil` 轮询工具。
- **观测 SPI**: `SkyLightSPI` 新增只读的 `SLSCopySpacesForWindows`、`SLSCopyManagedDisplaySpaces`、`_AXUIElementGetWindow`，缺失时返回 nil。
- **AgentDisplay**: 显示器就绪改为轮询 bounds + 新 Space 出现；停靠改为轮询窗口 frame 进入显示器且 Space 归属更新；恢复改为轮询 frame 回到原位；SPI 缺失时退回固定等待。
- **sky_key**: 记录 activate / key_window / deliver / total；尝试用 AX focused window 与 focused element 观测 Chrome 变 key 均提前报告，实测导致输入丢失，因此保留 300 ms 固定 settle。
- **Benchmark**: `BackgroundInputBenchmarkLiveTests` 对被遮挡 Chrome 跑 N 轮 `sky_click` + `sky_key`，输出成功数与 p50 / p95 / max。

### 🧠 Design Intent (Why)
*能观测的等待用轮询，观测不到的保留实测出来的固定值并记录下来，不猜。*

### ✅ Verification
- `swift test`：175 tests，6 个默认跳过的实机 live test，0 failures。
- 基准：25/25 `sky_click`、25/25 `sky_key` 成功，前台不变；`sky_click` 观察到 p50 389 ms / p95 398 ms，`sky_key` 观察到 p50 270 ms / p95 279 ms。
- `AgentDisplayLiveTests` 通过：创建 334 ms、就绪 407 ms、停靠 230 ms、恢复 260 ms。
- 一次性实验：目标处于 synthetic key 状态时 HID 键盘事件仍送到真实前台 app。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TimingLog.swift`、`SkyLightSPI.swift`、`AgentDisplay.swift`、`SkyKeyboardSimulation.swift`、`SkyClickSimulation.swift`、`AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundInputBenchmarkLiveTests.swift`
- `docs/RELIABILITY.md`、`docs/references/macos-window-visibility-and-spaces.md`
