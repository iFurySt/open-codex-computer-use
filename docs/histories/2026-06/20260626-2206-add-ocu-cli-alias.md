## [2026-06-26 22:06] | Task: Add `ocu` CLI Alias

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> 希望 npm / brew 安装后除了 `open-computer-use`，也能像 `open-browser-use` 的 `obu` 一样提供 `ocu` 短别名。

### Changes Overview
**Scope:** npm package staging and docs

**Key Actions:**
- **[npm alias]**: Added `ocu` to generated npm package `bin` mappings and staged `bin/ocu` with the same launcher as `open-computer-use`.
- **[docs]**: Documented the short alias in README, skill references, CI/CD notes, and release verification checks.

### Design Intent (Why)
`ocu` should be a packaging-level alias, not a separate runtime path. Reusing the existing Node launcher keeps command behavior identical while letting global npm installs expose a shorter command.

### Files Modified
- `scripts/npm/build-packages.mjs`
- `README.md`
- `README.zh-CN.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/installation.md`
- `skills/open-computer-use/references/usage.md`
- `docs/CICD.md`
- `docs/releases/RELEASE_GUIDE.md`
