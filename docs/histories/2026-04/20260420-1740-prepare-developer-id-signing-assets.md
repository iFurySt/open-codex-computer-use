## [2026-04-20 17:40] | Task: 准备 Developer ID signing 资产并恢复可选 CI 签名链路

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 你直接做吧，做到不能做或者需要我的时候再叫我。

### 🛠 Changes Overview
**Scope:** `.github/workflows/`、`docs/`、`scripts/`

**Key Actions:**
- **[Developer ID Asset Prep]**: 将用户本机基于 CSR 签发下来的 `Developer ID Application` 证书导入 `login.keychain-db`，确认存在可用 codesigning identity，并导出本地可复用的 `.p12` 资产。
- **[CI Signing Fix]**: 修复 `scripts/build-open-computer-use-app.sh` 在使用临时 keychain 时仅把 keychain 传给 `codesign --keychain`、但未加入用户搜索链导致“item could not be found in the keychain”的问题。
- **[Workflow Restore]**: 把 release workflow 的可选证书导入步骤补回；当 repo secrets 里配置 `OPEN_COMPUTER_USE_CODESIGN_*` 时，CI 会导入 `.p12` 并统一用 `Developer ID Application` identity 对 npm release `.app` 签名，未配置时仍退回 ad-hoc。
- **[Docs Sync]**: 同步 CI/CD 与 release guide，明确当前状态是“Open Computer Use 可选 Developer ID 签名，Cursor Motion 仍为 ad-hoc，notarization 还未接”。

### 🧠 Design Intent (Why)
用户已经在自己机器上完成 CSR，并用团队账号在 Apple Developer 网站上签发了 `Developer ID Application` 证书。此时最重要的不是继续停留在“材料怎么拿”，而是把这份证书真正转成可用于 CI 的 `.p12` 资产，并把仓库里的签名链路补回到“有 secret 就统一签名、没 secret 也不阻塞发版”的状态。这样后续只剩 GitHub secrets 与 notarization 两个外部依赖点。

### 📁 Files Modified
- `scripts/build-open-computer-use-app.sh`
- `.github/workflows/release.yml`
- `docs/CICD.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260420-1740-prepare-developer-id-signing-assets.md`
