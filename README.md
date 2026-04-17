# open-computer-use

## 简介

一个用 Swift 实现的开源 macOS `computer-use` MCP server。

当前版本聚焦两件事：

- 通过 `stdio` MCP 暴露 9 个和官方 `computer-use` 同名的 tools。
- 在仓库内自带一个 GUI fixture app、smoke suite 和无 Dock 图标的 app 模式权限引导，并为 `click` 补一层独立 visual cursor overlay，保证这 9 个 tools 有稳定可回归的本地验证路径。

当前实现的 9 个 tools：

- `list_apps`
- `get_app_state`
- `click`
- `perform_secondary_action`
- `scroll`
- `drag`
- `type_text`
- `press_key`
- `set_value`

## npm 一键安装

现在可以直接用 npm 安装预编译包，不需要用户自己先装好 Swift/Xcode 再编译：

```bash
npm install -g open-computer-use
```

下面三个包名都可以安装到同一套内容：

- `open-computer-use`
- `open-computer-use-mcp`
- `open-codex-computer-use-mcp`

安装任意一个后，都会同时提供这三个命令别名：

```bash
# 查看 CLI 版本和完整命令帮助
open-computer-use --version
open-computer-use --help
open-computer-use help snapshot

# 直接写入 Codex 的 MCP 配置；重复执行会自动幂等跳过
open-computer-use install-codex-mcp

# 直接写入 Claude Code 当前项目的 MCP 配置；重复执行会自动幂等跳过
open-computer-use install-claude-mcp

# 检查当前权限状态；如果有缺失会直接拉起权限 onboarding 窗口
open-computer-use doctor

# 以 stdio MCP server 模式启动，给 Claude Desktop / Cursor / Cline / 自定义 client 连接
open-computer-use mcp

# 安装到本机 Codex 插件系统，作为 repo-local / local marketplace plugin 使用
open-computer-use install-codex-plugin
```

安装完成后，建议先做这一条：

```bash
open-computer-use doctor
```

先确认并授权宿主终端或 MCP client 的 macOS `Accessibility` 和 `Screen Recording` 权限；缺权限时会直接拉起权限 onboarding 窗口。

如果你是把它当普通 stdio MCP server 配到自己的 client 里，用法基本就是：

1. 全局安装一个包：

```bash
npm install -g open-computer-use
```

2. 在支持 MCP 的 client 配置里加一段 JSON：

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
```

3. 第一次实际调用前，给宿主终端或 app 授予 macOS `Accessibility` 和 `Screen Recording` 权限。

也就是说，如果只是通过 MCP 使用，它现在就是“`npm install -g` + 一段配置 + 首次授权”这条路径。

如果你的 client 也采用 `mcpServers` 这类 stdio MCP 配置结构，上面这段 JSON 可以直接作为起点。

如果你想默认关闭点击时的软件 cursor overlay，也可以这样写：

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"],
      "env": {
        "OPEN_COMPUTER_USE_VISUAL_CURSOR": "0"
      }
    }
  }
}
```

说明：

- npm 包内已经携带预编译的 `Open Computer Use.app`，当前面向 macOS 14+。
- 包内 `.app` 是 universal binary，同时支持 Apple Silicon 与 Intel Mac。
- 真正执行前，宿主终端或 app 仍然需要被授予 `Accessibility` 与 `Screen Recording` 权限。
- `open-computer-use install-claude-mcp` 会按 Claude 官方 MCP 文档的 local scope 结构，把当前仓库写到 `~/.claude.json` 的 `projects."<repo-path>".mcpServers` 下；写入前会先校验现有 JSON，重复执行会 no-op。
- `open-computer-use install-codex-mcp` 会把 `[mcp_servers."open-computer-use"]` 幂等写入 `~/.codex/config.toml`；写入前会先用 TOML 解析校验现有配置，避免重复追加同一项。
- `open-computer-use install-codex-plugin` 会把 npm 包自身注册到本机 Codex 插件系统，不需要源码仓库路径。

## 从源码运行

环境要求：

- macOS 14+
- Xcode Command Line Tools / Swift 6.2+
- 已授予宿主终端或 app 的 `Accessibility` 与 `Screen Recording` 权限

构建与诊断：

```bash
swift build
.build/debug/OpenComputerUse --version
.build/debug/OpenComputerUse --help
# 缺权限时会打开权限 onboarding 窗口
.build/debug/OpenComputerUse doctor
.build/debug/OpenComputerUse list-apps
```

