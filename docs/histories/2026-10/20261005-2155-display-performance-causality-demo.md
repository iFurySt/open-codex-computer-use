## [2026-10-05 21:55] | Task: 独立复现实验分离虚拟显示器性能因素

### 🤖 Execution Context
* **Agent ID**: Codex side conversation
* **Base Model**: GPT-6
* **Runtime**: Codex desktop，macOS 26.5.1 arm64

### 📥 User Query
> 回溯最早的性能问题，用独立 demo 验证几个候选原因，了解前因后果；允许热插拔暂停现有会话。

### 🛠 Changes Overview
**Scope:** `experiments/DisplayPerformance` 与独立调查文档。

- 新增 Swift CG/SCK 查询、捕获与 CI/Metal 离屏渲染探针，以及有界 Python 热插拔和 CPU/日志/ICC 观测流程。
- 四次创建/退出使用三个固定身份，遵守生产身份锁，仅管理自身 helper；没有修改生产 runtime、签名制品、系统色彩配置或物理偏好。
- 修复实验目标缓存失效：捕获前重新查询在线目标，记录跳过/失败及拓扑变化，清理结果写入报告。
- 留档脱敏逐窗数据与结论：身份变化新增持久 ICC；在线虚拟屏放大已有循环，移除后循环持续。根因启动者、历史残留贡献仍未证实。
- 验证：独立 Swift 编译通过；三个 CPU 解析/日志窗口/失效目标测试通过；真实四次创建/移除及 capture/render 成功；一分钟额外恢复观察，无 demo 显示器/helper 遗留。

### 🧠 Design Intent (Why)
将在线工作负载、热插拔与持久身份状态拆开测量，避免把日志处理次数等同于 ICC 文件创建，或者把相关性直接宣布为最初卡顿根因。OS 拒绝 root daemon 堆栈读取，不自动提权或清理系统状态。

### 📁 Files Modified
- `experiments/DisplayPerformance/Probe.swift`
- `experiments/DisplayPerformance/run.py`
- `experiments/DisplayPerformance/test_metrics.py`
- `experiments/DisplayPerformance/README.md`
- `experiments/DisplayPerformance/results-20261005.json`
- `docs/references/20261005-display-performance-causality.md`
- `docs/exec-plans/completed/20261005-display-performance-causality.md`

### 续测：累计启停、用户体感与恢复方案

- 增加每批最多三次的已有身份启停 runner，ICC 增长即停止；累计九次正常结束，ICC 保持 146，自身显示器/helper 均退出。
- 增加只读 Objective-C ColorSync 查询/有效性/耗时 demo，重复查询上限 16；四项测试与独立编译通过，146 份 OCU ICC 验证无失败/警告。
- A/B/C/D 和三批打字反馈已脱敏保存；最后一批反馈退化，但中间存在非 demo 虚拟屏上线，两个窗口标为混杂，不归因成单一 demo 触发。
- 用户离开后停止热插拔，观察五分钟仅物理屏仍存在约 14.3/s 整组 XPC 请求、两项 ColorSync 合计约 89% 单核的持续循环。
- 自有查询客户端样本包含 WindowServer Mach 同步、ColorSync registry 解析/XPC 等待；没有健康对照，不能把 API 耗时等同于打字延迟或确认洪泛发起者。
- 报告新增最大嫌疑、历史计数口径、其他负载限制和保留配置的单次服务恢复对照方案；本轮没有恢复系统服务、删除配置或重启主 App。
- 新增/更新：`ColorProfiles.m`、`cycles.py`、`results-subjective-20261005.json`、README/指标测试与 completed 累积采集计划。历史根因与恢复验收保持开放。
