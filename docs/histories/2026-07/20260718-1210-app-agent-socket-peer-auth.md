## [2026-07-18 12:10] | Task: app-agent socket 对端认证

### 🤖 Execution Context
* **Agent ID**: `/hvn:cortex` follow-up
* **Base Model**: Claude Opus 4.8
* **Runtime**: Claude Code (background job)

### 📥 User Query
> 合并 v0.2.0 + 锁屏放行到 fork 后，开一个 socket peer-auth PR，让 agent 能在锁屏时安全地继续工作。

### 🛠 Changes Overview
**Scope:** app-agent Unix domain socket 对端认证（peer authentication）

**Key Actions:**
- **[纯策略]**: 新增 `AppAgentPeerAuthPolicy`（Kit，可单测）—— 依据 peer uid / self uid / agent TeamID / 对端是否满足签名需求，产出 `allow` / `allowUnsignedFallback` / `reject`。
- **[IO 校验]**: 新增 `SocketPeerAuthenticator`（app）—— `getpeereid` 校验同 uid；`getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` 取 audit token → `SecCodeCopyGuestWithAttributes` 还原对端 `SecCode`，用需求 `anchor apple generic and certificate leaf[subject.OU] = "<agent TeamID>"` 校验同开发者签名；`SecCodeCopySelf` 解析 agent 自身 TeamID。
- **[接入]**: `AppAgentSocketListener.acceptLoop` 在处理连接前认证；reject 则关闭 fd 并记录原因；未签名 dev 构建走 `.allowUnsignedFallback` 并打印一次提示。
- **[验证]**: +5 策略单测（uid 不符、签名同队放行、签名 agent 拒绝不符对端、未签名回退、未签名仍拒绝异 uid）；共 177 测试全绿；full workspace build 通过。

### 🧠 Design Intent (Why)
锁屏放行（`OPEN_COMPUTER_USE_ALLOW_LOCKED`）让 agent 可在锁屏时驱动 app，但 app-agent 常驻进程持有 TCC 授权、socket 仅靠 0600 同 uid 权限，任意同 uid 进程都可复用其授权（confused deputy）。对端签名认证要求连接方与 agent 同开发者签名，**抬高门槛**——挡掉外部/未签名/异开发者二进制直接连接。但需如实说明其边界（经 codex + Fable-max 交叉复审确认）：签名校验不能区分合法运维方与同 uid 攻击者，后者可 `exec` 那份合法签名 CLI 中转命令，故**未真正关闭**同 uid confused-deputy；不可信主机仍应使用独立登录 session。未签名 dev 退化为同 uid 并提示，且已在 `copyDiagnostics` 暴露该状态。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentPeerAuthPolicy.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/SocketPeerAuthenticator.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/histories/2026-07/20260718-1210-app-agent-socket-peer-auth.md`

### 🔁 Follow-up
- 交叉复审跟进项 #2 已落地：release 构建现在 fail-closed —— 签名会回退到 ad-hoc/无签名时，`build-open-computer-use-app.sh` 直接报错拒绝构建，避免发布版本静默退化为仅同 uid trust。
- override env：`OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1`（设置后脚本打印醒目 WARNING，peer-auth 仍不生效）。
