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

- 2026-10-06：20 秒窗口 / 私有窗口坐标编码实测：双过滤器放行 down/up，点击约 200ms 后重新扫描出现唯一 UserPasswordTextField，可写且空写成功；启动约 20 秒后 unlockTimeout，未观察到机制 / 许可。双方释放 ACK 约失败后 0.15 秒，随后 Touch ID 手动解锁触发真正的 right 求值与 remote 机制；此时 Broker 已 awaitingManualUnlock 并正确拒绝，不算自动解锁。修复测试控制器复用旧常驻 agent 的问题，每轮采用新独立 namespace。当前瓶颈是可交互密码 UI 到授权链之间，非 5 秒许可提前过期或 guardLost。
- 下一验证版仅管理员验证 profile 在唯一真实密码字段支持 AXConfirm 且空写成功时尝试一次确认；Root hello 显式传递开关，默认与旧协议关闭，未知动作不盲试，不合成全局 Return。新增固定布尔 / OSStatus 日志；同时修复报告 PATTERNS 重复 Watchdog 键覆盖导致部分退出原因丢失。待签名构建与实际测试，不作为成功证据。

- 确认实验离线验证：原完整 Swift 260 项（1 跳过、0 失败）通过；新增验证 profile / Guardian 身份 / 旧协议开关回归后 coordinator 10 项通过。报告 15 项与控制器 1 项通过，签名组件、插件 ABI、内核身份正反例和 app 构建通过。旧系统验证版已卸载并恢复原规则，新版正在安装；实际 AXConfirm 结果仍待验证。

- 确认实验实测：点击后约 200ms 唯一真实密码框出现；空写成功，字段明确支持 AXConfirm，单次 AXConfirm 返回 success。仍等满原 20 秒截止，没有观察到 right 求值 / 机制 / 许可；失败后约 0.17 秒确认双保护释放，随后用户 Touch ID 解锁才出现 right 求值与 remote 机制。Root 此时正确拒绝过期 claim，普通解锁成功。不可把本轮算作自动解锁；后续关键未知是无用户凭据条件下 loginwindow 如何进入 screensaver right 求值，不再仅延长等待或重复等价 UI 动作。只读检查参考 InstallerTool / service 未找到 screenUnlockMode 字符串（不证明完整实现不存在间接路径），本机该偏好未设置。实验结束已卸载并恢复原认证策略；生产关闭、尚未合并。

- HID 单变量实验：用户授权尝试仅将受控 down/up 投递从 session 改到 HID；复用已认证 Root 的验证 profile 开关，生产 / 旧协议保持 session。事件字段、双会话过滤的一次性能力、硬件活动接管、空写 + 单次支持确认、20 秒截止不变。新增固定 clickTap 枚举日志；此改动不保证被系统视作真实硬件或启动认证，待实测。

- HID 实测已完成：明确 clickTap=hid，双 session 过滤器放行同一对 down/up；点击后先短暂 AX 发布不完整，再出现唯一真实密码框，空写成功且声明支持 AXConfirm，但单次确认返回 cannotComplete (-25204)。20 秒截止内无观察到的 right 求值 / 机制 / 许可 / 自动解锁；失败后约 0.22 秒收到双保护释放 ACK，用户随后正常手动解锁才触发 remote 机制。不能宣布 HID 活动假设成立，或仅凭此轮失败排除所有 HID 路径。完整 Swift 261 项（1 跳过、0 失败）、报告 15 项通过；签名 / ABI / 内核身份正反例和 app 构建通过。未合并，生产关闭。

- 本轮 HID 实验卸载完成，只读复核 screensaver 原认证规则已恢复。

- 确认超时修正：扫描给候选 AX 对象设置的 50ms 消息超时会被后续 action 沿用。Apple AXUIElementPerformAction 文档明确 cannotComplete 可能源自超时 / 模态处理，但不能仅据错误码确认因果或动作未执行。session 轮先前已执行同一确认并返回成功，不是 HID 轮首次加入。验证版为单次确认独立设置最多 2 秒、裁剪到原 3 秒 UI 请求截止的超时，结束恢复扫描超时；记录配置结果、实际调用开始、调用耗时与结果。不自动重试，避免无法确认是否执行时重复提交。Root 总 20 秒截止、取消 / 排空与双保护不变。待实测比较。

