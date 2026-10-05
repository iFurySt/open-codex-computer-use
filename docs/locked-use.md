# macOS Locked Use（实验阶段）

目标是在已登录用户的屏幕锁定后，允许已授权客户端临时解锁 GUI 会话，同时遮蔽所有物理显示器，继续通过 AX / ScreenCaptureKit / 输入执行任务，最后重锁。

**当前不是可用的自动解锁功能。** 当前交付的是只读诊断、可测试的保护状态机、真实 app 的锁屏拒绝路径、独立 Guardian / watchdog rehearsal、Broker 的签名认证 / 批准记录 / 一次性许可组件，以及始终拒绝授权的独立插件 ABI / 系统加载实验。生产 Broker IPC、guardian 集成、安装授权与真实 loginwindow backend 尚未完成；不能通过环境变量或另一厂商的插件开启。

## 当前可用入口

```sh
ocu locked-use status
ocu locked-use status --json
ocu doctor
```

诊断分别报告 AX、Screen Recording 和 Input Monitoring 的当前进程 runtime preflight，以及会话状态、系统组件是否存在、其他 Authorization 插件名称和未完成的门槛。查询不请求权限，不安装、不解锁、不锁屏；安装文件存在也不表示签名、注册或运行已验证。`available` / `enabled` 当前始终为 false。

原生诊断由 `.app` agent 执行，与真实控制进程保持相同权限身份。源码 CLI 的开发验证应绕过已经安装的旧版本 agent：

```sh
swift build
OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 .build/debug/OpenComputerUse locked-use status --json
```

无完成登录的控制台 GUI session、切换用户或未知会话时，真实 app 控制明确拒绝。正常锁屏也返回 Locked Use 未验证的错误，不再尝试恢复窗口或向锁屏注入输入。缓存的真实 AX snapshot 每次复用前重新检查会话；输入事件投递和 AX 动作 / 属性变更路径补充检查。fixture 是测试数据，不代表真实桌面，仍可用于 headless smoke。会话检查不能提供与 WindowServer 事务原子性相同的保证。

## 保护状态机

`LockedUseStateMachine` 是纯状态 / effect reducer，**未接入生产自动解锁**。未来 Broker 串行驱动它；执行 effect 不构成系统成功证据。

- `idle → preparing → authorizing → unlocking → active → relocking`
- 先收到全部显示器遮蔽、输入拦截和独立 watchdog 健康证据，才发一次性许可并请求解锁。
- 许可绑定 connection UUID、用户 UID 和 audit session；只允许认证后的插件回执消费一次，5 秒失效。
- 消费许可后还要确认相同会话已解锁，才能允许工具动作。
- 单调时间计时：3 秒 heartbeat 期限、10 秒启动期限、30 秒空闲期限、300 秒绝对租约上限。真实 guardian 需独立于 GUI action 维持 heartbeat。
- `turn-ended`、EOF、JS reset / timeout 或租约结束应撤销许可并重锁；这些生命周期接入仍待生产 backend 实现。
- 本地输入、显示器 topology generation 改变、guardian 失效或会话异常立即停止并重锁；未知输入按接管处理。
- Broker 确认许可撤销已提交、解锁尝试取消 / 排空、动作投递停止后，还需确认原会话锁定，才能释放遮蔽。原锁屏仍可见不代表排队解锁已取消。未知 / 其他用户的锁定事件不算重锁成功；失败保留保护并重试。
- 接管和异常后进入 `awaitingManualUnlock`。正常人工解锁事件才清除抑制，排队请求不能重新解锁。

## Guardian 与锁屏实测

开发构建，不安装系统组件：

```sh
./scripts/build-locked-use-guardian.sh --identity 'Developer ID Application: <your identity>'
'.build/locked-use/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian' --diagnose
'.build/locked-use/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian' --peer-self-test
```

缺少权限时显式执行同一 binary 的 `--request-permissions`，由用户在系统设置授予 Accessibility 与 Input Monitoring。`--diagnose` 本身不请求权限、不锁屏。

先单独确认所有物理显示器遮蔽与倒计时，再验证遮罩期间的动作：

```sh
python3 scripts/run-locked-use-rehearsal.py --shield-preview
```

该独立 preview 复用 rehearsal 的显示器覆盖与 WindowServer 检查，覆盖确认后显示 15 秒倒计时。输入事件仅按类型 / source PID / source state 汇总，不保存按键或文本；鼠标移动不会提前结束，Esc 立即退出。它不创建 AX fixture、不截图、不执行应用动作、不启动重锁 watchdog、不请求锁定或解锁。结束或 controller 的开发应急超时只撤掉预览；不能复用该输入策略或超时退出作为生产保护。物理屏幕需人工观察，枚举的 NSScreen 数量也可能包含虚拟显示器。

**只有用户准备好锁屏、并有人观察物理屏幕时运行：**

