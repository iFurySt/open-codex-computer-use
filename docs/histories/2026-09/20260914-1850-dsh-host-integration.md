## [2026-09-14 18:50] | Task: 为 DeepSeek Harness 补齐宿主集成

### 🤖 Execution Context
* **Agent ID**: `session-66aa166d-ee60-437e-a52e-940a311c8c76` (DSH)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI

### 📥 User Query
> 你要复用的话，那我 fork 的那个仓库有 dsh 插件吗？如果其他人想在我 fork 仓库基础上在 dsh 使用是否也具备我当前同等能力，不能把复用简单化懂吗，最终是要在每台 mac 电脑上，同样适用 dsh 服务都一样的能力。

（背景：本轮之前，DSH 侧的能力是在一台机器上手工拼出来的——自己写 `cordis.patch.yml` 片段、自己写 `~/.dsh/ocu-hooks.json`、自己把 skill 拷进 `~/.dsh/skills`。仓库里没有任何 DSH 集成，别人 clone 之后拿到的是零。）

### 🛠 Changes Overview
**Scope:** `scripts/`（宿主安装器）、`scripts/npm/`（npm 包命令表与打包）、`skills/open-computer-use/references/`、`README.md`、`scripts/ci.sh`。

**Key Actions:**
- **新增 DSH 宿主安装器**：`scripts/install-dsh-mcp.sh`（`--profile` / `--dsh-home` / `--command` / `--no-hook` / `--no-skill`），与既有 `install-{claude,codex,gemini,opencode}-mcp.sh` 同一形状。
- **`install-config-helper.mjs` 新增 `dsh-mcp` 子命令**：往 `<dsh-home>/profiles/<profile>/cordis.patch.yml` 写入由 marker 包裹的托管块（MCP 行 + turn 边界钩子行），并写 `<dsh-home>/ocu-hooks.json`。块按 marker 原位替换而非合并，因此可重复执行且不动用户自己的行。
- **turn 边界钩子随 MCP 一起安装**：用 `@deepseek-ai/dsh-hooks-codex` 把 `Stop`（= `agent/turn-stopping`）映射到 `open-computer-use turn-ended`。这是 DSH 区别于其它宿主的必需项，理由见下。
- **skill 安装到 `<dsh-home>/skills`**：DSH 把该目录当作用户级 skill 根扫描，所有新会话可见。
- **npm 侧对齐**：`scripts/npm/build-packages.mjs` 增加 `install-dsh-mcp` 命令、帮助文本、`help install-dsh-mcp` 分支、打包清单与拷贝逻辑（含把 `skills/open-computer-use` 打进包里，否则 npm 用户没有 skill 可用）。
- **文档**：`skills/open-computer-use/references/installation.md` 增加 DSH 章节；`README.md` 宿主命令列表补齐。
- **验证能力**：新增 `scripts/tests/install-dsh-mcp.test.sh` 并接入 `scripts/ci.sh`。

### 🧠 Design Intent (Why)
- **钩子必须和 MCP 一起装**：OCU 的软件光标只在 turn 边界隐藏，触发源是 MCP 通知 `notifications/turn-ended`（`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift` → `SoftwareCursorOverlay.reset()`；设计取舍见 `SoftwareCursorOverlay.swift:425-429`——进程内没有 inactivity timer，因为一轮里模型思考数分钟是常态）。而 `dsh-mcp-client` 从不发送该通知，任何会话或子代理调过一次动作后光标会永久留在屏幕上。只写 MCP 配置的安装器会把这个缺陷一起交付给用户。
- **用 marker 块而不是解析 YAML**：helper 是零依赖的（只用 `node:fs`/`node:path`），而 profile patch 是用户也会手改的 YAML。一对注释 marker 圈定托管区间、整块替换，既不需要 YAML 依赖，也不会破坏用户自己的行。
- **`--command` 必须是绝对路径**：DSH 的 mcp-client 直接 spawn 可执行文件（不经过 shell），PATH 上的裸命令名对它无效；安装器按 `--command` → `$OPEN_COMPUTER_USE_COMMAND` → 常见 app 安装位置 → npm 全局布局 → PATH shim 的顺序探测，全失败时给出可执行的修复指引。
- **把 skill 打进 npm 包**：否则 npm 安装路径下找不到 skill 源，"同等能力"就只在源码 checkout 场景成立。

### 📁 Files Modified
- `scripts/install-dsh-mcp.sh`（新增）
- `scripts/install-config-helper.mjs`
- `scripts/npm/build-packages.mjs`
- `scripts/tests/install-dsh-mcp.test.sh`（新增）
- `scripts/ci.sh`
- `skills/open-computer-use/references/installation.md`
- `README.md`

### ✅ Verification
- `scripts/tests/install-dsh-mcp.test.sh`：5 项断言全部通过（保留用户行 + 两条托管行、钩子命令带引号、skill 落位、重复执行字节不变、`--no-hook`/`--no-skill` 生效）。
- `bash -n` / `node --check`：新增与改动的脚本通过。
- 产物 YAML 经独立解析器校验：顶层 2 个条目，`insert` 中 id 为 `["mcp-open-computer-use", "ocu-turn-ended-hook"]`。
- 与真机对照：在相同的目录结构下安装后，产物与当前手工维护的 DSH 配置等价。

### ⚠️ 未覆盖 / 风险
- 未在全新 Mac（无历史 DSH profile、无既有 OCU 安装）上端到端跑过；命令探测只在本机覆盖了 app 包路径与显式 `--command`。
- Windows / Linux 未覆盖：钩子命令与 `~/Applications` 探测都是 macOS 取向。
- 安装器不负责构建或安装 app 本身：只注册已存在的可执行文件，找不到时失败并提示（`npm install -g open-computer-use` 或源码 `make app`）。
- `--no-hook` 会把光标粘屏问题留给用户，帮助文本已明确说明。
