# Configurable click method

## 目标

为 `click` 增加向后兼容的 `click_method` 参数，让调用方可以显式选择 accessibility、app-posted mouse event 或 global pointer event，同时保证未传参数时的 `auto` 行为与当前版本一致。

## 范围

- 包含：
  - macOS `click` dispatcher、tool schema、service 路由和输入模拟安全边界。
  - Windows / Linux 同名协议参数、已有能力映射和 unsupported 错误。
  - Swift / Go 单元测试、架构、安全、skill usage 和 history 文档。
- 不包含：
  - 修改 `auto` 下的 AX 后代候选扫描策略。
  - 为 Windows 新增全局 `SendInput`，或为 Linux 新增进程定向鼠标后端。
  - 发布、打 tag 或推送远端。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`skills/open-computer-use/references/usage.md`。
- 相关代码路径：`ComputerUseService.click`、`InputSimulation.clickTargeted` / `clickGlobally`、`MacOSAppAgentProxy`、Windows UIA / `PostMessage` bridge、Linux AT-SPI bridge。
- 已知约束：默认行为不能变化；强制模式不能静默 fallback；全局指针仍需 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`。

## 风险

- 风险：全局指针事件会移动真实鼠标、改变前台焦点或命中非目标窗口。
- 缓解方式：要求调用参数和环境变量双重显式授权，并在执行前拒绝未授权请求。
- 风险：跨平台底层能力不对称。
- 缓解方式：保持公共枚举一致，对平台不支持的模式返回稳定错误，不伪装成功或回退到其他实现。
- 风险：重构 `auto` 路径引入行为漂移。
- 缓解方式：保留现有分支和 fallback 函数，只在外围增加显式路由。

## 里程碑

1. 增加公共参数、解析与安全校验。
2. 接入三平台已有实现并补测试。
3. 更新文档、完成验证并记录 history。

## 验证方式

- 命令：`swift test`。
- 命令：`(cd apps/OpenComputerUseWindows && go test ./...)`。
- 命令：`(cd apps/OpenComputerUseLinux && go test ./...)`。
- 命令：`npm run package:skill`。
- 手工检查：确认 `tools/list` 暴露四个枚举值，默认仍为 `auto`。
- 观测检查：显式 `app_post` 不进入 AX 路由，显式 `global` 未授权时不产生鼠标事件。

## 进度记录

- [x] 确认范围、现有三平台实现和安全边界。
- [x] 完成协议与实现。
- [x] 完成测试与文档。
- [x] 完成验证并归档计划。

## 决策记录

- 2026-07-22：公共参数命名为 `click_method`，枚举为 `auto`、`accessibility`、`app_post`、`global`；`app_post` 表示向目标 app/window 投递事件，在 macOS 映射到 `postToPid`，在 Windows 映射到 HWND `PostMessage`。
- 2026-07-22：`accessibility` 要求 `element_index`；`app_post` / `global` 可使用 `element_index` 或 `x/y`。
- 2026-07-22：Windows 第一版不支持 `global`，Linux 第一版不支持 `app_post`，均返回显式错误。
- 2026-07-22：macOS CLI 与 MCP proxy 都随请求转发 `OPEN_COMPUTER_USE_*` 环境变量，确保真正执行输入的 app agent 能看到全局指针授权。
- 2026-07-22：`swift test`、Windows / Linux `go test ./...`、skill 打包、标准 9-tool smoke 和 visual cursor idle smoke 全部通过；未自动执行会移动真实鼠标的 live global click。
