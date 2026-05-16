# Open Computer Use skill

## 用户诉求

用户希望确认仓库当前是否没有 skills，并参考 `open-codex-browser-use` 的 `skills/` 结构，为本仓库补上 `open-computer-use` skill；`SKILL.md` 作为 TOC，安装、使用、排障等内容拆到按需加载的文件里；同时在中英文 README 里增加 `npx skills` 安装和升级方式。

## 改动

- 新增 `skills/open-computer-use/SKILL.md`，作为 Open Computer Use agent skill 入口和目录。
- 新增 `skills/open-computer-use/references/installation.md`、`usage.md`、`troubleshooting.md`，拆分安装、MCP/CLI 使用和排障说明。
- 新增 `skills/open-computer-use/agents/openai.yaml`，提供 agent 展示元数据和默认提示。
- 新增 `scripts/package-skill.sh` 与 `package:skill` npm script，用于校验并打包 `.zip` / `.skill` 制品。
- 更新 `README.md` 和 `README.zh-CN.md`，加入 `npx skills add` 和 `update` 的安装与升级命令。
- 更新 `docs/ARCHITECTURE.md`，补充 `skills/` 目录和 skill 打包验证路径。

## 设计动机

沿用 `open-codex-browser-use` 的 skill 组织方式，让 agent 先读取轻量入口，再按任务需要打开安装、使用或排障参考，避免把所有细节塞进单个 `SKILL.md`。同时保留打包脚本，方便后续 release 附带可下载 skill 制品。

## 影响文件

- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/installation.md`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/references/troubleshooting.md`
- `skills/open-computer-use/agents/openai.yaml`
- `scripts/package-skill.sh`
- `package.json`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
