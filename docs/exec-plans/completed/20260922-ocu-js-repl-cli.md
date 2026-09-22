# `ocu js` / `ocu repl` CLI

## 目标

让 npm 分发的 `open-computer-use` / `ocu` 在保留原生 9-tool MCP compatibility surface 的同时，正式提供一次性 `js` 执行和终端内持久 `repl`，并以稳定、可机器读取的 capability 诊断说明 Node、adapter 与 native runtime 是否可用。

## 范围

- 包含：
  - `ocu js '<code>'`、`ocu js -`、`ocu js --file <path>` 与 `--timeout`。
  - `ocu repl`，在当前终端会话内复用同一 JavaScript kernel 与 native MCP child。
  - `ocu capabilities` / `ocu capabilities --json`，以及 help 中稳定展示 `js` / `repl` 的可用状态。
  - 将 npm launcher 的命令分发逻辑移到可复用、可测试的 Node 模块。
  - npm staging、自动测试、CLI 实机验证和文档同步。
- 不包含：
  - 修改原生 `ocu mcp` 的 9-tool surface。
  - 把 `repl` 伪装成 MCP tool。
  - 本轮内置或下载一份独立 Node distribution。
  - 合入独立的 PR #79 修复。

## 背景

- 相关文档：
  - `docs/ARCHITECTURE.md`
  - `docs/references/js-repl.md`
  - `docs/RELIABILITY.md`
  - `docs/SECURITY.md`
- 相关代码路径：
  - `scripts/npm/build-packages.mjs`
  - `scripts/node-repl/open-computer-use-repl.mjs`
  - `scripts/node-repl/open-computer-use-kernel.mjs`
- 已知约束：
  - 当前 npm bin 使用 `#!/usr/bin/env node`，所以 PATH 完全缺少 Node 时，launcher 无法运行到 help 或 capability 检测阶段。
  - 已经运行起来的 launcher 应使用 `process.execPath` 对应的 Node，不应再次依赖 PATH 查找 `node`。
  - help 的命令面必须稳定；缺依赖时应显示 unavailable 与修复提示，而不是隐藏命令。
  - 不得在 commit 或 PR 中加入禁止的 Co-authored-by trailer。

## 风险

- 风险：`js` / `repl` 新增一层 native MCP child 与 Worker lifecycle，异常退出可能留下子进程。
  - 缓解方式：统一在 `finally`、stdin EOF 和 signal 路径关闭 Worker 与 native child，并增加集成测试。
- 风险：把 code-first 能力混入 `ocu mcp` 会破坏既有 host。
  - 缓解方式：launcher 只拦截 CLI 子命令；`mcp` 原样转发 native runtime。
- 风险：任意 JavaScript 具备启动进程用户的本地权限。
  - 缓解方式：延续现有安全文档与 native safety gate，并在 CLI help 中明确这一信任边界。
- 风险：动态隐藏命令会让 Agent 无法形成稳定调用策略。
  - 缓解方式：始终列出命令，以结构化 capability 状态表达可用性。

## 里程碑

1. 收敛生命周期、命令面和 capability contract。
2. 实现可测试 launcher、`js`、`repl` 与诊断。
3. 完成自动测试、npm 打包、Terminal 实测、文档与交付。

## 验证方式

- 命令：
  - `node --test scripts/node-repl/*.test.mjs`
  - `node ./scripts/npm/build-packages.mjs --skip-build`
  - `make check-docs`
  - `swift test`
  - `./scripts/run-tool-smoke-tests.sh`
- 手工检查：
  - `ocu --help` 稳定列出 `js` / `repl` 和当前状态。
  - `ocu capabilities --json` 返回 Node、adapter、native runtime 与两种 JS 模式的结构化状态。
  - positional、stdin、file 三种 `js` 输入都能执行，错误返回非零状态。
  - `repl` 连续输入保留 binding，`.reset` 清空，`.exit` / Ctrl-D 清理进程。
  - `ocu mcp` 的 `tools/list` 仍恰好为 9 个 native tools。
- 观测检查：
  - `js` 完成或失败后没有残留 adapter、Worker 或 native MCP child。
  - `repl` 只在当前 terminal session 内长驻。

## 进度记录

- [x] 确认进程生命周期与稳定 capability 展示策略。
- [x] 完成 CLI 模块、npm launcher 接入与 capability contract。
- [x] 完成测试、文档、history 与本机、Linux devbox 实机验证。
- [x] 同步远端并通过 PR #80 交付。

## 决策记录

- 2026-09-22：help 始终展示 `js` / `repl`，并新增 `capabilities` 状态；不根据 PATH 动态删除命令。
- 2026-09-22：`js` 是一次性 session，`repl` 在当前终端会话内持久，`mcp` 继续是 native 9-tool stdio server。
- 2026-09-22：当前 npm launcher 已依赖 Node，因此运行时直接复用 `process.execPath`。无 Node bootstrap 属于后续 native launcher / bundled Node 设计，不以不可靠的 PATH 探测伪装解决。
- 2026-09-22：最终验证覆盖 18 个 Node contract/integration tests、167 个 Swift tests、Linux/Windows Go tests、Linux Python tests、9-tool smoke、release 全平台构建、本机隔离 tgz 安装和 Linux x64 devbox 隔离安装。两端都验证了 help/capabilities、一次性 `js`、stdin、持久 binding、`.editor`、`.reset`、SIGTERM child cleanup 和原生 MCP 恰好 9 tools。完整 `scripts/ci.sh` 只被 `main` 已存在的 repository-hygiene 缺失文件阻断，其余子步骤均单独通过。
- 2026-09-22：PR #80 以 squash merge 合入 `main`，merge commit 为 `07610f09b0c118c45cc3bd0a8781029f678e3b7d`；仓库没有为该 commit 配置或触发 GitHub Actions run。合并后的 `main` 再次通过 capabilities、`js`、多行 `repl` 和 native 9-tool sanity check。
