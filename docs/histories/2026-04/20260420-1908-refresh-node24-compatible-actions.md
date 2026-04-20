## [2026-04-20 19:08] | Task: 升级 release workflow 到 Node 24 兼容的 GitHub Actions 版本

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 没问题了，现在修复一下这个 warn 的问题

### 🛠 Changes Overview
**Scope:** `.github/workflows/`、`docs/`

**Key Actions:**
- **[Action Pin Refresh]**: 将 `release.yml` 里的 `actions/setup-node` 更新到官方 `v6.4.0` 对应 SHA，将 `actions/upload-artifact` 更新到官方 `v7.0.1` 对应 SHA。
- **[Warning Removal]**: 收掉 GitHub Actions 在 `v0.1.18` release run 中提示的 “Node.js 20 actions are deprecated” 警告，避免后续 runner 默认切到 Node 24 时继续出现已知噪音。

### 🧠 Design Intent (Why)
`0.1.18` 的 release 已经功能成功，但 workflow 仍依赖基于 Node 20 的老 action 版本。既然 warning 已明确指出后续 runner 会默认转到 Node 24，就应该尽早把 pinned SHA 升到官方最新 release，避免把已知兼容性风险留到之后再集中爆出来。

### 📁 Files Modified
- `.github/workflows/release.yml`
- `docs/histories/2026-04/20260420-1908-refresh-node24-compatible-actions.md`
