# 发版指南

这份文档约束这个仓库未来的 patch / minor release 流程，目标是避免再次出现 “git tag 已经发了，但 npm staging 产物版本还是旧值” 这类版本源不一致问题。

## 什么时候必读

- 只要任务里包含这些动作之一，就先读这份文档：
  - bump 版本
  - 打 release tag
  - 推送 release tag
  - 看 GitHub Actions release 失败原因
  - 重发某个失败版本

## 当前 release 入口

- 本地 staging / 打 tgz：`./scripts/release-package.sh`
- 本地构建 Cursor Motion DMG：`./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version <version>`
- 本地 stage npm 包目录：`node ./scripts/npm/build-packages.mjs`
- 本地 publish：`node ./scripts/npm/publish-packages.mjs`
- CI workflow：`.github/workflows/release.yml`
- 用户可见发布记录：`docs/releases/feature-release-notes.md`

## 当前版本源

这个仓库当前有两类 release 版本源：

- npm staging 包版本：以 `plugins/open-computer-use/.codex-plugin/plugin.json` 里的 `version` 为准。
- `CursorMotion-<version>.dmg` 文件名与 GitHub Release asset 版本：以 release tag 为准；workflow 会把 `vX.Y.Z` 规范化成 `X.Y.Z` 写进 DMG 文件名，也可以在本地显式传 `--version`。

也就是说：

- 只改 git tag，不改这个 manifest，不会得到新 npm 版本。
- `scripts/npm/build-packages.mjs` 会从这个 manifest 读取版本，再生成三个 staging 包。
- 所以 release 前必须先把这份 manifest bump 到目标版本。
- 如果要让 `CursorMotion` 的 DMG 文件名和 release 页面资产名正确落到目标版本，也必须使用目标 tag 推送，或本地显式传入同样的 `--version`。

## Release Checklist

### 1. 先统一版本号

至少检查并同步这些位置：

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/` 中本轮 release 对应的 history

如果这轮 release 还改了其他对外暴露版本字符串，也要一起对齐，不要只改一半。

### 2. 本地验证版本源已经生效

至少跑这三步：

```bash
swift test
node ./scripts/npm/build-packages.mjs --skip-build --out-dir dist/release/npm-staging-check
./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version 0.1.14
```

然后直接检查 staging 包版本和 DMG 文件名：

```bash
node -p "require('./dist/release/npm-staging-check/open-codex-computer-use-mcp/package.json').version"
ls dist/release/cursor-motion/CursorMotion-0.1.14.dmg
```

如果这里打印的不是目标版本，或者 DMG 没按目标版本名产出，不要打 tag。

### 3. 提交版本 bump

- 用单独 commit 提交 release version bump。
- commit message 要能直接看出这是 release 收口，而不是普通功能提交。

### 4. 打 tag 并推送

当前约定用 `vX.Y.Z`：

```bash
git tag -a v0.1.14 -m "v0.1.14"
git push origin main
git push origin v0.1.14
```

tag push 后，`.github/workflows/release.yml` 会自动做两件事：

- 发布 npm 包。
- 构建 `CursorMotion-0.1.14.dmg`，并创建或更新同名 tag 的 GitHub Release asset。

## Release 失败时怎么查

### 1. 先看最新 run

```bash
gh run list -R iFurySt/open-codex-computer-use --limit 10
gh run view -R iFurySt/open-codex-computer-use <run-id> --log-failed
```

### 2. 重点看哪一类错误

- `npm error 403 ... You cannot publish over the previously published versions`
  - 通常不是 token 权限问题，而是 staging 包版本仍然是旧版本。
  - 先回头检查 `plugin.json` 的 `version`，再检查 staging 包实际产出的 `package.json`。
- `npm error 404 Not Found - PUT https://registry.npmjs.org/<package>`
  - 先确认 registry 上目标包旧版本是否仍可见：`npm view <package> versions --json`。
  - 当前 publish 脚本会在发布前跳过已经存在的同版本 package，并对 publish 失败做短暂重试；如果 GitHub Actions OIDC 可用，会优先用 `--provenance` 走 trusted publishing，再回退到 `NODE_AUTH_TOKEN`。如果 tag 重发前某个 package 已经部分发布成功，重新跑同一个 release 不会因为该 package 已存在而中断。
- `npm error need auth ... You need to authorize this machine using npm adduser`
  - 如果日志显示已经选择 `GitHub Actions OIDC trusted publishing`，优先检查 CI 里的 npm CLI 版本；trusted publishing 需要 npm `11.5.1+`，当前 release workflow 会先升级到 npm `11.12.1`。
  - 如果 npm CLI 版本满足要求仍报这个错误，说明 npmjs.com 包侧还没有把当前 GitHub repo / workflow 文件配置成 trusted publisher。
- 构建阶段失败
  - 优先看 `Build npm release artifacts`、`Build Cursor Motion DMG` 或 Swift 编译错误。
- GitHub Release 资产上传失败
  - 优先看 `Publish Cursor Motion DMG to GitHub Releases`，确认 tag 是否存在、`GH_TOKEN` 权限是否正常，以及生成的 `CursorMotion-<version>.dmg` 路径是否匹配。
- publish 认证失败
  - 再去看 `.github/workflows/release.yml`、`scripts/npm/publish-packages.mjs` 和 npm trusted publishing / token fallback 配置。

## 当前已知边界

- `Open Computer Use` 的 npm release 产物在没有配置 `OPEN_COMPUTER_USE_CODESIGN_P12_BASE64` / `OPEN_COMPUTER_USE_CODESIGN_P12_PASSWORD` 等 secrets 时，仍会退回 ad-hoc signing；配置后会先导入 `Developer ID Application` 证书，再按该 identity 统一签名。
- `Cursor Motion` 当前 release 资产会优先复用 `OPEN_COMPUTER_USE_CODESIGN_*` 对 app 做 `Developer ID Application` 签名；如果同时配置 `APPLE_NOTARY_API_KEY_P8_BASE64`、`APPLE_NOTARY_KEY_ID`、`APPLE_NOTARY_ISSUER_ID`、`APPLE_DEVELOPER_TEAM_ID`，workflow 会继续对 `.dmg` 执行 notarization 和 staple。
- 如果上述 secrets 缺失，workflow 会分别退回 ad-hoc signing 或跳过 notarization，而不是阻塞整条 release。

## 如果 tag 已经打错了

如果远端 tag 已经指向错误 commit，先删 tag，再修版本源，再重打。

本地删 tag：

```bash
git tag -d v0.1.14
```

远端删 tag：

```bash
git push origin :refs/tags/v0.1.14
```

修好后再重新创建并推送同名 tag。

## 文档同步要求

每次 release 都至少同步这三类文档：

- `docs/releases/feature-release-notes.md`
- `docs/histories/` 对应 release history
- 如果 release 流程本身有变化，这份 `docs/releases/RELEASE_GUIDE.md`

如果一次 release 暴露出新的流程坑，就不要只在聊天里记住，直接补进这份文档。
