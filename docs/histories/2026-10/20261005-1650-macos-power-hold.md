## [2026-10-05 16:50] | Task: 独立 macOS 电源保活能力

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6
* **Runtime**: Codex desktop

### 📥 User Query
> 独立实现 Part 4 电源管理，从本地 awesome-extension 切出 worktree，完成后合并。提供由调用方控制的保活原子能力，支持可选无限持续；崩溃不能永久禁用睡眠。用户批准 helper 并配合实机测试。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUsePower`、独立构建/验证脚本与文档。

- 实现 manual / timed / connection 请求、跨 CLI 协调器、IOKit 系统和显示器断言，以及默认关闭的电量/温度截止条件。
- 签名 root XPC helper 管理短租约、全机互斥、持久化恢复记录及 pmset 合盖睡眠开关；验证内核读回，异常不静默降级。
- Developer ID 固定 host/helper 角色、无 get-task-allow、XPC peer 签名约束和 Unix peer UID 验证。
- 独立真实 AppKit GUI 探针执行 AXPress / 值读回 / ScreenCaptureKit 截图，父进程死亡后清理 fixture。
- macOS 26 实测 BundleProgram 在启动解析阶段失败，采用标准 Applications 路径 ProgramArguments；SMAppService 仍负责登记与用户批准。

### 🧠 Design Intent (Why)
无限持续是调用方的功能许可，30 秒内部租约是异常恢复机制。两者分开，避免猜测外部任务何时结束，也避免协调器失联后留下持久睡眠禁用。独立 package 不耦合 Virtual Display 或 Locked Use。

### ✅ Validation
20 项自动测试、真实普通断言跨进程 smoke、签名角色/entitlement 负例、外部 SDK 编译及根仓库回归通过。已批准 helper 的真实 XPC、pmset 开关、8 秒定时恢复、协调器 SIGKILL 后恢复通过。开盖真实 AX/SCK 连续 3 次验证通过并保持前台应用。首轮物理合盖等待超时；重试验收通过：内核确认物理合盖，30 秒完成 11 次 AX 点击/计数读回/SCK 截图变化验证。结束后请求 released、SleepDisabled=0、fixture 退出，随后关闭协调器。证据限于本机当前配置；helper 本身 SIGKILL 后的 launchd 恢复、电源插拔及功耗尚未验收。

### 📁 Files Modified
- `packages/OpenComputerUsePower/`
- `scripts/build-power-hold-app.sh`
- `scripts/run-power-hold-smoke.py`
- `scripts/run-power-hold-lid-smoke.py`
- `scripts/test-power-hold-signing.py`
- `docs/power-hold.md`
- `docs/exec-plans/completed/20261005-macos-power-hold.md`
