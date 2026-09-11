# 稳定性与可运维性

## 当前最低验证线

- 构建：`swift build`
- 单元测试：`swift test`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`
- macOS SkyLight 实机回归：`OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests`
- macOS SkyLight 后台键盘实机回归：`OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests`
- macOS 被遮挡窗口 keep-alive 实机回归：`OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests`
- macOS 多 app 扫描（对运行中的每个 GUI app 做 read-only snapshot，并在空白文本框里输入再删除一个标记；会向真实 app 输入，只在无人使用时跑）：`OPEN_COMPUTER_USE_RUN_APP_MATRIX=1 swift test --filter AppMatrixLiveTests`；加 `OPEN_COMPUTER_USE_APP_MATRIX_PARK=1` 会把每个非全屏窗口停靠到 agent display 上做同样的事再移回原位。
- macOS 后台输入基准（25 轮 `sky_click` + `sky_key`，输出成功数与 p50 / p95 / max）：`OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH=1 OPEN_COMPUTER_USE_BENCH_CYCLES=25 swift test --filter BackgroundInputBenchmarkLiveTests`
- 基准结果与复现命令汇总在 `docs/references/background-input-benchmarks.md`。
- 输入默认值以跨版本可靠性优先：普通 `auto` 的 type chunk / press-key settle 保持 20 / 100 ms，`sky_key` 的 key-window / release settle 为 10 / 10 ms；六个 timing knob 均可通过对应 `OPEN_COMPUTER_USE_*` 环境变量显式覆盖。
- 逐阶段耗时：任何命令前加 `OPEN_COMPUTER_USE_DEBUG_TIMING=1`，stderr 输出 `[open-computer-use] timing <阶段> <ms>ms`（`sky_key.*`、`sky_click.total`、`snapshot.window_capture`、`snapshot.tree_walk`、`agent_display.*`）。
- 跑实机回归时不要在这台 Mac 上打字或点鼠标：测试会短暂把目标窗口放到前台，用户的按键会落进去，前台 fixture 也会因用户操作失去 active。
- macOS agent display 实机回归（会短暂创建并销毁一块 virtual display）：`OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST=1 swift test --filter AgentDisplayLiveTests`
- macOS 其他 Desktop 实机回归（需要第二个 Desktop，测试会短暂切换 Space 启动目标）：`OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests`
- Linux runtime：`(cd apps/OpenComputerUseLinux && go test ./...)`、`./scripts/build-open-computer-use-linux.sh --arch arm64`
- 本地诊断：
  - `open-computer-use doctor`
  - `open-computer-use snapshot <app>`

## 已知关键依赖

- macOS 上必须给 `Open Computer Use.app` 授权 `Accessibility` 与 `Screen Recording`；终端本身不应该再是必需授权对象。
- macOS `click_method=sky_click` 额外依赖 SkyLight / ApplicationServices 私有符号 `SLEventPostToPid`、`SLEventSetIntegerValueField`、`CGEventSetWindowLocation`、`SLPSPostEventRecordTo` 和 `GetProcessForPID`。截图主路径依赖可选的 `SLSHWCaptureWindowList`，窗口绑定依赖可选的 `_AXUIElementGetWindow`，缺失时分别退回 ScreenCaptureKit 与标题启发式。运行时会动态探测并 fail closed，但 macOS 更新、签名方式或目标 app 输入策略变化仍可能让后台投递失效。受控实机回归除 DOM、前台 PID、鼠标和 z-order 外，还必须验证前台 AppKit active、key window、first responder 以及 resign/key-loss 计数。`key_method=sky_key` 复用同一组符号，实机回归还要确认被遮挡 Chrome 的输入框收到文字、`cmd+a` 菜单快捷键生效，以及投递结束后 Chrome 页面重新 blur。
- smoke suite 依赖本地 GUI session，不能把它当成无头环境命令。
- 普通 app 的 `get_app_state` 结果依赖 AX tree 和窗口截图，复杂 app 上输出会有差异；Electron/WebView app 的 AX tree 通常很深，当前会压缩空 wrapper 并放宽遍历深度，以优先保留可操作文本、按钮和输入框。
- Linux runtime 依赖已登录桌面用户 session；缺少 `XDG_RUNTIME_DIR`、`DBUS_SESSION_BUS_ADDRESS` 或 display 环境时，会尝试从 `/run/user/<uid>` 和常见桌面进程自动发现当前用户的 session env。纯 SSH tty 如果找不到桌面 session 仍不能直接访问 AT-SPI GUI tree。
- GNOME Wayland 截图可能被 compositor 限制，当前 Linux bridge 会把黑图视为无效截图并省略 image block。

## 当前故障排查顺序

1. 先跑 `open-computer-use doctor`，确认权限状态；如果缺权限，命令会通过 `.app` app agent 拉起权限 onboarding 窗口，已全部授权则只打印状态并退出。
2. 用 `open-computer-use list-apps` 确认目标 app 是否被发现。
3. 用 `open-computer-use snapshot <app>` 看是 transport 问题还是 snapshot / action 问题。
4. 如果 `sky_key` 输入没有落到目标：先确认目标不是隐藏 app、窗口仍属于同一 PID；Chromium 目标可以在页面里观察 `document.hasFocus()`，投递期间应为 true。跑实机回归时不要同时在其他窗口打字，否则前台 fixture 会因为用户自己的操作失去 active。
5. 如果被遮挡或其他 Space 的 Chromium / Electron 窗口 tree 里没有网页内容，看 tree 末尾是否有 “window is covered” 说明：说明 agent 第一次看到它时它已经被遮挡。让窗口露出一次再 `get_app_state`，之后再遮挡也会保留内容；或者显式调用 `get_app_state` 并传 `window_placement=agent_display` 把窗口停靠到 agent 显示器，用完 `restore`。
6. 如果只有 `sky_click` 失败，先重新执行 `get_app_state`，确认窗口仍属于同一进程且 app 未被隐藏；错误里出现 `missing SkyLight symbols` 时不要改用隐式 fallback，应按当前 macOS 版本重新验证私有 SPI。被遮挡的 Chromium 页面仍无效果时，再用受控页面区分 renderer 策略变化与坐标/window-local 映射问题。
7. 如果只想验证仓库基线，直接跑 fixture + smoke，不要先在复杂第三方 app 上排查。
8. 排查 Linux runtime 时，先确认目标命令是否由桌面用户运行，再用 `open-computer-use call list_apps` 和 `open-computer-use snapshot <app>` 区分 session/env 问题与 AT-SPI tree/action 问题。如果是 Codex MCP，重新执行 `open-computer-use install-codex-mcp` 后重启 Codex，确认配置仍是 `open-computer-use mcp`。

## 后续补强方向

- 增加结构化日志和失败原因分类。
- 继续补充 screenshot capture / AX traversal 的失败上下文和普通 app 回归样本。
- 增加普通 app 回归样本，而不是只覆盖 fixture。

CI/CD 流程结构和 release 自动化的默认方案，统一写在 `docs/CICD.md`。
