## [2026-10-05 11:44] | Task: 实现 macOS 虚拟显示器与独立 OCU 工作区

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6（宿主未提供更细型号）
* **Runtime**: Codex desktop

### 📥 User Query
> 实现 macOS 私有虚拟显示器持有进程、后台 Computer Use 会话、ScreenCaptureKit 实时预览与独立 Swift GUI，复用既有 OCU 签名/权限身份，并提供 CLI/MCP/JS 接入、真实 demo 和文档。

### 🛠 Changes Overview
**Scope:** SwiftPM、OpenComputerUseKit、macOS App/holder、Node adapter 与文档。

- 新增运行时探测的 Objective-C bridge 和每会话显示器 holder，以私有管道 EOF 管理生命周期，确认系统移除而非假定对象释放足够。
- 实现串行 registry、明确 PID/window 绑定、AX 放置读回、多窗口、暂停/继续、恢复记录、专用 Chrome profile 和礼貌清理。借用应用不退出；未保存内容阻止清理时保留会话。
- 增加显示器 SCStream、最新 CVPixelBuffer / Metal 共享预览、帧订阅与捕获诊断。输入强制禁止全局 HID/激活/剪贴板，限制所选窗口的坐标、AX 对象与键盘焦点。动作结果区分投递和观察到变化。
- macOS 新增六个 session tools，旧 app tools 可带 session_id、get_app_state 可指定 window_id。JS 增加 session API；MCP 客户端独立缓存，turn-ended 清除缓存/光标且保留会话。Windows/Linux 工具不变。
- 独立原生 GUI 提供应用选择、预览和生命周期；关窗保活、重开复用 runtime、安全 Quit。签名 helper 随正式 bundle 分发。
- 真实 AppKit runner / lab 验证 AX、捕获和清理，不用 FixtureBridge 模拟目标成功。同步架构、GUI、权限、安全、稳定性、质量与参考文档。

### 🧠 Design Intent (Why)

把私有显示器对象隔离在专用进程中，减少残留和崩溃影响；让 GUI 与工具共用生产实现，并通过真实 UI 读回验证后台能力。应用自行激活与不生效的 PID 事件明确记录，避免把虚拟显示器当作独立登录桌面或通用输入兼容层。

### 📁 Files Modified
- `Package.swift`
- `apps/VirtualDisplayHost/`、`packages/VirtualDisplayBridge/`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayCapture.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift`
- `scripts/build-open-computer-use-app.sh`、`scripts/node-repl/`
- `experiments/VirtualDisplay/`、`scripts/run-virtual-display-tests.sh`
- `docs/design-docs/virtual-display.md`、`docs/references/macos-virtual-display.md`

### Validation and limits

macOS 26.5.1 / arm64：Swift 175 tests（1 个 opt-in live test 跳过）、Node 23 contracts、现有 smoke、真实 AppKit AX 点击/Unicode set_value/滚动/sheet、1×/2× 红色捕获来源标记、20 次显示器/捕获启停、客户端/turn 缓存隔离和 helper 异常退出清理通过。正式 bundle 和 helper 使用原有 Developer ID 配置并通过严格签名检查。

正式 GUI 复用已有权限，Calculator 专用启动、虚拟屏放置、实时预览、CLI 加入同一会话、AX 修改并还原数值、暂停拒绝输入、继续、关窗保活、重开与 End 清理通过；带活动会话的安全 Quit 清理也已通过。Dev 权限缺失状态已检查。

TextEdit 默认启动没有普通可管理窗口；Chrome 专用启动自行进入前台，均作为兼容性失败并清理。AppKit app_post/sky_click 未改变计数，press_key 尚未验证具体效果，拖拽明确拒绝。前台 AppKit probe 遇到前台切换，未形成有效焦点保持证据。Space/Stage Manager、锁屏/睡眠、权限撤销、主进程崩溃恢复及其他系统/架构仍需验收。

文档骨架检查通过。仓库 hygiene 检查因基线缺少 editorconfig、部分 GitHub workflow/template 和 markdownlint 配置未通过；未引入无关模板补丁。未执行发布、公证提交、Git commit 或 push。

最后补强：恢复与输入检查使用内核进程启动时间（解决无 bundle 测试进程的 LaunchServices launchDate 缺失），不渲染系统菜单栏，拒绝所选窗口外的 AX/坐标输入；NSAlert 自行激活的回归线索保留，受控测试使用真实 nonactivating NSPanel sheet。最新 2× 核心真实 runner 通过。

最终制品复验：release/dev bundle 与 helper 均重新构建并通过严格签名检查；打包脚本沿用每次仅保留当前 variant 的行为，最终保留 release App。无参数 CLI 启动通过 LaunchServices 建立独立 GUI 进程。最新版 Calculator 再次验证共享 session 的 AX 修改/还原及活动会话 Quit；应用、helper、在线显示器和专用恢复标记均清理。Swift/Node、文档和 diff 检查重新通过。增加专用实例恢复标记、既有 JS session 入口及 native 能力探测，并隔离定向事件继承的物理修饰键。完整硬件验收仍在 active execution plan 中跟踪，未将其标记完成。
