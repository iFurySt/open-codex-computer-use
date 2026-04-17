# open-computer-use

## 简介

一个用 Swift 实现的开源 macOS `computer-use` MCP server。

当前版本聚焦两件事：

- 通过 `stdio` MCP 暴露 9 个和官方 `computer-use` 同名的 tools。
- 在仓库内自带一个 GUI fixture app、smoke suite 和无 Dock 图标的 app 模式权限引导，保证这 9 个 tools 有稳定可回归的本地验证路径。

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

## 快速开始

环境要求：

- macOS 14+
- Xcode Command Line Tools / Swift 6.2+
- 已授予宿主终端或 app 的 `Accessibility` 与 `Screen Recording` 权限

构建与诊断：

```bash
swift build
.build/debug/OpenComputerUse doctor
.build/debug/OpenComputerUse list-apps
```

打包 app 并打开权限引导窗口：

```bash
./scripts/build-open-computer-use-app.sh debug
open dist/OpenComputerUse.app
```

启动 MCP server：

```bash
.build/debug/OpenComputerUse mcp
```

安装到本机 Codex 插件系统：

```bash
./scripts/install-codex-plugin.sh
```

这会把当前仓库注册成一个 repo-local marketplace，并启用插件 `open-computer-use`。脚本会在缺少打包产物时自动构建 `dist/OpenComputerUse.app`，写入 `~/.codex/config.toml`，并移除旧的直连 MCP 配置，避免同一组 tools 被重复注册。安装后重启 Codex 即可看到插件入口。
它还会把插件包和已构建的 app 同步到 `~/.codex/plugins/cache/open-computer-use-local/open-computer-use/<version>/`，这样 Codex 实际加载的是本机插件缓存，而不是直接从源码仓库路径启动。
如果你之前给旧的 `OpenCodexComputerUse.app` 授过 `Accessibility` / `Screen Recording` 权限，切到 `OpenComputerUse.app` 后需要在系统设置里重新授权一次。

本地验证：

```bash
swift test
./scripts/run-tool-smoke-tests.sh
```

如果你想单独看某个 app 当前会被如何序列化，可以直接跑：

```bash
.build/debug/OpenComputerUse snapshot Finder
```

如果直接运行 `OpenComputerUse` 而不带子命令，默认会进入 app 模式并显示权限 onboarding 窗口；该窗口以 agent-style app 方式运行，不会在 Dock 常驻显示图标。

## 抓 Codex 上游流量

如果你想用 `mitmproxy` / `mitmweb` 观察 Codex 自己打到上游的请求，仓库内提供了一个默认脱敏的 addon：

详细的长期复用方法、后台启动方式和样本沉淀约定，见 [docs/references/codex-network-capture.md](/Users/bytedance/projects/github/open-codex-computer-use/docs/references/codex-network-capture.md)。

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
- `plugins/open-computer-use`
  repo-local Codex plugin 包装层，包含 plugin manifest、MCP 启动脚本和展示资源。
- `scripts/install-codex-plugin.sh`
  把当前仓库注册到本机 Codex 的本地 marketplace，安装插件缓存包，并启用 `open-computer-use` 插件。

## 当前取舍

- 普通 app 路径优先走 macOS Accessibility、窗口截图和 CGEvent 输入事件。
- fixture app 为了提供稳定回归，会额外导出一份合成状态，并接受测试专用 command bridge。
- 当前不复刻官方闭源 app 的签名边界、私有 IPC、overlay UI 和插件自安装逻辑。

## 许可证

[MIT](./LICENSE)
