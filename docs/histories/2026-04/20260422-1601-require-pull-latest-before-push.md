## [2026-04-22 16:01] | Task: require syncing latest remote code before push

### 背景

- 用户要求把“push 前先拉最新代码”补进仓库规则，并明确加到 `AGENTS.md`。

### 变更

- **[Agent Routing]**: 在 `AGENTS.md` 的工作规则中补充显式约束：推送前先同步远端最新代码，再执行 `git push`。
- **[Canonical Repo Rule]**: 在 `docs/REPO_COLLAB_GUIDE.md` 的 Git 约定中同步同一条规则，避免该要求只停留在入口导航文档里。

### 验证

- 通过：`make check-docs`

### 影响文件

- `AGENTS.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/histories/2026-04/20260422-1601-require-pull-latest-before-push.md`
