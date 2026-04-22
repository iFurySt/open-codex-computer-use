# 架构总览

这个仓库当前已经从模板收敛成一个本地 `computer-use` 项目。主线仍是 Swift 实现的 macOS automation MCP server，同时新增了实验性的 Windows runtime，用独立 Go `.exe` 暴露同一组 9 个 Computer Use tools。

## 当前目录结构

- `apps/OpenComputerUse`
  主入口，负责 `mcp`、`doctor`、`list-apps`、`snapshot`、`call`、`turn-ended` 等 CLI 命令，以及 `-h` / `--help` / `-v` / `--version` 这类全局参数；不带参数启动时会先检查权限，只有缺失时才进入无 Dock 图标的 app 模式权限引导窗口，`doctor` 也只会在检测到缺失权限时拉起这套 onboarding UI。
- `apps/OpenComputerUseFixture`
  本地 GUI fixture app，用来承载低风险、可预测的点击/输入/滚动/拖拽验证路径。
- `apps/OpenComputerUseSmokeSuite`
  端到端 smoke runner，会拉起 fixture 和 MCP server，并通过 JSON-RPC 真实调用 9 个 tools；同时也支持单独的 visual cursor idle smoke，用跨进程 observation file 断言等待下一次 move 时是 anchored tip + tiny rotate wobble，而不是横向漂移。
- `apps/OpenComputerUseWindows`
  实验性 Windows runtime。它不依赖 Swift 或 `.app` bundle，Go CLI/MCP 入口会嵌入 PowerShell UI Automation bridge，构建产物是 `open-computer-use.exe`。
- `packages/OpenComputerUseKit`
  核心库，包含：
  - MCP stdio transport 与 tool registry
  - app discovery
  - Accessibility / 窗口 snapshot
  - 键鼠输入模拟
  - software cursor overlay
  - fixture test bridge
- `experiments/CursorMotion`
  独立的 Swift cursor motion lab，用于试验 `Bezier + arc + spring` 参数模型、调参 UI 和独立渲染，不直接耦合主 MCP runtime。
- `experiments/StandaloneCursor`
  新的独立 Swift cursor viewer，直接复用 `scripts/cursor-motion-re/official_cursor_motion.py` 里收敛出来的候选路径、score 与 raw spring timeline，用来观察更贴近 binary lift 的表现。
- `scripts/`
  仓库级自动化命令，包括 smoke test、`.app` 打包入口、Windows `.exe` 构建入口、npm 分发脚本，以及 `scripts/computer-use-cli/` 这个用于探测官方 bundled `computer-use` 的 Go helper。
- `docs/`
  逆向分析、执行计划、history 和项目约束。

## 运行分层

### 1. App Mode 层

- `OpenComputerUse` 默认 app 模式会拉起 `PermissionOnboardingApp`。
- app bundle 以 `LSUIElement` agent-style 形态运行，默认不在 Dock 暴露常驻图标，但仍可按需显示权限窗口。
- 主窗口负责渲染 `Accessibility` / `Screen & System Audio Recording` 两类权限卡片、`Allow` / `Done` 状态和 relaunch 后的状态收敛；当两项权限都已完成时会自动关闭，不再要求用户手动退出。
- 辅助 drag panel 会跳转到对应的 `System Settings` 页面；点击 `Allow` 后，panel 会从主窗口里的按钮位置做一段 spring + curved frame 的入场，再落到 `System Settings` 内容区下沿。panel 默认保持在窗口右侧内容区下方居中并固定贴近窗口底边，不再依赖实时扫描权限页内部 `+ / -` 控件行；窗口层级上会显式排在当前 `System Settings` 窗口之上，避免被权限列表内容盖住，同时尽量减少对系统设置自身滚动区域的干扰。panel 内也补了显式返回按钮，允许用户中断当前 guidance、回到 onboarding 主窗口重新选择权限步骤。
- 权限状态优先基于 TCC 持久授权记录判断，避免 CLI 子进程与 GUI app 对授权状态看到不一致的结果；正式 release 仍以 CI 打出来的 `Open Computer Use.app` 为准，而本地 debug/dev 打包现在显式命名为 `Open Computer Use (Dev).app`，并在 dev bundle 运行时优先认当前 dev 副本，避免系统设置里出现两个完全同名的条目。

### 2. MCP 层

