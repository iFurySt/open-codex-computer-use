# Cross-platform npm distribution

## 目标

让 `npm i -g open-computer-use` 在 macOS、Linux 和 Windows 上都能安装同一个既有 npm package，并由 root launcher 根据当前 `os-arch` 调用包内对应的 native app 或 binary。

## 范围

- 包含：
  - 把 npm staging 从单一 macOS app 包改成三端 bundled artifacts。
  - 既有 `open-computer-use`、`open-computer-use-mcp`、`open-codex-computer-use-mcp` 三个包内置 `darwin-arm64`、`darwin-x64`、`linux-arm64`、`linux-x64`、`win32-arm64`、`win32-x64` runtime。
  - 保持 release/publish 面只包含既有三个 npm 包名。
  - 更新 release workflow、README、架构文档、发版指南和 history。
  - bump patch version、tag release，并用 Linux VM 实测 npm 全局安装后的 MCP `tools/list`。
- 不包含：
  - 新增 Linux/Windows 图形 fixture。
  - 完成 Windows 交互式桌面 smoke。
  - 改变 9 个 tools 的协议面。

## 背景

- 相关文档：
  - `docs/ARCHITECTURE.md`
  - `docs/CICD.md`
  - `docs/releases/RELEASE_GUIDE.md`
- 相关代码路径：
  - `scripts/npm/build-packages.mjs`
  - `scripts/npm/publish-packages.mjs`
  - `scripts/release-package.sh`
  - `.github/workflows/release.yml`
  - `scripts/build-open-computer-use-linux.sh`
  - `scripts/build-open-computer-use-windows.sh`
- 已知约束：
  - 当前 npm registry 上的 `open-computer-use@0.1.33` 仍声明 `os=["darwin"]`，Linux/Windows 不会正常安装。
  - Linux/Windows runtime 是实验性 first version，但已经暴露同一组 9 个 MCP tools。
  - root package 需要保持 `open-computer-use`、`open-computer-use-mcp`、`open-codex-computer-use-mcp` 三个历史入口。

## 风险

- 风险：包体积比 macOS-only 版本更大。
  - 缓解方式：先保持既有 npm 包名和可复现安装路径，后续如果 npm package 权限准备好再评估拆分平台包。
- 风险：launcher 找不到当前 `os-arch` 的 bundled runtime。
  - 缓解方式：launcher 输出明确的缺失 bundled artifact 路径和重装命令。
- 风险：CI macOS runner 没有 Go toolchain，导致 Linux/Windows cross compile 失败。
  - 缓解方式：release workflow 显式 setup Go。
- 风险：Linux runtime 需要桌面 session，纯 SSH 不能验证 GUI 操作。
  - 缓解方式：本次 Linux 发布后验证目标限定为 npm install、版本、MCP initialize 和 `tools/list`。

## 里程碑

1. 设计并实现 npm 包结构。
2. 同步文档、history 和版本源。
3. 本地 staging / pack / MCP tools list 验证。
4. 提交、tag、推送并跟踪 release workflow。
5. Linux VM 全局 npm 安装最新版并验证 MCP tools list。

## 验证方式

- 命令：
  - `node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`
  - `./scripts/release-package.sh`
  - `swift test`
  - `(cd apps/OpenComputerUseLinux && go test ./...)`
  - `(cd apps/OpenComputerUseWindows && go test ./...)`
  - `node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging --dry-run`
- 手工检查：
  - root/alias packages 不再声明 `optionalDependencies`。
  - staging 包包含 `dist/Open Computer Use.app`、`dist/linux/` 和 `dist/windows/`。
  - npm tarball 数量为 3，和 release manifest 对齐。
- 观测检查：
  - GitHub Actions release workflow 成功：`24816330343`。
  - npm registry `open-computer-use@0.1.35`、`open-computer-use-mcp@0.1.35`、`open-codex-computer-use-mcp@0.1.35` 可见。
  - Linux VM `npm i -g open-computer-use@0.1.35` 后 raw MCP `tools/list` 返回 9 个 tools。

## 进度记录

- [x] 确认当前 npm 包仍是 macOS-only。
- [x] 完成 root/alias package bundled artifact staging。
- [x] 完成 publish 面收敛到既有三个 npm 包，并保留 CI Go toolchain 调整。
- [x] 完成版本、文档、history 同步。
- [x] 完成本地验证：staging / release tarballs / dry-run publish / Swift tests / Linux Go tests / Windows Go tests / macOS npm prefix install / MCP tools list。
- [x] 完成 tag release、CI 跟踪、npm registry 验证。
- [x] 完成 Linux VM npm install 与 MCP tools/list 验证。

## 决策记录

- 2026-04-23：初版采用 npm `optionalDependencies` + 每平台 `os`/`cpu` package，但 `v0.1.34` release 在 CI 发布新 npm package 名时被 npm 权限挡住。
- 2026-04-23：`v0.1.35` 改为在既有三个 npm package 中 bundled 三端六个 runtime，避免新增 package 名权限问题；root launcher 继续按 `process.platform-process.arch` 做映射。
