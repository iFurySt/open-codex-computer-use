# open-computer-use

[中文说明](./README.zh-CN.md)

[![Open Computer Use custom demo cover](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

`open-computer-use` is an open-source `Computer Use` service exposed over `MCP`, so any AI agent or MCP client can call it directly and use computer interaction capabilities on macOS.

This project was inspired by OpenAI's recently released [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/). It showed that non-intrusive CUA can be built on top of macOS Accessibility, which is why I decided to build an open-source version.

I bootstrapped this repo with my earlier [harness template](https://github.com/iFurySt/harness-template). It is a template for spinning up an AI-oriented repository quickly, especially for projects that are close to 100% AI-generated. This has been one of our most useful workflows over the past month, and it now lets us ship new ideas very quickly. If you are interested, I also wrote [a post](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/) about the methodology behind it.

## Quick Start

Install it globally first:

```bash
npm i -g open-computer-use
```

Before first use, grant macOS `Accessibility` and `Screen Recording` permission to the `Open Computer Use.app` you actually plan to keep installed. The CI-built release package remains the stable identity for distribution. Local debug/dev builds are intentionally packaged as `Open Computer Use (Dev).app`, so System Settings shows them as a separate development app instead of another indistinguishable `Open Computer Use`. If you are not sure about the current state, run:

```bash
open-computer-use
```

Then add it to your MCP client:

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

## More

Besides using the MCP JSON config above, you can also use the built-in subcommands:

```bash
# Install into Claude Code by writing to ~/.claude.json
open-computer-use install-claude-mcp
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
# Install as a Codex plugin, mainly for Codex App usage; if you use this, you usually do not need install-codex-mcp as well
open-computer-use install-codex-plugin
# Start the MCP server directly
open-computer-use mcp
# Call a single Computer Use tool and print the MCP-style JSON result
# Image payloads stay in the result shape, but CLI stdout summarizes base64 instead of dumping it verbatim
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
# Run a sequence in one process so element_index state can be reused
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
# Check permissions; onboarding only opens when something is missing
open-computer-use doctor
# Show help
open-computer-use -h
```

## Cursor Motion

Cursor Motion is an open-source cursor motion system for macOS, based on public information shared by members of the Software.Inc team. You can run it from source or download the app from the [Releases page](https://github.com/iFurySt/open-codex-computer-use/releases).

```bash
swift run CursorMotion
```

[![Cursor Motion custom demo cover](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## License

[MIT](./LICENSE)