- 超时分离首次实测：2 秒动作超时配置成功，AXConfirm 实际 37ms 返回 success；之后仍未观察到 right 求值 / 机制 / 许可。因此不能确认上一轮 -25204 唯一源自 50ms，也不能以确认返回成功推出认证已提交。本轮总起始约 18.9 秒出现 guardLost，主 Guardian 私有状态持续报告遮罩 / tap / watchdog 健康，收到 root stopRequested 后退出；失败后约 0.25 秒确认双保护释放、正常手动解锁。新增 Broker 两类报告 age / watchdogProtected 固定诊断，进一步区分 IPC 陈旧与真实遮罩不健康；新增只读按钮 enabled 计数与密码框焦点布尔，明确没有收集标题、标识字符串或值。修正等待期间每秒常规 300 秒 active 标签覆盖 20 秒启动倒计时的问题，只有观察到解锁后显示 active 标签。确认只有一次，无模糊结果重试。系统验证版已卸载并恢复原规则，下一诊断版待复测。

- 第二轮 2 秒确认实测：真实密码框 focused=true，扫描按钮 enabled=2 / disabled=0 / unknown=0；AXConfirm 34ms 返回 success，无观察到的认证求值 / 许可。约启动 14 秒 guardLost 的 Broker 固定证据显示 guardian report age≈1570ms / watchdog report age≈1577ms，watchdogProtected=true；本地 Guardian 仍持续健康。不能将本轮归因为动作超时或 UI 未聚焦，Root 失联新鲜度仍待定位。双保护释放与正常手动解锁完成，卸载恢复原认证规则。按用户新要求，暂停受保护复测，下一步独立无遮罩 / 无 watchdog 解锁诊断；不得假造生产 guardsReady、不得执行 GUI 应用动作或签发生产验证记录。

## 无遮罩解锁诊断（仅管理员验证 profile）

用户明确要求拆开解锁与保护问题后，新增独立 `LockedUseUnshieldedDiagnostic`，不复用生产 guardsReady 或 GUI action 状态机。Root 只接受管理员验证 profile 下、已批准签名 UI 探针的原锁定 UID / audit session；诊断总期限 20 秒，插件首次同会话 claim 才签发最多 5 秒且裁剪到原截止的一次性许可。无守护健康 / 心跳条件，也不伪造覆盖证据。断开、认证策略失效、期限到达或许可过期撤销后不能恢复。所有应用 action、生产验证 / promotion 与正常租约入口在诊断活跃时拒绝；重启不恢复任何诊断许可。

签名工具的独立 `--unshielded-unlock-diagnostic --confirm-visible-desktop-test` 入口复用 `LockScreenInteractor`，没有构造 DisplayGuardian、遮罩、输入 tap、硬件 monitor 或 child watchdog。因此桌面若被解锁会实际可见，不能视为生产 Locked Use。它只观察原会话解锁并立即请求 / 确认重锁，最后向 Root 结束诊断；结果与私有报告始终 productionEvidenceEligible=false，不访问应用窗口 / ScreenCaptureKit / Keychain。外部控制器入口为：

```sh
python3 scripts/run-locked-use-unshielded-diagnostic.py --confirm-visible-desktop-test
```

该入口针对人为配合的单次故障定位，没有完整保护路径的进程崩溃与遮蔽保证。实现回归覆盖生产 profile 拒绝、原 session / role 绑定、跨 audit session / 重复 claim / 许可重放、晚到许可裁剪、5 秒过期 / 20 秒过期 / 取消不可重启、非原会话结束与 GUI / 生产验证拒绝。当前 Swift 266 项（1 跳过、0 失败）通过，真实诊断待安装运行。


### 无遮罩实测归因与报告修正

首轮诊断观察到原会话解锁、插件消费许可和重锁，但系统时间线先出现 Touch ID match，约 0.67 秒后才出现 remote mechanism。因此它证明手动认证与待命许可重叠时插件链可完成，不能证明自动解锁；测试后的再次解锁也由用户完成。

