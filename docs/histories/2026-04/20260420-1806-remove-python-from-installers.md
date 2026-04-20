## [2026-04-20 18:06] | Task: 去掉 install-* 对 Python 的运行时依赖

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `open-computer-use install-codex-mcp` 现在报 `python3 with tomllib is required`，理论上 install 命令不应该依赖 Python；可以考虑 Swift 之类的来做，把所有 `install-*` 都检查处理一下。

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/`, `docs/histories/`

**Key Actions:**
- **抽出共享安装配置 helper**：新增 `scripts/install-config-helper.mjs`，集中处理 Claude JSON、Codex TOML 和 plugin manifest 的读写逻辑。
- **去掉 install-* 的 Python 依赖**：`install-claude-mcp.sh`、`install-codex-mcp.sh`、`install-codex-plugin.sh` 全部改为调用 Node helper，不再要求本机有 `python3` / `tomllib`。
- **同步 npm 分发内容**：更新 `scripts/npm/build-packages.mjs`，把新的 helper 一并打进 npm 包，避免全局安装包缺文件。

### 🧠 Design Intent (Why)
这几个安装命令本质上是 npm CLI 的一部分，运行时再额外要求 Python 既不符合用户预期，也会让最简单的安装路径被系统 Python 版本绊住。相比运行时 `swift` 脚本，Node 已经是 npm 包成立的前提，直接把配置改写逻辑收口到一个随包分发的 helper 里，依赖更少、行为也更一致。

### ✅ Verification
- `node --check scripts/install-config-helper.mjs`
- 用临时 `CODEX_HOME` 执行 `./scripts/install-codex-mcp.sh`，验证旧别名迁移和重复执行 no-op
- 用临时 `CLAUDE_CONFIG_PATH` 执行 `./scripts/install-claude-mcp.sh`，验证 JSON 幂等写入
- 用临时 `CODEX_HOME` 执行 `./scripts/install-codex-plugin.sh --configuration release`，验证 plugin cache 与 `config.toml` 更新
- `node ./scripts/npm/build-packages.mjs --skip-build --package open-computer-use --out-dir dist/tmp/npm-stage-check`

### 📁 Files Modified
- `scripts/install-config-helper.mjs`
- `scripts/install-claude-mcp.sh`
- `scripts/install-codex-mcp.sh`
- `scripts/install-codex-plugin.sh`
- `scripts/npm/build-packages.mjs`
