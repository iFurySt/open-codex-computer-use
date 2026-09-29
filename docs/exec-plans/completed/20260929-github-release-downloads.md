# GitHub Release direct downloads

## 目标

让 tag 驱动的 release workflow 在所有构建任务成功后，一次性把 Open Computer Use 的 macOS app、Linux / Windows CLI、skill、校验和与现有 Cursor Motion DMG 发布到 GitHub Releases，供不使用 npm 或 Homebrew 的用户直接下载和集成。

## 范围

- 包含：
  - 为已有 macOS universal app、Linux 双架构 binary、Windows 双架构 exe 生成清晰命名的 release archives。
  - 把 `open-computer-use` skill 的 `.zip` / `.skill` 制品加入 GitHub Release。
  - 生成 SHA-256 校验和与机器可读 asset manifest。
  - 将 GitHub Release 创建收敛为依赖全部构建 job 的单一发布 job。
  - 更新 CI/CD、发版指南、feature release notes 和 history。
- 不包含：
  - 新增 installer、Windows code signing 或 Linux desktop package。
  - 改变 npm package 结构或 runtime 行为。
  - 在本轮直接 bump 版本、打 tag 或发布公开 release。

## 背景

- 相关文档：
  - `docs/CICD.md`
  - `docs/releases/RELEASE_GUIDE.md`
  - `docs/SUPPLY_CHAIN_SECURITY.md`
- 相关代码路径：
  - `scripts/release-package.sh`
  - `scripts/package-skill.sh`
  - `.github/workflows/release.yml`
- 已知约束：
  - macOS runtime 必须保留在 `.app` bundle 中，才能复用稳定权限身份和 app-agent proxy。
  - GitHub Release asset 不能直接上传目录，因此 `.app` 必须封装为 zip。
  - 所有 GitHub Actions 必须固定到 commit SHA。

## 风险

- 风险：多个并行 job 同时创建或更新同一个 GitHub Release，可能产生半成品或竞态。
  - 缓解方式：构建 job 只上传 Actions artifacts，唯一的发布 job等待全部依赖成功后再统一上传。
- 风险：用户误把 macOS bundle 内 binary 单独复制出来，导致权限代理找不到 app。
  - 缓解方式：只发布完整 `.app.zip`，并在发版文档中说明 bundle 边界。
- 风险：release archive 漏架构或丢失可执行位。
  - 缓解方式：打包脚本验证 app 架构、签名、输入 executable，并在归档后检查文件清单和数量。

## 里程碑

1. 对照 Open Browser Use 的 release assets，确定命名与公开资产集合。
2. 实现直接下载制品打包与 manifest / checksum。
3. 重构 workflow 为构建后统一发布。
4. 完成本地打包验证、文档与 history 收口。

## 验证方式

- 命令：
  - `bash -n scripts/package-github-release-assets.sh scripts/release-package.sh`
  - `./scripts/package-github-release-assets.sh --version 0.3.5`
  - `./scripts/release-package.sh`
  - `make ci`
  - `git diff --check`
- 手工检查：
  - macOS zip 内只有完整 `Open Computer Use.app` bundle。
  - Linux archives 内 binary 名为 `open-computer-use` 且保留可执行位。
  - Windows archives 内 binary 名为 `open-computer-use.exe`。
  - skill zip 和 `.skill` 字节一致。
  - workflow 的 publish job 同时依赖 npm/direct-download assets 与 Cursor Motion DMG。

## 进度记录

- [x] 确认现有 GitHub Release 只公开 Cursor Motion DMG。
- [x] 对照 Open Browser Use 的 CLI / skill release asset 组织方式。
- [x] 完成直接下载制品打包脚本。
- [x] 完成 workflow 汇总发布 job。
- [x] 完成文档、history 与本地验证。
- [x] 完整 `release-package.sh` 实跑成功，产出 3 个 npm tarball 与 9 个 GitHub direct-download/meta assets；macOS archive 解压后签名和 universal 架构校验通过，SHA-256 全量校验通过。
- [x] Swift 168 项测试通过（1 项 live test 按默认配置跳过），Linux / Windows Go tests 与 Linux Python tests 通过。
- [x] 文档、Action pinning、shell syntax、workflow YAML 与 diff 检查通过。
- [x] 记录两项既有基线阻塞：`make ci` 在本次 diff 之外的仓库模板缺失检查处失败；Node REPL 测试稳定复现 20/21 通过、`WorkerJavaScriptSession` late throw 用例失败，相关源码未由本任务修改。

## 决策记录

- 2026-09-29：macOS 只发布完整 universal `.app.zip`，不发布脱离 bundle 的裸 binary；后者无法可靠保留 app-scoped 权限身份。
- 2026-09-29：Linux 和 Windows 延续 Open Browser Use 的 archive 形式，分别使用 `.tar.gz` 与 `.zip`，避免 GitHub asset 重名并保留平台惯用解压体验。
- 2026-09-29：GitHub Release 由单一汇总 job 创建；构建 job 不再直接写 Release。
- 2026-09-29：Developer ID 与 Apple notary secrets 同时可用时，先 notarize / staple direct-download app 再重新封装；缺少配置时保持既有 ad-hoc fallback。
