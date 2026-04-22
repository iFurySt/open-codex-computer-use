## [2026-04-22 17:59] | Task: bump open-computer-use to 0.1.32

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS shell`

### User Query
> bump a new version

### Changes Overview
**Scope:** release version sources, feature release notes, task history

**Key Actions:**
- **[Version bump]**: 将 Open Computer Use 的主版本源和相关测试/文档示例统一从 `0.1.30` bump 到 `0.1.32`。
- **[Release record repair]**: 补齐 `0.1.31` 的 feature release note，并新增 `0.1.32` 的版本对齐记录。
- **[Version-line decision]**: 先核实远端已经存在 `v0.1.31` tag 和 GitHub Release，因此这轮不复用 `0.1.31`，直接顺延到 `0.1.32`，避免继续扩大版本源不一致。

### Design Intent
这轮的关键不是再发明新的版本规则，而是把仓库重新拉回“单一版本源”状态。当前 `HEAD` 已经对应远端 `v0.1.31`，但仓库里的 manifest 和版本常量仍停在 `0.1.30`；如果继续沿用 `0.1.31`，后续 tag、staging 产物和用户看到的版本号仍然容易打架。顺延到 `0.1.32` 可以在不改写既有 release 的前提下，把当前主线重新收口到一致的版本线。

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1759-bump-open-computer-use-to-0.1.32.md`
