## [2026-09-15 20:30] | Task: 截图改用 JPEG 编码

### 🤖 Execution Context
* **Agent ID**: `claude-code`
* **Base Model**: `Claude Opus 5`
* **Runtime**: `Claude Code CLI / macOS`

### 📥 User Query
> 把 fork 里已经验证过的截图编码改动整理成上游 PR：截图从 PNG 改为 JPEG，去掉字节上限。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **[编码格式]**: 窗口图片改为 JPEG，quality `0.8`，最长边仍然是 `1280`。
- **[移除字节上限]**: 删除 `screenshotResultMaxPNGBytes`（900 KB）和 `screenshotResultMinScale`，以及为了逼近字节上限而反复缩小重编码的循环；现在只做一次按最长边的缩放。
- **[命名跟随行为]**: `boundedScreenshotPNGData` → `boundedScreenshotData`，`ToolResultContentItem.pngImage` → `jpegImage`（mimeType 同步改为 `image/jpeg`），`AccessibilitySnapshot.screenshotPNGData` → `screenshotData`。
- **[测试]**: 两个尺寸测试改用新接口，并断言输出确实是 JPEG（`FF D8 FF`）。

### 🧠 Design Intent (Why)
模型按图片的像素尺寸计费，不按字节数，所以字节上限并没有省下模型侧的成本，只是在本地花时间反复缩小重编码，还会为了压到 900 KB 而牺牲像素尺寸——牺牲的恰恰是模型真正看的那一维。改成 JPEG 之后，同一张屏幕的字节数只有 PNG 的一小部分，文字依然清晰，像素尺寸则完全由最长边上限决定。

字段名里带 `PNG` 而内容是 JPEG 会误导后续调用方，所以命名一起跟着行为改。这是 `OpenComputerUseKit` 的公开 API 变更。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolResult.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
