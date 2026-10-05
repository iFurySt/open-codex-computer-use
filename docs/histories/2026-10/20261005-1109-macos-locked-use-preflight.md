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

### Guardian 实机调试补充

- 用户配合进行了锁屏 rehearsal。会话观察确认真实系统锁定，随后用户正常认证解锁；带提示文字的黑屏是 Guardian 遮罩，系统认证页面是原生锁屏。
- 部分测试因启动阶段 mouseMoved 接管而很快重锁。增加事件类型、source PID / state、capture 阶段、stop reason 和单调时间；不读取或保存按键内容，来源字段本身不足以区分真人与系统事件。
- 同进程 fixture 的后台 AXPress 引发 AppKit / MainActor 断言退出；改为 MainActor AXPress，独立自检验证 counter 变化。开发 controller 不再在 guardian 异常退出时立即终止 watchdog，先请求 / 观察重锁再清理测试进程组。
- 按用户要求先拆出纯遮罩 preview，复用同一覆盖实现，显示 15 秒倒计时，Esc 退出；不执行 AX / capture，不请求锁定或解锁。两块显示器持续约 15 秒 WindowServer 覆盖检查通过且无输入事件；用户确认两块物理屏幕完整覆盖、倒计时正常、结束正常恢复桌面。
- 修改后完整 Swift 206 项、1 项 gated live test 跳过、0 失败。
- 用户保持输入静止后的受控动作 rehearsal 验证通过：AXPress 使 counter 0→1，SCK 捕获被遮挡窗口的预期蓝色内容，动作后图像不同；guardian / watchdog 健康，约 15 秒 leaseExpired 后确认真实锁定再释放遮罩。用户确认两块物理屏幕持续遮住、未露出桌面 / fixture、手动解锁正常；没有执行真正自动解锁。
- 新增 4 项离线 controller 回归通过，覆盖异常 / 超时先请求重锁再清理、preview 不请求锁屏、锁定会话不启动 GUI。与物理测试结合，仍不能宣称组件死亡时零泄漏或生产 backend 已完成。

### 接管与 watchdog 故障注入补充

- 用户在约剩 10 秒时移动鼠标，立即 localInput 停止，约 90 毫秒后观测原会话锁定才撤罩；用户确认接管 / 解锁正常。倒计时不是接管等待时间，收到本地输入立即重锁。
- 后续只记录首次 inputTakeover，避免停止后的高频 mouseMoved 刷屏，输入仍持续被过滤。
- 新增显式 `--confirm-watchdog-test`：仅在受控 AX / SCK 验证通过后阻塞 Guardian 主线程 5 秒，依赖独立 child watchdog。增加 request-only 回报，恢复前锁定和原 session 确认的通过门槛；不将普通租约结束当作故障测试通过。该测试不验证进程死亡时零泄漏。
- controller 离线回归现为 5 项通过，包含 watchdog 测试异常恢复顺序。
- 首次 watchdog 实机尝试在约 0.4 秒健康检查失败，尚未执行卡死注入；测试明确失败并经 controller 确认锁定。新增 coverage 具体失败项、tap disable、Secure Input 和 watchdog 心跳 / 管道健康埋点，再定位；不把提前重锁视为故障测试通过。
- 第二次 watchdog 验证通过：受控动作 / 截图验证完成后 Guardian 主线程实际卡死约 5 秒，恢复时 session 已锁定，同时收到独立 watchdog 重锁请求回报；原会话锁定策略随后才释放遮罩。用户确认未露出桌面、手动解锁正常。此通过不追溯解释第一次健康检查失败，也不涵盖遮罩进程死亡 / 热插拔。

### 认证安装边界补充

- 新增纯离线 `LockedUseAuthorizationRules` 安装 / 卸载规划，保留现有 OR fallback、拒绝更高阈值与不兼容格式、重复本项目引用、第三方规则修改和篡改备份。7 项回归通过；没有写入系统认证数据库。
- 沉淀 Apple opaque 认证 session 与内核 audit session 的区别，以及上游 Platform SSO fallback 被替换的机器报告；不把报告当作本机复现或自动解锁通过。
- 完整 Swift 回归现为 213 项，1 项 gated live test 跳过，0 失败；controller 离线回归 5 项通过。

### 本地合并进度

开发提交保留在隔离分支。目标工作区的另一个会话仍有与 app agent、入口、snapshot / service 重叠的未提交改动；不 stash / reset / 覆盖其工作。等待目标改动提交后执行本地合并和集成验证，不推远端。

### 关键路径

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/LockedUseStateMachine.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/LockedUseDiagnostics.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/LockedUseTests.swift`
- `experiments/LockedUse/`
- `scripts/build-locked-use-plugin.sh`
- `scripts/manage-locked-use-probe.sh`
- `docs/locked-use.md`
