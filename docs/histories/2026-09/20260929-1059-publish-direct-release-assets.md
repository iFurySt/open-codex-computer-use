## [2026-09-29 10:59] | Task: 发布可直接下载的跨平台制品

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-5
* **Runtime**: TraeCode

### 📥 User Query
> 在 CI 后把 Open Computer Use 的 macOS app、Windows exe、CLI binary 和 skill 发布到 GitHub Releases，让用户无需 npm 或 Homebrew 也能下载集成；参考 Open Browser Use 的发布方式。

### 🛠 Changes Overview
**Scope:** release packaging、GitHub Actions 与用户文档。

**Key Actions:**
- 新增 direct-download 打包脚本，封装 macOS universal app、Linux / Windows 双架构 CLI 与 skill，并生成 SHA-256 校验和及 manifest。
- 将 GitHub Release 创建收敛到单一汇总 job，等待 npm/direct-download 和 Cursor Motion DMG 构建成功后再发布全套 assets。
- 为 Developer ID 签名的 direct-download macOS app 接入可选 notarization 与 staple。
- 补充架构、CI/CD 与发版指南中的直接下载、验证和失败排查说明。

### 🧠 Design Intent (Why)
macOS runtime 必须保留完整 app bundle 才能维持稳定的权限身份；Linux / Windows 则适合像 Open Browser Use 一样以按平台和架构命名的 CLI archive 直接分发。统一的发布 job 可以避免并行任务提前创建只有部分 assets 的 Release。

### 📁 Files Modified
- `scripts/package-github-release-assets.sh`
- `scripts/release-package.sh`
- `.github/workflows/release.yml`
- `package.json`
- `Makefile`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/releases/feature-release-notes.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/exec-plans/completed/20260929-github-release-downloads.md`

### Validation

- `./scripts/release-package.sh` 完整通过，生成 3 个 npm tarball、macOS app zip、Linux / Windows 双架构 CLI archives、两种 skill 包、checksums 与 manifests。
- macOS archive 解压后通过 `codesign --verify --deep --strict`，binary 为 `x86_64 arm64` universal；Linux / Windows 输入 binary 的四个目标架构经 `file` 确认。
- `SHA256SUMS` 全量验证通过，skill `.zip` / `.skill` 字节一致，版本不匹配会被打包脚本拒绝。
- Swift 168 项测试通过（1 项 live test 默认跳过）；Linux / Windows Go tests 和 Linux Python tests 通过；文档、Action pinning、shell syntax、workflow YAML、diff 检查通过。
- 仓库既有基线仍有两项非本次改动导致的失败：`make ci` 会先被缺失的模板文件阻断；Node REPL suite 为 20/21，通过之外的失败是既有 `WorkerJavaScriptSession` late throw 用例。
