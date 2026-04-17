# `scripts/computer-use-cli`

这个目录下放的是一个独立 Go CLI，用来做两类事情：

- 探测官方 Codex 桌面版自带的闭源 `computer-use`
- 直接连接普通 stdio MCP server，例如本仓库产出的 `open-computer-use`

它不是仓库主产物，而是调试/逆向分析辅助工具。

## 为什么需要它

在这台机器上，官方 bundled `computer-use` 的可执行文件 `SkyComputerUseClient` 不能被一个普通 unsigned MCP client 稳定直接拉起。

已验证的现象是：

- 标准 stdio MCP client 握手前就退出
- 官方 Go MCP SDK 自带示例也会失败
- crash report 指向 `Launch Constraint Violation` / `CODESIGNING`

结论是：这不是单纯的 MCP 协议兼容问题，而是宿主签名/父进程约束。要探测官方 bundled `computer-use`，应优先借助已签名的 Codex 宿主，通过 `codex app-server` 走 `mcpServer/tool/call`。

## 目录位置

```text
scripts/computer-use-cli/
```

目录本身是一个独立 Go module，内部自带 `go.mod`、单测和 README。

## AI 默认用法

如果任务目标是“验证官方 Codex 自带的 `computer-use` 能不能列工具、能不能调某个 tool”，优先这样跑：

```bash
cd scripts/computer-use-cli
go run . list-tools
go run . call list_apps
go run . call get_app_state --args '{"app":"Feishu"}'
```

默认 `auto` 模式会自动选择：

- 官方 bundled `computer-use` -> `app-server`
- 显式传入的非 Sky server binary -> `direct`

## 两种 transport

### 1. `app-server`

适用于官方 bundled `computer-use`。

```bash
cd scripts/computer-use-cli
go run . list-tools --transport app-server
go run . call list_apps --transport app-server
```

这个模式会：

1. 启动 `codex app-server`
2. 建一个 ephemeral thread
3. 通过 `mcpServer/tool/call` 调目标 server

如果本机 Codex 可执行不在默认位置，可以显式指定：

```bash
CODEX_APP_SERVER_BIN=/Applications/Codex.app/Contents/Resources/codex \
go run . call list_apps --transport app-server
```

### 2. `direct`

适用于普通 stdio MCP server，例如本仓库本地产出的 `open-computer-use`。

```bash
cd scripts/computer-use-cli
go run . call list_apps \
  --transport direct \
  --server-bin ~/.codex/plugins/cache/open-computer-use-local/open-computer-use/0.1.7/scripts/launch-open-computer-use.sh
```

## 什么时候不要再重试 direct

如果目标是官方 `SkyComputerUseClient`，而且你已经看到下面这类现象，就不要再浪费时间试“换一个通用 MCP client”：

- `EOF`
- `broken pipe`
- 初始化前退出
- crash report 里出现 `Launch Constraint Violation`

这类情况下，优先切回 `app-server` 模式。

## 本地验证

```bash
cd scripts/computer-use-cli
go test ./...
```

如果只是想快速确认工具链没坏，最小正向验证通常是：

```bash
cd scripts/computer-use-cli
go run . list-tools
go run . call list_apps
```