如果你只是想把它作为 Codex 的普通 stdio MCP server 写进本机配置，不走 plugin marketplace，可以直接执行：

```bash
./scripts/install-codex-mcp.sh
```

这个脚本只会更新 `~/.codex/config.toml` 里的 `[mcp_servers."open-computer-use"]`，并在写入前先验证现有文件仍是合法 TOML；如果同一条配置已经存在，会直接 no-op，不会重复写入。

如果你想把它安装到 Claude Code 当前项目的 `~/.claude.json`，可以直接执行：

```bash
./scripts/install-claude-mcp.sh
```

它会按 Claude 官方 MCP 文档里的 local scope 结构，把当前仓库路径写到 `projects."<repo-path>".mcpServers."open-computer-use"`；如果同一条配置已经存在，也会直接 no-op。

打包 app 并打开权限引导窗口：

```bash
./scripts/build-open-computer-use-app.sh debug
open "dist/Open Computer Use.app"
```

如果你要产出可分发的 universal app，可以显式传：

```bash
./scripts/build-open-computer-use-app.sh --configuration release --arch universal
```

启动 MCP server：

```bash
.build/debug/OpenComputerUse mcp
```

如果你想临时关闭点击时的软件 cursor overlay，可以显式传：

```bash
OPEN_COMPUTER_USE_VISUAL_CURSOR=0 .build/debug/OpenComputerUse mcp
```

安装到本机 Codex 插件系统：

```bash
./scripts/install-codex-plugin.sh
```

这会把当前仓库注册成一个 repo-local marketplace，并启用插件 `open-computer-use`。脚本会在缺少打包产物时自动构建 `dist/Open Computer Use.app`，写入 `~/.codex/config.toml`，并移除旧的直连 MCP 配置，避免同一组 tools 被重复注册。安装后重启 Codex 即可看到插件入口。
它还会把插件包和已构建的 app 同步到 `~/.codex/plugins/cache/open-computer-use-local/open-computer-use/<version>/`，这样 Codex 实际加载的是本机插件缓存，而不是直接从源码仓库路径启动。
如果你之前给旧的 `OpenCodexComputerUse.app` 或 `OpenComputerUse.app` 授过 `Accessibility` / `Screen Recording` 权限，切到 `Open Computer Use.app` 后通常需要在系统设置里重新授权一次。

本地验证：

```bash
swift test
./scripts/run-tool-smoke-tests.sh
```

如果你需要从仓库里直接探测官方 Codex 桌面版自带的闭源 `computer-use` 插件，优先用：

```bash
cd scripts/computer-use-cli
go run . list-tools
go run . call list_apps
```

这不是仓库主产物，而是一个调试/探针 CLI。它会自动在两种模式间切换：

- 对官方 bundled `computer-use`，走 `codex app-server` 代理调用。
- 对显式传入的非 Sky stdio server，走 direct MCP 连接。

详细背景、约束和用法见 [docs/references/codex-computer-use-cli.md](./docs/references/codex-computer-use-cli.md)。

如果你想单独看某个 app 当前会被如何序列化，可以直接跑：

```bash
.build/debug/OpenComputerUse snapshot Finder
```

如果直接运行 `OpenComputerUse` 而不带子命令，默认会进入 app 模式并显示权限 onboarding 窗口；该窗口以 agent-style app 方式运行，不会在 Dock 常驻显示图标。
如果想看某个子命令的参数说明，可以直接用 `OpenComputerUse help <command>` 或 `<command> --help`。

## 抓 Codex 上游流量

如果你想用 `mitmproxy` / `mitmweb` 观察 Codex 自己打到上游的请求，仓库内提供了一个默认脱敏的 addon：

详细的长期复用方法、后台启动方式和样本沉淀约定，见 [docs/references/codex-network-capture.md](./docs/references/codex-network-capture.md)。

如果你只是想快速后台启动一份抓包并让后续 Agent 复用，优先直接用：

```bash
./scripts/start-codex-mitm-dump.sh basic-ok
```

```bash
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py
```

默认输出目录会落到系统临时目录下的 `codex-dumps/<timestamp>/`。如果你想把抓包结果长期留在仓库里做分析，推荐显式指定到被 Git 忽略的 `artifacts/codex-dumps/`：

```bash
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py \
  --set codex_dump_dir=artifacts/codex-dumps/session-001
```

然后让 Codex 走这个 HTTPS 代理：

