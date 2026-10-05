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
- [ ] 本地输入 / watchdog 故障恢复专项验证。
- [x] 内核 audit-token / 动态签名认证、root 批准记录读取与短期一次性 permit registry；签名 / 角色实机自检与离线策略回归。
- [ ] 真正 loginwindow 解锁、独立保护与 Keychain 保持实验（阻塞生产 backend 开放）。
- [ ] Broker、独立 Shield / watchdog、管理员安装与客户端授权 UI、真实自动解锁。

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

基于本地 awesome-extension 的已提交状态。另一个会话有未提交的虚拟显示器工作；不 stash / reset 该会话。合并前再次检查目标工作区，只有不覆盖其改动时才在本地合并；不推远端。

## 进度记录

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
