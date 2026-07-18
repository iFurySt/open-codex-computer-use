# open-computer-use

[![English](https://img.shields.io/badge/English-Click-yellow)](./README.md)
[![简体中文](https://img.shields.io/badge/简体中文-点击查看-orange)](./README.zh-CN.md)
[![Release](https://img.shields.io/github/v/release/iFurySt/open-codex-computer-use)](https://github.com/iFurySt/open-codex-computer-use/releases)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/iFurySt/open-codex-computer-use)
<a href="https://llmapis.com?source=https%3A%2F%2Fgithub.com%2FiFurySt%2Fopen-codex-computer-use" target="_blank"><img src="https://llmapis.com/api/badge/iFurySt/open-codex-computer-use" alt="LLMAPIS" width="20" /></a>

> [!TIP]
> Interested in Browser Use? Check out [open-browser-use](https://github.com/iFurySt/open-codex-browser-use).

---

`open-computer-use` is an open-source `Computer Use` service wrapped as `MCP`. Any AI agent or MCP client can use it to run Computer Use on macOS, Linux, and Windows.

This project was inspired by OpenAI's [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/). It showed that non-intrusive CUA can be built on top of Accessibility, so I decided to build an open-source version.

I started this repo with my [harness template](https://github.com/iFurySt/harness-template), a template for quickly spinning up AI-first projects. It has been one of our most useful workflows lately, especially for nearly 100% AI-generated projects. I also wrote [a post](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/) about the methodology behind it.

## Demos

### Codex App and Codex CLI

[![Open Computer Use custom demo cover](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

<sub><em>`open-computer-use` used as Computer Use in Codex App and Codex CLI, matching the official experience.</em></sub>

### Gemini CLI

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI connects to `open-computer-use` through MCP and runs full Computer Use actions.</em></sub>

### Linux

https://github.com/user-attachments/assets/e036b1c8-2200-4896-abd4-19225915cf66

<sub><em>`open-computer-use` running on Linux.</em></sub>

## Limitations

**Lock Screen:** By default, Computer Use is blocked while macOS is locked (fail-closed). `CGSessionCopyCurrentDictionary` is unavailable to unprivileged processes when the session is locked; any lock-state evidence that is absent, nil, or unparseable is treated as locked. For fully attended, screenshot-driven automation, unlock the Mac or use a dedicated logged-in desktop session.

For unattended agents (Claude Code, Codex) that must keep working while the screen is locked, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` to opt into **best-effort** control while locked. This works because every action tool delivers input process-targeted — accessibility actions (`AXUIElementPerformAction` / `AXUIElementSetAttributeValue`) or `CGEvent.postToPid`, never the global HID event tap — which keeps functioning while the login window owns the screen. Under this opt-in an agent can still read the accessibility tree via `get_app_state` and drive an accessibility-controllable app with element-targeted `click` / `type_text` / `scroll` / `set_value`. **Known limitations while locked:** window screenshots return blank (macOS blocks capture for security, so `get_app_state` yields the AX tree without an image) and coordinate-only paths that need a visible cursor are unreliable — prefer element-targeted (`element_index`) actions.

**Trust boundary (read before enabling):** the opt-in is off by default. When you run from the `.app` bundle, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` in the shell that first launches the agent — the policy is fixed for that agent's lifetime (quit it from the menu bar to change it) and is passed only through the trusted launch environment, not the per-call IPC channel, so another process cannot flip it against a running agent. The app-agent socket is peer-authenticated: on each connection the agent checks the caller's uid (`getpeereid`) and, whenever the agent binary carries a Team Identifier (any signed build, including Dev bundles auto-signed with an Apple Development certificate), requires the connecting process to be code-signed by the same developer (Team Identifier) — and, when the agent runs from a bundle, with the agent's own bundle identifier — via its audit token. This **raises the bar** — a foreign, unsigned, or other-developer binary can no longer connect and drive the agent. It does **not** make the agent safe on an untrusted machine: a process running as your user can still `exec` the legitimate, same-developer-signed CLI (it lives at a fixed path in the app bundle) and relay commands through it, so same-uid code you don't control can still reuse the agent's Accessibility grant — including while the screen is locked. Unsigned local `swift build` binaries fall back to same-uid trust only (a one-time stderr notice is printed). The release build script refuses to produce an ad-hoc-signed/unsigned release bundle unless `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` is set explicitly, so a distributed release cannot ship with peer authentication silently inactive. **For hostile or multi-tenant machines, use a dedicated logged-in session — do not rely on peer-auth or the locked opt-in as an isolation boundary.**

## Quick Start

```bash
npm i -g open-computer-use
```

The npm package also exposes `ocu` as the short CLI alias.

> [!IMPORTANT]
> The macOS runtime requires macOS 14.0 or later.

**On macOS, run it once and grant `Accessibility` and `Screen Recording`. Windows and Linux do not need this step.**

```bash
open-computer-use
# or
ocu
```

Before using it, install it into your agent:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
```

Or add it to your own client manually:

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

### Skill

Install the skill directly:

```bash
# Install for Codex
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y
npx skills ls -g -a codex | rg 'open-computer-use'
```

Install for Claude Code:

```bash
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use -y
```

Update an existing global install, including the Codex install created above:

```bash
npx skills update open-computer-use -g -y
```

You can also manually download and install the
[`open-computer-use` skill](./skills/open-computer-use).

## More

Besides the MCP JSON config above, you can also use the built-in commands:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
ocu install-codex-mcp

# Install as a Codex plugin, mainly for Codex App
open-computer-use install-codex-plugin

# Install into Claude Code by writing to ~/.claude.json
open-computer-use install-claude-mcp

# Install into Gemini CLI for the current project by writing to ./.gemini/settings.json
open-computer-use install-gemini-mcp

# Install into Gemini CLI user config instead
open-computer-use install-gemini-mcp --scope user

# Install into opencode by writing to ~/.config/opencode/opencode.json (or the active config file)
open-computer-use install-opencode-mcp

# Call a single Computer Use tool and print the MCP-style JSON result
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'

# Run a sequence in one process so element_index state can be reused
# Sequence runs sleep 1s between successful operations by default
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

# Check permissions; onboarding only opens when something is missing
open-computer-use doctor

# Run local validation from a source checkout
make smoke
OPEN_COMPUTER_USE_STRESS_LOOPS=20 make stress
make agent-smoke
make agent-smoke SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=claude,codex --command=open-computer-use
OPEN_COMPUTER_USE_HERMES_PROVIDER=anthropic OPEN_COMPUTER_USE_HERMES_MODEL=claude-opus-4-20250514 make agent-smoke AGENTS=hermes SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --hermes-max-turns=12

# Show help
open-computer-use -h
ocu -h
```

## Cursor Motion

Cursor Motion is an open-source cursor motion system for macOS, based on public information shared by members of the Software.Inc team. You can download the app from the [Releases page](https://github.com/iFurySt/open-codex-computer-use/releases).

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
