## [2026-04-17 16:19] | Task: 新增 Codex mitm 抓包脚本

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 帮我写一个 `codex_dump.py`，用于通过 mitmproxy/mitmweb 抓 Codex 的上游 API 与 WebSocket 流量。

### 🛠 Changes Overview
**Scope:** `scripts`、`README.md`、`.gitignore`、`docs/references`、`docs/histories`

**Key Actions:**
- **[抓包脚本]**: 新增 `scripts/codex_dump.py`，支持持久化 Codex 相关 HTTP 与 WebSocket 流量。
- **[后台启动脚本]**: 新增 `scripts/start-codex-mitm-dump.sh`，自动创建 session 目录、后台拉起 mitmdump，并输出可直接 `source` 的代理环境。
- **[默认脱敏]**: 对 `Authorization`、Cookie 和常见 token 字段做脱敏，避免把登录凭证原样写盘。
- **[最小文档]**: 在 `README.md` 补充运行 mitmdump/mitmweb 抓 Codex 主链路的基本用法。
- **[样本忽略]**: 把 `artifacts/codex-dumps/` 加入 `.gitignore`，便于把分析样本留在仓库目录里长期查看。
- **[复用 runbook]**: 新增 `docs/references/codex-network-capture.md`，明确前台抓包、后台启动、session 目录约定和后续 eval 分析流程。

### 🧠 Design Intent (Why)
Codex 当前主模型调用走 `chatgpt.com/backend-api/codex/responses` WebSocket，而不是传统 REST body。仓库里需要一份可直接复用、默认脱敏、且不把真实抓包结果落进仓库的脚本，避免每次都靠聊天上下文临时拼 addon。

### 📁 Files Modified
- `.gitignore`
- `scripts/codex_dump.py`
- `scripts/start-codex-mitm-dump.sh`
- `README.md`
- `docs/references/README.md`
- `docs/references/codex-network-capture.md`
- `docs/histories/2026-04/20260417-1619-add-codex-mitm-dump-script.md`
