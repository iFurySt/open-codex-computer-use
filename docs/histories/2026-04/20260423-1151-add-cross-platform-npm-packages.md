## [2026-04-23 11:51] | Task: 三端 npm 安装按 os-arch 选择 native runtime

## 用户诉求

希望 `npm i -g open-computer-use` 在 macOS、Linux、Windows 上都能安装成功，并根据当前 `os-arch` 调用对应的 `.app`、Linux binary 或 Windows `.exe`。本轮还需要 bump patch version、tag 推送触发 release，并在 Linux VM 上实测 npm 全局安装后的 MCP tools list。

## 主要改动

- **[NPM Packaging]**: 将 npm staging 从单一 macOS package 改为三个 root/alias packages 加六个 platform packages：`darwin-arm64`、`darwin-x64`、`linux-arm64`、`linux-x64`、`win32-arm64`、`win32-x64`。
- **[Runtime Launcher]**: root package 的 `bin/open-computer-use` 改为跨平台 Node launcher，通过 `process.platform` / `process.arch` 解析并执行对应 native package；缺少 optional dependency 时给出明确重装提示。
- **[Release Flow]**: release package 构建现在会同时构建 macOS app、Linux binaries、Windows exes；publish script 会先发布 platform packages，再发布 root/alias packages。
- **[Plugin Path]**: Codex plugin launcher 和 installer 增加 Linux / Windows native payload fallback，保留 macOS app bundle 路径。
- **[Version Bump]**: 将插件 manifest、Swift 版本常量、Linux/Windows Go runtime、smoke/test 输入和 CLI helper 文档统一 bump 到 `0.1.34`。
- **[Docs]**: 同步 README、中文 README、架构文档、CI/CD、质量说明、release guide、feature release notes 和相关 execution plans。

## 设计动机

使用 npm 原生的 `optionalDependencies`、`os`、`cpu` 机制，而不是 postinstall 下载制品。这样 root package 可以保持一个用户入口，平台包由 npm 根据当前环境选择，安装路径也更容易复现和审计。macOS 继续构建 universal `.app`，但拆成 `darwin-arm64` / `darwin-x64` 两个 npm platform packages，让 launcher 的映射规则在三端保持一致。

## 受影响文件

- `.github/workflows/release.yml`
- `scripts/npm/build-packages.mjs`
- `scripts/npm/publish-packages.mjs`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseWindows/main.go`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `docs/`

## 验证

- 通过：`node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`
- 通过：`./scripts/release-package.sh`
- 通过：本地 npm prefix 安装 `open-computer-use-0.1.34.tgz` + `open-computer-use-darwin-arm64-0.1.34.tgz` 后，`open-computer-use --version` 输出 `0.1.34`。
- 通过：本地 npm prefix 安装后的 `open-computer-use mcp` raw JSON-RPC `tools/list` 返回 9 个 tools。
- 通过：`swift test`
- 通过：`(cd apps/OpenComputerUseLinux && go test ./...)`
- 通过：`(cd apps/OpenComputerUseWindows && go test ./...)`
- 通过：`node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging --dry-run`，发布顺序为六个 platform packages 先于三个 root/alias packages。
- 通过：`git diff --check`
- 待补：GitHub Actions release workflow。
- 待补：Linux VM npm 全局安装和 MCP `tools/list`。
