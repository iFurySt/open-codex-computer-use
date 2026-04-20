## [2026-04-20 16:08] | Task: 收口 Open Computer Use 的跨渠道 app 身份

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> `npm i -g open-computer-use && open-computer-use` 拉起的授权，以及仓库里 `./scripts/build-open-computer-use-app.sh debug` / `./dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse` 拉起的授权，被系统识别成两个 app。希望不管从 npm / brew / dmg 等什么渠道安装，identify 都一样，不要再分裂成多个授权对象；另外需要进一步确认 npmjs 上通过 GitHub Actions 打出来的包是否也会影响这个问题。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `scripts/`, `.github/workflows/`, `README`, `docs/`

**Key Actions:**
- **[Unified Codesign Path]**: 给 `scripts/build-open-computer-use-app.sh` 补上统一的 codesign 入口，支持显式 identity、自动发现本机 Apple signing identity、以及 ad-hoc/skip 降级，并在 ad-hoc 情况下直接提示 TCC 仍可能把不同构建识别成不同 app。
- **[Channel-Agnostic Bundle Discovery]**: 把权限目标发现从“优先 npm 全局路径”改成“统一发现当前运行副本、`/Applications`、npm、Homebrew 等渠道的同 bundle app，再优先使用稳定安装副本作为权限目标”，减少渠道偏置，同时避免临时运行副本抢在长期授权对象前面。
- **[CI Release Signing]**: 给 `release.yml` 增加可选的证书导入步骤；当配置 `OPEN_COMPUTER_USE_CODESIGN_*` secrets 时，GitHub Actions 打出来的 npm 包会用统一 codesign identity 封装，避免 npmjs 上的 `.app` 因 ad-hoc/unsigned 而继续分裂 TCC 身份。
- **[Docs Sync]**: README、架构和 CI/CD 文档统一改成“正式发布渠道靠同一 bundle id + 同一签名身份收口”，不再把 npm 路径写成唯一长期授权对象。

### 🧠 Design Intent (Why)
macOS 的 TCC 不只看 `CFBundleIdentifier`，还会把 code requirement 一起纳入身份判断。只统一 bundle id 但继续让各个渠道产出 ad-hoc 或未正式签名的 `.app`，权限条目仍会拆开。要真正把 npm / brew / dmg 收成同一个 app，必须让它们共享同一个 bundle identifier 和同一条正式签名链；源码调试态没有这条签名链时，则要明确告诉用户这是降级行为，而不是继续假装“已经是同一个 app”。

### 📁 Files Modified
- `.github/workflows/release.yml`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/histories/2026-04/20260420-1608-unify-open-computer-use-app-identity.md`