修正控制器将原生 stdout 缓冲到进程退出才记录的时间偏差：改为有界逐行读取，以原生 uptime 对齐本轮时间线；修正 trace 清理调用为 finish，确保保存报告。报告增加 authorizing 窗口内 Touch ID 介入标记，拒绝将这类结果当作自动解锁证据；没有该标记也不自动认定为成功。新增 3 项归因回归测试，覆盖窗内 / 窗外 Touch ID 与单独 evaluatePolicy 不能证明人工操作。

第二轮明确不操作鼠标、密码或 Touch ID，无遮罩、无输入过滤、无 watchdog 等满原 20 秒：唯一真实密码框已聚焦，空写成功，单次 AXConfirm 88ms 返回 success，但未观察到认证 right 求值、mechanism、许可消费或原会话解锁。结束后确认原会话锁定、Root 返回 idle。这说明撤掉保护逻辑本身没有解决认证入口；AXConfirm success 不能替代实际解锁证据。生产保持关闭，尚未合并。


### Return 单变量诊断（待实测）

用户提供成功时间线中 secure textfield Return → loginPressed → authBegan → authCopyRights → 插件的链路，作为新的待验证假设。Apple 文档仍将 AXConfirm 定义为模拟 Return，不能据该样本断言所有实现中它只聚焦或按钮永远不能提交；当前系统上的 AXConfirm 实测未产生同样授权链。

仅独立无遮罩诊断改为固定 keyCode 36 的单对 HID down/up，替代 AXConfirm，未加入保护路径。要求同一原锁定会话、完整扫描唯一密码框、空写成功且可写 / focused、Apple loginwindow 签名有效、无 Shift / Control / Option / Command，签名检查后再校验焦点与会话 / 请求截止。私有事件源，无修饰键、重复或文字载荷，派发按下后立即释放，即使期间取消也释放；不重试。Root 20 秒诊断窗口及首次 claim 才发一次性许可不变，观察实际解锁后立即重锁。受保护输入过滤器没有键盘许可，不能直接推广该实验。

新增固定枚举日志 secureReturnObserved / localAuthenticationBegan / loginwindowRightsRequested 与 Return dispatch / queued 标记，不保存 surrounding 账户 / 认证上下文。Swift 编译通过，报告回归 17 项、诊断归因 3 项通过。Developer ID 签名两次返回 errSecInternalComponent，新制品未部署 / 未实测；等待用户恢复系统构建签名私钥访问。旧已签名 components 未替换，生产关闭，尚未合并。


- 签名阻塞追踪：Return 代码已提交 b444978，旧 components 保持原已签名版本。重试默认身份、显式 login 钥匙串与无 timestamp 均失败；只读默认钥匙串状态 flags=7，不能归因为普通锁定。securityd 固定错误码含 errSecAuthFailed / CSSMERR_CSP_OPERATION_AUTH_DENIED；不能据此确定凭据损坏。没有修改私钥 ACL、信任设置、钥匙串文件或生产签名策略，也未发送 Return / 启动锁屏。GUI Terminal 重试被 Computer Use 工具安全限制拒绝，准备私有本机构建签名脚本供用户在 GUI 终端完成；随后再运行真实测试。


### 签名与已安装机制回溯

主 checkout 仅只读核对：Dev App 严格 deep 校验通过、Hardened Runtime、既有签名时间为本地 12:19；不是新的签名成功证据。worktree 最后成功组件签名约 12:42，新 Guardian 首次观察到签名失败约 16:55，中间没有连续签名探测，不能断言故障发生于某一次解锁。隔离 /usr/bin/true 副本（未执行）同一 Developer ID 签名也失败，最新重试仍失败，因此不局限于 Guardian 构建内容或一次偶发错误。

当前 system.login.screensaver OR 首分支和 remote evaluate-mechanisms 仍指向 OCU；安装插件 strict 签名有效、SHA256 与本 worktree 制品一致，安装 Broker 二进制与本地制品一致且运行，未观察到当前被替换。历史 authd 日志本地 15:18 调用了 OCU mechanism，15:30 / 15:31 则调用 CodexComputerUseAuthorizationPlugin；15:31 后 loginwindow SecKeychainLogin 返回 -25293。这证明历史机制确有差异，不证明当前仍被顶掉，也不能仅据日志确定何人或何时改过 policy。钥匙串状态 flags=7 与签名认证失败并存，未更改权限、信任、搜索链或钥匙串数据。需分开验证图形会话认证状态与签名环境，禁止把空值认证导致的普通 keychain login 失败直接判为钥匙串损坏。