```sh
python3 scripts/run-locked-use-rehearsal.py --confirm-lock-test
```

测试从已正常解锁的会话开始，创建专用蓝色窗口，再使用独立、覆盖所有 NSScreen 的黑色 window 遮蔽。它检查 WindowServer 中的窗口 PID、frame、alpha、layer 和物理显示器映射，不能把 `isVisible` 单独当成已覆盖。过滤型 session event tap 不读取或记录按键内容，对所有全局输入保守接管；定向 `postToPid` 不走这条全局 stream。Secure Event Input、tap disable、显示器 topology 改变、watchdog 失效均停止测试并请求锁屏。软件 overlay 无法提供原子热插拔、系统级 overlay 或进程死亡时零泄漏的证明，必须实际观察。

`shieldReady` 后，使用 AXPress 点击专用窗口按钮，并以 ScreenCaptureKit 的 desktop-independent window filter 验证遮挡后的蓝色内容和动作前后画面变化。AX / capture 未完成时不提前宣告 quiescence。输出只有结果与状态，截图不写磁盘。最长 15 秒租约到期或本地输入都会请求重锁；只有原 UID / audit session 观测到锁定、且动作已排空，才移除遮罩。

child watchdog 与 UI event loop 分离，监测 inherited pipe 心跳；1.5 秒超时、EOF 或非法输入会独立请求重锁。该测试 watchdog 从未接收解锁许可。测试完成后，Guardian 只读取 loginwindow 的 AX role / subrole / action names，最多 300 节点、12 层、3 秒；不读取值、用户名、输入框、选中文本或密码，也不执行 loginwindow 动作。单次 AX RPC 额外有 0.5 秒 timeout，因此整个 traversal 可能比预算略长。

开发 controller 默认提前 5 秒提示用户放开输入。rehearsal 的非正常退出 / 35 秒超时会先保留 child watchdog，同时请求重锁并观察会话状态，再清理自身测试进程组；preview 的恢复不请求锁屏。这是只供人工实验的应急路径，**不能在生产 Locked Use 中用超时移除遮罩**。rehearsal 没有改变认证规则，也不自动解锁；用户随后按普通方式解锁。

事件输出包含单调时间与 capture 阶段 / stop reason，便于区分覆盖失败、输入接管、动作失败及租约到期。同进程受控 fixture 的 AXPress 在 MainActor 上执行；AppKit 会直接在调用线程派发按钮动作，不能从后台队列调用带 MainActor 隔离的 target。`--fixture-ax-self-test` 可独立验证此路径，不遮蔽、不锁屏。

### Broker 认证组件

- `LockedUseNative` 用 `LOCAL_PEERTOKEN` 获得 kernel audit token，包含 PID version；不把客户端自报 PID 转成身份。
- `LockedUsePeerIdentity` 用 token 查询动态 SecCode，并验证 administrator-approved requirement。
- `LockedUseClientApprovals` 固定从 `/Library/Application Support/OpenComputerUse/LockedUse/clients.json` 读取，逐层 `openat` / `O_NOFOLLOW`，检查 root ownership、group/other 不可写与无允许修改的 extended ACL，拒绝 symlink、非 regular file、超大配置、无效 signer / team 和重复记录。不在仓库保存真实批准记录。这里尚未实现写入 UI / installer。
- 批准记录绑定 UID、角色、signing identifier 和 Team ID；角色按连接 endpoint 选择，不取请求 payload。批准 peer 必须启用 hardened runtime，并拒绝 get-task-allow、禁用 Library Validation、允许 DYLD 环境注入或 unsigned executable memory 等 entitlement。Developer ID 签名的 self-test 验证正确 signer / role 成功及错误 signer / role 拒绝；这不表示完整 Broker IPC 已完成。
- `LockedUsePermitRegistry` 使用 SecRandomCopyBytes 生成 32-byte nonce，绑定 connection UUID、attempt UUID、UID、audit session，5 秒过期，单次消费，断开撤销，重放拒绝。最多 32 个 pending permit；4096 个 retired attempt 后拒绝发新许可，需要在无租约状态下重新建立 registry epoch，尚待 Broker 生命周期实现。该 registry 不验证插件身份，调用它之前必须先认证 Apple SecurityAgent peer。

## Authorization 插件实验

先在普通用户进程内验证 ABI，不注册系统 right：

```sh
./scripts/build-locked-use-plugin.sh
```

产物全部在 `.build/locked-use/`：插件 bundle、ABI tests、`authorization-probe`。该插件仅支持 `preflight`，每次 `MechanismInvoke` 都返回 `kAuthorizationResultDeny`；不读取任何认证上下文，不设置密码，不执行解锁。未知机制（包括 `allow`）不能创建。

离线 `dlopen` 与 codesign 验证不证明 SecurityAgent 的 Library Validation 可以加载插件。要测试实际系统加载，需要先用自己的 Developer ID Application identity 签名：

