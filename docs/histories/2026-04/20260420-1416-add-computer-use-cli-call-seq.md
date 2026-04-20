## [2026-04-20 14:16] | Task: 为 computer-use-cli 增加顺序调用能力

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 想自己通过 `scripts/computer-use-cli/` 连官方 bundled `computer-use`，复现哪些 tool 调用会出现 overlay cursor，并直接用 `go run` 测。

### 🛠 Changes Overview
**Scope:** `scripts/computer-use-cli`

**Key Actions:**
- **新增 `call-seq` 子命令**: 允许在同一条 direct MCP 连接或同一条 app-server ephemeral thread 里顺序执行多个 tool call，解决官方 `computer-use` 动作类工具必须先做 `get_app_state` 的前置约束。
- **补充官方自测样例**: 新增 `examples/textedit-overlay-seq.json`，包含 `get_app_state -> set_value -> scroll -> perform_secondary_action` 的正例序列。
- **更新说明与测试**: README 补充 `call-seq` 用法与限制说明，单测覆盖顺序调用 JSON 解析。

### 🧠 Design Intent (Why)
官方 bundled `computer-use` 在动作类 tool 前要求同线程内已有对应 app 的最新 state。原来的 `call` 每次都会新建一个 app-server 临时 thread，无法直接用 `go run` 复现这条链路。新增 `call-seq` 后，用户可以用一个 JSON 文件稳定复现实测路径，也更适合后续继续做官方行为对比。

### 📁 Files Modified
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/app_server.go`
- `scripts/computer-use-cli/main_test.go`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/examples/textedit-overlay-seq.json`

### 🔁 Follow-up (2026-04-20 15:07)

- **[9 tool coverage sample]**: 将 `examples/textedit-overlay-seq.json` 扩成一条覆盖官方 9 个 tools 的 `TextEdit` 序列，方便直接用 `go run . call-seq` 手工观察整体效果。
- **[官方 stale-state 约束留档]**: 样例在每个会改动 app state 的 action 之间显式插入 `get_app_state`，因为官方 bundled `computer-use` 会在 mutation 后返回“先重新 query 最新 state”的约束。

**Follow-up Files:**
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/examples/textedit-overlay-seq.json`
