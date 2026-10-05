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

## Broker 与 remote 机制实现

新增独立签名 Broker、受角色约束的内核身份认证 IPC、Guardian challenge 和一次性 remote 插件许可。IPC 限制消息 / 排队大小并使用绝对截止时间，重验动态签名身份；放行不等于桌面解锁，动作仍需独立 Guardian 观测和健康证明。取消后不以旧锁屏状态提前撤罩。Guardian 接入锁屏 AXConfirm 和不读取键值的硬件活动监测，后者尚待 Secure Input 实机验证。

验证：完整 Swift 222 项、1 项 gated live test 跳过、0 失败；已签名 remote 插件离线 ABI 验证拒绝、重复调用与取消。系统安装、OCU 租约入口和真实解锁仍在后续计划内，未合并目标分支。

### 原生租约接入与恢复开发

用户要求先提交当前开发，再继续完成全部实现 / 验证，最后一次性本地合并；已有开发 checkpoint，未合并目标分支。补齐签名 native Installer、CLI / settings 的安装 / 停用 / 部分恢复与验证转生产入口，以及 SCM_RIGHTS 原始 CLI 内核身份、app-agent 连接级租约 / 动作排空、客户端 EOF 和 JS reset / timeout 旧 epoch 停止。

root Broker 增加 boot-bound crash journal，回复授权前 fsync，不保存 / 恢复 permit；旧 peer 只能重连接续排空 / 重锁。Guardian / 独立 watchdog 双进程遮罩与输入保护、root 健康回报和 release ACK 防止新租约 / 卸载跨越未释放保护。认证策略改变后撤销本 epoch，新保护健康要求和恢复边界有离线测试。

新增固定真实 AX / SCK fixture 和自有 Keychain probe / 监督式控制器，图片 / 随机值不落盘或输出；完整测试证据由 root 记录并匹配 OS / 组件哈希，生产 promotion 仍要求实测和管理员认证。构建支持匹配 profile 的自有 Keychain group；本机缺少匹配 profile，Data Protection 尚未实测。未锁屏 legacy 自有项目创建 / 读取 / 清理通过；原生 AX / SCK preflight 因新 app 权限缺失被拒绝，已打开引导。修复旧 agent 的启动时间懒初始化，构建 UUID 阻止复用旧代码。

当前完整 Swift 234 项（1 项跳过、0 失败）、Node 24 项、fixture / cursor smoke、签名插件离线 ABI 和 profile 校验测试通过。还没有真实自动解锁、系统 Installer / recovery / promotion、Secure Input 键鼠、进程死亡 / 服务重启 / 显示器变化与完整 Keychain 保持的实测证据；保留生产关闭，不提前合并。

- 用户完成隔离 app 授权并重启验证实例后，固定独立 native fixture 的真实 AXPress、计数器变化、前后 SCK 图像变化及 legacy 自有测试项通过；没有执行锁屏或自动解锁，测试项已清理。

- 首次系统验证 profile 安装与安全卸载成功，screensaver 的原 fallback 保留并恢复。发现管理员 staging 的 umask 077 使系统 namespace 不可供用户遍历，已修正为明确的系统目录权限；锁屏测试在启动前退出，没有尝试解锁。恢复 / 验证记录改为从创建起 0600、清除继承 ACL、原子替换和 fsync，不先公开再 chmod；增加继承读取 ACL 和不可信目录回归。修正版已完成管理员认证和重新安装。

- 修正版系统目录可遍历、客户端批准及认证策略完整性诊断通过。第一次真实锁屏事务在 preparing 阶段因独立 watchdog 未完成健康注册中止，未发出解锁许可；用户正常解锁。补充 watchdog 停止原因及 Broker 注册诊断。会话门单测以受控 validator 隔离系统安装状态；完整 Swift 236 项、1 项跳过、0 失败。

- 真实锁屏复测定位独立 watchdog 的 `shieldNotInWindowServer`，Broker 注册本身成功；未放行解锁。主 / 备用遮罩增加公开 AppKit `canBecomeVisibleWithoutLogin`；主遮罩锁屏覆盖检查通过，备用进程补齐 `finishLaunching` 与首帧 RunLoop 绘制后待实测。

