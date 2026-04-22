## [2026-04-22 16:36] | Task: launch npm postinstall onboarding

### 🤖 Execution Context
* **Agent ID**: `OpenCode`
* **Base Model**: `gpt-5.4`
* **Runtime**: `OpenCode CLI`

### 📥 User Query
> Make a PR to `iFurySt/open-codex-computer-use` so install uses the `permiso`-style permission onboarding on install.

### 🛠 Changes Overview
**Scope:** `scripts/npm`, repository README docs

**Key Actions:**
- **[Auto-launch onboarding from npm postinstall]**: Updated the npm package generator so interactive local global installs detach-launch the bundled permission onboarding app instead of only printing next steps.
- **[Sync install docs]**: Updated English and Chinese README install sections plus generated package README text to explain the automatic onboarding behavior and the manual fallback command.

### 🧠 Design Intent (Why)
The repo already ships a native permission onboarding flow that mirrors the `permiso` UX, but npm install previously left users at a text-only next step. Launching the bundled helper during interactive global installs shortens the path from install to granted permissions without blocking CI or non-interactive environments.

### 📁 Files Modified
- `scripts/npm/build-packages.mjs`
- `README.md`
- `README.zh-CN.md`
- `docs/histories/2026-04/20260422-1636-launch-npm-postinstall-onboarding.md`
