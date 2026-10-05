## [2026-10-05 14:27] | Task: 修复创建卡死并减少桌面与启动窗口干扰

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6 (Codex)
* **Runtime**: Codex desktop, macOS 26.5.1 / arm64

### 📥 User Query
> 上下排列的物理屏中，创建 virtual display 后 Dock 从主屏跑到下方副屏；Calculator 有时一闪而过。手动创建会话又长时间等待，请定位修复。每次完成后本地提交。

### 🛠 Changes Overview
**Scope:** macOS app-agent / virtual display helper / session input and launch / real runners

- 栈采样确认旧 app-agent 处于 terminateLater 的嵌套事件循环，MainActor/主 dispatch executor 被启动 terminate 的回调占用，导致退出回复及新建 Task 无法执行。改为 RunLoop 调度 terminate/reply、worker 清理；Quit 时关闭 GUI 操作并停止后续 notebook 单元，失败保留会话。确认旧 runtime 无会话后仅重启自有空 GUI，未终止用户应用。
- helper 使用 namespace/bundle 稳定空闲 serial，读取 origin/mirror，跳过重复布局事务，保留主屏和物理 frame；新增只读 Dock/main/frame 观察与迁移暂停，不修改 Dock/Spaces 偏好或用户光标。
- 专属应用隐藏启动；TextEdit 文档作为初始 OpenDocuments event 交给 LaunchServices。只隐藏核对过的新实例；等待 AX 窗口时维持隐藏，隐藏状态下移动并读回全部窗口，验证后 unhide。
- virtual-session sky_click 禁用 synthetic focus records、使用 private event source 和屏内 primer，普通调用保持原行为；重复 AX scroll 每次检查会话输入门。
- 创建 sheet 显示进度；新增实际签名 app-agent 退出 smoke、20-cycle 桌面观察、16ms 目标窗口几何/激活采样及稳定 serial/输入策略测试。
- 同步架构、工作区说明、安全/稳定性、质量记录、参考资料和 active execution plan。

### 🧠 Design Intent (Why)
分别验证创建重配置、窗口启动和输入激活，不把主屏 ID 不变或最后 frame 正确误当成完全隔离。修复当前阻塞并保留严格检查；未通过的桌面/启动兼容性持续留在计划中。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/VirtualDisplayHost/Sources/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayDesktopObservation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayIdentity.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyClickSimulation.swift`
- `experiments/VirtualDisplay/Runner/Example.swift`、`DesktopLifecycle.swift`、`WindowContainmentObservation.swift`
- `scripts/run-app-agent-lifecycle-smoke.mjs`

### Verification and open acceptance

Swift 182 tests（1 opt-in skip）、Node 24 contracts、既有工具/光标 smoke 通过。Release/helper 已复用签名，严格 bundle 校验通过。新版 GUI 实机创建成功；独立 namespace 的活动会话退出 smoke 确认 runtime/helper 在约 0.6s 正常移除。

上下排列 20 次生命周期保持主屏 ID、物理 frame、起始 Dock 屏归属且无残留 helper；该轮 Dock 基线已经在下屏，不能声称上屏保持验收通过。原实现确实复现从上屏迁移且销毁后不恢复。创建/移除的 WindowServer 重配置及上屏 Dock 保持仍开放。

六单元真实 example 完成 Calculator 714、TextEdit UI、SCK 截图，成功样本显示零物理窗口样本、无目标激活、前台保持、零全局事件和正常清理。严格重复仍捕获 TextEdit 启动的一次物理窗口样本并按预期失败；Calculator 样本为零。不能声称任意应用零闪现或完整人工并行 AppKit 焦点验收。未知后续窗口/Spaces/睡眠/锁屏的更广验收仍开放。前一轮 GUI 的原生/显式 sidebar toggle 重复也尚未通过最终折叠检查。

本地提交，不推送；执行计划继续 active。
