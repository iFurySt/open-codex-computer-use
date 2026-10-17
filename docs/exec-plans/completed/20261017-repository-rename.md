# 仓库改名为 open-computer-use

## 目标

将 GitHub 仓库从 `iFurySt/open-codex-computer-use` 改名为 `iFurySt/open-computer-use`，同步 npm、plugin、skill、发布校验和当前文档，保持现有安装与 App 身份兼容。

## 完成状态

2026-10-17 已完成：仓库代码通过 #107 合入 main，三个 npm 包的新 Trusted Publisher 已保存并完成真实 OIDC 验证，页面均显示 Valid。

## 范围与约束

- 更新当前仓库引用、Go module 路径和本地 origin。
- 核对三个既有 npm 包的 Trusted Publisher；账号登录或两步验证由用户完成。
- 保留三个 npm 包名、CLI 别名、MCP 旧配置迁移、App Bundle ID、签名与制品命名。
- 保留 histories、已完成计划、已发布 release notes 和逆向样本的历史原文；发布校验兼容旧仓库链接。
- 此任务更新发布配置，不以发布新版本作为验证手段。

## 风险与缓解

- npm provenance 要求包内 repository.url 与实际仓库一致：同步包生成脚本，并检查真实 staging 包。
- Trusted Publisher 与 GitHub 仓库身份绑定：检查账号设置，保持 workflow 为 release.yml。
- 旧链接依赖 GitHub 重定向：验证旧地址与新地址对应同一 repository ID，不复用旧仓库名。
- 历史发布校验可能被新地址破坏：增加兼容性测试，覆盖新旧地址及无关仓库拒绝。

## 验证方式

- 仓库基础 CI、发布 notes 校验及 Go runtime 测试。
- npm staging / pack 检查三个包的元信息、命令别名、内置 runtime 和 App Bundle ID。
- GitHub 新旧 API / Git 地址、既有 Release 下载重定向检查。
- npm Trusted Publisher 账号侧读取与迁移结果检查；不把 dry-run 当成真实发布授权证明。

## 进度记录

- [x] 已同步远端，基于最新 main 建立独立工作目录，确认 GitHub ADMIN 权限。
- [x] 确认当前项目没有 Homebrew formula/cask，现有 npm 直接内置 runtime。
- [x] 完成当前引用和发布校验迁移。
- [x] 完成验证：40 个本地 Node 测试、Linux / Windows Go 测试、14 个 Linux Python 测试、DSH 安装回归、文档与 Action pinning 检查；三个 npm 包真实 staging / pack、签名组件和 App 身份检查通过。同步并发合入的 #100 后，在 GitHub Linux runner 上再次验证两个 Go runtime、14 个 Python 测试与 4 个 release-notes 测试。
- [x] GitHub 改名并更新共享 origin；新旧 GitHub API 与 Git 地址对应同一仓库，旧 Release 下载返回 HTTP 200。
- [x] 提交并推送改动，代码迁移通过 [PR #107](https://github.com/iFurySt/open-computer-use/pull/107) 交付。
- [x] 完成 npm Trusted Publisher 迁移：用户逐包完成安全密钥验证，新连接均使用 `iFurySt/open-computer-use` / `release.yml`，沿用原有 publish / stage 权限。
- [x] 真实 OIDC 复验三个包均返回 HTTP 201，新连接均变为 Valid；没有发布新版本或保存返回的凭据。
- [x] 清理临时验证分支与已合入的代码迁移分支。

## 验证边界

- 基础 `scripts/ci.sh` 被 main 已有的 repo-hygiene 检查阻断：缺少模板要求的 11 个文件，包括 `.editorconfig` 与旧 CI workflows。没有为改名任务补回这些无关模板；相关测试已分别执行。
- npm staging 复用 registry 已发布的 1.1.1 原生 runtime，验证本次包元信息与封装，没有重建或发布 App。
- 首次真实 OIDC 检查：[Actions run 39011291883](https://github.com/iFurySt/open-computer-use/actions/runs/39011291883)，证明只检查页面状态不足以发现改名后的认证问题。
- 同步 #100 后的 Linux 平台验证：[Actions run 39011557748](https://github.com/iFurySt/open-computer-use/actions/runs/39011557748) 的 platform tests step 通过；该 run 后续仍因尚未完成 npm 账号迁移而失败。新增 bridge 测试要求 Linux，不能以 macOS 本地执行结果替代。
- 最终复验：[Actions run 39012120822](https://github.com/iFurySt/open-computer-use/actions/runs/39012120822) 全部通过，包括两个 Go runtime、14 个 Python 测试、4 个 release-notes 测试及三个包的真实 OIDC token exchange；浏览器随后确认三个新连接均为 Valid。

## 决策记录

- 2026-10-17：仓库名采用全小写 open-computer-use；现有产品与包身份保持稳定。保留历史原文，避免改写已发布记录。
- 2026-10-17：真实 token exchange 已使三个新连接完成 validation，无需为了迁移验证而公开发布新版本。旧名失效连接保留为迁移记录，可在下一次正式发版后按需清理。
