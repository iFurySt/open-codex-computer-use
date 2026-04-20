## [2026-04-20 18:42] | Task: 发布 0.1.16 并拆分本地 Dev app 身份

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 不然这样吧，原来 CI 上的就按照原来的方式来就行了（等我未来有证书了再来处理），这样就只以 CI 发的为准就行了。然后本地开发都用自己本地的 sign 就好了。不过本地 DEBUG 或者 dev 打包的时候，应用应该要加个 `(Dev)` 结尾，这样会明确一点。

### 🛠 Changes Overview
**Scope:** `.github/workflows/`、`apps/`、`docs/`、`packages/`、`plugins/`、`scripts/`

**Key Actions:**
- **[CI Boundary Reset]**: 把 release workflow 里的证书导入步骤移除，`package-npm` 重新明确使用 ad-hoc 打包，恢复 “CI 产物按原方式发布” 的边界。
- **[Dev App Split]**: 本地非 release 构建统一输出 `Open Computer Use (Dev).app`，display name 改成 `Open Computer Use (Dev)`，bundle identifier 改成 `com.ifuryst.opencomputeruse.dev`，避免和正式发布版继续显示成同名授权对象。
- **[Permission Routing]**: 权限发现逻辑在 dev bundle 运行时会优先绑定当前 dev app，而 release 运行时仍优先寻找稳定安装的正式 bundle；launch/install 脚本也同步适配新的 `(Dev)` 包名。
- **[Release Bump]**: 将插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、测试 MCP client version、CLI 文档路径与用户可见 release note 统一提升到 `0.1.16`。

### 🧠 Design Intent (Why)
这次目标不是继续强行让本地临时构建和 CI 分发产物共用一条签名链，而是先把“正式发布身份”和“本地开发身份”清晰拆开。CI 继续保持稳定、可重复的 release 入口；本地 dev/debug 构建则明确带上 `(Dev)` 后缀和独立 bundle id，这样既不会误导成和正式版完全等价，也能让系统权限列表里的两个对象一眼可区分。

### 📁 Files Modified
- `.github/workflows/release.yml`
- `scripts/build-open-computer-use-app.sh`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1842-bump-open-computer-use-to-0.1.16.md`
