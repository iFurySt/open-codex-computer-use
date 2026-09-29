# CI/CD 说明

这个模板自带一套不依赖具体语言栈的 CI/CD 骨架。

## 当前 release 入口

- `scripts/release-package.sh`：构建 universal `Open Computer Use.app`，cross-compile Linux / Windows runtime，stage 三个既有 root/alias npm 包；每个包都会内置 macOS app、Linux binaries 和 Windows exes，并暴露 `open-computer-use` / `ocu` 等 npm bin 入口。脚本同时调用 `scripts/package-github-release-assets.sh`，产出 npm tarballs、GitHub Release 直接下载制品与对应 manifest。当前 CI 继续显式使用 ad-hoc signing，保持和此前发布链路一致；本地 debug/dev 构建则允许使用开发机自己的签名身份。
- `scripts/package-github-release-assets.sh`：把已构建的 universal `.app`、Linux 双架构 binary、Windows 双架构 `.exe` 和 `open-computer-use` skill 封装到 `dist/release/github/`，并生成 `SHA256SUMS` 与 `release-assets-manifest.json`。macOS 必须分发完整 app bundle，不能把 bundle 内 binary 当成独立安装包。
- `scripts/build-cursor-motion-dmg.sh`：本地构建 `Cursor Motion.app` 并封装 `dist/release/cursor-motion/CursorMotion-<version>.dmg`，支持 `native` / `arm64` / `x86_64` / `universal`。
- `scripts/build-open-computer-use-linux.sh`：本地构建实验性 Linux `open-computer-use` binary，支持 `arm64` / `amd64`；release package 会把这两个产物内置进既有 npm 包的 `dist/linux/`。
- `scripts/build-open-computer-use-windows.sh`：本地构建实验性 Windows `open-computer-use.exe`，支持 `arm64` / `amd64`；release package 会把这两个产物内置进既有 npm 包的 `dist/windows/`。
- `.github/workflows/release.yml`：支持 push semver tag 自动发布，也支持手动触发；tag push 时会并行构建 npm/direct-download artifacts 与 `Cursor Motion` DMG，只有两个构建 job 都成功后，单一汇总 job 才会创建或更新 GitHub Release 并上传全套 assets。`Open Computer Use` 的 npm 与 app 制品默认走 ad-hoc signing；如果配置了 `OPEN_COMPUTER_USE_CODESIGN_*` secrets，则会先导入 `Developer ID Application` 证书，再按同一 identity 对 release `.app` 统一签名。若同时配置 `APPLE_NOTARY_*` secrets，direct-download app zip 会在 notarization 与 staple 后重新封装；`Cursor Motion` DMG 也会走 notarization 和 staple。

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
- `dist/release/github/Open-Computer-Use-<version>-macOS-universal.app.zip`
- `dist/release/github/open-computer-use-cli-<version>-linux-{arm64,amd64}.tar.gz`
- `dist/release/github/open-computer-use-cli-<version>-windows-{arm64,amd64}.zip`
- `dist/release/github/open-computer-use-skill.zip`
- `dist/release/github/open-computer-use.skill`
- `dist/release/github/SHA256SUMS`
- `dist/release/github/release-assets-manifest.json`
- `dist/release/cursor-motion/CursorMotion-<version>.dmg`
- GitHub Actions 中上传的 npm 与 direct-download release artifacts
- GitHub Releases 中上述 direct-download assets 与和 tag 对齐的 `CursorMotion-<version>.dmg`

也就是说，即使项目还没进入更复杂的部署阶段，仓库现在也同时具备 npm 分发链路，以及由 git tag 驱动、覆盖 macOS / Linux / Windows 和 skill 的直接下载链路。
