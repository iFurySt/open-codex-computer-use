## [2026-06-07 23:20] | Task: 修复 Windows runtime JSON 入参 UTF-8 解码

### 🤖 Execution Context
* **Agent ID**: `claude-opus-session`
* **Base Model**: `gpt-5.3-codex-spark`
* **Runtime**: `Windows PowerShell + Go`

### 📥 User Query
> 同步并发起 PR，修复 Windows runtime 中 `type_text` 与 `set_value` 的入参中文/非 ASCII 乱码问题。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUseWindows/runtime.ps1`

**Key Actions:**
- **[Action 1]**: 将 MCP operation JSON 的读取从 `Get-Content -Raw` 改为 `[System.IO.File]::ReadAllText(..., [System.Text.Encoding]::UTF8)`。
- **[Action 2]**: 保持 `type_text` 与 `set_value` 使用同一个 `$operation` 对象（`$operation.text`, `$operation.value`）读取路径，覆盖非 ASCII 入参场景。
- **[Action 3]**: 在 `main` 同步到 `upstream/main` 后提交该补丁，确保 PR 只包含新增覆盖。

### 🧠 Design Intent (Why)
Windows PowerShell 5.1 在无 BOM 文件上可能使用系统 ANSI 编码（如中文环境下的 GBK），导致 JSON 中的非 ASCII 文本在 `Get-Content -Raw` 解析前被破坏。显式以 UTF-8 读取 operation 文件可避免该问题，确保 `type_text` 与 `set_value` 接收的入参保持原始内容。

### 📁 Files Modified
- `apps/OpenComputerUseWindows/runtime.ps1`