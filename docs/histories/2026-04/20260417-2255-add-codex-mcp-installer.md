## [2026-04-17 22:55] | Task: 增加 Codex MCP 安装命令

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 再增加一个 `open-computer-use install-codex-mcp`，可以安装到 Codex 的 `~/.codex/config.toml`；安装前要通过 TOML 检测原配置里是否已经装过，避免重复执行。

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/build-packages.mjs`, `README.md`

**Key Actions:**
- **新增 MCP 安装脚本**：增加 `scripts/install-codex-mcp.sh`，专门把 `open-computer-use mcp` 写入 Codex 的 `mcp_servers` 配置。
- **加入 TOML 幂等检测**：写入前先用 `tomllib` 解析现有 `~/.codex/config.toml`，如果同一条 MCP 配置已存在则直接 no-op。
- **接入 npm CLI 入口**：让全局安装后的 `open-computer-use install-codex-mcp` 直接代理到这个脚本，并同步帮助文本与 README。

### 🧠 Design Intent (Why)
这个需求本质上是“把 npm CLI 本身作为一个可自安装的 Codex MCP server”。它和 plugin marketplace 安装是两条不同路径，最重要的是不要粗暴地往 `config.toml` 末尾不断追加重复段落。先做一次真正的 TOML 解析，再按目标 section 幂等 upsert，能在保留现有文件格式的同时，避免多次执行把配置堆乱。

### 📁 Files Modified
- `scripts/install-codex-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
