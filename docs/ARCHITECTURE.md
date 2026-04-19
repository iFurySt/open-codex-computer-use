# 架构总览

这个仓库当前已经从模板收敛成一个 Swift 实现的本地 `computer-use` 项目，目标是在开源前提下提供一版可运行、可验证、可继续演进的 macOS automation MCP server。

## 当前目录结构

- `apps/OpenComputerUse`
  主入口，负责 `mcp`、`doctor`、`list-apps`、`snapshot`、`turn-ended` 等 CLI 命令，以及 `-h` / `--help` / `-v` / `--version` 这类全局参数；不带参数启动时会先检查权限，只有缺失时才进入无 Dock 图标的 app 模式权限引导窗口，`doctor` 也只会在检测到缺失权限时拉起这套 onboarding UI。
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
  - software cursor overlay
  - fixture test bridge
- `experiments/StandaloneCursorLab`
  独立的 Swift cursor motion lab，用于试验 `Bezier + arc + spring` 参数模型、调参 UI 和独立渲染，不直接耦合主 MCP runtime。
- `experiments/StandaloneCursor`
  新的独立 Swift cursor viewer，直接复用 `scripts/cursor-motion-re/official_cursor_motion.py` 里收敛出来的候选路径、score 与 raw spring timeline，用来观察更贴近 binary lift 的表现。
- `scripts/`
  仓库级自动化命令，包括 smoke test、`.app` 打包入口、npm 分发脚本，以及 `scripts/computer-use-cli/` 这个用于探测官方 bundled `computer-use` 的 Go helper。
- `docs/`
  逆向分析、执行计划、history 和项目约束。

## 运行分层

### 1. App Mode 层

- `OpenComputerUse` 默认 app 模式会拉起 `PermissionOnboardingApp`。
- app bundle 以 `LSUIElement` agent-style 形态运行，默认不在 Dock 暴露常驻图标，但仍可按需显示权限窗口。
- 主窗口负责渲染 `Accessibility` / `Screen & System Audio Recording` 两类权限卡片、`Allow` / `Done` 状态和 relaunch 后的状态收敛；当两项权限都已完成时会自动关闭，不再要求用户手动退出。
- 辅助 drag panel 会跳转到对应的 `System Settings` 页面；点击 `Allow` 后，panel 会从主窗口里的按钮位置做一段 spring + curved frame 的入场，再落到 `System Settings` 内容区下沿。panel 默认保持在窗口右侧内容区下方居中并固定贴近窗口底边，不再依赖实时扫描权限页内部 `+ / -` 控件行；窗口层级上会显式排在当前 `System Settings` 窗口之上，避免被权限列表内容盖住，同时尽量减少对系统设置自身滚动区域的干扰。panel 内也补了显式返回按钮，允许用户中断当前 guidance、回到 onboarding 主窗口重新选择权限步骤。
- 权限状态优先基于 TCC 持久授权记录判断，避免 CLI 子进程与 GUI app 对授权状态看到不一致的结果；同时会兼容 bundle-id 和路径型授权记录，并在源码启动场景下优先认 npm 全局安装后的稳定 `.app` 路径，仓库内 `dist/` 产物只作为开发兜底。

### 2. MCP 层

- 当前只实现 `stdio` transport。
- 当 `OPEN_COMPUTER_USE_VISUAL_CURSOR` 未被显式关闭时，`mcp` 命令会切到一个最小 AppKit runtime：主线程保留 event loop 承载 overlay UI，stdio server 仍在后台线程串行读取与响应。
- 请求 framing 采用一行一个 JSON-RPC message。
- 当前支持的 method：
  - `initialize`
  - `notifications/initialized`
  - `ping`
  - `tools/list`
  - `tools/call`

### 3. Tool Service 层

