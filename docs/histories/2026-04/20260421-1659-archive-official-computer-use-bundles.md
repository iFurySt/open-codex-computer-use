## [2026-04-21 16:59] | Task: 归档官方 computer-use bundle zip

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 将本地 bundled plugin cache 里的两个官方 `computer-use` 版本 zip 包加入仓库某个特定目录，并使用 Git LFS 管理。

### 🛠 Changes Overview
**Scope:** 官方 `computer-use` 逆向参考资料归档

**Key Actions:**
- **[Archive]**: 新增 `official-bundles/computer-use/` 目录，归档 `1.0.750.zip` 和 `1.0.755.zip`。
- **[LFS]**: 新增 `.gitattributes` 规则，让该目录下的 zip 通过 Git LFS 跟踪。
- **[Docs]**: 补充资产目录说明和 SHA-256 校验信息，方便后续复现与版本对比。

### 🧠 Design Intent (Why)
将官方 zip 放在逆向资料资产目录下，可以明确它们是参考输入而不是源码或构建依赖；使用 Git LFS 避免大二进制污染普通 Git object，同时保留可追溯的版本样本。

### 📁 Files Modified
- `.gitattributes`
- `docs/references/codex-computer-use-reverse-engineering/assets/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/SHA256SUMS`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/1.0.750.zip`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/1.0.755.zip`