### 密码解锁恢复签名与 Return 首轮通过

用户用账户密码正常解锁后，同一 Developer ID 签名命令立即通过严格校验，未修改证书、私钥 ACL、信任、钥匙串搜索链或数据。这支持先前签名认证拒绝与会话认证状态有关，但仍不能将变化唯一归因到 OCU / Codex 某个插件。签名通过的新 UI 探针替换本地 components，未替换系统安装插件。

首次新探针诊断在 beginUnshieldedDiagnostic 被 Root 拒绝、未发 Return。只读回溯证实本地 15:30:12 installationPolicyInvalidated；Broker 对认证策略变化永久关闭该 service epoch 的 accepting，恢复相同规则不能自动重新授权。校验当前规则、安装插件 / Broker 与本地制品一致、无活跃保护后，经 macOS 管理员认证仅 kickstart 验证 Broker，未改规则或削弱策略失效时的关闭行为。

随后无遮罩复测出现完整自动链：FocusedUser 空写 → 单次 HID 点击 → 唯一密码框空写、focused=true → Return 单对派发 → loginPressed / authBegan / loginwindow rights request → OCU mechanism claim / 一次性 permit consume / SetResult allowed → 原会话实际 unlocked → 立即请求且确认 locked → Root idle。原生诊断起始约 8.358s，观察解锁约 9.692s，结束 / 重锁确认约 10.137s（相对控制器开始，含 5 秒初始提示）。报告内无 Touch ID match；未访问应用 GUI、SCK 或 Keychain。不能视为完整生产验收，报告仍 productionEvidenceEligible=false，自动归因没有因缺失 Touch ID 就签发证书。用户现场观察仍待补充。

下一步是为受保护主 / watchdog 过滤器增加严格的一次性 Return 能力，保留硬件接管 / 重锁、原会话及焦点校验，再验证遮罩期间应用操作和故障恢复。本轮 Return 尚未启用到受保护路径；生产关闭，未合并 awesome-extension。


### 受保护 Return 接入（待真实完整复测）

用户确认无遮罩通过后要求提交并恢复 Guardian。此前实现与证据已分别提交 b444978 / 48d918f。新增 LockedUseReturnAllowance，通过 Guardian → watchdog 私有继承管道传递独立随机 returnTag，只在 Root 管理员 validation profile 下创建，不与鼠标 clickTag 混用。两套 session tap 分别验证同一原锁定 UID / audit session、Guardian 来源 PID、能力 tag、有效目标 PID、固定 keyCode 36、无重复 / 修饰键、5 秒总有效期和 250ms 匹配 down/up；重放、错序、取消和真实硬件接管均不能重开。watchdog / 主 Guardian 停止会撤销两类输入能力。

LockScreenInteractor 在完整扫描唯一密码框、空写成功、可写且焦点确认、Apple loginwindow 签名 / 会话再次检查后才提交 Return；受保护事件写入来源 / 目标和独立 tag。没有通用键盘放行、没有 PID-only 绕过。无 Return 能力的旧 bootstrap 不获得键盘权限。生产 profile 暂不启用。新增 6 项策略回归覆盖两独立 gate、nonce / 来源错误、其他按键 / 修饰 / repeat、跨会话 / 过期、顺序 / 目标 / 间隔 / 重放、取消与旧 bootstrap。Swift 272 项（1 跳过、0 失败）、Python 报告 17 项与归因 3 项通过；签名组件、ABI、内核身份检查与 Dev app 构建通过。真实受保护完整链待安装复测，未合并。


### 受保护首轮：Return / 插件通过，遮罩过渡失败