```sh
./scripts/build-locked-use-plugin.sh --identity 'Developer ID Application: <your identity>'
sudo ./scripts/manage-locked-use-probe.sh install
.build/locked-use/authorization-probe
/usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS "OpenComputerUseAuthorizationProbe invoked"'
sudo ./scripts/manage-locked-use-probe.sh uninstall
```

安装脚本是独立实验入口，不是 `ocu locked-use enable`。只注册 `dev.opencomputeruse.locked-use.preflight`，只安装自己的 bundle，不修改 `system.login.screensaver`；拒绝覆盖已有 right / bundle。注册失败会移除本次复制的 bundle。卸载前核对 right 和 bundle 仍属于实验，再删除 right、bundle 与自己的系统 staged 副本。脚本要求 root 和 Developer ID 签名，拒绝 ad-hoc 安装。不关闭 SIP / Library Validation，也不承诺仅签名即可通过系统加载限制。

探针预期返回 `errAuthorizationDenied`。**denied 也可能来自插件加载失败**，只有实际机制的固定日志 marker 才是加载证据。探针不请求 screensaver right；输出 `sessionUnlockRequested=false` 指本探针没有请求解锁，不是对桌面状态的观测。实验日志不得加入用户名、密码、Keychain 内容或授权上下文。

## 测试前清理其他插件

若诊断显示 `CodexComputerUseAuthorizationPlugin.bundle`，它是 Codex / ChatGPT 的 Locked Use Authorization 插件。优先在应用 **Settings → Computer Use → Locked use** 中关闭该功能，然后用只读命令核对：

```sh
security authorizationdb read system.login.screensaver
ls /Library/Security/SecurityAgentPlugins
```

正常清理后不应再有 `com.openai.sky.CUAService.AuthorizationPlugin.remote` 引用和 Codex 插件 bundle。`StagedPlugins` 目录本身不代表它仍启用。不要只删除 bundle，也不要把整个 screensaver right 覆盖成固定模板：其他认证产品可能也有规则。关闭后若残留，先保存规则并诊断其所有者，不在此实验中自动删除第三方组件。

## 当前实机结果

在 Apple Silicon / macOS 26.5.1 上，Developer ID 签名的独立 probe 已实际安装、调用和卸载。4 次 AuthorizationCopyRights 都返回预期 denied；SecurityAgentHelper 的固定机制日志证明插件实际执行。首次加载曾记录 platform-binary Library Validation 错误，随后同一 helper 仍执行了机制，不能仅据那条错误判定全部调用失败，也不能只凭 denied 推断加载成功。

实验后诊断 right、原 bundle 和自身 StagedPlugins 副本均已移除，screensaver right 没有变化。没有尝试真实解锁或读取用户 Keychain 项，因此这些结果不证明真实 loginwindow unlock / Keychain 保持、完整 guardian 或系统版本兼容性已通过。

## 生产 backend 的开放门槛

1. 实际 SecurityAgent 加载、正常认证不被阻塞；保留 `use-login-window-ui`。
2. 真正 loginwindow 解锁事务可由短期许可驱动；AuthorizationCopyRights 成功本身不算桌面解锁。
3. 解锁过渡、所有显示器与 Spaces、热插拔及保护进程退出时的实测遮蔽与重锁行为；软件截图无法验证物理显示泄漏。
4. AX / ScreenCaptureKit 可以捕获遮挡的目标窗口，fixture 点击 / 输入后 AX 和画面验证一致。
5. 普通密码 / Touch ID 解锁，以及 login / Data Protection Keychain 不受破坏；用测试项验证，不读取用户凭据，不做密码重置或 Keychain 修复。
6. 认证 IPC 来源、客户端登记、许可重放和撤销、并发所有者、宿主断开与接管抑制全部通过。

测试账户有助于隔离业务数据，但 Authorization 数据库和插件是系统级的；账户隔离不等同于系统隔离。实际认证实验要有可恢复的机器 / VM 和管理员操作路径。

## 参考

- [Apple Authorization 插件](https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins)
- [AuthorizationCopyRights](https://developer.apple.com/documentation/security/authorizationcopyrights(_:_:_:_:_:))
- [NullAuthPlugin ABI 示例](https://developer.apple.com/library/archive/samplecode/NullAuthPlugin/Introduction/Intro.html)
- [Apple DTS 关于 Data Protection Keychain 的已知问题](https://developer.apple.com/forums/thread/796487)：FB13128730，没有公开可靠 workaround，不能假定本系统已修复。
- [官方 Computer Use / Locked Use 设置](https://learn.chatgpt.com/docs/computer-use)
- [DispatchShield](https://github.com/VenusOne-Lee/DispatchShield)：已解锁桌面遮蔽参考，不是锁屏自动解锁实现。
- [trycua Authorization 插件讨论](https://github.com/trycua/cua/issues/1744)：方案参考，不是完成链路的证据。
