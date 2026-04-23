# Linux Computer Use Runtime

## 目标

把 `open-computer-use` 从 macOS / Windows 扩展到 Linux 桌面，优先让同一组 9 个 Computer Use tools 能在 Ubuntu GNOME 桌面 session 里通过独立二进制跑通，并把 Linux 桌面自动化的能力边界记录清楚。

## 范围

- 包含：
  - Linux 独立 runtime，不耦合 Swift `.app`。
  - Go CLI / MCP / `call --calls` 入口。
  - `list_apps`、`get_app_state`、`click`、`perform_secondary_action`、`scroll`、`drag`、`type_text`、`press_key`、`set_value` 的功能性实现。
  - Linux arm64/amd64 构建脚本和基础 Go 单测。
  - Ubuntu GNOME VM 上的 9-tool 实机 smoke。
  - 架构文档、README、质量说明和 history。
- 不包含：
  - 替换 macOS Swift 主线。
  - Linux installer、desktop entry、system package 或 code signing。
  - visual cursor overlay。
  - 完整 Linux fixture / 可重复 smoke runner。

## 背景

- 相关文档：
  - `docs/ARCHITECTURE.md`
  - `docs/QUALITY_SCORE.md`
  - `docs/SECURITY.md`
  - `docs/RELIABILITY.md`
- 相关代码路径：
  - `apps/OpenComputerUseLinux/`
  - `scripts/build-open-computer-use-linux.sh`
  - `scripts/ci.sh`
  - `apps/OpenComputerUseWindows/`
- 已知约束：
  - Linux 上最接近 macOS AX 的桌面接口是 AT-SPI2，经由 D-Bus 暴露 app/window/accessibility tree、actions、editable text 和 value 接口。
  - Ubuntu GNOME 默认 Wayland session 下，任意后台坐标键鼠和截图都不是一套等价于 macOS AX 的通用模型。
  - 第一版策略是 AT-SPI semantic action / editable text / value 优先，coordinate click / drag / key synthesis 仅作为 best-effort fallback。
  - SSH tty 默认没有 `XDG_RUNTIME_DIR` / `DBUS_SESSION_BUS_ADDRESS` / display 环境；真实 UI 测试需要跑在已登录桌面用户 session 里。

## 风险

- 风险：不同 toolkit 暴露的 AT-SPI tree 深度、role、action 名称差异大。
  - 缓解方式：Linux bridge 单独放宽 tree traversal depth，并保留字段级容错。
- 风险：Wayland 下 screenshot 可能返回黑图或被 portal/ compositor 拒绝。
  - 缓解方式：截图只做 best-effort；检测到全黑采样时不回传 image block，避免误导调用方。
- 风险：coordinate click / drag / key synthesis 可能影响当前 foreground context。
  - 缓解方式：MCP instructions 和 README 明确写出 Linux background input boundary；优先使用 element-targeted AT-SPI action。

## 里程碑

1. 确认 Linux 可用接口和边界。
2. 完成 Linux Go runtime、Python AT-SPI bridge 和 9-tool 功能性实现。
3. 完成本地单测、交叉编译和 Ubuntu GNOME VM 9-tool smoke。
4. 后续补 Linux fixture、可重复 smoke runner、system package 和更稳定截图方案。

## 验证方式

- 命令：
  - `(cd apps/OpenComputerUseLinux && go test ./...)`
  - `./scripts/build-open-computer-use-linux.sh --arch arm64`
  - `./scripts/build-open-computer-use-linux.sh --arch amd64`
  - `open-computer-use mcp`
  - `open-computer-use call list_apps`
  - `open-computer-use call --calls-file <9-tool smoke json>`
- 手工检查：
  - 在 Ubuntu GNOME desktop session 里打开 `gnome-text-editor`。
  - 运行 `get_app_state -> set_value -> type_text -> press_key -> perform_secondary_action -> click -> scroll -> drag` sequence。
  - 确认每个 tool 返回 `isError=false`，并且 Text Editor 内容包含 marker。
- 观测检查：
  - 纯 SSH tty 没有桌面环境变量时应返回明确错误，而不是误判为 AT-SPI 逻辑失败。

## 进度记录

- [x] 确认 Ubuntu GNOME VM 有已登录 `leo` Wayland session、AT-SPI bus、Python GI、Atspi、Gdk/GdkPixbuf。
- [x] 新增 `apps/OpenComputerUseLinux`，用 Go 实现 CLI、MCP、tool schema、`call --calls` 和 snapshot cache。
- [x] 嵌入 Python AT-SPI bridge，实现 app/window discovery、tree rendering、semantic action、editable text、value、key/mouse fallback 和 best-effort screenshot。
- [x] 新增 Linux arm64/amd64 构建脚本。
- [x] 新增 Go 单测，并接入仓库基础 CI。
- [x] 本地通过 `(cd apps/OpenComputerUseLinux && go test ./...)`。
- [x] 本地通过 `./scripts/build-open-computer-use-linux.sh --arch arm64` 和 `--arch amd64`。
- [x] 上传 arm64 二进制到 Ubuntu VM，验证 `--version` 为 `0.1.33`。
- [x] 在 Ubuntu VM 中验证 `call list_apps` 返回 `isError=false` 并包含 `gnome-text-editor`。
- [x] 在 Ubuntu VM 中验证 MCP `initialize` / `tools/list`，tool count 为 9。
- [x] 在 Ubuntu VM 中验证 8-tool sequence：`get_app_state`、`set_value`、`type_text`、`press_key`、`perform_secondary_action`、`click`、`scroll`、`drag` 均 `isError=false`。
- [ ] 增加 Linux fixture 和可重复 smoke runner。
- [ ] 评估 xdg-desktop-portal / compositor-specific screenshot 路径，补非黑图 capture。
- [x] 将 Linux artifact 接入 npm release packaging，通过 `open-computer-use-linux-arm64` / `open-computer-use-linux-x64` platform packages 分发。
- [ ] 评估用原生 Go D-Bus/libatspi 替换 Python GI bridge 的收益和风险。

## 决策记录

- 2026-04-22：Linux runtime 不复用 Swift `.app` 或 Windows `.exe` bridge，采用独立 Go binary，避免把 macOS / Windows 的权限和输入模型强行带到 Linux。
- 2026-04-22：第一版用 Go 管协议、状态和分发边界，用嵌入式 Python GI 调 AT-SPI/GDK，优先完成 9-tool 功能性闭环。
- 2026-04-22：Linux 默认使用 AT-SPI semantic action / editable text / value；coordinate mouse、drag、keyboard synthesis 作为 best-effort fallback，并在 MCP instructions 中明确不是通用 Wayland background input。
- 2026-04-22：GNOME Text Editor 的 AT-SPI tree 深度超过 Windows runtime 沿用的 16 层，Linux bridge 单独把 traversal depth 放宽到 64。
- 2026-04-22：GNOME Wayland 下 GDK root capture 在 VM 上返回黑图；Linux bridge 检测全黑采样后省略 image block，后续再评估 portal/compositor-specific capture。
- 2026-04-23：Linux release artifact 接入 npm platform package，不新增系统 installer；root `open-computer-use` package 通过 optional dependency 按 `linux-arm64` / `linux-x64` 自动选择 binary。