```bash
HTTPS_PROXY=http://127.0.0.1:8082 \
NO_PROXY=127.0.0.1,localhost \
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem \
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

当前主模型流量通常会出现在：

```text
https://chatgpt.com/backend-api/codex/responses
```

它会先做 `101 Switching Protocols`，随后在 WebSocket 帧里承载 `response.create`、`response.output_text.delta` 等消息。`scripts/codex_dump.py` 会把这些帧按 JSONL 持久化到 `websocket/` 目录里，同时把匹配到的 HTTP 请求写到 `http/` 目录。

现在脚本还会把当前抓包 `session_id` 对应的 `~/.codex/sessions/rollout-*.jsonl` 摘要一起写到 `local-sessions/`，所以同一个实验目录里可以直接对照看：

- 模型侧的 tool decision
- Codex 宿主侧的 `function_call`
- 本地 tool 的 `function_call_output`

仓库默认已经把 `artifacts/codex-dumps/` 加进 `.gitignore`，适合把真实抓包样本留在 repo 目录里反复分析，而不误提交到 Git。

## 工程结构

- `apps/OpenComputerUse`
  `stdio` MCP server、本地诊断入口和默认 app 模式权限引导；默认 bundle 以 agent-style 运行，避免在执行过程中额外暴露 Dock 图标。
- `packages/OpenComputerUseKit`
  MCP transport、tool registry、app discovery、snapshot、输入模拟和 fixture bridge。
- `apps/OpenComputerUseFixture`
  本地 GUI 夹具，用于安全验证点击、输入、滚动和拖拽等行为。
- `apps/OpenComputerUseSmokeSuite`
  端到端 smoke runner，会真实拉起 fixture 和 MCP server，对 9 个 tools 做回归。
- `scripts/build-open-computer-use-app.sh`
  生成最小可运行的 `.app` bundle，便于真实授权与本地 UI 验证。
- `scripts/npm/`
  生成三个 npm 包名对应的 staging 目录，并提供 dry-run / publish 脚本。
- `scripts/computer-use-cli`
  一个独立 Go 模块，用来探测官方 bundled `computer-use` 和普通 stdio MCP server；默认会对官方 Sky client 走 `codex app-server` 代理，避免 caller signing / launch constraint 问题。
- `plugins/open-computer-use`
  repo-local Codex plugin 包装层，包含 plugin manifest、MCP 启动脚本和展示资源。
- `scripts/install-codex-mcp.sh`
  把 `open-computer-use mcp` 作为普通 stdio MCP server 幂等写入 `~/.codex/config.toml`。
- `scripts/install-claude-mcp.sh`
  把 `open-computer-use mcp` 作为 Claude Code 当前项目的 local-scope MCP server 幂等写入 `~/.claude.json`。
- `scripts/install-codex-plugin.sh`
  把当前仓库注册到本机 Codex 的本地 marketplace，安装插件缓存包，并启用 `open-computer-use` 插件。

## 当前取舍

- 普通 app 路径优先走 macOS Accessibility、窗口截图和 CGEvent 输入事件。
- `click` 现在会额外拉起一层独立的软件 cursor overlay，用来给用户提供移动轨迹、点击 pulse 和短暂停留；它是可视化层，不改变底层 AX/HID 的动作决策，并会在动作结束后自动消失。
- overlay 会优先在运行时从本机官方 `Codex Computer Use.app` 的 bundle 里读取 `SoftwareCursor` 资产并做一次轻量处理；如果本机没有官方 bundle，再回退到仓库内的矢量绘制样式。
- overlay 不再固定置顶，而是尽量按目标 window 的编号和层级排到“目标 app 之上、其他当前更高层窗口之下”的位置。
- fixture app 为了提供稳定回归，会额外导出一份合成状态，并接受测试专用 command bridge。
- 当前不复刻官方闭源 app 的签名边界、私有 IPC、完整 overlay choreography 和插件自安装逻辑。

## npm 发布

仓库现在提供了三层 npm 相关入口：

```bash
node ./scripts/npm/build-packages.mjs
./scripts/release-package.sh
node ./scripts/npm/publish-packages.mjs
```

- `build-packages.mjs` 会构建 universal app 并 stage 三个 npm 包目录到 `dist/npm/`。
- `release-package.sh` 会额外把它们打成 `dist/release/npm/*.tgz`，并生成 `dist/release/release-manifest.json`。
- `.github/workflows/release.yml` 支持通过 push `0.1.7` / `v0.1.7` 这类 git tag 自动发布，也保留手动触发作为兜底；默认兼容 npm Trusted Publishing，同时也支持通过仓库 `NPM_TOKEN` secret 兜底发布。

## 许可证

[MIT](./LICENSE)
