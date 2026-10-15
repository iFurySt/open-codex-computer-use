# Locked Use unlock latency and cleanup

## 用户诉求

结合另一个会话的系统卡顿诊断，修复 Locked Use 问题、检查类似路径并提交 PR。

## 定位结果

本机保留的是旧开发组件。原始解锁日志中，系统评估插件约耗时六秒，并报公证与 Library Validation 错误；但插件随后确实进入 MechanismInvoke，Broker 在约 12 ms 内拒绝空闲请求。因此加载错误不能单独作为最终加载失败的证据。

独立授权测试中，公开 1.1.0 插件约 449 ms 进入机制。修正版导出的标记证明普通宿主与 privileged 宿主都能加载；当前普通用户 CLI 发起的测试里，后者的内核 audit session 与调用方一致。完整受保护 GUI 测试进一步确认了新宿主的许可绑定。

## 修正

- 非 UI 机制使用 Apple 文档支持的 privileged host。Broker 固定验证 Apple 签名、helper identifier、root UID、原 audit session 与一次性许可，不放宽保护条件。
- 安装前运行独立 load-check right。只有实际插件返回成功并导出固定标记后，才接入系统锁屏规则。该检查只授予独立检查权，shared=false，使用全新且随后销毁的 AuthorizationRef；不请求锁屏权、不读取或写入凭据。真实测试发现拒绝结果不会导出 context，因此不能用 deny 作为加载成功证据。
- macOS 14.4+ 的已批准 peer 复核绑定内核 audit token、精确 CodeDirectoryHash、identifier 与动态有效/已签名标志，避免在 heartbeat/message 控制队列上重复执行完整签名评估。首次批准仍保留原管理员 requirement；现代失败不回退。
- 转交的 SCM_RIGHTS 客户端同样进入有界工作队列。副本通过 borrowed-socket 生命周期管理保留在途验证，取消只释放本地 fd，不 shutdown 调用方仍在使用的原连接。
- 空闲且两套保护完全释放后，轮询降为一秒；活动/未完成恢复仍为 100 ms，入站状态切换立即恢复频率，许可和策略新鲜度不变。
- 不再删除 OS 保护的 StagedPlugins 缓存，交给 authd 清理。安装只在旧缓存与新签名哈希不同的情况下等待刷新，最多 15 秒，失败不挂接锁屏规则。
- 停用优先使用当前 App 内的签名安装器，修复旧安装器无法卸载缓存的问题。status 显示已安装/内置插件版本差异与明确重装步骤。
- 测试控制器在已重锁且确认双保护释放后保留 Counter，即使人工解锁观察超时；未观察到解锁仍如实报未完成。

## 验证

- Swift 334 项，8 项跳过、0 失败；额外跳过项要求正常解锁的 console session，其余为 opt-in live 测试。内核 hash/token/无效 fd 反例、borrowed fd 在途释放与原连接可用性、版本提示和轮询边界通过。
- 签名 native App 与四组件、remote ABI/重放/取消/load-check 失败反例、kernel verifier 正负例通过。
- 本机旧组件正常卸载，修正版普通 enable 成功，权限和认证规则完整，status available=true。没有改变 SIP 或 Apple 签名。
- 最后一轮受保护 normal MCP 实测完整通过：自动解锁并捕获，AX Counter 0→1、截图变化、保持五秒、重锁与双保护释放 ACK，随后观察到人工解锁且 Counter 仍为 1；连接在 turn-ended 后继续可用。用户确认两块物理屏幕全程遮蔽、无桌面闪现、正常解锁后可见 Counter: 1。演示窗口保留。
- 未进行完整故障矩阵、Intel 实机或系统凭据保持验收；本轮结果不代表系统整体卡顿已经消除。已提交 [PR #99](https://github.com/iFurySt/open-codex-computer-use/pull/99)。
