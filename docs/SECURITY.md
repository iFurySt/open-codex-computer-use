# 安全默认约束

## 当前实现边界

- 对 MCP host 暴露的接口仍是本地 `stdio`；macOS CLI 与 `.app` app agent 之间会使用用户临时目录下的 Unix domain socket，socket 创建后会收紧为当前用户读写，且不对外监听 TCP/HTTP 端口。未设置 `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` 时继续使用历史 Socket；设置后仅以 namespace 摘要派生私有文件名，不把宿主目录或原始 namespace 写入 Socket 路径。
- Codex plugin 默认把一个本地 Node.js REPL 放在 native MCP 前面，npm CLI 的 `ocu js` / `ocu repl` 也直接使用同一 runtime。`js` 是任意本地 JavaScript 执行能力，不是受限表达式语言：代码可按启动进程权限读取文件、环境、模块和网络。只应在 host 已经具备并允许 model-code execution 的信任边界内启用；不接受这条边界的 host 应继续直连 `open-computer-use mcp` 的离散 native tools。
- REPL 里的 Computer Use 调用仍经过 native MCP，因此密码管理器 denylist、`OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` 等 native safety gate 不会被 JavaScript adapter 绕过。JS kernel 在 Worker 中运行，超时会终止整个 Worker 并清空 bindings。
- 所有动作都必须显式带 `app` 参数；当前不会在后台自动扫描并控制任意 app。
- macOS 真实 app 路径依赖 `Open Computer Use.app` 已获得 `Accessibility` 与 `Screen Recording` 权限；终端里的 CLI / Node launcher 会把 `mcp`、`doctor`、`call`、`snapshot` 和 `list-apps` 转发给由 LaunchServices 启动的本地 app agent，避免把权限要求落到 iTerm / Terminal 身上。
- 实验性 Linux runtime 依赖已登录桌面用户的 AT-SPI2 / D-Bus session；coordinate mouse、drag、keyboard synthesis 只是 best-effort fallback，不应被视为跨 Wayland compositor 的通用后台输入授权。

## 数据处理

- 普通 app 的 screenshot 默认只在内存中编码成 PNG，并通过 MCP `image` content block 直接回传；默认不长期持久化。
- Linux runtime 的 screenshot 是 best-effort；如果 GNOME Wayland 返回黑图，bridge 会省略 image block，避免把无效截图误当成真实画面。
- fixture app 的合成状态只写到本地临时 JSON 文件，目的是支撑 deterministic smoke test；当前写入走原子替换，减少测试期间的读写竞争。
- 当前仓库不引入第三方服务，也不上传截图、AX tree 或输入内容。

## 授权与最小权限

- 当前只保留一层密码管理器 bundle denylist / bundle-id gate：
  - 会阻止对 1Password、Bitwarden、Dashlane、LastPass、NordPass 和 Proton Pass 做直接 `get_app_state` / action 调用。
  - 终端类 app、Chrome / Atlas 和系统组件不再属于内置阻止目标。
  - 对 bundle identifier 直传时返回 safety denial；对 app name 查询时默认不把这些密码管理器暴露成可解析目标。
- 但当前仍然没有官方闭源实现里的 session approval / 动态 app policy。
- 这意味着开源版当前的安全边界主要由：
  - 明确的 tool 调用参数
  - 内置密码管理器 denylist
  - `Open Computer Use.app` 的系统权限
  - 本地使用场景
  共同提供。
- `click_method=global` 是显式的系统级指针路径，可能移动真实鼠标、改变前台焦点或命中坐标处的其他窗口。调用参数本身不视为足够授权；macOS 和支持该模式的 Linux runtime 还要求进程环境中设置 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`。未设置时必须在任何可见 cursor 移动或真实输入事件之前拒绝请求。
- `click_method=app_post`、`sky_click` 与 `accessibility` 不允许静默切换到 `global`。这保证调用方选择的非侵入边界在失败时仍然成立。
- `click_method=sky_click` 是显式 macOS 私有 SPI 能力，不进入 `auto`。它不移动系统指针、不改变 WindowServer frontmost app，也不 raise 或切换目标窗口；内部只让目标应用短暂进入 synthetic-active 状态，绝不向真实前台应用发送 defocus record，renderer settle 后也只撤销目标的合成状态。点击后的 action-result snapshot 禁止 activate / `AXRaise` 恢复。它仍会向指定 PID/window 注入真实输入语义，因此只允许使用当前 snapshot 的 on-screen、同 PID 窗口，并在窗口身份不匹配、target-focus record 失败或私有符号缺失时 fail closed。第一版仅支持同一 Space 内的左键单击/双击。
- SkyLight ABI、raw event field 和 Chromium 接收行为都不受 Apple 公共兼容性承诺保护。系统升级后的失败不得触发静默 global fallback；应先重新验证符号和受控目标，再决定是否更新实现。
- 下一阶段应优先补：
  - session 级审批
  - 更清楚的敏感 app / 系统设置防护策略

## Fixture Bridge 约束

- `FixtureBridge` 只用于仓库内测试夹具，不是给第三方 app 的控制平面。
- 任何面向真实 app 的能力新增，都不应该复用这条测试专用通道。

仓库级的依赖、SBOM 和 provenance 默认能力，统一写在 `docs/SUPPLY_CHAIN_SECURITY.md`。

## macOS Locked Use 实验边界

- 当前 `available` / `enabled` 始终 false，真实锁屏控制 fail closed；用户环境、请求 metadata 和其他产品的插件都不能开启自动解锁。
- 状态机的 connection / session 身份必须由未来认证 IPC 提供，纯 reducer 不提供身份认证；effect 不是系统状态证据。
- 独立 Authorization 探针始终拒绝，不读写密码上下文；安装实验只注册独立 deny-only right，不改 `system.login.screensaver`。安装与卸载要求管理员执行并核对自身条目，不覆盖其他认证配置。
- 独立 Guardian / watchdog 目前只供显式人工 rehearsal；覆盖检查、输入拦截和重锁尚未经过物理观察，未签发生产解锁许可。开发 controller 的应急结束不能作为生产遮罩释放规则。
- Broker 的基础组件从 Unix socket 的内核 audit token 验证动态签名；批准文件必须在逐层 root 所有、不可由普通用户写入且无 symlink 的固定目录下。批准绑定 UID、角色、signer 和 Team ID，不能从环境或请求 payload 选择任意 requirement。许可使用安全随机 nonce，绑定会话、连接和 attempt，过期 / 消费 / 撤销后不可重放。完整 Broker IPC / 登记 UI 尚未接入。
- 开放 backend 前必须验证 Keychain 保持、保护组件故障和重锁确认。没有通过这些门槛不得将 AX / Screen Recording 授权等同于后台解锁许可。见 [实验与恢复说明](locked-use.md)。