- 当前只实现 `stdio` transport。
- 当 `OPEN_COMPUTER_USE_VISUAL_CURSOR` 未被显式关闭时，`mcp` 命令会切到一个最小 AppKit runtime：主线程保留 event loop 承载 overlay UI，stdio server 仍在后台线程串行读取与响应。
- 请求 framing 采用一行一个 JSON-RPC message。
- 当前支持的 method：
  - `initialize`
  - `notifications/initialized`
  - `notifications/turn-ended`
  - `ping`
  - `tools/list`
  - `tools/call`
- `notifications/turn-ended` 是开源版显式的 turn boundary hook；收到后会清理当前进程里的 visual cursor overlay。CLI `open-computer-use turn-ended [payload]` 也会通过 macOS distributed notification 通知正在运行的 AppKit MCP 进程执行同一类清理，用于接 Codex legacy notify 的 after-agent payload。

### 3. Tool Service 层

- `ComputerUseService` 负责把 Computer Use tool 请求映射到本地能力，`ComputerUseToolDispatcher` 则把 9 个 tool 的参数解析与 service 方法分发收敛成 MCP server 和 `open-computer-use call` 共用的一层。
- `list_apps` 通过 Spotlight metadata query 拉取标准 application 目录里的 app bundle，并读取 `kMDItemUseCount` / `kMDItemLastUsedDate_Ranking` 这类系统元数据；再与 `NSWorkspace` 的运行态 app 合并，输出“当前运行中 + 近 14 天用过”的视图。
- `get_app_state` 优先走真实 AX / 窗口截图，但不再为了读状态而显式 `activate` 目标 app；当目标是仓库内 fixture app 时，回退到 fixture 导出的合成状态。
- MCP `tools/list` 的 description / input schema 当前按官方 `computer-use` 的 9 个 tools 文案和参数面收敛，尽量减少 host 侧提示词和 tool surface 偏差。
- `open-computer-use call <tool> --args '{...}'` 会直接输出 MCP-style JSON result；`open-computer-use call --calls '[...]'` / `--calls-file <path>` 会在同一进程里顺序执行 JSON 数组里的 tool calls，并复用同一个 `ComputerUseService` 内存态，因此 `get_app_state` 之后的 action tool 可以继续使用同一轮 snapshot 的 `element_index`。序列执行默认会在成功的相邻操作之间 sleep 1 秒，也可以用 `--sleep <seconds>` 覆盖；遇到 `isError=true` 的 tool result 后停止。
- 对真实 app 的 `get_app_state` / action tool 入口，当前新增了一层官方风格的高风险 bundle denylist：bundle-id 直传时直接返回 safety denial；名称匹配时默认不解析到这些 app，尽量贴近官方对终端、密码管理器、Chrome 与少量系统敏感组件的防护行为。
- 普通 app 的 element frame 当前按“窗口左上角为原点”的 window-relative 坐标输出，便于后续把 `element_index` 和截图坐标统一到同一套参考系。
- `click` / `set_value` 在执行真实动作前后，会额外驱动一层透明 `SoftwareCursorOverlay` window：两者的移动阶段现在共用一条 heading-driven 的官方风格 motion 内核，显式把“当前 cursor 朝向”和“最终 resting pose”一起喂给选路器，优先生成需要时先掉头、再沿车头方向推进的 C 形/单侧大弧轨迹；首次显示时按官方 binary 的 fresh state 从 AppKit 全局 `(0,0)` window origin 生成起点，后续动作继续复用上一帧 visible tip。真正显示出来的 cursor 不再直接等于 path sample，而是经过一层独立的 visual dynamics 状态，把 visible tip、velocity、angle 和 fog/offset 持续推进。`click` 结尾会衔接 click pulse 和更明显但仍然很小的 rotate wobble，`set_value` 则只做 settle / idle，不给 pulse；两者收尾后会在目标点继续保持 idle 状态，等待下一次动作时 tip 保持 anchored、只保留可感知的小角度摆动；只有连续 30 秒没有新动作时才做 cleanup，这样连续 tool call 不会反复从 fresh `(0,0)` 起步；如果宿主在任务 / turn 结束时发出 `turn-ended`，cursor 会立即消失并清掉本轮位置状态。
- overlay 的 visual style 不再自己从官方 app bundle 裁 `SoftwareCursor` 小图；主 MCP runtime 现在和 `CursorMotion` 一样优先渲染仓库里沉淀的 `official-software-cursor-window-252.png` baseline，只有资源缺失时才退回 `OpenComputerUseKit` 内部的程序化 pointer/fog fallback。命中点 anchor 仍固定在 `126x126` 画布里的同一组 tip-offset 上；glyph 自身的 neutral heading 继续沿用 `CursorMotion` / 官方 baseline 的 `-3π/4`。主 runtime overlay window 按 AppKit 全局坐标移动，因此在把 AX / `CGWindowList` 产出的 y-down screen-space 点击目标喂给 overlay 之前，会先转换成对应屏幕的 AppKit 全局坐标；路径选路用屏幕上实际可见的 AppKit forward heading，进入 visual dynamics / render state 前则把 velocity 的 y 轴翻回 CursorMotion 的 y-down screen state，再交给 AppKit 绘制层做角度和 `dy` 翻转。程序化 fallback 保留 neutral artwork correction，把它的天然轮廓轴对齐到 `CursorMotion` / 官方 baseline 的 `-3π/4` forward 方向，但不让实验线依赖 runtime 代码。
- overlay 的层级不再固定 `.floating`；现在会跟随 snapshot 命中的目标 window id / layer，把自己排到该目标 window 之上，而不是粗暴压到所有前台 app 最上层。
- overlay 的曲线路径不再只按固定 Bezier 模板生成；当前主线采用 reverse-engineering 约束下的 heading-driven candidate 族，候选只保留 `direct` / `turn` / `brake` / `orbit` 这些能稳定产出单侧主弧的 family，并继续保留 target-window 命中策略作为同类候选间的 tie-break。原始 binary lift 恢复出来的 `20` 条路径和 score 仍然保留在独立的 `StandaloneCursor` viewer / Python 重建脚本里，用于对照分析，不再直接作为 runtime 默认 chooser。
- overlay 的 progress 曲线也不再是固定 `easeInOut`；主线现在复用官方 `response=1.4`、`dampingFraction=0.9`、`dt=1/240` 的 spring/`VelocityVerlet` 形状，默认 move 时长对齐已恢复出的 close-enough endpoint-lock 时间 `343 / 240 = 1.4291667s`，不再按路径距离额外压缩。
- overlay 不再依赖临时 `terminal settle` 补丁来修尾；主线现在统一改成“路径层给目标点，visual dynamics 层给可见姿态”的双层模型，所以 move 末段、pulse 和 idle 共用同一套状态，不会再出现 endpoint 锁住后只剩原地翻角的收尾。
- overlay 的渲染输入也从单一 `rotation` 扩展成 `rotation + cursorBodyOffset + fogOffset + fogScale`，让速度滞后能真正体现在画面上，而不是只存在于主循环内部状态；其中 `rotation` 现在按二进制里 `SoftwareCursorStyle.angle + CursorView._animatedAngleOffsetDegrees` 的分层去近似，不再把“跟随运动方向的主朝向”和“小幅 wiggle offset”压成同一个受限小角度。
- 动作型 tools 对普通 app 采用“非侵入优先，物理指针路径显式 opt-in”策略：
  - `perform_secondary_action` 只执行目标元素已经暴露出来的 AX action；无效 action 返回官方风格的 `... is not a valid secondary action for ...`，fixture 的 `Raise` 路径也不再为了测试去准备全局物理指针输入
  - `set_value` 会先用 `AXUIElementIsAttributeSettable(kAXValueAttribute)` 判断目标是否真的是可设置值元素，只有 settable 时才调用 `AXUIElementSetAttributeValue`；不可设置时返回官方风格的 non-settable 错误，不退到键盘输入、剪贴板或未公开的文本替换接口
  - element-targeted `click` 的左键路径会先试 `AXPress` / `AXConfirm` / `AXOpen` 这类真正语义化的激活动作；如果目标本身不可点，还会继续尝试其子孙 AX 元素（例如 Finder sidebar row 下面暴露 `AXOpen` 的 cell）和命中点附近的 AX hit-test 结果，只有这些都失败后才退到窗口/根元素常见的 `AXRaise`、`kAXMainAttribute`、`kAXFocusedAttribute`，最后才会退到 `postToPid` 定向鼠标事件与显式 opt-in 的全局物理指针 fallback。这里也不再把 `AXUIElementIsAttributeSettable` 的结果当成硬门槛，因为像 `TextEdit` window 这类元素在 `kAXFocusedAttribute` 上会出现“`isSettable=false` 但直接 set 成功”的官方同款场景；`click_count > 1` 也会优先重复可用的 AX action
  - `AXUIElementCopyElementAtPosition` 做坐标命中，尽量把 coordinate click 反解成可操作 AX 元素
  - `CGEvent.postToPid` 定向发送键盘事件，避免为了 `type_text` / `press_key` 抢前台；`press_key` 的 xdotool parser 覆盖官方 binary key table 里常见的 `BackSpace`、`Page_Up`、`Prior` / `Next`、`F1...F12` 和 `KP_*` alias
  - `scroll.pages` 对齐官方 `1.0.755` 的 `number` schema，支持小数页数；整数页且目标暴露 `AXScroll*ByPage` 时优先走 AX action，否则用 `CGEvent.postToPid` 向目标进程定向发送 scroll event
  - `drag` 仍是 coordinate-only API，但默认不再使用全局 `.cghidEventTap` mouse event；默认改为 `CGEvent.postToPid` 定向发送 mouse move / down / dragged / up 事件，避免移动用户真实硬件光标；这些 coordinate tool 的 `x/y` 先按 screenshot pixel 坐标解释，再依据截图像素尺寸与目标 window bounds 的比例映射回 window point / Quartz global 坐标，避免 Retina 窗口上把 2x 像素误当成 1x point 导致点击落到错误位置
  - `click` / `scroll` / `drag` 只有设置 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` 时才允许全局 `CGEvent.post(tap: .cghidEventTap)` 物理指针兜底；其中 `click` 默认会先走 AX，再走 `postToPid` 定向鼠标事件，最后才是显式开启的全局物理指针 fallback；默认路径不再为了 fallback 调用 `NSRunningApplication.activate`

### 4. Fixture Bridge

- `OpenComputerUseFixture` 会把自己的窗口与元素状态写到临时 JSON 文件。
- 对 fixture 的 `get_app_state` 和少量测试专用动作，会通过 `FixtureBridge` 走显式 command 通道。
- 这个 bridge 只服务于仓库内 deterministic smoke path，不是面向真实第三方 app 的能力边界。
- 因为 SwiftPM 裸 executable 形式启动的 fixture 没有稳定的 bundle identifier，`list_apps` 会仅对 `OpenComputerUseFixture` 注入一个内部 synthetic identifier，保证 smoke suite 仍能覆盖 `list_apps`，普通第三方 app 仍按真实 bundle id 输出。

### 5. Cursor Lab

- `StandaloneCursor` 是一个新的独立 SwiftUI/AppKit demo target，可通过 `swift run StandaloneCursor` 本地启动。
- 这条线优先验证 Python 重建脚本已经收敛出来的核心：`20` 条候选路径、`measure + score`、`prefer in-bounds then lowest-score` 选路，以及 `response=1.4` / `dampingFraction=0.9` / `dt=1/240` 的 raw spring timeline。
- 当前它刻意不引入 speculative 的 wall-clock duration 映射，也不复用 `CursorMotion` 里更偏视觉手感试验的 pose dynamics。
- `CursorMotion` 是一个单独的 SwiftUI demo target，可通过 `swift run CursorMotion` 本地启动。
- 这条线优先验证 motion model 本身：当前主线是 heading-driven 的 turn / brake / orbit / direct candidate 族、spring progress、独立 visual dynamics 和 debug UI；moving 阶段真正画出来的箭头角度会持续跟随 visual dynamics 的主 heading，接近停住后再平滑回到默认 resting pose，并在 idle 阶段保留原地小摆角。
- lab 的 cursor 视觉继续以 `scripts/render-synthesized-software-cursor.swift` 为参考：优先使用仓库里保存的官方 `252x252` runtime baseline 图，缺失时再退回脚本里的 procedural pointer/fog 近似；settle 态也改成中心固定的小幅摆角，而不是继续沿 XY 轻微漂移。
- 当前它不接真实 tool call，也不回写主 `SoftwareCursorOverlay`，目的是把实验噪音与产品行为边界隔离开。

### 6. Windows Runtime

- Windows runtime 位于 `apps/OpenComputerUseWindows`，以 Go 维护 CLI、`call --calls` sequence、MCP JSON-RPC、tool schema 和进程内 snapshot cache。
- 构建入口是 `scripts/build-open-computer-use-windows.sh --arch arm64|amd64`，默认输出到 `dist/windows/<arch>/open-computer-use.exe`；当前 npm 包仍只发布 macOS app bundle，Windows 分发还没有接入 release package。
- Go runtime 通过 `go:embed` 带上 `runtime.ps1`，执行 tool call 时临时落盘并调用 Windows PowerShell。PowerShell bridge 使用 `System.Windows.Automation` 做 app/window/element discovery、tree rendering、UIA pattern action、ValuePattern set value 和 ScrollPattern scroll；当目标 app 不暴露对应 pattern 时，fallback 到 `PostMessage` / `SendMessage` 形式的 Win32 window message。
- Windows runtime 默认只连接已经运行的 app，不会在 `get_app_state` 找不到进程时自动 `Start-Process`，也不会默认允许 `SetFocus` secondary action；这两条前台抢占路径分别需要 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` 和 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1` 显式打开。`type_text` 默认优先对可写文本控件的 child HWND 发送 `EM_SETSEL` / `EM_REPLACESEL`，不再默认走可能触发前台激活的 UIA `ValuePattern.SetValue` fallback；需要旧行为时必须设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1`。UIA pattern 和 Win32 message fallback 本身仍是 best-effort：很多控件可以在后台响应，但 Windows 没有一套对所有 GUI toolkit 都等价于 macOS AX 的后台键鼠输入模型。
- 这 9 个 tool 的协议面与 macOS 主线保持一致：`list_apps`、`get_app_state`、`click`、`perform_secondary_action`、`scroll`、`drag`、`type_text`、`press_key`、`set_value`。其中 element-targeted action 会优先复用上一轮 `get_app_state` 的 runtime id / automation metadata，coordinate action 使用 screenshot/window-relative 坐标。
- Windows UI Automation 需要运行在已登录用户的桌面 session 里。通过 SSH 作为脱离桌面的后台进程运行时，PowerShell 可以启动并返回 JSON，但系统可能不给它暴露顶层窗口；这种情况下 `list_apps` 会是空，`get_app_state` 可能返回 `appNotFound(...)`。
- 当前 Windows 侧仍是功能性第一版：没有 visual cursor overlay、没有 installer/onboarding、没有 code signing，也没有独立的 Windows smoke fixture。后续 TODO 记录在 `docs/exec-plans/active/20260422-windows-computer-use-runtime.md`。