- watchdog 首帧健康检查新增独立、不锁屏的 surface self-test。实测缩放后的窗口矩形与完整显示器不同；禁用 NSWindow 出现动画后自检通过。全屏窗口禁用 AppKit frame constraint，并增加真实矩形诊断。控制器支持观察正常手动解锁替代 stdin 确认，遵循用户固定解锁节奏；不以等待时间当作解锁证据。

- 双保护真实锁屏准备检查已通过，Broker 进入 authorizing；解锁触发未找到可提交 AX secure field，实际会话保持锁定，保护正常收束。加入有界 AX publication 等待与仅结构的诊断，尚未证明自动解锁。

- 固定 Return 提交未证明自动解锁。失败后 Broker 通信超时、agent 排空 ACK 缺失，保护反复锁定并阻碍用户登录数分钟；终止本项目验证 agent 后保护正常收束。已卸载验证组件、恢复原认证策略，并暂停进一步锁屏测试。
- 修复已观测到锁定时仍重复请求锁屏的主 / 备用保护行为；新增独立 agent 准备 8 秒 / 停止 5 秒 deadline，重试不能延长期限，超时只结束自身进程。保留实际锁定、动作和解锁工作排空的释放 barrier，补充排空通信诊断。独立进程主线程故意卡住时按预期退出码 70 自动结束，不调用锁屏或 UI；全系统故障恢复时延仍待验证。
- 完整 Swift 241 项、1 项跳过、0 失败；签名独立进程 deadline、签名 peer identity 和 remote 插件 ABI 检查通过。此次修复没有重新安装组件或执行锁屏测试。

- 参考用户提供的锁屏方案后，移除主动账户选择、AXConfirm 与固定 Return，改为双保护准备后的单次公开显示器唤醒，随后等待系统认证与实际解锁证据。新增独立 display-sleep assertion；不把唤醒等同于授权成功。资料中的返回码、Keychain 保证、AX 树绝对断言和提前撤罩顺序不能直接采用。
- 将 AuthorizationRightGet 移出 Broker 协调队列；签发 / 消费只接受有界新鲜策略观察，超时拒绝新许可而保留清理通信。新增只限验证 profile 的 recovery-only 事务，准备双保护后在签发任何许可前主动停止并检查双方释放 ACK；下一步先实测此链路，再验证自动解锁。

- 第一轮恢复专项约 3.1 秒清理，两个保护进程均退出，随后观测正常手动解锁；但备用进程注册前准备计时已到期，不算完整双保护通过。修正准备期与运行期心跳计时边界；准备总期限仍为 8 秒，Guardian 等待独立子进程就绪最多 3.5 秒。新增 root recoveryProbePrepared 证据和启动失败不能假报成功的回归。

- 修正版 recovery-only 实机通过：备用进程完成 root 注册，主保护报告 shieldReady，Root 记录双方就绪后主动停止；约 2.0 秒收到动作排空、实际锁定与双保护释放证据。检查保护进程已退出，并观测用户正常手动解锁。没有签发任何解锁许可，未执行 GUI / Keychain 动作；下一轮仅测单次唤醒和立即重锁。

- 2026-10-05：按更新参考实现 identifier-only、有界固定 AXValue 可写性探测；不读密码、不发送认证动作。新增取消 / 在途写入排空回归；完整 Swift 249 项，跳过 1 项，0 失败。快速控制器在真实 GUI 验证后立即重锁、等待双方释放，并保存不含原始日志 / 字段 / 图像的私有诊断时间线。自动解锁与完整生产验证仍待实测，尚未合并。

- 2026-10-05：首轮快速真实流程找到 14 节点、唯一 FocusedUser，但预查询不可写而未执行固定值探测，未触发机制 / 自动解锁；失败后进入 awaitingManualUnlock、双方保护退出。移除将可写性预查询作为写入前置条件的差异，保持其仅作诊断；实际写入仍仅限固定 AXValue、取消与同会话检查。

- 2026-10-05：第二轮固定 AXValue 实际写入返回成功，但未触发认证机制 / 自动解锁；约 6.6 秒保护事务失败结束，控制器确认双保护释放。正常手动登录中的 Broker 校验出现 -67061；另一个不锁屏、无租约的 remote-only 探测中全部签名校验成功，Broker 正确拒绝无许可 claim。暂不能归因于签名材料本身，需继续核对认证宿主环境与认证发起时序。新增独立不锁屏诊断入口，Python 报告过滤 4 项通过。尚未完成 / 合并。
