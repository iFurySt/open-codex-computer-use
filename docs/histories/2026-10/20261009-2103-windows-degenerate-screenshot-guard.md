## [2026-10-09 21:03] | Task: 拒绝 Windows 退化截图

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: `GPT-5`
* **Runtime**: `TRAE CLI / macOS arm64 + Windows 10 interactive DevBox`

### 📥 User Query
> 修复 Windows Computer Use 偶发返回 1x1 screenshot、导致部分 LLM 拒绝图片的问题；极端情况下可以没有截图，但不能伪造 1x1，并统一优化窗口有效性判断后提交 PR。

### 🛠 Changes Overview
**Scope:** Windows Go runtime、PowerShell UI Automation bridge、测试与截图行为文档。

**Key Actions:**
- **Window capture gate**: 截图前要求主窗口可见、未最小化、未被 DWM cloaked、与 virtual screen 相交，且宽高至少 64 像素、面积至少 20,000 像素；`list_apps` 使用同一规则过滤退化窗口。
- **PNG defense in depth**: Go 层在构造 MCP result 前再次解码 PNG header，并结合 window bounds 应用同一尺寸门槛；无效图片会从 snapshot cache 和 image content 中移除，不做放大、补边或占位图。
- **Fail-closed coordinates**: 缺少有效截图时仍返回 accessibility tree 和说明，但 coordinate click / drag 明确失败；element-targeted UI Automation action 仍可尝试，发生 coordinate fallback 时 PowerShell 也会再次检查 bounds。
- **Resource safety**: Windows bitmap、graphics 和 memory stream 在成功或异常路径都通过 `finally` 释放。
- **Regression coverage**: 新增 PNG 尺寸/格式、snapshot image omission、coordinate action 和 PowerShell guard 回归测试，并在 Windows 交互桌面验证真实 binary。

### 🧠 Design Intent (Why)
截图坐标只有在画面真实、可见且尺寸足以操作时才有意义。对 1x1 或无效窗口生成一个格式合法的 PNG 会把底层窗口状态问题推迟成上游模型错误，也可能让坐标动作落到错误位置。因此实现选择保留可用的语义树、明确省略图片并阻止 coordinate action，而不是伪造视觉状态。

### 📁 Files Modified
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `skills/open-computer-use/references/troubleshooting.md`
- `docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20261009-windows-degenerate-screenshot-guard.md`

### ✅ Validation
- `(cd apps/OpenComputerUseWindows && go test ./...)` 通过。
- `./scripts/build-open-computer-use-windows.sh --arch amd64` 通过。
- Windows 10 build 19045 交互桌面实测当前 binary SHA-256 与本地构建一致：正常 320x240 fixture 返回 320x240 PNG；1x1 和 minimized fixture 均保留文本/树但无 image，并包含 `Screenshot unavailable` 说明。
- 同一实测中，`list_apps` 保留正常 fixture，过滤 1x1、minimized 和 DWM-cloaked `TextInputHost`；1x1 snapshot 后 coordinate click 返回 `No usable screenshot is available`。
