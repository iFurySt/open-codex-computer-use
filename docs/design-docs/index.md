# 设计文档索引

用这个目录集中管理架构设计和产品设计文档。

建议约定：

- 一个主题一份文档。
- 每份文档写清当前状态和简短摘要。
- 关联引入它的 execution plan 或 spec。

## 文档

- `core-beliefs.md`
- `record-and-replay-replication.md`
  - Record & Replay 官方复刻和 OCU 独立扩展的设计入口，包含官方兼容层、OCU 扩展层、推进顺序和当前缺口。
- `record-and-replay-handoff.md`
  - Record & Replay 后续推进的短入口，汇总当前决策、官方上下文、OCU baseline、待解决问题、推进协议、下一轮推进顺序和常用验证命令。后续处理 R&R 时优先从这里读起。
- `record-and-replay-official-golden-capture.md`
  - Record & Replay 官方 successful recording golden fixture 的采集、inspect-only、正式导入、OCU candidate 对比和验收 gate 操作清单。

## Record & Replay 阅读顺序

后续继续推进 Record & Replay 时，默认按下面顺序读：

1. `record-and-replay-handoff.md`：先确认当前口径、边界、待解决问题和下一步路径。
2. `record-and-replay-replication.md`：再看完整方案，区分官方兼容层、OCU 扩展层、校准合同和独立 repo 合同。
3. `record-and-replay-official-golden-capture.md`：需要采集或导入官方 successful recording fixture 时读这份。
4. `../references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`：需要追溯官方插件、Codex.app asar、二进制字符串、MCP surface 和 raw probe 证据时读这份。
5. `../exec-plans/active/20260626-record-and-replay-event-stream.md`：需要确认当前里程碑、验证命令和执行拆解时读这份。
