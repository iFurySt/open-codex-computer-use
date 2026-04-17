## [2026-04-17 16:39] | Task: 补充 Codex 本地日志观测文档

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 把“优先看 LLM call dump，不足时再查 Codex 自己日志”的结论写进 `docs/references/`，单独建一份放在 `codex-network-capture.md` 旁边，并更新 `docs/references/README.md`。

### 🛠 Changes Overview
**Scope:** `docs/references`、`docs/histories`

**Key Actions:**
- **[独立 Runbook]**: 新增 `docs/references/codex-local-runtime-logs.md`，说明何时补查 Codex 本地 `logs_2.sqlite`，以及如何查询 `computer-use` 这类本地 `stdio` MCP 的参数与结果。
- **[优先级说明]**: 在 `docs/references/codex-network-capture.md` 补充“先看上游抓包、再看本地日志”的默认顺序。
- **[索引更新]**: 在 `docs/references/README.md` 增加新文档入口，并明确它是抓包文档的补充路径，而不是默认入口。

### 🧠 Design Intent (Why)
上游抓包和本地日志解决的问题不同。把两条观测路径拆成独立文档，并明确优先级，可以避免后续一遇到本地 MCP / `computer-use` 问题就直接走高侵入的拦截路线；多数场景先看 LLM call dump 已经足够，只有不足时才需要补看 Codex 宿主日志。

### 📁 Files Modified
- `docs/references/codex-local-runtime-logs.md`
- `docs/references/codex-network-capture.md`
- `docs/references/README.md`
- `docs/histories/2026-04/20260417-1639-document-codex-local-runtime-logs.md`
