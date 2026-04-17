# CI/CD 说明

这个模板自带一套不依赖具体语言栈的 CI/CD 骨架。

## 当前 release 入口

- `scripts/release-package.sh`：构建 universal `Open Computer Use.app`，stage 三个 npm 包目录，并产出 `dist/release/npm/*.tgz` 与 `dist/release/release-manifest.json`。
- `.github/workflows/release.yml`：支持 push semver tag 自动发布，也支持手动触发；它会调用仓库内的 npm release 打包逻辑，并优先兼容 GitHub Actions OIDC / npm Trusted Publishing，同时支持仓库 `NPM_TOKEN` secret 作为发布兜底。

## 设计原则

这套默认流水线的目标，是在项目真正成形前先把交付链路搭起来，而不是假装已经知道未来项目该怎么 build 和 deploy。

当新项目的技术栈确定后，你应该继续在 `scripts/release-package.sh` 这条真实构建链路上扩展，而不是另起一套平行流程。

所有 GitHub Actions 都已经 pin 到 commit SHA。后续升级 action 时，也要继续保持这个约束。

## 推荐接入顺序

1. 保留 `ci.yml`，作为仓库的基础门禁。
2. 在 `scripts/ci.sh` 里继续叠加项目自己的验证命令。
3. 在 `scripts/release-package.sh` 已有的真实构建基础上继续扩展 release 产物。
4. 技术栈和环境稳定后，再补具体的部署 job。
5. 即使交付方式变化，SBOM 和 provenance 这类供应链能力也建议保留。

## 默认 release 产物

当前 release 流水线会产出：

- `dist/release/release-manifest.json`
- `dist/release/npm/open-computer-use-<version>.tgz`
- `dist/release/npm/open-computer-use-mcp-<version>.tgz`
- `dist/release/npm/open-codex-computer-use-mcp-<version>.tgz`
- GitHub Actions 中上传的 npm release artifact

也就是说，即使项目还没进入更复杂的部署阶段，仓库现在也已经具备了一条真实可复用的 npm 制品封装链路。