新验证版安装和普通已解锁真实 AX / SCK preflight 通过。完整 fast / legacy-only 轮两套过滤器均放行鼠标 down/up，Return 派发后 OCU 插件 claim / consume / SetResult 成功。还未确认 active GUI 就遇 watchdog shieldBoundsMismatch：实际 Quartz bounds 在系统解锁动画缩至 2404×1352 且偏移 78,44，未覆盖原 2560×1440。watchdog 正确请求 guardLost 重锁；约 9.594 秒（含 5 秒提示）Root 确认双保护释放，没有循环遮罩。不得把此轮算完整成功，也没有观察到 returnAdmitted 日志，Secure Input 时事件是否经过 session tap 仍须谨慎描述。

修正使用居中 1.5× 实际不透明窗口，使系统 zoom 缩放后仍覆盖屏幕；不是放宽 coverage 判定。保留对 WindowServer 实际 bounds 完整包含 CGDisplayBounds、alpha=1、owner / layer / active topology 的严格要求。新增负坐标 / 不同比例缩放下 overscan 实际覆盖测试及不足覆盖拒绝，Swift 273 项（1 跳过、0 失败）通过。仅更新经 Developer ID 签名的 staged Guardian，保持 root 所有与普通用户不可写，Broker / auth rules 不变，待复测。

用户提供 Native Fixture “not open anymore” 提示。控制器在失败恢复后会关闭 RPC 并终止固定测试 fixture，当前没有发现其相关新 crash report，无法仅凭截图判定为崩溃；Finder 最新状态未见该弹窗。将其作为测试窗口生命周期诊断，未改私钥或认证策略。


### 受保护完整流程首次通过（overscan 修正版）

更新 staged Guardian 后，同一 fast / legacy-only 真实测试通过：约 11.532s 派发单对 Return，11.534s loginwindow 观察 secure Return，11.539s authBegan，12.555s 首次 claim 签发许可，12.560s consume，12.561s SetResult allowed，12.564s 系统报告解锁，12.815s Root 在双保护健康下进入 active。固定签名 Native Fixture 在 13.421s 捕获 counter=0，14.198s AX 操作验证 counter 增加且 SCK 图像改变；14.560s 确认重锁，14.825s 确认双保护释放。用户随后正常手动解锁，30.859s 自有隔离 legacy Keychain 项验证 / 清理通过。报告无 failureType，没有本轮 guardLost / shieldBoundsMismatch。时间均相对控制器开始，含初始 5 秒提示；实时 / 历史副本不代表重复派发。

本轮首次证明受保护自动解锁 → GUI / SCK 变化 → 重锁 → 双保护释放的实际闭环。没有观察到 returnAdmitted 日志，不能宣称 Secure Input 下两个 session tap 实际接收了该按键；需要继续验证硬件接管。现场两块物理显示器的持续覆盖仍待用户补充。legacy-only 报告 productionEvidenceEligible=false，不覆盖 Data Protection Keychain、崩溃 / 拓扑变化或生产 promotion；默认生产 profile 仍关闭 Return。未合并 awesome-extension。


### 5 秒受保护停留复测通过

用户指出首轮遮罩不足 5 秒。核对首轮 --fast 将 hold_seconds 设为 0：authorizing 到双方释放约 3.683 秒，active 到观察重锁约 1.745 秒，结束原因 turnEnded，非遮罩失效。为控制器补充 protectedHoldStarted / protectedHoldEnded，实际等待采用 monotonic 计时；没有更改 Root 截止、遮罩或输入策略。

随后不使用 --fast、指定 --hold-seconds 5 的同账号 legacy-only 复测通过：12.659s active，13.799s AX counter 增加且 SCK 图像变化；13.815s 开始停留，18.817s 结束，实际 5.002 秒；18.834s turnEnded 重锁，19.108s 确认锁定，19.203s 双保护释放，22.703s 普通手动解锁后自有隔离项验证 / 清理通过。authorizing 至双方释放约 7.780 秒，无报告覆盖故障 / guardLost。两轮完整流程均通过，但仍不能替代生产验收；物理显示器持续覆盖及剩余故障 / Data Protection Keychain 等验证需继续，生产关闭，未合并。


### 遮罩文字跳变修正

