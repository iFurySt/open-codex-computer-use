# Windows Computer Use Runtime

## 目标

把当前只覆盖 macOS Accessibility 的 `open-computer-use` 扩展到 Windows，优先让同一组 9 个 Computer Use tools 能通过独立 `.exe` 跑起来，并保留后续补强路径。

## 范围

- 包含：
  - Windows 独立 runtime，不耦合 Swift `.app`。
  - Go CLI / MCP / `call --calls` 入口。
  - `list_apps`、`get_app_state`、`click`、`perform_secondary_action`、`scroll`、`drag`、`type_text`、`press_key`、`set_value` 的功能性实现。
  - Windows `.exe` 构建脚本和基础 Go 单测。
  - 架构文档、README 和 history。
- 不包含：
  - 替换 macOS Swift 主线。
  - Windows installer、code signing。
  - visual cursor overlay。
  - 完整 Windows fixture / smoke suite。

## 背景

- 相关文档：
  - `docs/ARCHITECTURE.md`
  - `docs/QUALITY_SCORE.md`
  - `docs/exec-plans/active/20260422-remaining-tool-official-alignment.md`
- 相关代码路径：
  - `apps/OpenComputerUseWindows/`
  - `scripts/build-open-computer-use-windows.sh`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- 已知约束：
  - Windows UI Automation 需要 runtime 运行在已登录桌面 session；脱离桌面的 SSH/service 进程可能看不到顶层窗口。
  - 第一版以 Go 生成 `.exe` 为交付边界，但 UIA 操作通过嵌入式 PowerShell bridge 调 Windows 内置 .NET UI Automation API。
  - Win32 window message fallback 能减少真实鼠标抢占，但不同 GUI toolkit 对后台消息支持不一致。
  - Windows 没有一套对任意 app 都等价于 macOS AX 的后台键鼠模型；当前策略是 UIA pattern 优先、window message best-effort，并把启动 app / `SetFocus` / UIA text fallback 这类前台抢占路径做成显式 opt-in。

## 风险

- 风险：PowerShell bridge 比纯 Go UIA 慢，也更依赖 Windows PowerShell 5.1 / .NET Framework 可用性。
  - 缓解方式：Go runtime 先把协议面、状态复用和构建产物稳定下来；后续可把 bridge 内部逐步替换成原生 Go COM/UIA。
- 风险：SSH 验证进程不在交互式桌面上下文里，导致误判 `list_apps` / `get_app_state`。
  - 缓解方式：把 SSH 仅作为 exe 启动、JSON/MCP、错误路径验证；真实 UI 操作补交互式桌面 smoke。
- 风险：窗口消息 fallback 对 Electron、WinUI、UWP、浏览器等复杂 app 的行为差异较大。
  - 缓解方式：UIA pattern 优先，fallback 行为明确记录；后续加 Windows fixture 和真实 app 样本。

## 里程碑

1. 完成 Windows Go runtime 骨架和 9-tool 功能性实现。
2. 完成 `.exe` 构建脚本、Go 单测、MCP/tools list 和 SSH 基础验证。
3. 补交互式桌面 smoke、Windows fixture、installer/signing 和更原生 UIA 实现。

## 验证方式

- 命令：
  - `(cd apps/OpenComputerUseWindows && go test ./...)`
  - `./scripts/build-open-computer-use-windows.sh --arch arm64`
  - `open-computer-use.exe --version`
  - `open-computer-use.exe call list_apps`
  - `open-computer-use.exe mcp`
- 手工检查：
  - 在已登录 Windows 桌面里打开 Notepad，运行 `get_app_state -> set_value/type_text/press_key/click` sequence。
  - 确认 action 后返回最新 state text 和截图。
- 观测检查：
  - 确认 SSH/service 环境下的空窗口列表被明确呈现，不把它误写成 UIA 逻辑失败。

## 进度记录

