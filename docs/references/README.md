# 外部参考资料

这个目录用于沉淀那些值得长期放进仓库、供 Agent 直接读取的外部参考材料。

适合放这里的内容包括：

- 团队会反复依赖的框架、部署或接入说明。
- 设计系统参考、API 使用约定。
- 对外标准、合作方协议或外部文档的简要整理版。
- 闭源依赖、第三方二进制或外部工具的逆向分析与整理结论。

不要把大段供应商文档原样塞进来。这里应该是经过筛选和整理后的资料。

## 当前目录

- `codex-computer-use-reverse-engineering/`
  - 官方 `Codex Computer Use.app` / `SkyComputerUseClient` 的持续逆向分析资料；大体积一次性分析产物默认在本地 `research/` 下重新生成，不提交进仓库。
  - Record & Replay 相关入口是 `codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`，记录官方 `record-and-replay` 1.0.857 的插件包装、Codex.app asar 分工、Computer Use runtime 字符串、event-stream MCP surface、no-active / raw-timeout fixture、required `simple-action-stop` successful recording golden fixture，以及 recommended golden 场景的后续缺口。
- `codex-network-capture.md`
  - 用 `mitmdump` + `scripts/codex_dump.py` 抓 Codex 上游 HTTP / WebSocket 流量，并把对应 `session_id` 的本地 `function_call` / `function_call_output` 摘要一起沉淀到 `artifacts/codex-dumps/` 做持续分析。
- `codex-local-runtime-logs.md`
  - 当抓包目录里的 `websocket/` + `local-sessions/` 仍不足以解释本地 tool / MCP 行为时，再补查 Codex 本地 `logs_2.sqlite`。
- `codex-computer-use-cli.md`
  - 仓库内 `scripts/computer-use-cli/` 的用途、使用方法，以及为什么探测官方 bundled `computer-use` 时要优先走 `codex app-server` 代理而不是 direct stdio。
