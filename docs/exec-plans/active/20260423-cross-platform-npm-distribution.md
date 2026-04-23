# Cross-platform npm distribution

## 目标

让 `npm i -g open-computer-use` 在 macOS、Linux 和 Windows 上都能安装同一个 root package，并由 root launcher 根据当前 `os-arch` 调用对应的 native app 或 binary。

## 范围

- 包含：
  - 把 npm staging 从单一 macOS app 包改成 root/meta package + platform packages。
  - 为 `darwin-arm64`、`darwin-x64`、`linux-arm64`、`linux-x64`、`win32-arm64`、`win32-x64` 生成可发布 npm 包。
  - 调整 release/publish 顺序，先发布平台包，再发布 root/alias 包。
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

- 风险：root package 发布早于 platform packages，用户立刻安装时缺少 optional dependency。
  - 缓解方式：publish script 按 package 类型排序，platform packages 优先。
- 风险：用户用 `--omit=optional` 或 npm 跳过 optional dependency 后，root launcher 找不到 native runtime。
  - 缓解方式：launcher 输出明确的缺失平台包和重装命令。
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
  - root packages 包含 `optionalDependencies`。
  - platform packages 包含正确的 `os` / `cpu`。
  - npm tarball 数量和 release manifest 对齐。
- 观测检查：
  - GitHub Actions release workflow 成功。
  - npm registry 最新版可见。
  - Linux VM `npm i -g open-computer-use@<version>` 后 raw MCP `tools/list` 返回 9 个 tools。

## 进度记录

- [x] 确认当前 npm 包仍是 macOS-only。
- [x] 完成 root/meta package 与 platform package staging。
- [x] 完成 publish 顺序与 CI Go toolchain 调整。
- [x] 完成版本、文档、history 同步。
- [x] 完成本地验证：staging / release tarballs / dry-run publish / Swift tests / Linux Go tests / Windows Go tests / macOS npm prefix install / MCP tools list。
- [ ] 完成 tag release、CI 跟踪、npm registry 验证。
- [ ] 完成 Linux VM npm install 与 MCP tools/list 验证。

## 决策记录

- 2026-04-23：采用 npm `optionalDependencies` + 每平台 `os`/`cpu` package，而不是 postinstall 下载制品。这样安装路径更可复现，也避免 install script 依赖额外网络下载逻辑。
- 2026-04-23：macOS 仍构建 universal `.app`，但发布为 `darwin-arm64` 和 `darwin-x64` 两个 npm platform package。这样 root launcher 统一按 `process.platform-process.arch` 做映射。
