# Windows 滚动坐标修复与全局输入兜底

用户报告 Windows runtime 的 `scroll` 直接报错、坐标类动作在 150% 缩放下失效，并要求按上游方式修复而不是本地绕过。

- 修复 `scroll` 请求没有带 `windowBounds`，导致坐标回退路径必然抛 `No usable screenshot coordinates are available`；`drag` 分支同样依赖该字段。
- PowerShell bridge 启动时对齐 DPI 物理坐标（`SetProcessDpiAwarenessContext` + `SetThreadDpiAwarenessContext`），使 `GetSystemMetrics` / `GetWindowRect` 与 UIA frame、操作文件里的 `windowBounds` 处于同一坐标空间，修复窗口位于虚拟化屏幕之外时的可捕获性误判。
- `Invoke-Scroll` 在 `ScrollPattern.Scroll` 抛错时回退到坐标路径，不再让整个 tool call 失败。
- 新增 Windows 全局输入兜底：`click_method=global` 用真实指针事件实现；`drag` / `scroll` / `press_key` 在 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` 时改用真实指针与键盘输入；`app_post` 与默认 `auto`（UIA 优先）语义保持不变，未授权时在移动指针前拒绝。
- 覆盖真实指针/键盘输入时前台锁定的处理：`SetForegroundWindow` 需要先以一次合成 Alt 取得前台切换许可。
- 新增/更新 Go 回归用例（`scroll` 必须携带 `windowBounds`、`global` 开关门控、runtime.ps1 全局输入守卫），同步更新架构文档、安全文档与发布记录。

验证：`go test ./...`（apps/OpenComputerUseWindows）、runtime.ps1 AST 语法解析、以及真实桌面端到端用例——默认配置下 `scroll` 不再报错；开关关闭时 `global` 被门控拒绝且 `app_post` 行为不变；开关开启时 `global` 点击生效、`press_key` 在 WinUI 3 应用中生效；窗口移到虚拟化屏幕之外后 `get_app_state` 仍返回截图与 bounds（修复前后对照）。