- [x] 新增 `apps/OpenComputerUseWindows`，用 Go 实现 CLI、MCP、tool schema、`call --calls` 和 snapshot cache。
- [x] 嵌入 Windows PowerShell UIA bridge，实现 9 个 tools 的功能性路径。
- [x] 新增 Windows arm64/amd64 `.exe` 构建脚本。
- [x] 新增 Go 单测，并接入仓库基础 CI。
- [x] 通过 SSH 到 Windows 验证 `.exe --version`、`call list_apps` 和 MCP initialize/tools list。
- [x] 通过 Windows Codex App session history 定位首轮真实 MCP 测试问题：`list_apps` 正常，`get_app_state` 对 `Notepad` 返回 `Argument types do not match`，对 `notepad.exe` 返回 `appNotFound(...)`。
- [x] 修正 Windows app 匹配和 UIA tree rendering 容错，避免单个控件属性异常导致整个 `get_app_state` 失败。
- [x] 通过交互式 Windows scheduled task 复现并验证 `get_app_state -> type_text -> get_app_state`，确认 Notepad 文本区能写入 `hello windows mcp`，并在后续 snapshot 中显示 ValuePattern 值。
- [x] 收紧 Windows 后台运行默认策略：找不到 app 时不再自动启动，`SetFocus` 默认禁用，只能通过环境变量显式开启。
- [x] 将 `type_text` 默认路径从 UIA `ValuePattern.SetValue` 改为 child HWND `EM_SETSEL` / `EM_REPLACESEL` 优先；可能把 app 带到前台的 UIA text fallback 改成环境变量显式开启。
- [x] 通过交互式 Windows scheduled task 验证新 `type_text` 路径：`get_app_state -> type_text -> get_app_state` 三步均 `isError=false`，Notepad 文本包含 `bgmsg-*` marker，前台窗口调用前后均为 Codex。
- [ ] 在交互式 Windows 桌面 session 补 Notepad / Edge 等真实 UI action smoke。
- [ ] 增加 Windows fixture 和可重复 smoke runner。
- [ ] 评估用 `PrintWindow` / Windows Graphics Capture 补一条不依赖窗口可见性的 background screenshot 路径。
- [ ] 为必须依赖前台输入的 app/toolkit 场景补更明确的 capability/error，避免静默退到抢焦点行为。
- [x] 将 Windows artifact 接入 npm release packaging，通过 `open-computer-use-win32-arm64` / `open-computer-use-win32-x64` platform packages 分发。
- [ ] 补 Windows signing / installer 方案。
- [ ] 评估把 PowerShell bridge 替换为原生 Go COM/UIA 的收益和风险。

## 决策记录

- 2026-04-22：Windows runtime 不复用 Swift `.app`，采用独立 Go `.exe`，避免把 macOS 权限/onboarding 模型强行带到 Windows。
- 2026-04-22：第一版用 Go 管协议、状态和分发边界，用嵌入式 PowerShell 调 Windows UI Automation / Win32 API，优先完成 9-tool 功能性闭环。
- 2026-04-22：保留 `call --calls` 的同进程状态复用语义，Windows action tool 优先消费上一轮 `get_app_state` 的 `element_index` metadata。
- 2026-04-22：真实 Codex App 测试显示 `list_apps` 可用，但 `get_app_state` 仍会被 UIA 属性读取异常拖垮；Windows snapshot renderer 改成字段级安全读取，并支持 `notepad.exe` 这类进程名输入。
- 2026-04-22：PowerShell 对 .NET generic list 的 `@(...)` 包装会在返回对象时触发 `Argument types do not match`；Windows bridge 统一改成 `.ToArray()` 返回 UIA records/element collections。
- 2026-04-22：`type_text` 不再只给顶层窗口发 `WM_CHAR`；优先寻找同进程可写 `ValuePattern` 文本元素并追加文本，找不到再走 window-message fallback。
- 2026-04-22：为避免 Windows tools 主动抢占用户焦点，`Resolve-App` 默认不再 `Start-Process` 目标 app，`SetFocus` secondary action 默认返回错误；需要前台行为时分别设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` 或 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1`。
- 2026-04-22：Notepad 实测反馈 `type_text` 的 UIA `ValuePattern.SetValue` 会把窗口带到前台；默认改为 child HWND `EM_REPLACESEL` 后台消息路径，旧 UIA fallback 需要 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1`。
- 2026-04-22：Windows 交互式 scheduled task 验证显示新 `type_text` 能写入 Notepad 且不会把前台从 Codex 切到 Notepad；Notepad 文本控件 UIA class 为 `RichEditD2DPT`，有 child native handle，可接收 `EM_REPLACESEL`。
- 2026-04-23：Windows release artifact 接入 npm platform package，不新增系统 installer/signing；root `open-computer-use` package 通过 optional dependency 按 `win32-arm64` / `win32-x64` 自动选择 `.exe`。
