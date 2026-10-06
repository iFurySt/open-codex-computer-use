# macOS Locked Use

## 目标与边界

用户显式安装并授权客户端后，普通 OCU GUI 调用在已登录会话锁定时自动进入临时解锁、全显示器遮蔽、AX / ScreenCaptureKit / 输入控制模式。turn-ended、断开、30 秒空闲或本地输入触发撤销许可和重锁。仅 macOS；首次启动 / FileVault / 用户切换不在范围。

## 实施门槛

1. 在可恢复测试环境验证真实 SecurityAgent 插件加载和 loginwindow 解锁事务。
2. 证明先建立显示器、输入和独立 watchdog 保护，再允许解锁；组件死亡和显示器重配置不得继续动作。
3. 验证正常密码 / Touch ID 解锁与 login / Data Protection Keychain 不受影响。
4. 可以先开发 Broker、guardian 和客户端登记等组件；生产启用必须等以上实测通过。未验证的 backend 必须 fail closed；不能以 AuthorizationCopyRights 返回成功伪装桌面已解锁。

## 当前实现切片

- [x] 只读原生会话、权限、安装及兼容性诊断，CLI / doctor 入口。
- [x] 可注入的保护状态机和回归测试：一次性许可、确认解锁、所有者、超时、接管、重锁确认。
- [x] 独立 Authorization 插件实验源码与无安装构建；仅支持 preflight 机制，始终拒绝授权。
- [x] 默认 GUI 边界对锁定 / 未知控制台状态明确拒绝，避免旧 snapshot 继续输入。
- [x] Swift / JS / GUI smoke / 插件构建验证与文档同步。
- [x] 独立 deny-only right 的管理员实机加载 / 调用 / 卸载探针。
- [x] 独立 Shield Guardian / watchdog rehearsal、受控 AX / SCK capture fixture、只读 loginwindow 结构探针和交互式恢复 controller。
- [x] 独立 15 秒遮罩倒计时 preview；两块物理显示器覆盖、倒计时和退出由用户确认，WindowServer 检查持续通过。
- [x] 遮罩期间受控 fixture 的 AX / SCK 实机闭环与 15 秒租约重锁日志验证。
- [x] 动作测试的两块物理屏幕持续遮蔽及正常手动解锁确认。
- [x] 本地鼠标输入接管专项验证：立即停止、确认锁定后撤罩，用户正常解锁。
- [x] 独立 watchdog 主线程卡死故障恢复软件专项验证。
- [x] watchdog 测试的物理屏幕持续遮蔽 / 正常解锁确认。
- [ ] 组件死亡与显示器变化故障验证。
- [x] 内核 audit-token / 动态签名认证、root 批准记录读取与短期一次性 permit registry；签名 / 角色实机自检与离线策略回归。
- [x] 保留现有认证 fallback 的离线安装规划；拒绝不同阈值、规则变化与篡改备份，未执行系统写入。
- [ ] 真正 loginwindow 解锁、独立保护与 Keychain 保持实验（阻塞生产 backend 开放）。
- [x] 签名 Broker 控制面、限定角色 IPC、remote 插件一次性放行与锁屏 Guardian 接入；离线验证通过，已安装验证 profile，真实许可消费与 SetResult(Allow) 已通过，解锁切换被严格遮罩尺寸检查中止；完整 GUI 闭环仍未通过。
- [x] 管理员安装 / 卸载入口、同团队原生客户端登记与 OCU 自动租约接入；已编译，系统验证 profile 安装与卸载已通过。
- [x] JS reset / timeout / EOF 停止通道与独立 Keychain 自有测试项 API。
- [x] 安装失败恢复入口、Broker 崩溃 journal / 双 Guardian release ACK、同团队原生客户端登记和验证转生产入口；离线通过，系统效果待实测。
- [ ] 真实安装 / 恢复、故障注入、升级失效与生产 promotion 验证。
- [ ] 真实自动解锁、Secure Input 硬件输入与 Keychain 保持验证。

## 环境观测

当前只读观测为 Apple Silicon / macOS 26.5.1。初始系统已有 Codex 的 screensaver remote rule / Authorization 插件，用户关闭后已确认移除。开发在独立 worktree；用户完成 Codex 插件清理后，通过系统管理员授权窗口运行了独立 deny-only right 的安装 / 卸载实验；不触碰 screensaver 链路，没有触发锁屏或读取凭据。不保存用户名、证书身份、本地绝对路径或原始日志。

