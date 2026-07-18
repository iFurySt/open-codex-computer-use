# 安全默认约束

## 当前实现边界

- 对 MCP host 暴露的接口仍是本地 `stdio`；macOS CLI 与 `.app` app agent 之间会使用用户临时目录下的 Unix domain socket，socket 创建后会收紧为当前用户读写，且不对外监听 TCP/HTTP 端口。
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
- 下一阶段应优先补：
  - session 级审批
  - 更清楚的敏感 app / 系统设置防护策略

## Lock Guard 与 App-Screen 不变量

- `MacSessionGuard` 在每个 tool call 入口检查 `CGSessionCopyCurrentDictionary` 的锁定状态；当字典缺失、为空或解析失败时一律视为已锁（fail-closed），返回 "Lock state unknown" 指示器。
- 默认策略 `.blockWhileLocked`：锁定时不允许任何 `list_apps` / `get_app_state` / action tool 执行，安全保证与原先一致。
- 显式 opt-in `OPEN_COMPUTER_USE_ALLOW_LOCKED=1`（`.allowWhileLocked`）：放行锁屏 best-effort 控制。未设置时保持 fail-closed。放行仅改变 guard 是否拦截，不绕过 Accessibility 权限（仍需系统授权）、不落盘截图、也不启用全局 HID event tap（`globalPointerFallbacksEnabled()` 默认仍为 false）。锁定时窗口截图受系统安全限制返回空图。
- **App-agent 信任边界**：`.app` 模式下有一个持有 TCC 授权的常驻 agent，监听 `$TMPDIR/open-computer-use-agent.sock`（chmod 0600，仅限同一 uid，但**无对端认证**）。锁屏 opt-in 属于安全敏感设置，因此**只通过可信的启动环境**（`NSWorkspace.OpenConfiguration.environment`，由运维方运行的 proxy 从其真实 shell env 传入）在 agent 启动时固定，**不经过 per-call socket 通道**；agent 侧还会主动剥离 client 传入的该键（defense in depth），因此同 uid 的第三方进程**无法**对已运行的 agent 伪造该标志。策略在 agent 生命周期内固定，需从菜单栏退出 agent 后重启才能变更。
- **App-agent socket 对端认证（peer authentication）**：`AppAgentSocketListener.acceptLoop` 在每个连接被处理前调用 `SocketPeerAuthenticator.authenticate(fd:)`：
  - `getpeereid` 校验对端 euid == agent euid（同 uid），否则拒绝。
  - 经 `LOCAL_PEERTOKEN` 取对端 audit token（含 pid + pidversion，能精确锁定连接进程实例，规避 PID 复用/连后 exec 的 TOCTOU）→ `SecCodeCopyGuestWithAttributes` 还原对端 `SecCode`，用需求 `anchor apple generic and identifier "<agent bundle id>" and certificate leaf[subject.OU] = "<agent TeamID>"` 校验：对端必须由与 agent **相同开发者（Team Identifier）签名**，且签名 identifier 与 agent 的 bundle identifier 一致（即本 app 自己的可执行文件；同 team 但 identifier 不同的二进制会被拒绝）。agent 非 bundle 运行时退化为仅 team pin。任一校验不满足则拒绝。
  - **开发回退**：agent 自身未签名/ad-hoc（本地 `swift build`）时无法进行签名校验，退化为仅同 uid（`.allowUnsignedFallback`），并向 stderr 打印一次提示。纯策略逻辑在 `AppAgentPeerAuthPolicy`（可单测）。
- **对端认证的真实边界（务必如实理解，勿夸大）**：签名校验只证明「连接进程运行的是这份已签名代码」，**不能**区分合法运维方与同 uid 攻击者。同 uid 代码可直接 `exec` 那份合法、同开发者签名的 CLI（位于 app bundle 固定路径，world-readable，见 `plugins/.../launch-open-computer-use.sh`）来中转命令，从而**仍能**复用 agent 的 TCC 授权——锁屏时亦然。因此对端认证只是**抬高门槛**（挡掉外部/未签名/异开发者的二进制直接连接），并**未真正关闭**同 uid confused-deputy。PR#2 记录的残余风险依旧成立。
- **另需注意**：release 构建现在默认 fail-closed —— 当签名会回退到 ad-hoc/无签名时，`build-open-computer-use-app.sh` 直接报错拒绝构建；如确有意分发 ad-hoc release，须显式设置 `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1`（此时脚本会打印醒目警告，peer-auth 不生效）。
- **结论**：对不可信/多租户主机，请使用**独立登录 session**，不要把 peer-auth 或锁屏 opt-in 当作隔离边界。真正更强的隔离需进一步收紧需求（Developer ID marker OID pinning）——见 issue #4。
- `AppScreenSession` 维护严格的目标屏幕不变量：action call 执行前会比对 pid、target window ID、window bounds（8pt 容差）和截图像素尺寸；任一维度变更时返回 `appScreenStaleStateError`，要求 caller 先重新调用 `get_app_state`。
- 状态菜单（`ControlStatusMenuController`）的诊断信息只暴露 toolName、app name / bundle id、pid 和连接数，不暴露 element labels、raw action args、截图数据或 AX 文本。

## Fixture Bridge 约束

- `FixtureBridge` 只用于仓库内测试夹具，不是给第三方 app 的控制平面。
- 任何面向真实 app 的能力新增，都不应该复用这条测试专用通道。

仓库级的依赖、SBOM 和 provenance 默认能力，统一写在 `docs/SUPPLY_CHAIN_SECURITY.md`。
