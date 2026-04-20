## [2026-04-20 18:34] | Task: 去掉 plugin installer 对 rsync 的依赖

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 为什么有 `rsync`？干什么的
>
> 换掉吧，node `cpSync` 是可以的。

### 🛠 Changes Overview
**Scope:** `scripts/`

**Key Actions:**
- **移除 `rsync` 依赖**：`scripts/install-codex-plugin.sh` 不再调用外部 `rsync` 复制 plugin 目录和 `.app` bundle。
- **扩展共享 helper**：在 `scripts/install-config-helper.mjs` 里增加 `copy-into-dir` 子命令，用 Node `cpSync` 递归复制多个源路径到目标目录。
- **保持安装行为不变**：插件缓存目录结构和后续 `config.toml` 写入逻辑保持原样，只收口宿主命令前提。

### 🧠 Design Intent (Why)
`rsync` 在这里并不是业务必需能力，只是“递归复制目录”的实现手段。既然 `open-computer-use` 的 npm 分发路径已经接受 Node 作为天然前提，就没必要再让 `install-codex-plugin` 多背一个额外系统命令依赖。改成 `cpSync` 后，安装器的运行时前提更一致，也更符合前面去掉 Python 依赖的方向。

### ✅ Verification
- `node --check scripts/install-config-helper.mjs`
- 临时 `CODEX_HOME` 下执行 `./scripts/install-codex-plugin.sh --configuration release`
- `node ./scripts/npm/build-packages.mjs --skip-build --package open-computer-use --out-dir dist/tmp/npm-stage-check`
- `rg -n "rsync" dist/tmp/npm-stage-check/open-computer-use -S`

### 📁 Files Modified
- `scripts/install-codex-plugin.sh`
- `scripts/install-config-helper.mjs`
