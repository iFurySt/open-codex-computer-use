# 稳定性与可运维性

## 当前最低验证线

- 构建：`swift build`
- 单元测试：`swift test`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`
- Linux runtime：`(cd apps/OpenComputerUseLinux && go test ./...)`、`./scripts/build-open-computer-use-linux.sh --arch arm64`
- 本地诊断：
  - `open-computer-use doctor`
  - `open-computer-use snapshot <app>`

## 已知关键依赖

- macOS 上必须给 `Open Computer Use.app` 授权 `Accessibility` 与 `Screen Recording`；终端本身不应该再是必需授权对象。
- smoke suite 依赖本地 GUI session，不能把它当成无头环境命令。
- 普通 app 的 `get_app_state` 结果依赖 AX tree 和窗口截图，复杂 app 上输出会有差异；Electron/WebView app 的 AX tree 通常很深，当前会压缩空 wrapper 并放宽遍历深度，以优先保留可操作文本、按钮和输入框。
- Linux runtime 依赖已登录桌面用户 session；缺少 `XDG_RUNTIME_DIR`、`DBUS_SESSION_BUS_ADDRESS` 或 display 环境时，会尝试从 `/run/user/<uid>` 和常见桌面进程自动发现当前用户的 session env。纯 SSH tty 如果找不到桌面 session 仍不能直接访问 AT-SPI GUI tree。
- GNOME Wayland 截图可能被 compositor 限制，当前 Linux bridge 会把黑图视为无效截图并省略 image block。

## 当前故障排查顺序

1. 先跑 `open-computer-use doctor`，确认权限状态；如果缺权限，命令会通过 `.app` app agent 拉起权限 onboarding 窗口，已全部授权则只打印状态并退出。
2. 用 `open-computer-use list-apps` 确认目标 app 是否被发现。
3. 用 `open-computer-use snapshot <app>` 看是 transport 问题还是 snapshot / action 问题。
4. 如果只想验证仓库基线，直接跑 fixture + smoke，不要先在复杂第三方 app 上排查。
5. 排查 Linux runtime 时，先确认目标命令是否由桌面用户运行，再用 `open-computer-use call list_apps` 和 `open-computer-use snapshot <app>` 区分 session/env 问题与 AT-SPI tree/action 问题。如果是 Codex MCP，重新执行 `open-computer-use install-codex-mcp` 后重启 Codex，确认配置仍是 `open-computer-use mcp`。

## Lock Screen / Stale-Target / 状态菜单排查

**锁定 session：**
- 症状：所有 tool（除 `tools/list`）返回 "Session is locked" 或 "Lock state unknown"。
- 排查：`CGSessionCopyCurrentDictionary` 在用户 session 锁定或不可用时返回 nil；fail-closed 行为是**默认**预期设计，不是 bug。
- 解决（有人值守）：解锁当前 macOS 用户 session 后重试，或使用已登录桌面 session。
- 解决（无人值守 agent 需锁屏继续工作）：设置 `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` 开启 best-effort 锁屏放行。开启后 action 仍能经 process-targeted 投递（AX / `postToPid`）驱动可访问性可控的 app；但**窗口截图返回空图**（`get_app_state` 只回 AX tree），coordinate-only 路径不可靠 —— 用 `element_index` 定位的 action。首次放行时 stderr 会打印一次降级提示。默认不开启。

**Stale target（目标窗口发生变化）：**
- 症状：action tool 返回 "Computer Use target screen changed. Call get_app_state for this app before acting again."
- 原因：目标 app 的 pid、window ID、bounds 或截图尺寸在上一次 `get_app_state` 之后发生了变化（超过 8pt 容差）。
- 解决：重新调用 `get_app_state` 取最新快照，再执行 action。

**状态菜单 Restart 不可用：**
- 症状：状态菜单的 "Restart" 菜单项在 direct AppKit MCP 模式下显示为禁用。
- 原因：`ControlStatusMenuController` 只在 app-agent 模式下启用 Restart；direct 模式需要由宿主重新 launch，无法从 MCP 进程内部触发。
- 解决：如需在 direct 模式重启，在宿主侧手动重启 `open-computer-use mcp` 进程。Restart 仅对通过 CLI 启动的 app-agent 会话有效。

## Background-Only Operation Guarantee

By default, all MCP tool operations target apps by PID using accessibility APIs and targeted CGEvents — no app activation (`NSRunningApplication.activate`) is ever called on the normal path.

- `globalPointerFallbacksEnabled()` returns `false` unless `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` is set; the global pointer paths (`clickGlobally` / `scrollGlobally` / `dragGlobally`) are never invoked without this explicit opt-in.
- Keyboard events use `CGEvent.postToPid` with the target PID; the target app need not be frontmost.
- Mouse events use `AXUIElement` `performAction` or `CGEvent.postToPid` targeted to the app's PID; no front-most requirement exists.
- This guarantees MCP tools do not steal focus, move the user's hardware cursor, or interrupt the user's active workflow.

## 后续补强方向

- 增加结构化日志和失败原因分类。
- 继续补充 screenshot capture / AX traversal 的失败上下文和普通 app 回归样本。
- 增加普通 app 回归样本，而不是只覆盖 fixture。

CI/CD 流程结构和 release 自动化的默认方案，统一写在 `docs/CICD.md`。
