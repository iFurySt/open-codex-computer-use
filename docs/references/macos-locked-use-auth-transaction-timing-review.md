# Locked Use 认证时序复核

核对日期：2026-10-05。用户提供的 `locked-use-auth-transaction-timing.md` 是分析资料，不是系统安装指令。当前自动解锁仍未通过；不把一次插件 Allow 或手动恢复登录记为自动解锁成功。

## 资料与实测的边界

此前快速测试在双保护就绪后执行单次电源唤醒和固定 AXValue 探测，5 秒许可窗口内没有观察到机制调用，随后安全收束。正常手动登录阶段才观察到机制调用和过期许可拒绝。历史另一轮有 claim / consume / SetResult(Allow) 成功，但没有排除人工认证重叠，不能证明唤醒导致认证。现有 rule 的 remote 分支在真实 SecurityAgent 已可达；不是仅凭 rule 静态结构推断。

新资料正确强调区分认证入口、插件裁决和实际会话解锁，但“没有日志即没有事务 / helper”“仅密码提交能触发”等排他性结论尚未证明。日志可以缺失；right 成功记录是结果，不是发起时刻。未核实日志括号数值的格式，不将其解释成独立 OSStatus。

## 本机参考样本的修正

只读分析本机 CUALockScreenGuardian build **1001365** 的符号、Mach-O 地址与调用链，未运行该应用。这个版本与此前“只写固定 AXValue、没有事件合成”的结论不同：

- `SystemLockScreenController.unlock` 在 `0x1001e4be8` 将零长度 Swift String 存入待写入的 Any 值；`0x1001e4c10` 调用 `.value` 属性 getter，返回的是属性名 AXValue；`0x1001e4c48` 调用 `setValue(_:forAttribute:)`。这一路径写入的是**空字符串**，AXValue 是属性名，不能把两个参数混为一谈。后续另一路径重复空字符串写入。
- unlock 查找 FocusedUser 后调度的 async descriptor `0x1010d7300` 指向 helper `0x1001e35ec`。helper 在 `0x1001e3b64` 调用 `SynthesizedEvent.click(...)`，随后 `0x1001e3cd4` 转入 `SynthesizedEvent.send(delay:)`。因此这个版本的可达路径包含合成点击；CGEventPost 零导入不能证明完整调用链没有事件发送。
- 尚未确认 Return 提交、该点击的实际认证效果或 Keychain 行为。不能从这些静态证据直接宣布已经找到完整自动解锁方案，也不能泛化到其他 build。

大体积二进制 / 反汇编留在私有忽略目录，不提交供应商二进制、原始系统日志或账户数据。固定 AXValue 探针是历史实现，当前版本见末尾更新；没有加入私有解锁 SPI。

## 本轮实现与测试

控制器在锁屏之前启动只读 debug log stream，白名单归一化 authd right 求值 / 机制、loginwindow 本地提交 / Touch ID / 认证求值 / Keychain 固定故障标记、SecurityAgentHelper 日志活动。记录上限 2000 条，单条原始记录上限 64 KiB，流最长 150 秒；只在内存处理原始记录，报告只保存固定枚举及经过白名单验证的本项目日志。采集失败不改变认证或保护状态。缺失事件不证明不存在。

私有报告 schema 2 按 Broker authorizing 开始、relocking / awaitingManualUnlock / idle 结束分窗，保留 unlocking 阶段的 SetResult，排除之后的手动恢复阶段；窗口内本地认证标记仍需核对，不能仅凭 Allow 自动归因。新增被动观察模式，不锁屏、不请求授权、不创建租约。

主 / 备用保护复用 Quartz 全局坐标的完整包含检查：允许遮罩大于屏幕，拒绝任何未覆盖边缘、非有限 / 无效矩形和实际缩小到 90% 的窗口；其余身份、层级、alpha、可见性和拓扑检查继续保留。并未放宽实际覆盖要求，也未证明登录切换时的缩放已消失。

离线 Swift 251 项（1 项跳过、0 失败）、Python 报告 10 项、rehearsal 5 项通过；签名组件构建、remote ABI / 内核签名正反例通过。不锁屏 surface 自检通过；5 秒被动采集完成，无授权或锁屏请求。本轮没有安装验证规则、没有真实自动解锁测试。

