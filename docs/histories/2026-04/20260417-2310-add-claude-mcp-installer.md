## [2026-04-17 23:10] | Task: 增加 Claude MCP 安装命令

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 再增加一个 `open-computer-use install-clauce-mcp`，安装到 `~/.claude.json`，参考 Claude 官方 MCP 文档，也要幂等。

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/build-packages.mjs`, `README.md`

**Key Actions:**
- **新增 Claude 安装脚本**：增加 `scripts/install-claude-mcp.sh`，按 Claude 官方 MCP 文档的 local scope 结构写入当前项目的 `~/.claude.json`。
- **加入 JSON 幂等检测**：写入前先解析现有 `~/.claude.json`，若当前项目下的同名 MCP 配置已存在且内容一致，则直接 no-op。
- **接入双命令别名**：npm CLI 同时支持 `install-claude-mcp` 和用户请求里的 `install-clauce-mcp`，都指向同一实现。

### 🧠 Design Intent (Why)
Claude Code 的 `~/.claude.json` 不是一个只放 MCP 的单用途文件，而是用户状态与项目配置的混合 JSON。这里如果像 TOML 那样用简单字符串拼接很容易破坏现有内容，所以更稳妥的方式是按官方文档先做 JSON 解析，再只更新当前项目路径下的 `mcpServers`。这样既能保证幂等，也能避免把 server 错误装成跨所有项目生效的 user-scope 配置。

### 📁 Files Modified
- `scripts/install-claude-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
