## [2026-04-17 22:28] | Task: 强化 npm 安装后的下一步提示

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> npm 全局安装完 `open-computer-use` 后，要提醒安装的版本和下一步动作；先让用户跑 `open-computer-use doctor`，去授权 Accessibility 和 Screen Recording，再打印一段可直接贴到支持 MCP 的 client 里的 JSON。

### 🛠 Changes Overview
**Scope:** `scripts/npm/build-packages.mjs`、`README.md`

**Key Actions:**
- **补 postinstall 版本提示**：npm 安装后现在会打印 `${packageName}@${version}`，不再只说包名。
- **补首次使用引导**：把 `open-computer-use doctor` 提前到安装后的第一步，并明确提示去授权 `Accessibility` 和 `Screen Recording`。
- **补 MCP 配置落地文本**：安装提示里直接打印可复制的 `mcpServers` JSON，同时附上 npm package 页面链接。
- **同步 README**：仓库首页的 npm 安装说明改成与实际安装后提示一致的路径。
- **补 npm 页面安装说明**：npm 包 README 模板的 `Install` 段和包短描述都明确写出“安装后先运行 `open-computer-use doctor`”。

### 🧠 Design Intent (Why)
这个包的首次体验核心不是“安装成功”本身，而是让用户在最短路径里完成授权并把它接到 MCP client 上。把版本号、`doctor`、权限说明和 JSON 配置直接放进 postinstall，并且在 npm 页面正文与短描述都重复一遍，可以减少用户安装后还要回头翻文档的次数。

### 📁 Files Modified
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/histories/2026-04/20260417-2228-improve-npm-postinstall-next-steps.md`
