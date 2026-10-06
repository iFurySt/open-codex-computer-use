## [2026-10-06 22:41] | Task: 当前源码内置屏/外屏各 30 次控制变量

### Execution Context
- Agent ID: `/root`
- Base Model: GPT-6
- Runtime: Codex local workspace

### User Query
> 不接外屏测试 30 次，然后接回外屏，用当前分支代码再测 30 次，明确 ColorSync 与 OCU、扩展坞/外屏的关系。

### Changes
- 独立全新 scratch 构建生产 helper/bridge，用既有 Developer ID 签名并严格验证；两个条件相同二进制和源码指纹。
- 内置屏 30 次无累积；LG 30 次后首窗 89.64% / 13.451 XPC/s，静置约 90 秒维持 78.2% / 12.1。
- 60 次自身 display/helper 清理全部验证，146 ICC 内容不变。保持既有主 App/后台消费者，不执行 AX/input、捕获或系统清理。
- 更新脱敏指标、对照报告、质量边界、execution plan 与参考入口。没有生产代码/主 App bundle 修改或重启。

### Intent and Validation
确认当前创建/释放核心仍可在外屏组合条件触发问题，复用是缓解而非已修根因；不将 CalDigit、LG 或具体系统回调定责。4 项离线测试和同构建/60 次清理/拓扑/ICC 脱敏断言通过。本轮用户手动恢复尚未确认，明确保留当前高负载状态。

### Files
- `docs/references/20261006-current-source-display-controls.md`
- `experiments/DisplayPerformance/results-builtin-current-source-20261006.json`
- `experiments/DisplayPerformance/results-lg-current-source-20261006.json`
- `docs/exec-plans/completed/20261006-physical-topology-color-controls.md`
- `docs/QUALITY_SCORE.md`
- `experiments/DisplayPerformance/README.md`
- `docs/references/20261006-thirty-display-cycles.md`
