## [2026-10-17 14:49] | Task: Rename repository to open-computer-use

### Execution Context

- Agent ID: `/root`
- Base Model: GPT-6 family（运行时未暴露精确模型标识）
- Runtime: Codex desktop

### User Query

将仓库改名为 Open Computer Use，并同步 npm 发布相关设置，确认既有包、App 与分发链路的兼容性。

### Changes Overview

- 将 GitHub 仓库迁移到 `iFurySt/open-computer-use`，保持仓库 ID、Stars、Issues、Git 历史和 Release 制品；共享 origin 使用新地址。
- 更新双语 README、徽章、skill 安装地址、plugin 和 npm 元信息、Go module 路径与发布模板。
- 保留三个 npm 包名、CLI 别名、旧 MCP 配置迁移、App Bundle ID 和签名身份。
- 发布 notes 校验接受规范地址与原始历史地址；新增回归，拒绝无关仓库、相似 URL 和错误 tag。
- 同步发布指南和功能记录；histories、已完成计划、已发布 notes 和逆向样本保留原文。
- 用户逐包完成安全密钥验证后，为三个 npm 包新增新仓库名的 Trusted Publisher，沿用原有权限；真实认证成功后，新连接均为 Valid，临时验证分支已清理。

### Design Intent

让仓库地址与跨 Agent、跨平台的产品身份一致，同时保持已有安装和历史发布兼容。npm Trusted Publisher 的页面状态不能替代真实 OIDC 认证验证。

### Validation

- Node REPL / CLI / release notes：40 tests passed。
- Linux / Windows Go runtime：`go test ./...` passed；Linux Python：14 tests passed；DSH 安装回归 passed。同步并发合入的 #100 后，在真实 GitHub Linux runner 上补跑两个 Go runtime、14 个 Python 测试与 4 个 release-notes 测试，platform tests step 全部通过（run 39011557748）；本机 macOS 不满足新增 bridge 测试的 Linux 平台要求。
- `make check-docs`、Action SHA pinning、shell syntax 与 `git diff --check` passed。
- 基于已发布 1.1.1 runtime 生成并 pack 三个 npm 包，规范 repository / homepage / bugs 地址与四个 CLI 入口检查通过；universal App 的四个 Locked Use 组件签名验证通过，App 身份保持不变；`ocu capabilities --json` 全部可用。
- 新旧 GitHub API / Git 地址指向同一仓库；已有 macOS Release 下载返回 HTTP 200。
- 基础 CI 的 repo-hygiene 检查因 main 既有的 11 个模板文件缺失而失败；相关检查已分别执行，没有扩大本次改名范围。
- npm 旧 Trusted Publisher 页面在改名后仍显示 Valid，但三个包的真实 OIDC token exchange 均返回 HTTP 404。新增新名称连接后，[最终复验 run 39012120822](https://github.com/iFurySt/open-computer-use/actions/runs/39012120822) 全部成功：三个包均返回 HTTP 201，随后页面均显示 Valid，最初的 Pending validation 已解除。没有发布新版本、保存返回的 token 或扩大原有权限。
- 旧名失效连接保留为迁移记录，下次正式发版成功后可按需清理；现有 npm 版本仍为 1.1.1，规范仓库元信息随下一次正常发版生效。

### Files Modified

- `README.md`、`README.zh-CN.md`、`AGENTS.md`
- `scripts/npm/build-packages.mjs`
- `scripts/validate-github-release-notes.mjs`、`scripts/tests/release-notes.test.mjs`
- `scripts/ci.sh`、`scripts/init-project.sh`、`Makefile`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `apps/OpenComputerUseLinux/go.mod`、`apps/OpenComputerUseWindows/go.mod`
- `skills/open-computer-use/references/installation.md`
- `docs/releases/RELEASE_GUIDE.md`、`docs/releases/github/TEMPLATE.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20261017-repository-rename.md`