## 下一轮实际验证条件

先在独立测试账户 / 测试 Mac 或 macOS VM 验证空字符串清理与合成点击的作用（隔离环境是开发建议，不是 Apple API 的规定），逐步确认认证求值是否开始、插件是否放行及会话是否真正可用；没有证据前不发送 Return。每轮继续使用短许可和已验证双保护释放，失败不延长锁屏循环。使用隔离 Keychain 测试项并检查正常登录后的访问，不能因为插件没有调用 Keychain 就认为系统没有改变它。

重新完整核对[上游故障报告](https://github.com/openai/codex/issues/40226)：它记录插件介入后 SecKeychainLogin 失败、后续屏幕解锁跳过 Keychain 解锁，导致当前登录会话无法访问凭据；报告者明确称文件完整、哈希稳定、重启并密码登录恢复。报告没有空输入证据，也没有证明 Keychain 被重设。此前将它写成空输入导致重设不准确，已纠正。隔离环境仍是减少开发故障影响的建议，不能引用此报告宣称会永久丢失凭据或强制该环境。

[Apple DTS 的 screenUnlockMode 说明](https://developer.apple.com/forums/thread/737268)针对旧式 SFAuthorizationPluginView 插件与 UI 兼容问题，不证明本项目非 UI remote 机制必须设置该全局偏好。本轮不修改它。[trycua 的提案](https://github.com/trycua/cua/issues/1744)也不是已验证的自动解锁实现。

生产保持关闭；Data Protection Keychain、Secure Input、真实进程 / Broker 故障、显示器变化与完整自动闭环仍未完成，不能合并或开放生产。

## 官方 API 核对补充

[SetResult](https://developer.apple.com/documentation/security/authorizationcallbacks/setresult) 定义机制授权结果：Allow 后继续剩余机制，全部允许才授权成功；没有承诺会解锁 GUI / Keychain，也没有规定重设 Keychain。

[Apple Security 公开源码](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/SecKeychain.cpp) 区分 SecKeychainLogin 的 login / stash 路径与 SecKeychainResetLogin 的重设路径。公开代码说明登录关联的 Keychain 处理存在，但不是当前 macOS loginwindow 的完整源码，不能据此断言每次屏幕解锁如何选择分支。

[Apple Support](https://support.apple.com/guide/keychain-access/kyca2429/mac) 说明用户登录密码与 login Keychain 密码及重设的关系；其上下文是登录 / 密码变更，不能直接外推为插件 Allow 会重设。当前应验证的是 GUI 解锁后 Keychain 是否保持可用，而不是把它当作实现所需的凭据环节。本轮仅资料核对，未执行认证 / 锁屏 / Keychain API。

2026-10-06 更新：用户要求在当前账户持续迭代；验证路径已改为 3 秒 AX 完整发布重试、唯一候选空字符串写入、一次 FocusedUser AXPress，替代固定 AXValue 探针。没有加入 Return / 全局事件；不以 AX 返回成功算认证开始。此前固定探针边界是历史实现，不再代表当前验证版本。实测结果见执行计划。

2026-10-06 后续复核：参考 build 的 send 路径在 0x1007150cc 调用 0x10021875c（CGEventAPI.post(_:tap:)），传入 tap=1，封装经缓存函数指针发送事件。这支持会话级合成点击路径，CGEventPost 零导入不能排除动态发送；仍不证明认证效果。我们之前的 postToPid 点击 / Return 均没有观察到机制调用，已撤回。验证实验改用公开 annotated application stage、显式目标 PID / 窗口字段、唯一有效几何的一次点击；保留两级会话过滤和硬件监测。此路由与参考 tap=1 不同，尚待实测，不能声称照搬或保证成功。[Apple 的 stage 定义](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation/cgannotatedsessioneventtap) 和 [post API](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)) 只说明投递位置，不保证锁屏认证被触发。

许可模型改为保护待命 → 首次合法插件 claim → 签发 / 消费许可；保留原 8 秒启动截止，晚签发不会延长测试锁屏。待命实测完整 AX 树和空写返回成功，但原截止内没有机制，仍无法证明自动解锁。agent 独立上限增加现有 2 秒 RPC 排空余量，控制器修复 BrokenPipeError 掩盖失败与报告丢失。
