# Windows 退化截图保护

## 目标

Windows runtime 在目标窗口不可稳定截图时只返回文本与 UI Automation 树，绝不向 MCP host 返回 1x1、极小、最小化、cloaked 或离屏窗口生成的无效 PNG，同时阻止失去截图坐标基础的 coordinate action。

## 范围

- 包含：Windows 窗口可捕获性检查、PNG 像素级兜底、coordinate action fail-closed、单元测试、Windows 交互桌面回归、架构/可靠性/安全/skill/release/history 文档。
- 不包含：替换 `CopyFromScreen`、支持被其他窗口遮挡时的离屏合成、修改 macOS 或 Linux 截图实现、版本发布。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/RELIABILITY.md`、`docs/SECURITY.md`、`docs/QUALITY_SCORE.md`。
- 相关代码路径：`apps/OpenComputerUseWindows/runtime.ps1`、`apps/OpenComputerUseWindows/main.go`、`apps/OpenComputerUseWindows/main_test.go`。
- 已知约束：Windows runtime 必须运行在已登录交互桌面；极端情况下允许没有 screenshot，但不能伪造、放大或补边一个不可操作的小图。

## 风险

- 风险：过滤过严会让合法的小工具窗口不再返回截图。
- 缓解方式：以 macOS 已使用的 20,000 像素候选面积为语义基线，同时要求宽高至少 64 像素；仍保留 accessibility tree 和 element-targeted action。
- 风险：PowerShell bridge 回归后仍可能返回异常图片。
- 缓解方式：Go 层再次解码 PNG header 并应用同一尺寸门槛，coordinate action 也以通过校验的截图为前提。

## 里程碑

1. 收敛窗口与截图有效性规则。
2. 实现 PowerShell 与 Go 双层保护并补测试。
3. 在 Windows 交互桌面验证正常窗口与 1x1/minimized/cloaked 边界。
4. 完成文档、history 与 PR 交付准备。

## 验证方式

- 命令：`(cd apps/OpenComputerUseWindows && go test ./...)`、`./scripts/build-open-computer-use-windows.sh --arch amd64`、`make check-docs`、`git diff --check`。
- 手工检查：Windows DevBox 交互桌面运行正常窗口 snapshot，并用受控 1x1 fixture 断言结果不含 image block。
- 观测检查：最小化、cloaked、离屏或过小窗口不再进入 `list_apps` 的可截图集合；缺截图时 coordinate click/drag 明确失败。

## 进度记录

- [x] 在 Windows DevBox 用原实现复现 1x1 PNG。
- [x] 完成双层有效性保护和回归测试。
- [x] 完成 Windows 实机复验。
- [x] 完成文档、history 与 PR 交付准备。

## 决策记录

- 2026-10-09：无效截图采用 fail-closed，不做放大、补边或占位图；截图缺失时仍返回 accessibility tree。
- 2026-10-09：窗口截图最低要求统一为宽高各 64 像素且面积至少 20,000 像素，与 macOS 正常窗口候选的面积基线对齐。
- 2026-10-09：实机验证覆盖正常、1x1、minimized、DWM-cloaked 和无图 coordinate click，固定当前 fail-closed 边界。
