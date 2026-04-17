# 架构总览

这个仓库当前已经从模板收敛成一个 Swift 实现的本地 `computer-use` 项目，目标是在开源前提下提供一版可运行、可验证、可继续演进的 macOS automation MCP server。

## 当前目录结构

- `apps/OpenComputerUse`
  主入口，负责 `mcp`、`doctor`、`list-apps`、`snapshot` 等 CLI 命令；不带参数启动时默认进入无 Dock 图标的 app 模式权限引导窗口。
- `apps/OpenComputerUseFixture`
  本地 GUI fixture app，用来承载低风险、可预测的点击/输入/滚动/拖拽验证路径。
- `apps/OpenComputerUseSmokeSuite`
  端到端 smoke runner，会拉起 fixture 和 MCP server，并通过 JSON-RPC 真实调用 9 个 tools。
- `packages/OpenComputerUseKit`
  核心库，包含：
  - MCP stdio transport 与 tool registry
  - app discovery
  - Accessibility / 窗口 snapshot
  - 键鼠输入模拟
  - fixture test bridge
- `scripts/`
  仓库级自动化命令，包括 smoke test、`.app` 打包入口，以及 `scripts/computer-use-cli/` 这个用于探测官方 bundled `computer-use` 的 Go helper。
- `docs/`
  逆向分析、执行计划、history 和项目约束。

## 运行分层

### 1. App Mode 层

- `OpenComputerUse` 默认 app 模式会拉起 `PermissionOnboardingApp`。
- app bundle 以 `LSUIElement` agent-style 形态运行，默认不在 Dock 暴露常驻图标，但仍可按需显示权限窗口。
- 主窗口负责渲染 `Accessibility` / `Screen & System Audio Recording` 两类权限卡片、`Allow` / `Done` 状态和 relaunch 后的状态收敛。
- 辅助 drag panel 会跳转到对应的 `System Settings` 页面，并提供 app bundle 拖拽 tile。
- 权限状态优先基于 TCC 持久授权记录判断，避免 CLI 子进程与 GUI app 对授权状态看到不一致的结果。

### 2. MCP 层

- 当前只实现 `stdio` transport。
- 请求 framing 采用一行一个 JSON-RPC message。
- 当前支持的 method：
  - `initialize`
  - `notifications/initialized`
  - `ping`
  - `tools/list`
  - `tools/call`

### 3. Tool Service 层

- `ComputerUseService` 负责把 MCP tool 请求映射到本地能力。
- `list_apps` 通过 `NSWorkspace` 枚举运行中的 app。
- `get_app_state` 优先走真实 AX / 窗口截图，但不再为了读状态而显式 `activate` 目标 app；当目标是仓库内 fixture app 时，回退到 fixture 导出的合成状态。
- MCP `tools/list` 的 description / input schema 当前按官方 `computer-use` 的 9 个 tools 文案和参数面收敛，尽量减少 host 侧提示词和 tool surface 偏差。
- 普通 app 的 element frame 当前按“窗口左上角为原点”的 window-relative 坐标输出，便于后续把 `element_index` 和截图坐标统一到同一套参考系。
- 动作型 tools 对普通 app 采用“非侵入优先，HID 兜底”策略：
  - `AXUIElementPerformAction`
  - `AXUIElementSetAttributeValue`
  - `AXUIElementCopyElementAtPosition` 做坐标命中，尽量把 coordinate click 反解成可操作 AX 元素
  - `CGEvent.postToPid` 定向发送键盘事件，避免为了 `type_text` / `press_key` 抢前台
  - 当必须退回全局鼠标路径时，先尝试对目标窗口做 `AXRaise` / main-window 聚焦，只有这些 AX 提升失败后才调用 `NSRunningApplication.activate`
  - 只有 drag 或无法命中 AX 元素的鼠标路径，才退回全局 `CGEvent` 键鼠事件并尽量缩小对用户当前焦点的影响

### 4. Fixture Bridge

- `OpenComputerUseFixture` 会把自己的窗口与元素状态写到临时 JSON 文件。
- 对 fixture 的 `get_app_state` 和少量测试专用动作，会通过 `FixtureBridge` 走显式 command 通道。
- 这个 bridge 只服务于仓库内 deterministic smoke path，不是面向真实第三方 app 的能力边界。

## 关键边界

- 开源版当前不复刻官方闭源实现里的 caller signing、私有 IPC、overlay UI 和 plugin 自安装逻辑。
- 因为官方 `SkyComputerUseClient` 带有宿主侧 launch constraints，普通 stdio MCP client 在本机上可能被系统直接杀掉；如果要探测官方 bundled `computer-use`，默认应通过 `scripts/computer-use-cli` 的 app-server 模式走已签名的 Codex 宿主。
- 当前权限引导已经具备可运行 app、深链和拖拽辅助，但还没有完全复刻官方那套嵌入式 choreography / overlay 体验。
- screenshot 当前使用系统窗口截图 API，但默认直接以 MCP `image` content block 的 base64 PNG 返回，不再把普通 app 截图落盘到仓库或临时目录。
- 会话状态现在是进程内内存态，保存每个 app 最近一次 snapshot 和 element index 映射。

## 主要验证路径

- 单元测试：`swift test`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`
- app 打包：`./scripts/build-open-computer-use-app.sh debug`
- 对比样本：`artifacts/tool-comparisons/20260417-focus-behavior/`
- 手工诊断：
  - `.build/debug/OpenComputerUse doctor`
  - `.build/debug/OpenComputerUse snapshot <app>`
