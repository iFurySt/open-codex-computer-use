# macOS Locked Use 认证边界

核对日期：2026-10-05。以下用于下一阶段 Broker / installer 实现，不表示真实解锁已经验证。

## 两种 session ID

[Apple AuthorizationCallbacks.GetSessionId](https://developer.apple.com/documentation/security/authorizationcallbacks/getsessionid) 的输出是 `AuthorizationSessionId` opaque handle（SDK typedef 为 `void *`），描述同一认证事务中机制之间的关联。它不是内核 audit session ID，也不能转换为 `SecuritySessionId` 来选择 GUI 用户。Broker 的目标 UID / audit session 仍必须来自经过签名验证的内核 IPC 身份与真实 GUI 会话观测。

## 保留现有 fallback

[Codex 上游 Platform SSO 报告](https://github.com/openai/codex/issues/47470) 描述原有 `psso-screensaver` 被固定的 `use-login-window-ui` 替代后，密码解锁失效。该报告提供原有 / 新规则与 authd 日志，是报告者的机器观测；本仓库没有在 Platform SSO 机器复现或验证自动解锁。

由此采用保守安装规划：只向原有 OR rule 添加自己的 branch，保留所有旧 rule 名称、顺序与其他语义字段；不把未知认证配置强制重建为系统默认。原有 rule 的 threshold 不是 1、格式未知或已存在本项目引用时拒绝规划。旧 rule 内部的阈值不改动。

`LockedUseAuthorizationRules` 仅生成离线变更计划。忽略 authorizationdb 管理的 created / modified 时间戳，其他字段变化都会拒绝使用旧计划恢复。持久计划需存于 root 所有的安全目录；真正 installer 要在写入前后重新读取验证、互斥自身操作，不能声称 authorizationdb 提供原子 compare-and-swap，也不能在第三方配置变化后盲目覆盖。

当前机器只读规则仍是 `use-login-window-ui`，没有执行 screensaver rule 写入。
