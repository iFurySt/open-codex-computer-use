## [2026-04-22 12:05] | Task: 修复 0.1.27 release npm publish 失败

### 背景

- `v0.1.27` tag 触发的 GitHub Actions release 在 `package-npm` job 失败。
- 失败点是 `Publish packages to npm`，registry 对 `open-codex-computer-use-mcp@0.1.27` 的 publish PUT 返回 404；同一 run 的 Cursor Motion DMG job 已成功。
- npm registry 当前仍能看到三个包的 `0.1.26`，但看不到 `0.1.27`。

### 变更

- **[Publish Recovery]**: `scripts/npm/publish-packages.mjs` 发布每个 staged package 前先用 `npm view <name>@<version>` 检查同版本是否已经存在；存在时直接跳过。
- **[Auth Preference]**: GitHub Actions 暴露 OIDC 时优先用 `--provenance` 走 npm trusted publishing，不再因为存在 `NPM_TOKEN` fallback 就强制清掉 OIDC 环境；token 仅作为 fallback。
- **[Trusted Publishing CLI]**: release workflow 在 publish 前固定升级到 npm `11.12.1`，满足 npm trusted publishing 对 CLI `11.5.1+` 的要求。
- **[Retry]**: npm publish 失败后最多重试 3 次，并在每次失败后再次检查版本是否已经对 registry 可见，用于覆盖 registry 短暂错误或部分发布成功场景。
- **[Release Guide]**: 在发版指南中补充 npm publish 404 的排查方式，以及 tag 重发时脚本如何处理已存在版本。

### 验证

- 通过：`node ./scripts/npm/build-packages.mjs --skip-build --out-dir dist/release/npm-staging-check`，staging package version 为 `0.1.27`
- 通过：`node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging-check --dry-run`
- 通过：`node --check scripts/npm/publish-packages.mjs`
- 通过：`swift test`

### 影响文件

- `scripts/npm/publish-packages.mjs`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260422-1205-harden-npm-release-retry.md`
