# 明确实例所有权与窗口接管

## 目标
保持 launch/adopt 两种模式；App 只定位应用，PID 标识进程，window_id 指定接管窗口。新增只读候选查询，GUI 显式选 PID/window，不自动选择不唯一候选。不隐式接管，不改变全局输入/激活边界。

## 进度
- [x] 审计现有启动/接管/清理与窗口校验。
- [x] Swift 候选查询与明确请求校验，返回 launch-reused 候选错误。
- [x] MCP/JS/GUI 候选选择，Chrome 初始虚拟坐标适配。
- [x] 范围/身份/协议回归、签名构建、文档/history 与本地提交。

## 验证边界
不继续 display hotplug 压力测试。以非显示器创建的真实候选查询、纯校验与既有测试验证；真实 AX 移动/恢复与应用闪现验收需后续稳定桌面协调。adopt 多窗口沿用现有逐个 window_id 的形式，不引入不明确的批量授权。未知 modal/sheet 采取暂停，不能以启动模式绕过身份边界。

## 完成记录
Swift 191 tests（1 opt-in skip）、Node 27 tests、正式 release/helper 签名构建及 strict/deep 校验通过。候选查询测试读取真实运行进程，AX 窗口查询依赖测试进程权限，不创建屏或移动窗口。scope 收紧为两阶段启动，显式整实例参数保留预置 case。GUI 两阶段及多窗口真实移动/恢复、通知 containment/零闪现仍留质量记录，不冒称已实测。暂停后的明确窗口授权保留暂停，需 resume；恢复记录重试不覆盖。