## 验证

- swift test（保护状态机 / CLI / session gate）
- swift build
- node --test scripts/node-repl/*.test.mjs
- ./scripts/run-tool-smoke-tests.sh
- ./scripts/build-locked-use-plugin.sh（仅输出隔离构建产物）
- open-computer-use locked-use status --json（不授权、不安装、不解锁）

## 已知风险与来源

Apple DTS 确认过 screensaver authorization plugin 的 Data Protection Keychain 问题 FB13128730；当前系统上的已知症状不能当作本实现已安全的依据。保留 use-login-window-ui，不改旧式认证 UI，不伪造密码上下文，不关闭 SIP / Library Validation。

- https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins
- https://developer.apple.com/documentation/security/authorizationcopyrights(_:_:_:_:_:)
- https://developer.apple.com/library/archive/samplecode/NullAuthPlugin/Introduction/Intro.html
- https://developer.apple.com/forums/thread/796487
- https://github.com/VenusOne-Lee/DispatchShield
- https://github.com/trycua/cua/issues/1744 （方案讨论，非完整可复用实现）

## 合并

2026-10-05 用户明确要求先保留开发 commit，所有实现与验证完成后才一次性合并到 awesome-extension；不提前合并任何实现切片。

基于本地 awesome-extension 的已提交状态。另一个会话有未提交的虚拟显示器工作；不 stash / reset 该会话。合并前再次检查目标工作区，只有不覆盖其改动时才在本地合并；不推远端。

## 进度记录

- 2026-10-05：继续下一阶段的安装边界，新增 LockedUseAuthorizationRules 与 7 项离线回归；保留原生 / Platform SSO rule 名称及顺序，只对现有 OR policy 插入本项目 branch，恢复前拒绝第三方语义变化与篡改计划。重新核对 Apple GetSessionId 为 opaque 认证事务 ID，不能冒充内核 audit session。当前系统 rules 仅只读检查，未安装生产 Broker 或自动解锁机制。

- 2026-10-05：watchdog 第二次实机测试软件通过：受控 AX / SCK 成功后 Guardian 主线程实际卡死约 5 秒；恢复时系统已锁定，privately inherited pipe 收到 watchdog 的重锁请求回报，再由原 session 锁定策略释放遮罩。不是 Guardian 在恢复后才完成锁定；用户确认没有露出桌面、手动解锁正常。没有自动解锁。卡死与进程死亡是不同故障；后者尚未验证。

- 2026-10-05：首次 watchdog 注入测试在启动约 0.4 秒时先发生 guardianFailure，未执行卡死注入；结果明确失败，controller 恢复路径观测系统锁定。补充 coverage 失败细项、tap disable 原因、Secure Input、watchdog pipe / heartbeat age 埋点后再定位，不能将这次提前重锁当作 watchdog 故障验证成功。

- 2026-10-05：输入接管专项测试：用户在倒计时约剩 10 秒时轻微移动鼠标，global mouseMoved 触发 localInput，约 90 毫秒后观测原会话锁定，再释放遮罩。用户确认接管与正常手动解锁。新增独立 watchdog 主线程 5 秒卡死注入入口；必须看到 watchdog 私有管道重锁请求回报且 Guardian 恢复前已锁定才能通过。

- 2026-10-05：多次人工 rehearsal 观测到真实系统锁屏并由用户正常解锁；其中一次同进程后台 AX 调用触发 MainActor 断言退出，已改为 MainActor AXPress 并通过独立自检。controller 异常路径先保留 watchdog / 请求确认重锁，再清理测试进程组。其他短暂遮罩测试有 mouseMoved 接管事件，不能直接归因于真实鼠标移动或宣称持续遮蔽通过。
- 2026-10-05：按用户要求拆出不锁屏、不执行动作的独立 preview，复用相同遮罩实现，增加倒计时、单调时间、每秒 coverage / 输入类型汇总。两块显示器持续约 15 秒软件覆盖检查通过，无输入事件；用户确认两块物理屏幕完整遮住、倒计时正常、结束恢复桌面。此结果仅覆盖遮罩预览，不证明锁屏解锁或动作闭环。修改后完整 Swift 206 项、1 项跳过、0 失败。
- 2026-10-05：用户保持输入静止后的受控动作 rehearsal 日志通过：同进程 AXPress counter 0→1，SCK 捕获被遮挡窗口预期蓝色内容并验证动作前后图像不同；guardian / watchdog 心跳持续健康，约 15 秒 leaseExpired 后观测同会话锁定再释放遮罩。用户确认两块物理屏幕始终遮蔽、未露出桌面或 fixture、手动解锁正常。没有执行自动解锁。新增 4 项离线 controller 回归验证异常 / 超时恢复顺序、preview 不请求锁屏与锁定会话不启动。

- 2026-10-05：创建隔离 worktree，基于本地 awesome-extension 已提交状态；未复制另一个会话的未提交代码。
- 2026-10-05：用户已在应用关闭 Codex Locked Use；只读检查证实其 bundle 和 screensaver remote rule 已清理，screensaver 保留 use-login-window-ui。
- 2026-10-05：20 项保护策略测试、完整 Swift 188 项测试（1 项 gated live test 跳过）、Node 21 项测试和 fixture / cursor smoke 通过。系统 Node 动态库损坏，Node 测试使用应用提供的 bundled runtime，不修改系统安装。
- 2026-10-05：插件离线 ABI probe 通过。新增只注册独立 deny-only right 的可审阅管理员实验脚本；终端 sudo -n 显示需要密码，尚未执行系统安装或真实解锁。
- 2026-10-05：macOS 26.5.1 的 CGSession dictionary 不提供 console-set key，改用公开 SessionGetInfo 的 audit-session identity，并校验当前 on-console、login-done 与 UID；新增缺字段和 session mismatch 回归。
- 2026-10-05：补充取消 / 排空 barrier。原锁屏仍可见不能提前解除遮蔽；Broker 确认许可撤销、解锁与动作排空后，再确认锁定。
- 2026-10-05：通过 macOS 管理员授权窗口安装独立签名 probe，修正 codesign inline requirement 必须使用 `=` 前缀的校验格式。4 次 AuthorizationCopyRights 返回预期 denied；SecurityAgentHelper 的固定日志确认实际机制调用。首次出现 Library Validation 错误后同一 helper 仍执行机制，记录这一行为，不将单条加载错误或 denied 返回当作唯一判据。
- 2026-10-05：实验完成后卸载独立 right、原 bundle 和自身 staged 副本；核对 screensaver right 与实验前一致。真实解锁 / Keychain 与生产 Broker / guardian 仍未完成。
- 2026-10-05：用户要求继续完成并同意配合锁屏测试。新增独立 Guardian 与独立 child watchdog；只在显式 rehearsal 中拦截输入和请求重锁，不解锁、不改系统认证规则。实际 desktop / Secure Input / 显示器覆盖仍待物理观察。测试 controller 可从工具侧结束自身进程组恢复操作，该恢复只用于开发，不能视为生产遮蔽保证。
- 2026-10-05：待用户确认首次 15 秒测试时间；测试同时验证遮挡的专用窗口经 AX 改变并经 SCK 捕获，重锁后只读检查 loginwindow 结构。真实 unlock trigger 不能根据猜测的 AX 控件或授权返回值实现。
- 2026-10-05：完整 Swift 206 项（1 项 gated live test 跳过）、fixture / cursor smoke 通过。签名 Guardian 的内核身份、批准角色、错误 signer / role 及 debug-injectable 副本拒绝均验证；批准文件拒绝 extended ACL 写授权。没有触发真实锁屏；生产 Broker IPC、客户端登记与实际 unlock backend 仍待完成。

- 2026-10-05：新增有界 framing / 绝对 RPC 超时、动态 audit token 与签名重校验的 Broker 服务和 remote 插件；授权放行与实际 GUI 可用状态分离，取消后等待解锁事务和动作排空才释放。Guardian 增加锁屏 AXConfirm 与只观察活动的 IOHID 输入保护；Secure Input 下的硬件事件交付仍需实机确认。完整 Swift 222 项、1 项跳过、0 失败；签名插件 ABI 拒绝 / 重复 / 取消回归通过。未安装生产服务、未更改 screensaver right。

- 2026-10-05：补齐固定已安装位置的签名 native Installer、原客户端 socket 的 SCM_RIGHTS 内核验证、连接级动作 / 排空、JS reset / timeout / EOF 终止旧 native epoch；新增 root boot-bound crash journal、严格旧 peer 重连及主 / watchdog 保护释放 ACK。Broker 策略被更改后撤销新许可但保留恢复通道。
- 2026-10-05：独立 watchdog 增加备用遮罩、tap 和硬件活动观察；准备阶段必须收到 child 的独立健康回报。新增固定真实 GUI / 自有 Keychain 验证、root 验证记录及管理员认证的 promotion 入口。缺少匹配 OCU 的 provisioning profile，Data Protection Keychain 尚未测试；构建已支持受限自有 group。
- 2026-10-05：Swift 234 项、1 项跳过、0 失败，Node 24 项通过，fixture / cursor smoke 和签名 remote ABI 通过。未锁屏的 legacy Keychain 自有项目 prepare / read / cleanup 通过；真实 native AX / SCK preflight 因新隔离 app 权限缺失被拒绝，不能报告通过。发现并修复懒初始化启动时间导致复用旧 agent 的问题，构建增加唯一标识。已打开权限引导，等待用户配合；尚未安装自动解锁 profile。

- 用户完成隔离 app 授权并重启验证实例后，固定独立 native fixture 的真实 AXPress、计数器变化、前后 SCK 图像变化及 legacy 自有测试项通过；没有执行锁屏或自动解锁，测试项已清理。

- 首次系统验证 profile 安装与安全卸载成功，screensaver 的原 fallback 保留并恢复。发现管理员 staging 的 umask 077 使系统 namespace 不可供用户遍历，已修正为明确的系统目录权限；锁屏测试在启动前退出，没有尝试解锁。恢复 / 验证记录改为从创建起 0600、清除继承 ACL、原子替换和 fsync，不先公开再 chmod；增加继承读取 ACL 和不可信目录回归。修正版已完成管理员认证和重新安装。

- 修正版系统目录可遍历、客户端批准及认证策略完整性诊断通过。第一次真实锁屏事务在 preparing 阶段因独立 watchdog 未完成健康注册中止，未发出解锁许可；用户正常解锁。补充 watchdog 停止原因及 Broker 注册诊断。会话门单测以受控 validator 隔离系统安装状态；完整 Swift 236 项、1 项跳过、0 失败。

- 真实锁屏复测定位独立 watchdog 的 `shieldNotInWindowServer`，Broker 注册本身成功；未放行解锁。主 / 备用遮罩增加公开 AppKit `canBecomeVisibleWithoutLogin`；主遮罩锁屏覆盖检查通过，备用进程补齐 `finishLaunching` 与首帧 RunLoop 绘制后待实测。

- watchdog 首帧健康检查新增独立、不锁屏的 surface self-test。实测缩放后的窗口矩形与完整显示器不同；禁用 NSWindow 出现动画后自检通过。全屏窗口禁用 AppKit frame constraint，并增加真实矩形诊断。控制器支持观察正常手动解锁替代 stdin 确认，遵循用户固定解锁节奏；不以等待时间当作解锁证据。

- 双保护真实锁屏准备检查已通过，Broker 进入 authorizing；解锁触发未找到可提交 AX secure field，实际会话保持锁定，保护正常收束。加入有界 AX publication 等待与仅结构的诊断，尚未证明自动解锁。

- 后续固定 Return 提交实验没有证明自动解锁，Broker RPC 超时后未收到 agent 排空 ACK，导致双保护反复请求锁定并阻碍用户登录数分钟。已停止真实锁屏实验、卸载组件并恢复原认证规则。新增停止重复锁屏、独立 agent 准备 / 清理 deadline 与排空日志；先验证无锁屏故障链路和恢复时延，再恢复实机测试。准备期限 8 秒、停止期限 5 秒只约束 agent 退出，不代表全系统恢复期限已经验证。

- 参考用户提供的锁屏方案后，移除主动账户选择、AXConfirm 与固定 Return，改为双保护准备后的单次公开显示器唤醒，随后等待系统认证与实际解锁证据。新增独立 display-sleep assertion；不把唤醒等同于授权成功。资料中的返回码、Keychain 保证、AX 树绝对断言和提前撤罩顺序不能直接采用。
- 将 AuthorizationRightGet 移出 Broker 协调队列；签发 / 消费只接受有界新鲜策略观察，超时拒绝新许可而保留清理通信。新增只限验证 profile 的 recovery-only 事务，准备双保护后在签发任何许可前主动停止并检查双方释放 ACK；下一步先实测此链路，再验证自动解锁。

- 第一轮恢复专项约 3.1 秒清理，两个保护进程均退出，随后观测正常手动解锁；但备用进程注册前准备计时已到期，不算完整双保护通过。修正准备期与运行期心跳计时边界；准备总期限仍为 8 秒，Guardian 等待独立子进程就绪最多 3.5 秒。新增 root recoveryProbePrepared 证据和启动失败不能假报成功的回归。

- 修正版 recovery-only 实机通过：备用进程完成 root 注册，主保护报告 shieldReady，Root 记录双方就绪后主动停止；约 2.0 秒收到动作排空、实际锁定与双保护释放证据。检查保护进程已退出，并观测用户正常手动解锁。没有签发任何解锁许可，未执行 GUI / Keychain 动作；下一轮仅测单次唤醒和立即重锁。

- 2026-10-05：按更新参考实现 identifier-only、有界固定 AXValue 可写性探测；不读密码、不发送认证动作。新增取消 / 在途写入排空回归；完整 Swift 249 项，跳过 1 项，0 失败。快速控制器在真实 GUI 验证后立即重锁、等待双方释放，并保存不含原始日志 / 字段 / 图像的私有诊断时间线。自动解锁与完整生产验证仍待实测，尚未合并。

- 2026-10-05：首轮快速真实流程找到 14 节点、唯一 FocusedUser，但预查询不可写而未执行固定值探测，未触发机制 / 自动解锁；失败后进入 awaitingManualUnlock、双方保护退出。移除将可写性预查询作为写入前置条件的差异，保持其仅作诊断；实际写入仍仅限固定 AXValue、取消与同会话检查。

- 2026-10-05：第二轮固定 AXValue 实际写入返回成功，但未触发认证机制 / 自动解锁；约 6.6 秒保护事务失败结束，控制器确认双保护释放。正常手动登录中的 Broker 校验出现 -67061；另一个不锁屏、无租约的 remote-only 探测中全部签名校验成功，Broker 正确拒绝无许可 claim。暂不能归因于签名材料本身，需继续核对认证宿主环境与认证发起时序。新增独立不锁屏诊断入口，Python 报告过滤 4 项通过。尚未完成 / 合并。

- 2026-10-05：核对两级认证规则、4-byte length + JSON 协议与显式 SetResult；独立 remote 分支在真实 SecurityAgent 已可达。新增 macOS 14.4+ public SecTask / ProcessCodeRequirement 验证，签名类别 + 固定 ID / Team + 动态有效 / runtime / LV + 注入 entitlement 检查，不做 identifier-only 放宽。独立签名合法 / 错误 ID / ad hoc / get-task-allow 正反检查与原 ABI 通过；Python 白名单报告 6 项通过。
- 2026-10-05：实机裁决链第一次通过：同 audit session claim 成功、consume 返回 authorized、SetResult(Allow) 返回成功；约 1 秒后因遮罩尺寸缩为 90% 而 guardLost，中止重锁并确认双保护退出。正常手动解锁与自有 Keychain 清理通过。仍不能记作完整 GUI 闭环通过；遮罩改为 nonactivating NSPanel，等待切换复测。

- 2026-10-05：nonactivating NSPanel + 主屏蔽层级 +1 的不锁屏 surface 自检通过；完整 Swift 249 项、1 跳过、0 失败。下一轮真实切换仍待系统管理员完成旧验证版卸载认证后安装新版，不将尺寸自检记为解锁切换覆盖证明。

- 待查：独立诊断中的合成 PID-version 实验发生进程退出未完成，已撤销该注入用例；生产前仍必须覆盖真实 Broker 死亡 / socket token 过期时 verifier 和认证宿主的有界恢复。合法 / 错误身份 / ad hoc / debug 的实际签名测试通过。

- 2026-10-05：新版 NSPanel 的真实快速闭环复测未自动解锁。双保护准备成功；单次显示器唤醒与固定 AXValue 写入成功，但整个 5 秒 authorizing 窗口没有机制调用，随后 unlockTimeout。锁定观测后约 7.1 秒确认双方释放。正常手动登录时机制调用、现代签名验证成功，过期 claim 被拒绝，原系统 fallback 成功；自有 legacy 测试项验证与清理通过。这轮没有进入 active / native AX-SCK，不能证明 NSPanel 在自动解锁切换时的覆盖修复。下一步定位系统认证事务启动时机差异，不能靠延长许可或重复锁屏宣称修复；生产仍关闭，尚未合并。

- 2026-10-05：复核新认证时序资料与本机 Guardian build 1001365，发现参考路径实际写空字符串、AXValue 是属性名，并调用 SynthesizedEvent.click / send；未确认 Return 或真实认证效果，未照搬到日常账户。历史 SetResult(Allow) 不排除人工认证重叠，不能算自动唤醒成功。新增锁屏前只读实时白名单采集、schema 2 许可 / 手动恢复分窗和不锁屏被动入口，缺失日志不证明缺失事务。遮罩使用 Quartz 全局坐标完整包含，仍拒绝任何未覆盖边缘和 90% 缩小。Swift 251 项（1 跳过、0 失败）、Python 报告 10 项 / rehearsal 5 项、签名组件 / ABI / 内核签名正反例、不锁屏 surface 自检通过；被动采集完成。本轮没有安装 / 真实解锁；新认证路径的 Keychain 可用状态尚待验证（后续复核纠正了重设归因）。生产关闭，未合并。

- 2026-10-05：用户要求按官方 API 复核 Keychain 风险。纠正此前错误归因：上游 #40226 是插件介入后的会话级访问失败，明确排除文件损坏并称重启恢复，没有空输入或重设证据。SetResult 只定义授权结果；Apple 公开 Security 源码区分登录处理与显式重设，不能当作当前 loginwindow 完整调用链。同步修正文档，将隔离环境明确为开发建议而非 API 要求；本轮无代码或系统认证变更。

- 2026-10-05：用户批准当前账户短测试，重新打包 / 管理员安装后运行 wake-only 基线，未加入空输入 / 点击 / Return，不创建 Keychain 测试项、不执行 GUI 动作。双保护成功准备；5 秒 authorizing 窗口内未观察到 screensaver right 求值或机制调用，AX 扫描只有根节点且不完整，未写固定值；unlockTimeout 后锁屏观测至双方释放约 7.9 秒。后续 Touch ID 人工登录出现 right 求值、签名验证通过、过期 claim 拒绝 / SetResult(Deny) 成功、原系统 right 成功。约 27 秒确认会话正常解锁；并无自动解锁成功证据。测试后成功卸载 / 恢复原策略，保护和 Broker 退出。采集过程中实时 / 历史日志重复阶段，修复 authorizing 重复开窗并新增回归；Python 报告 11 项、rehearsal 5 项通过。后续仍需定位 AX 发布时序并验证真正的认证入口，生产关闭，未合并。

- 2026-10-06：用户要求在当前账户持续实测迭代，不再重复未修改基线。验证入口改为 3 秒内重试完整 AXIdentifier 扫描，找到唯一候选后写空字符串，再尝试一次 FocusedUser AXPress；保留签名、同会话、取消 / 在途排空和 5 秒许可，不读取字段、不发送 Return。首轮在 preparing 因 physicalInput 收束，锁定观测后约 1.6 秒确认双保护释放；认证动作尚未执行，正常手动解锁通过。复测 readiness 在锁屏前因 Broker RPC 超时拒绝，未再次锁屏。补充原客户端死亡 / socket EOF 检查，先拒绝失效 SCM_RIGHTS 连接再签名重验；原因尚待重装实测确认。签名组件 / app 构建与 ABI / 内核身份正反例通过，Swift 251 项（1 跳过、0 失败）、Python 报告 11 项通过。正在等待系统管理员卸载认证；不得将本轮计为自动解锁或新认证入口验证成功。

- 2026-10-06：重装后实测完整 AX 树 14 节点、唯一 FocusedUser，空字符串写入成功；AXPress 返回 actionUnsupported（-25206），5 秒许可窗没有认证求值 / 插件调用，双方保护释放和正常手动解锁通过。恢复后的 readiness 仍超时，原客户端断开检查没有证明已解决该问题。下一版实测 public CGEvent 目标进程点击已发送，但仍未观察到认证；未将 queued 当作投递成功或自动解锁。继续加入一次目标进程 Return（不含密码）及 Broker observer 各阶段固定日志，待验证。组件 / app 签名构建及 ABI / 内核身份正反例通过，Python 报告 12 项通过。生产保持关闭，尚未合并。

- 2026-10-06：保护待命与许可签发分离：首次已认证插件 claim 才签发，许可 deadline 不超过原 8 秒启动上限。原等待版本实测没有机制，agent 的同刻 8 秒退出造成报告失败；修正为 8 秒启动 + 2 秒 RPC 排空余量，控制器容忍已退出 stdin 的 BrokenPipeError。Swift 253 项（1 跳过、0 失败），Python 报告 13 / controller 1 / rehearsal 5 项通过，签名组件 / ABI / 内核身份正反例与 app 构建通过。
- 短实测确认失败结果约启动 8.1 秒返回，约 0.3 秒后双保护退出 ACK，正常手动解锁和报告保存通过；没有机制 / 许可 / 自动解锁。一次 annotated-stage 点击因同 PID 几何包含目标不唯一而未发出，改为先匹配 AXWindow 完整几何再确定唯一 CGWindow，拒绝模糊目标。原 postToPid 点击 / Return 实验无认证证据，已撤回。参考 build 动态 CGEventAPI.post 路径支持会话级点击，不能再用零导入证明纯观察；实际认证效果仍未证明。生产关闭，未合并。

- 2026-10-06 后续：AXWindow 完整几何匹配后唯一目标和 annotated-stage queued 已实测，仍无机制；NSEvent.windowNumber 版本也未自动解锁，并出现一次 native RPC 超时，独立只读检查确认会话已解锁、保护已退出，但未取得该轮退出 ACK，不能算恢复验证通过。补齐 timer phase 与慢签名检查日志。
- 新增会话入口的一次性点击能力：独立随机标记经继承管道共享，双过滤器验证 Guardian 来源、有序同窗口 / 坐标点击、5 秒能力 / 250ms 配对；硬件接管与停止撤销，不使用 PID-only 豁免，标记不落日志。离线 Swift 257 项（1 跳过、0 失败）、报告 14 项、controller 1 项 / rehearsal 5 项通过，签名 / ABI / 内核身份正反例通过。第一轮点击被 watchdog 拒绝，约启动 2 秒收束并确认双保护退出 / 手动解锁，未证明跨过滤器投递；补充固定拒绝枚举并为 NSEvent 的 CGEvent 显式指定私有 source，待复测。生产关闭，未合并。

- 事件 source 复测仍由 watchdog 在 flags 检查处拒绝，未观察到一次放行。双保护退出 ACK 与正常手动解锁通过。将过严的所有 flags 为零检查收敛到四个会改变左键语义的键盘修饰键，保留能力 / 来源 / 几何 / 顺序 / 时限，并只记录整数 flags 与固定拒绝枚举，待投递复测。

- 2026-10-06：会话点击经过双过滤器放行已实测（down/up 均有 main / watchdog 记录），flags=0x20000000，四个点击修饰键为零；仍未见机制，约 8.6 秒后双保护退出 ACK / 正常手动解锁通过。参考进一步静态复核定位 CGEventSetWindowLocation 与 mouse subtype=3；本项目补齐编码，并在原 3 秒唤醒预算内有界重新扫描点击后出现的密码字段，不二次点击。
- 结合用户的待命建议，显式验证 profile 改为 20 秒总等待，双保护准备仍限于 8 秒；插件首次 claim 才签发最多 5 秒许可，截止裁剪到本轮起始 deadline。Root 的绝对 uptime 截止经 IPC 与继承管道传给 agent 和双遮罩，统一倒计时，agent 只增加既有 2 秒 RPC 排空余量。默认 profile 不变。新增晚到 claim、20 秒过期不可重启、待命时本地输入撤销回归；Swift 260 项（1 跳过、0 失败）、报告 14 / controller 1 项通过，签名组件 / ABI / 内核身份正反例与 app 构建通过。系统安装等待管理员认证；新的 20 秒 / 编码路径尚未实测，生产关闭，未合并。
