## [2026-08-08 04:09] | Task: Fix Linux AT-SPI interface detection

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.6`
* **Runtime**: `T3 Code / Codex harness`

### 📥 User Query
> 修复 Linux 文本编辑流程中发现的上游问题，并准备 Pull Request。

### 🛠 Changes Overview
**Scope:** Linux Computer Use runtime

**Key Actions:**
- **标准接口检测**: 使用 `Accessible.get_interfaces()` 判断 `Text` 与 `EditableText` 能力，移除对部分 PyGObject 环境不存在属性的访问。
- **回归覆盖**: 添加无桌面依赖的 Python 测试，并接入仓库基础 CI。
- **文档同步**: 更新 Linux 架构说明、troubleshooting 与用户可见功能记录。

### 🧠 Design Intent (Why)
Ubuntu 24.04 的 AT-SPI GI binding 不提供 `Accessible.is_text` 和 `Accessible.is_editable_text` 属性。原实现会在进入容错包装前抛出 `AttributeError`，导致快照和文本工具不可用。`get_interfaces()` 是实际 binding 提供的能力查询接口，并可在不同 toolkit 节点上安全降级。

### 📁 Files Modified
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseLinux/runtime_test.py`
- `scripts/ci.sh`
- `docs/ARCHITECTURE.md`
- `skills/open-computer-use/references/troubleshooting.md`
- `docs/releases/feature-release-notes.md`
