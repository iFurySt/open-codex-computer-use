# open-computer-use

[中文说明](./README.zh-CN.md)

<a href="https://llmapis.com?source=https%3A%2F%2Fgithub.com%2FiFurySt%2Fopen-codex-computer-use" target="_blank"><img src="https://llmapis.com/api/badge/iFurySt/open-codex-computer-use" alt="LLMAPIS" width="80" /></a>

*Partnership with [https://llmapis.com](https://llmapis.com) - Discover more AI tools and resources*

[![Open Computer Use custom demo cover](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI connected to `open-computer-use` through MCP, driving real Computer Use actions end to end.</em></sub>

`open-computer-use` is an open-source `Computer Use` service exposed over `MCP`, so any AI agent or MCP client can call it directly and use computer interaction capabilities on macOS. An experimental Windows runtime now lives in this repo too, with the same 9-tool surface implemented as a standalone Go-built `.exe`.

This project was inspired by OpenAI's recently released [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/). It showed that non-intrusive CUA can be built on top of macOS Accessibility, which is why I decided to build an open-source version.

I bootstrapped this repo with my earlier [harness template](https://github.com/iFurySt/harness-template). It is a template for spinning up an AI-oriented repository quickly, especially for projects that are close to 100% AI-generated. This has been one of our most useful workflows over the past month, and it now lets us ship new ideas very quickly. If you are interested, I also wrote [a post](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/) about the methodology behind it.

## Quick Start

The npm package currently ships the macOS app bundle. Install it globally first:

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
# Install into Gemini CLI for the current project by writing to ./.gemini/settings.json
open-computer-use install-gemini-mcp
# Install into Gemini CLI user config instead
open-computer-use install-gemini-mcp --scope user
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
# Install into opencode by writing to ~/.config/opencode/opencode.json (or the active config file)
open-computer-use install-opencode-mcp
# Install as a Codex plugin, mainly for Codex App usage; if you use this, you usually do not need install-codex-mcp as well
open-computer-use install-codex-plugin
# Start the MCP server directly
open-computer-use mcp
# Call a single Computer Use tool and print the MCP-style JSON result
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
# Run a sequence in one process so element_index state can be reused
# Sequence runs sleep 1s between successful operations by default
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5
# Check permissions; onboarding only opens when something is missing
open-computer-use doctor
# Show help
open-computer-use -h
```

## Windows Runtime

The Windows runtime is intentionally separate from the macOS Swift `.app`. It is built from `apps/OpenComputerUseWindows` and uses Windows UI Automation first, then Win32 window messages for fallback input.

```bash
# Build a Windows arm64 executable from this repo
./scripts/build-open-computer-use-windows.sh --arch arm64

# On Windows, run it directly
open-computer-use.exe mcp
open-computer-use.exe call list_apps
open-computer-use.exe call --calls "[{\"tool\":\"get_app_state\",\"args\":{\"app\":\"notepad\"}},{\"tool\":\"type_text\",\"args\":{\"app\":\"notepad\",\"text\":\"hello\"}}]"
```

Run the `.exe` in the signed-in desktop session. Running it as a Windows service or a detached SSH-only process may not expose top-level UI Automation windows.

By default, the Windows runtime only attaches to already running apps, does not call `SetFocus`, and avoids the UIA `ValuePattern.SetValue` fallback for `type_text` because some apps bring themselves forward from that path. If you explicitly want the old foreground behavior, set `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` to allow app launch fallback, `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1` to allow the `SetFocus` secondary action, and `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1` to allow UIA text fallback.

## Cursor Motion

Cursor Motion is an open-source cursor motion system for macOS, based on public information shared by members of the Software.Inc team. You can run it from source or download the app from the [Releases page](https://github.com/iFurySt/open-codex-computer-use/releases).

```bash
swift run CursorMotion
```

[![Cursor Motion custom demo cover](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## Star History

<a href="https://www.star-history.com/?repos=iFurySt%2Fopen-codex-computer-use&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
    <img alt="Star History Chart for open-computer-use" src="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
  </picture>
</a>

## License

[MIT](./LICENSE)
