## [2026-09-14 18:50] | Task: 为 DeepSeek Harness 补齐宿主集成

### 🤖 Execution Context
* **Agent ID**: `session-66aa166d-ee60-437e-a52e-940a311c8c76` (DSH)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI

### 变更原因

把已有的本机 DSH 配置收敛为仓库可复用的安装入口，并确保新机器能够获得一致、可验证且不会静默覆盖用户文件的集成。

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
- **非破坏性 skill 安装**：目标目录已存在且与 checkout 不一致时只警告不覆盖，`--force-skill` 才替换并留时间戳备份。理由：本机就存在一份比仓库更详细的中文运维版技能，直接覆盖等于静默毁掉用户自己的内容。
- **安装前完成 MCP 握手**：执行 `initialize` 与 `tools/list`，校验 server identity 和非空、合法的工具目录；不锁死工具数量，避免 OCU 演进时安装器误拒绝兼容版本，目标错误时也不会写 profile。
- **失败策略收紧**：显式安装的 MCP 行使用 `failOnStartupError: true`，避免 DSH 启动成功但用户请求的桌面工具实际缺席。
- **明确兼容层定位**：该安装器通过通用 `dsh-mcp-client` 接入，不冒充 DSH 的 first-class computer-use provider，也不会占用其 provider slot。

### 🧠 Design Intent (Why)
- **钩子必须和 MCP 一起装**：OCU 的软件光标只在 turn 边界隐藏，触发源是 MCP 通知 `notifications/turn-ended`（`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift` → `SoftwareCursorOverlay.reset()`；设计取舍见 `SoftwareCursorOverlay.swift:425-429`——进程内没有 inactivity timer，因为一轮里模型思考数分钟是常态）。而 `dsh-mcp-client` 从不发送该通知，任何会话或子代理调过一次动作后光标会永久留在屏幕上。只写 MCP 配置的安装器会把这个缺陷一起交付给用户。
- **用 marker 块而不是解析 YAML**：helper 是零依赖的（只用 `node:fs`/`node:path`），而 profile patch 是用户也会手改的 YAML。一对注释 marker 圈定托管区间、整块替换，既不需要 YAML 依赖，也不会破坏用户自己的行。
- **`--command` 固定为绝对路径**：DSH 的 mcp-client 可以通过 PATH 找命令，但 GUI / 后台启动未必继承安装时的 PATH；安装器因此把显式路径限制为绝对路径，并把自动发现的 PATH shim 固化为绝对路径。
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
- `scripts/tests/install-dsh-mcp.test.sh`：覆盖 MCP 握手、工具目录、失败前不写配置、显式命令不回退、绝对路径、同 id / 同 `serverName` 冲突、用户行保留、钩子命令、skill 落位、幂等、`--no-hook` / `--no-skill`、非破坏更新与备份。
- 生成的 patch 通过当前 DSH profile loader；真实 `open-computer-use 0.1.54` 完成 MCP 握手并发现 9 个工具。
- `bash -n` / `node --check`：新增与改动的脚本通过。
- 产物 YAML 经独立解析器校验：顶层 2 个条目，`insert` 中 id 为 `["mcp-open-computer-use", "ocu-turn-ended-hook"]`。
- 与真机对照：在相同的目录结构下安装后，产物与当前手工维护的 DSH 配置等价。

### ⚠️ 未覆盖 / 风险
- 未在全新 Mac 的发布版 DSH Web UI 上完成模型驱动的桌面动作 E2E；仓库验证覆盖 profile 解析、MCP 握手与工具发现。
- Windows / Linux 未覆盖：钩子命令与 `~/Applications` 探测都是 macOS 取向。
- 安装器不负责构建或安装 app 本身：只注册已存在的可执行文件，找不到时失败并提示（`npm install -g open-computer-use` 或源码 `make app`）。
- `--no-hook` 会把光标粘屏问题留给用户，帮助文本已明确说明。
- DSH 已提供一等 computer-use provider 注册模型；本安装器仍是通用 MCP 兼容路径，不负责跨仓库实现 OCU 专属 DSH provider。
