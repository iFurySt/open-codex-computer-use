# 锁屏自动化参考方案复核

用户提供的方案作为待核对资料，不作为安装指令或已验证系统行为。以下判断结合本项目实测和 Apple 的接口说明；当前仍未证明真实自动解锁与完整故障恢复。

| 资料中的主张 | 本项目判断 / 调整 |
| --- | --- |
| 先唤醒锁屏 UI，在系统认证事务中由插件放行 | 值得验证。用公开 IOPMAssertionDeclareUserActivity 做一次显示器唤醒，再观察实际机制调用、许可消费和会话解锁。API 只承诺电源活动，不能据此宣称会发起认证。 |
| AX 树在认证之前不存在，提前查必然为空 | 不能作绝对判断；本机实际读到 loginwindow 窗口 / 按钮结构，但没有唯一 secure field。新版参考补充 identifier 路径：按名字定位并验证 loginwindow，AXChildren 深度 ≤8，优先 UserPasswordTextField、回退 FocusedUser。只对完整扫描的唯一候选写固定 AXValue；不读取内容或输入密码，不执行认证 action / Return。真实效果须分阶段日志证实。 |
| 早版将 MechanismInvoke 返回 0 当作放行；新版已修正 | 采用新版修正。OSStatus 表示调用状态，授权结果必须通过 callbacks.SetResult 报告。现有插件已经显式报告 Allow / Deny。 |
| 仅靠签名 ID / Team ID，且必须 SecTask | 不采用这种收缩。继续使用内核 audit token 和动态 SecCode requirement 验证，检查 hardened runtime、危险 entitlement、角色与会话；不能仅把签名字符串当作有效签名证明。 |
| 单向固定 ALLOW 字串即可 | 不采用。继续使用有界协议、双向签名验证、一次性随机许可及会话 / 原客户端 / 租约绑定；短字串不能表达取消和排空。 |
| 整体 screensaver rule 改为 evaluate-mechanisms | 不覆盖原认证流程；保持原 OR fallback，只添加独立 remote right。插件不可用时仍须保留系统密码认证路径。 |
| 不读写 Keychain 就能保证 Keychain 正常 | 未被证明。login 与 Data Protection Keychain 是不同实现，必须用自身测试项覆盖临时解锁、重锁、正常解锁后的访问；不能仅凭插件代码没有 Keychain API 宣称无影响。 |
| 排除自身 PID 的输入 | 不直接采用。继续对硬件活动和过滤 tap 保持严格接管；PID 标签本身不应成为绕过实体输入保护的凭据。 |
| 撤罩、释放断言后再锁定 | 不采用。先撤销许可、停止动作、排空可能在途解锁，观测原会话锁定后才撤罩；保活断言随保护释放。 |
| socket 目录 0700 / 文件 0600 | 要结合跨用户 SecurityAgent 与 root Broker 拓扑。当前系统路径不可由普通用户写入，连接准入由内核身份和签名控制；不能照搬单用户私有目录而使系统 helper 无法连接。 |

## 本轮验证顺序

1. 离线证明认证服务器卡住时 Broker 的协调队列仍可处理恢复，策略过期时不会签发许可。
2. 独立进程 deadline 与纯恢复 barrier 回归。
3. 仅限管理员验证 profile 的 recovery-only 实机事务：不签发任何解锁许可，确认两个保护 ACK 与恢复耗时。
4. 单次显示器唤醒实测：按日志区分“唤醒成功”“机制调用”“许可消费”“实际解锁”，失败后验证正常登录恢复。
5. 自动解锁通过后继续 AX / SCK、两种 Keychain、Secure Input、故障和显示器变化。全部通过后再合并 / 开放生产。

## 一手依据

- [Apple AuthorizationCallbacks.SetResult](https://developer.apple.com/documentation/security/authorizationcallbacks/setresult)：异步 MechanismInvoke 也需要显式结果回报。
- [Apple IOPMAssertionDeclareUserActivity](https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity)：声明活动、开启显示器；没有自动授权保证。
- [Apple IOPMLib 源码接口](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h)：显示保活、断言超时与释放接口。
- [Apple TN3137](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains)：两种 Mac Keychain 实现及 Data Protection 的用户上下文 / profile 约束。

系统行为随 macOS 版本变化。以上 API 文档不能替代本机真实锁屏和正常密码 / Touch ID 恢复验证。

用户补充的二进制分析只观察到固定 AXValue 写入，没有密码输入、Keychain 或输入事件合成调用；这是参考样本的结论，不是本项目自动解锁已通过的证据。本项目将其实现为取消可阻断的有界探测，并增加单轮完整短流程与私有白名单诊断时间线。Keychain API 仅存在于隔离验证测试项路径，不参与解锁。
