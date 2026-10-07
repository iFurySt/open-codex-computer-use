## [2026-10-07 08:59] | Task: 缩小 ColorSync 周期请求累积触发范围

### Execution Context
- Agent ID: `/root`
- Base Model: GPT-6（具体变体不可见）
- Runtime: Codex 本地 macOS

### User Query
> 最小 demo 仅 71 行，继续分析原因；物理断开重连后已恢复顺畅。

### Changes Overview
- 新增外部 scratch 候选生成器：仅改变 queue 或 typed init，保持原 demo 不变。
- 新增单次持有对照、纯公共 CoreGraphics 观测探针、离线周期检验和测试。
- 保存四次有界对照及正常退出系统设置的脱敏结果；约 5.05 秒周期请求组从三次后的 7 组增至四次后的 9 组。
- 记录恢复后的健康基线及所有 ICC 内容不变。根因服务栈待用户管理员只读采样，未宣称定位具体泄漏函数或修复。

### Design Intent
分开验证调用方式、在线持有、观测框架和系统消费者，把热插拔后持续请求累积转为可检验的周期证据。保留其他 runtime、物理连接与权限限制，避免把候选或时序推断当成生产修复。

### Files Modified
- `experiments/DisplayPerformance/{build_minimal_variant.py,held.py,CoreGraphicsProbe.m,periodicity.py}`
- 对应离线测试、脱敏结果与实验 README。
- `docs/references/20261007-minimal-display-call-isolation.md`、质量记录、参考索引及 active execution plan。

### Validation
23 项 Python 离线测试通过；候选 clang 构建及 Developer ID 严格签名验证通过。四次 helper 退出、系统列表移除及 ICC/拓扑检查通过。生产 App 未修改，无需重启。系统设置恢复原查看页，未改变偏好；尚未读取 root 服务栈。
