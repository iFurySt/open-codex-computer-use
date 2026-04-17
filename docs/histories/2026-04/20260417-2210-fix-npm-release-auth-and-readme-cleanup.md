## [2026-04-17 22:10] | Task: 修复 npm release 认证并清理 npm README

### 📥 User Request

> npm 包页里把 `If you want the server without the visual cursor overlay:` 和下面那段 code block 删掉；发布这件事要一路干到能从 git tag 真正发出去，期间需要的话可以自己继续调版本或重发。

### 🔧 What Changed

- **清理 npm README 模板**：删除生成包 README 时那段“关闭 visual cursor overlay”的额外 MCP 配置示例，只保留默认安装与 MCP 配置说明。
- **补 npm 发布兜底链路**：在 `release.yml` 里新增 `Configure npm token fallback` 步骤；如果仓库配置了 `NPM_TOKEN` secret，就写入 `NODE_AUTH_TOKEN` 供 `npm publish` 使用。
- **同步仓库文档**：把根 README 和 `docs/CICD.md` 的发布说明改成“优先兼容 Trusted Publishing，同时支持 `NPM_TOKEN` secret 兜底”。

### 🧠 Design Intent (Why)

实际联调发现，GitHub Actions 构建已经能跑通，但 npm 发布会因为某些包没有单独配好 Trusted Publisher 而在 publish 阶段失败。对这个仓库来说，最稳妥的目标不是执着于单一路径，而是保证 `git tag` 这条 release 主路径真的能稳定把三份包发出去。

与此同时，npm 包页面对的是最终安装用户，README 应该尽量只保留默认成功路径，不额外堆可选环境变量分支，避免新用户以为还需要额外改 overlay 配置。

### 📌 Key Files

- `.github/workflows/release.yml`
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/CICD.md`
