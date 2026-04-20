## [2026-04-20 16:20] | Task: 发布 0.1.14

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 提交相关改动，增发一个版本

### 🛠 Changes Overview
**Scope:** `apps/`、`docs/`、`experiments/`、`packages/`、`plugins/`、`scripts/`

**Key Actions:**
- **[Packaged Glyph Fix]**: 修复 `Cursor Motion` 打包 app 没带官方 cursor PNG 的问题；release app 现在会优先从 bundle 资源读取 `official-software-cursor-window-252.png`，不再静默退回更低保真的 procedural glyph。
- **[DMG Script Sync]**: `scripts/build-cursor-motion-dmg.sh` 现在会把官方 cursor PNG 复制到 `Contents/Resources/`，并显式写入 `NSHighResolutionCapable=true`，让打包版和 `swift run CursorMotion` 的观感更一致。
- **[Version Bump]**: 把插件 manifest、Swift/Go 版本常量、smoke suite 初始化版本、单测里的 client version 与 CLI 文档路径统一提升到 `0.1.14`。
- **[Release Notes]**: 在 `docs/releases/feature-release-notes.md` 追加 `0.1.14`，记录这次 packaged `Cursor Motion` 观感一致性修复。
- **[Validation]**: 已重跑 `swift test`、npm staging 构建和 `Cursor Motion` DMG 打包，并直接检查 staging 包版本与 `CursorMotion-0.1.14.dmg` 产物，确认 release 输入已经完整收口到 `0.1.14`。

### 🧠 Design Intent (Why)
这次不是继续改曲线算法本身，而是修正 release app 和源码运行版之间的资源环境差异。用户已经明确看到 DMG 版出现更锯齿、朝向也不对的 cursor；如果不把 bundle 资源和版本一起收口，后续 release 页面会持续分发一份肉眼可见退化的构建结果。

### 📁 Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `scripts/build-cursor-motion-dmg.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260418-1430-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260420-1620-bump-open-computer-use-to-0.1.14.md`
