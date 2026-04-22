# open-computer-use

[English Version](./README.md)

[![open-computer-use 自定义演示封面](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI 作为 host 接入 `open-computer-use` MCP，并完整触发真实的 Computer Use 操作。</em></sub>

`open-computer-use` 是一个开源的 `Computer Use` 服务，已经包装成 `MCP` 协议，支持所有的 AI Agent 或 MCP Client 快速调用，实现 macOS 上的 `Computer Use` 能力。仓库里也已经新增实验性的 Windows runtime，用 Go 生成独立 `.exe`，暴露同样的 9 个 tool。

项目的背后是 OpenAI 刚发布的 [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/)，让我看到了基于 Accessibility 可以实现非抢占式 CUA 能力，因此决定复刻一个开源版本

在这期间我利用了之前写的 [harness 模版](https://github.com/iFurySt/harness-template) 开启了这个新项目。这是一个可以快速拉起面向 AI 仓库的 template，非常适合 100% AI-Generated 的项目，也是这一个月来我们最大的实践和收获。现在我们可以基于这套方法论快速实现很多东西；如果你有兴趣，我也写了一篇[文章](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/)专门介绍这套方法论

## Quick Start

当前 npm 包发布的是 macOS app bundle，先全局安装：

```bash
npm i -g open-computer-use
```

在本机交互式的全局安装场景下，npm 也会尝试自动拉起内置的 permiso 风格权限引导；如果没有弹出来，手动运行 `open-computer-use` 或 `open-computer-use doctor` 即可。

第一次使用前，给你实际准备长期保留的那个 `Open Computer Use.app` 授予 macOS 的 `Accessibility` 和 `Screen Recording` 权限。CI 产出的 release 包继续作为正式分发身份；本地 debug/dev 构建会故意打成 `Open Computer Use (Dev).app`，这样系统设置里会明确显示成一个开发版 app，而不是再出现两个同名的 `Open Computer Use`。

```bash
open-computer-use
```

接着把它配到你的 MCP client 里：

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

## 更多

除了直接用上面的 MCP JSON 配置，你也可以用一些内置子命令：

```bash
# 一键安装到 Claude Code，写到 ~/.claude.json 中
open-computer-use install-claude-mcp

# 一键安装到 Gemini CLI 当前项目，写到 ./.gemini/settings.json
open-computer-use install-gemini-mcp

# 一键安装到 Gemini CLI 用户级配置
open-computer-use install-gemini-mcp --scope user

# 一键安装到 Codex，写到 ~/.codex/config.toml 中
open-computer-use install-codex-mcp

# 一键安装到 opencode，写到 ~/.config/opencode/opencode.json（或当前生效的配置文件）
open-computer-use install-opencode-mcp

# 一键安装到 Codex 插件，主要方便在 Codex App 中使用
open-computer-use install-codex-plugin

# 直接启动 MCP server
open-computer-use mcp

# 直接调用单个 Computer Use tool，输出 MCP 风格的 JSON result
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'

# 在同一个进程里编排连续动作，复用 get_app_state 拿到的 element_index
# 连续动作默认会在成功的相邻操作之间 sleep 1 秒
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

# 检查权限；只有缺失时才会拉起引导，已全部授权则只打印状态并退出
open-computer-use doctor

# 查看帮助
open-computer-use -h
```

## Windows Runtime

Windows 侧不复用 Swift `.app`，而是放在 `apps/OpenComputerUseWindows` 里独立构建；执行时优先走 Windows UI Automation，必要时用 Win32 window message 做 fallback。

```bash
# 从仓库里构建 Windows arm64 exe
./scripts/build-open-computer-use-windows.sh --arch arm64

# 在 Windows 里直接运行
open-computer-use.exe mcp
open-computer-use.exe call list_apps
open-computer-use.exe call --calls "[{\"tool\":\"get_app_state\",\"args\":{\"app\":\"notepad\"}},{\"tool\":\"type_text\",\"args\":{\"app\":\"notepad\",\"text\":\"hello\"}}]"
```

这个 `.exe` 需要跑在已登录的桌面 session 里。作为 Windows service 或纯 SSH 脱离桌面运行时，系统可能不给它暴露顶层 UI Automation 窗口。

默认情况下，Windows runtime 只连接已经运行的 app，不会自动启动目标 app，也不会执行 `SetFocus`；`type_text` 也会避开 UIA `ValuePattern.SetValue` fallback，因为有些 app 会在这条路径里主动把自己带到前台。如果确实需要旧的前台行为，可以设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` 允许启动 fallback，设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1` 允许 `SetFocus` secondary action，设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1` 允许 UIA text fallback。

## Cursor Motion

Cursor Motion 是一个面向 macOS 的开源光标运动系统，基于 Software.Inc 几位大佬的公开信息实现的开源版本，可以代码里运行，也可以到 [Releases 页面](https://github.com/iFurySt/open-codex-computer-use/releases) 下载 app 运行。

```bash
swift run CursorMotion
```

[![Cursor Motion 自定义演示封面](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## Star History

<a href="https://www.star-history.com/?repos=iFurySt%2Fopen-codex-computer-use&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
    <img alt="open-computer-use Star History 趋势图" src="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
  </picture>
</a>

## License

[MIT](./LICENSE)