- `ComputerUseService` 负责把 MCP tool 请求映射到本地能力。
- `list_apps` 通过 Spotlight metadata query 拉取标准 application 目录里的 app bundle，并读取 `kMDItemUseCount` / `kMDItemLastUsedDate_Ranking` 这类系统元数据；再与 `NSWorkspace` 的运行态 app 合并，输出“当前运行中 + 近 14 天用过”的视图。
- `get_app_state` 优先走真实 AX / 窗口截图，但不再为了读状态而显式 `activate` 目标 app；当目标是仓库内 fixture app 时，回退到 fixture 导出的合成状态。
- MCP `tools/list` 的 description / input schema 当前按官方 `computer-use` 的 9 个 tools 文案和参数面收敛，尽量减少 host 侧提示词和 tool surface 偏差。
- 对真实 app 的 `get_app_state` / action tool 入口，当前新增了一层官方风格的高风险 bundle denylist：bundle-id 直传时直接返回 safety denial；名称匹配时默认不解析到这些 app，尽量贴近官方对终端、密码管理器、Chrome 与少量系统敏感组件的防护行为。
- 普通 app 的 element frame 当前按“窗口左上角为原点”的 window-relative 坐标输出，便于后续把 `element_index` 和截图坐标统一到同一套参考系。
- `click` 在执行真实动作前后，会额外驱动一层透明 `SoftwareCursorOverlay` window：移动阶段现在走一条 heading-driven 的官方风格 motion 内核，显式把“当前 cursor 朝向”和“最终 resting pose”一起喂给选路器，优先生成需要时先掉头、再沿车头方向推进的 C 形/单侧大弧轨迹；真正显示出来的 cursor 不再直接等于 path sample，而是经过一层独立的 visual dynamics 状态，把 visible tip、velocity、angle 和 fog/offset 持续推进，再衔接 click pulse、idle sway 和自动淡出。
- overlay 的 visual style 优先在运行时从本机官方 `Codex Computer Use.app` 的 `Package_ComputerUse.bundle` / `Package_SlimCore.bundle` 读取 `SoftwareCursor` 资产并做一次本地处理；如果本机没有这份 bundle，则回退到仓库内的矢量样式。
- overlay 的层级不再固定 `.floating`；现在会跟随 snapshot 命中的目标 window id / layer，把自己排到该目标 window 之上，而不是粗暴压到所有前台 app 最上层。
- overlay 的曲线路径不再只按固定 Bezier 模板生成；当前主线采用 reverse-engineering 约束下的 heading-driven candidate 族，候选只保留 `direct` / `turn` / `brake` / `orbit` 这些能稳定产出单侧主弧的 family，并继续保留 target-window 命中策略作为同类候选间的 tie-break。原始 binary lift 恢复出来的 `20` 条路径和 score 仍然保留在独立的 `StandaloneCursor` viewer / Python 重建脚本里，用于对照分析，不再直接作为 runtime 默认 chooser。
- overlay 的 progress 曲线也不再是固定 `easeInOut`；主线现在复用官方 `response=1.4`、`dampingFraction=0.9`、`dt=1/240` 的 spring/`VelocityVerlet` 形状，但 wall-clock duration 仍做本地校准，因为官方 transaction-level 时长映射还没有完全恢复。
- overlay 不再依赖临时 `terminal settle` 补丁来修尾；主线现在统一改成“路径层给目标点，visual dynamics 层给可见姿态”的双层模型，所以 move 末段、pulse 和 idle 共用同一套状态，不会再出现 endpoint 锁住后只剩原地翻角的收尾。
- overlay 的渲染输入也从单一 `rotation` 扩展成 `rotation + cursorBodyOffset + fogOffset + fogScale`，让速度滞后能真正体现在画面上，而不是只存在于主循环内部状态；其中 `rotation` 现在按二进制里 `SoftwareCursorStyle.angle + CursorView._animatedAngleOffsetDegrees` 的分层去近似，不再把“跟随运动方向的主朝向”和“小幅 wiggle offset”压成同一个受限小角度。
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

### 5. Cursor Lab

- `StandaloneCursor` 是一个新的独立 SwiftUI/AppKit demo target，可通过 `swift run StandaloneCursor` 本地启动。
- 这条线优先验证 Python 重建脚本已经收敛出来的核心：`20` 条候选路径、`measure + score`、`prefer in-bounds then lowest-score` 选路，以及 `response=1.4` / `dampingFraction=0.9` / `dt=1/240` 的 raw spring timeline。
- 当前它刻意不引入 speculative 的 wall-clock duration 映射，也不复用 `StandaloneCursorLab` 里更偏视觉手感试验的 pose dynamics。
- `StandaloneCursorLab` 是一个单独的 SwiftUI demo target，可通过 `swift run StandaloneCursorLab` 本地启动。
- 这条线优先验证 motion model 本身：当前主线是 heading-driven 的 turn / brake / orbit / direct candidate 族、spring progress、独立 visual dynamics 和 debug UI；显式保留“主朝向跟随速度方向、额外角度 offset 单独叠加”的姿态结构，并把当前可见朝向与最终 resting pose 一起参与选路，避免出现与官方视频不符的原地翻转或 S 形扭曲回环。
- 当前它不接真实 tool call，也不回写主 `SoftwareCursorOverlay`，目的是把实验噪音与产品行为边界隔离开。

## 关键边界

- 开源版当前不复刻官方闭源实现里的 caller signing、私有 IPC、完整 overlay choreography 和 plugin 自安装逻辑。
- 因为官方 `SkyComputerUseClient` 带有宿主侧 launch constraints，普通 stdio MCP client 在本机上可能被系统直接杀掉；如果要探测官方 bundled `computer-use`，默认应通过 `scripts/computer-use-cli` 的 app-server 模式走已签名的 Codex 宿主。
- 当前权限引导已经具备可运行 app、深链、拖拽辅助，以及一版更接近官方的 accessory panel 入场动画和返回 affordance；点击链路也已经补上独立 visual cursor、官方 asset fallback 和相对目标 window 的排序逻辑，但整体还没有完全复刻官方那套嵌入式 choreography / host 集成 / session approval 体验。
- screenshot 当前使用系统窗口截图 API，但默认直接以 MCP `image` content block 的 base64 PNG 返回，不再把普通 app 截图落盘到仓库或临时目录。
- 会话状态现在是进程内内存态，保存每个 app 最近一次 snapshot 和 element index 映射。

## 主要验证路径

- 单元测试：`swift test`
- standalone cursor 构建：`swift build --product StandaloneCursor`
- cursor lab 构建：`swift build --product StandaloneCursorLab`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`
- app 打包：`./scripts/build-open-computer-use-app.sh debug`
- npm staging：`node ./scripts/npm/build-packages.mjs`
- release tgz：`./scripts/release-package.sh`
- 对比样本：`artifacts/tool-comparisons/20260417-focus-behavior/`
- 手工诊断：
  - `.build/debug/OpenComputerUse doctor`
  - `.build/debug/OpenComputerUse snapshot <app>`
