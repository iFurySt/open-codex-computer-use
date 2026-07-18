## [2026-07-10 16:59] | Task: 补充 macOS 14.0+ 系统要求

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex Desktop`

### 📥 User Query
> 在 README 和 skill 文档中明确 macOS 运行环境要求 macOS 14.0 或更高版本，并说明低版本无法通过权限授权修复。

### 🛠 Changes Overview
**Scope:** `README.md`、`README.zh-CN.md`、`skills/open-computer-use`

**Key Actions:**
- **[双语 README]**: 在 Quick Start 中增加独立且醒目的 macOS 14.0+ 系统要求，和权限说明分开展示。
- **[Skill 工作流]**: 要求 Agent 在调用 CLI 或 `doctor` 前先检查 macOS 版本，避免把二进制不兼容误判为权限问题。
- **[安装与排障]**: 说明低于 macOS 14.0 时二进制无法启动，权限授权或 `doctor` 无法修复该兼容性错误。

### 🧠 Design Intent (Why)
让用户和 Agent 在安装及排障入口就能看到真实的最低系统要求，减少低版本 macOS 用户被错误引导到权限授权流程的情况。

### 📁 Files Modified
- `README.md`
- `README.zh-CN.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/installation.md`
- `skills/open-computer-use/references/troubleshooting.md`
