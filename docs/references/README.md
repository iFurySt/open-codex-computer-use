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
  - 官方 `Codex Computer Use.app` / `SkyComputerUseClient` 的持续逆向分析资料。
- `codex-network-capture.md`
  - 用 `mitmdump` + `scripts/codex_dump.py` 抓 Codex 上游 HTTP / WebSocket 流量，并把样本沉淀到 `artifacts/codex-dumps/` 做持续分析。