## 关键边界

- 开源版当前不复刻官方闭源实现里的 caller signing、私有 IPC、完整 overlay choreography 和 plugin 自安装逻辑。
- 因为官方 `SkyComputerUseClient` 带有宿主侧 launch constraints，普通 stdio MCP client 在本机上可能被系统直接杀掉；如果要探测官方 bundled `computer-use`，`scripts/computer-use-cli` 的 app-server 模式现在只适合做工具清单和协议面观察。官方 `1.0.755` 的真实 tool call 还会经过 service-side sender authorization / active IPC client 追踪，外部 raw helper 即使走已签名 Codex binary，也可能返回 `Sender process is not authenticated`；需要真实使用官方工具时应走正常 Codex agent/tool 调用链，开源版则继续提供可直连的 `open-computer-use` MCP server。
- 当前权限引导已经具备可运行 app、深链、拖拽辅助，以及一版更接近官方的 accessory panel 入场动画和返回 affordance；点击链路也已经补上独立 visual cursor、官方 asset fallback 和相对目标 window 的排序逻辑，并且在 overlay 可见期间会持续重申“排在目标 window 之上”，避免用户手动激活目标 app 后 cursor 被目标窗口重新盖住；但整体还没有完全复刻官方那套嵌入式 choreography / host 集成 / session approval 体验。
- screenshot 当前通过 `ScreenCaptureKit` 捕获目标窗口，并直接以 MCP `image` content block 的 base64 PNG 返回，不再把普通 app 截图落盘到仓库或临时目录。
- 会话状态现在是进程内内存态，保存每个 app 最近一次 snapshot 和 element index 映射。

## 主要验证路径

- 单元测试：`swift test`
- standalone cursor 构建：`swift build --product StandaloneCursor`
- cursor lab 构建：`swift build --product CursorMotion`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`（标准 9-tool smoke + visual cursor idle smoke）
- app 打包：`./scripts/build-open-computer-use-app.sh debug`
- npm staging：`node ./scripts/npm/build-packages.mjs`
- release tgz：`./scripts/release-package.sh`
- Windows runtime 单测：`(cd apps/OpenComputerUseWindows && go test ./...)`
- Windows exe 构建：`./scripts/build-open-computer-use-windows.sh --arch arm64`
- 对比样本：`artifacts/tool-comparisons/20260417-focus-behavior/`
- 手工诊断：
  - `.build/debug/OpenComputerUse doctor`
  - `.build/debug/OpenComputerUse snapshot <app>`
  - `.build/debug/OpenComputerUse call list_apps`
  - `.build/debug/OpenComputerUse call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}}]'`
