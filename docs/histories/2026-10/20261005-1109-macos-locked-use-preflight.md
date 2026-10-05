## [2026-10-05 11:09] | Task: 实现 macOS Locked Use 预检与独立认证插件实验

### Execution Context

- Agent ID：`/root`
- Base Model：GPT-6（会话未提供细分型号）
- Runtime：Codex desktop，独立 macOS worktree

### 用户诉求

在本地 awesome-extension 的独立 worktree 中推进 macOS 锁屏后继续 Computer Use 的实现，完成后本地合并，避免影响另一个会话。首次显式启用并授权客户端，后续锁屏自动进入；轮次结束 / 30 秒空闲 / 本地输入触发重锁。用户已关闭原有 Codex Locked Use 插件。

### 已交付改动

- 新增原生 `locked-use status [--json]`、doctor 和 npm help 入口，报告会话、runtime 权限、组件存在性和未通过的门槛。
- 会话读取使用 SessionGetInfo audit-session identity、CGSession 的 on-console / login-done / UID 状态；兼容当前系统缺少 console-set key 的情况。
- 真实 snapshot、缓存复用和输入事件路径在锁屏 / 未知会话时明确拒绝；fixture 保持 headless 可用。
- 新增可测试的保护状态机，覆盖一次性许可、所有者、短期授权、heartbeat、空闲和绝对期限、接管抑制、取消 / 排空 barrier 和重锁确认。
- 新增始终 deny 的最小 Authorization 插件 ABI probe、离线测试，以及只操作独立诊断 right 的管理员安装 / 卸载脚本。构建产物隔离在 .build，不修改 screensaver right。
- 同步架构、安全、可靠性、实验步骤及 active execution plan。

### 实现边界

这不是完成的 Locked Use 功能。独立 guardian / watchdog 已实现开发 rehearsal；Broker 的内核 peer 签名验证、root 批准记录与一次性许可组件已实现。生产 Broker IPC、客户端授权 UI、guardian 集成与真实 loginwindow unlock backend 尚未完成。`available` / `enabled` 始终 false；无生产 backend 时不可开启自动解锁。需先完成屏幕 / 输入保护与真正解锁、Keychain 保持验证。

系统现有 Codex 插件已由用户关闭，只读确认 bundle 和 remote screensaver rule 移除。实验插件完成 Developer ID 签名与离线验证，并通过 macOS 原生管理员授权窗口安装独立 deny-only right。4 次真实 AuthorizationCopyRights 返回 denied，SecurityAgentHelper 日志确认机制实际调用。首次有 Library Validation 报错后仍实际执行，记录此差异。实验后独立 right、原 bundle 与自身 staged 副本均已移除；screensaver 规则保持不变。未执行真正解锁，未读取密码或用户 Keychain 项。

### 验证

继续开发新增 `OpenComputerUseGuardian` app、独立 heartbeat watchdog、过滤型输入 tap、全显示器遮罩与 WindowServer coverage 观测、受控 AX / SCK fixture、只读 loginwindow 结构探针，以及有应急结束路径的人工 rehearsal controller。没有触发锁屏或解锁；等待用户准备好后实测。Developer ID 签名 bundle 的 runtime 检查显示 AX / Input Monitoring / 重锁符号均可用，secure input 未启用；socket peer 自检成功取得内核身份并验证签名，错误 signer 被拒绝。

Broker 基础组件补充 LOCAL_PEERTOKEN / Security 动态验证、固定路径 root 批准记录安全读取、Secure Random 一次性 permit。测试覆盖错误身份 / 角色、要求字符串注入、会话不匹配、过期与重放、断开撤销、guardian 心跳 / 热插拔 / 动作排空 barrier。生产 IPC / 安装登记仍未实现。

- `swift test`：188 项，1 项 gated live test 跳过，0 失败；其中 LockedUseTests 20 项。
- JS REPL / CLI：21 项通过；使用 bundled Node 绕过系统 Node 的既有动态库故障，没有修改系统安装。
- fixture 9-tool smoke 与 cursor idle smoke 通过。
- 插件 ABI / 生命周期 / deny-only 行为及 codesign 验证通过；离线通过不等同于系统加载或 notarization；另有上述 SecurityAgent 实机日志证据，仅覆盖独立诊断 right。
- shell syntax 与 git diff whitespace 检查通过。
- 继续开发后完整 Swift：206 项，1 项 gated live test 跳过，0 失败；Locked Use 的 38 项策略 / 许可 / 身份 / 批准记录测试通过。fixture 9-tool 与 cursor idle smoke 再次通过；增加 extended ACL mutation 回归，防止仅凭 mode bits 将可写配置当可信。
- Developer ID / hardened runtime Guardian 的内核 socket 身份与角色批准自检通过；同签名、同 identifier 但带 get-task-allow 的独立测试副本被批准策略拒绝。未在系统安装批准文件。
- Guardian runtime preflight：AX、Input Monitoring、Screen Recording 与重锁符号均可用。尚未执行真实遮罩、锁屏、loginwindow AX 或自动解锁测试；等待用户确认测试时间。

### 合并状态

开发提交保留在隔离分支。目标工作区的另一个会话仍有与 app agent、入口、snapshot / service 重叠的未提交改动；不 stash / reset / 覆盖其工作。等待目标改动提交后执行本地合并和集成验证，不推远端。

### 关键路径

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/LockedUseStateMachine.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/LockedUseDiagnostics.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/LockedUseTests.swift`
- `experiments/LockedUse/`
- `scripts/build-locked-use-plugin.sh`
- `scripts/manage-locked-use-probe.sh`
- `docs/locked-use.md`