用户现场观察认证倒计时 / 使用倒计时反复跳变。代码确认主 Guardian 的 startup 倒计时在 hasObservedUnlock 后仍每秒更新，与 active 标签互相覆盖；watchdog 又未离开 startup 标签。新增两套遮罩共用的纯显示状态 LockedUseShieldStatus：等待认证（同一 Root startup deadline）→ 正在操作 → 正在锁屏，阶段只前进，只有文字改变时绘制。操作阶段显示稳定提示，不再展示与固定 5 秒测试停留无关的 300 秒上限。此显示状态不授予 GUI 权限、不改变 Broker / 输入 / coverage 策略。新增两项回归覆盖解锁后旧 locked 样本 / 认证截止不能覆盖 active 文案、停止后不回退和主 / watchdog 同输入一致，均通过；真实部署复测待完成。


显示状态修正版 e25dd37 已签名部署。相同 5 秒停留实测的 AX / SCK 闭环通过，实际停留 5.005 秒，约 19.625s 确认重锁、19.679s 双保护释放；没有以显示文案变化代替认证 / coverage / 释放证据。现场文字稳定性与正常手动解锁清理待反馈。


用户因上一轮离开要求重新现场观察。上一轮双保护约 19.679s 已释放，之后仅等手动解锁，最终 120 秒手动验证等待超时；不应描述为完整验收或遮罩保留数分钟。此次相同显示状态修正版、legacy-only / hold=5 复测通过：10.647s 固定 AX / SCK 验证通过，实际停留 5.005 秒，16.260s 确认重锁，16.445s 双保护释放，20.439s 正常手动解锁后隔离项验证 / 清理通过。现场文字稳定性待用户反馈，报告 productionEvidenceEligible=false，未合并。


### 退出前文字重排修正

用户确认整体遮罩和主要文字状态正常，但消失前文字仍轻微跳动。退出状态原先立即替换为“正在锁屏”，触发一次新文字布局；两个窗口的释放时刻不同，可能放大视觉切换。改为停止时冻结最后呈现帧，不再更新标签或倒计时，直到已确认锁定 / 排空后关闭窗口。没有增加延迟、关闭动画或绕过双保护释放屏障。回归验证停止后包括晚到 unlocked 样本都不会触发绘制。现场修正版尚待观察，不将已知文字布局机制当作所有末帧视觉变化的唯一原因。


退出帧冻结修正版 714c020 真实复测的软件闭环通过：10.138s 固定 AX / SCK 验证完成，再停留 5.000 秒；15.764s 确认重锁、16.228s 双保护释放，23.080s 正常手动解锁后自有隔离 legacy 项验证 / 清理通过。现场退出文字是否稳定待用户反馈，不由软件流程成功推断；productionEvidenceEligible=false，未合并。


### 撤罩后桌面闪现：锁屏呈现屏障

用户确认退出字体稳定，但撤罩后桌面闪现再进入锁屏；该反馈推翻了此前“软件锁定 / 覆盖检查即可证明整个视觉交接无泄露”的假设。原 main policy 和 watchdog 都仅根据原会话 locked / 排空决定释放，缺少系统锁屏界面的呈现稳定检查。普通锁屏的只读元数据采样看到 Apple loginwindow 的全局背景层从 alpha=0 到 alpha=1 的过渡，不采集像素、标题或密码。

新增两进程各自执行的 LockScreenPresentation：验证 Apple loginwindow 动态签名，原 UID / audit session locked、所有活动显示器均由屏蔽层级及以上的 loginwindow alpha=1 窗口完整覆盖，显示器与背景几何指纹连续稳定至少 1 秒、采样间隔不超过 0.5 秒，才允许本进程释放。主 policy 默认缺少呈现证据不释放；watchdog 保留独立观察和 root / 主进程排空信号。窗口变化、覆盖缺失、跨会话、解锁、时钟异常均重置，不以固定睡眠、客户端标记或新一轮 lock SPI 替代证据。单次私有管道 release 信号被本地锁存以等待屏障，不在每次采样后丢失。

WindowServer 元数据并不提供像素或 compositor 原子交接保证；1 秒连续稳定仍是保守观测条件，需要两块物理屏幕现场验证。未放宽原 coverage、动作排空和输入保护；没有添加反复重锁或超时自动撤罩。11 项 Guardian / 呈现屏障策略回归通过，真实部署复测待完成。
