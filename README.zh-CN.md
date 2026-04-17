# open-computer-use

English version: [README.md](./README.md)

`open-computer-use` 是一个开源的 `Computer Use` 服务，已经包装成 `MCP` 协议，支持所有的 AI Agent 或 MCP Client 快速调用，实现 macOS 上的 `Computer Use` 能力。

项目的背后是 OpenAI 刚发布的 [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/)，让我看到了基于 Accessibility 可以实现非抢占式 CUA 能力，因此决定复刻一个开源版本。

在这期间我利用了之前写的 [harness 模版](https://github.com/iFurySt/harness-template) 开启了这个新项目。这是一个可以快速拉起面向 AI 仓库的 template，非常适合 100% AI-Generated 的项目，也是这一个月来我们最大的实践和收获。现在我们可以基于这套方法论快速实现很多东西；如果你有兴趣，我也写了一篇[文章](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/)专门介绍这套方法论。

## Quick Start

先全局安装：

```bash
npm i -g open-computer-use
```

第一次使用前，给 `Open Computer Use.app` 授予 macOS 的 `Accessibility` 和 `Screen Recording` 权限。

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

# 一键安装到 Codex，写到 ~/.codex/config.toml 中
open-computer-use install-codex-mcp

# 一键安装到 Codex 插件，主要方便在 Codex App 中使用
open-computer-use install-codex-plugin

# 直接启动 MCP server
open-computer-use mcp

# 检查权限；只有缺失时才会拉起引导，已全部授权则只打印状态并退出
open-computer-use doctor

# 查看帮助
open-computer-use -h
```

## License

[MIT](./LICENSE)。
