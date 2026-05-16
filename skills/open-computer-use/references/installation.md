# Open Computer Use Installation

Read this reference when the user asks to install, verify, repair, or explain Open Computer Use setup.

## Install The CLI

Use npm:

```sh
npm install -g open-computer-use
```

Verify:

```sh
open-computer-use -h
open-computer-use call list_apps
```

If the package is already installed and the user asks to update it:

```sh
npm update -g open-computer-use
```

## macOS Permissions

macOS needs Accessibility and Screen Recording permissions before real app state and actions can work.

Run:

```sh
open-computer-use doctor
```

If permissions are missing, the onboarding UI opens. Ask the user to grant the requested permissions in System Settings. Do not try to bypass TCC prompts or silently manipulate protected settings.

Windows and Linux do not use this macOS onboarding step, but they still need a logged-in desktop session.

## Install Into Agent MCP Configs

Use the built-in installers when they match the user's agent:

```sh
open-computer-use install-codex-mcp
open-computer-use install-claude-mcp
open-computer-use install-gemini-mcp
open-computer-use install-gemini-mcp --scope user
open-computer-use install-opencode-mcp
```

Codex App can also use the plugin installer:

```sh
open-computer-use install-codex-plugin
```

For any other MCP client, add a stdio server manually:

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

## Install This Skill

Install the skill for Codex:

```sh
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y
npx skills ls -g -a codex | rg 'open-computer-use'
```

Install the skill for Claude Code:

```sh
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use -y
```

Update an existing global skill install:

```sh
npx skills update open-computer-use -g -y
npx skills upgrade open-computer-use -g -y
```

## Verification

After CLI and MCP setup:

```sh
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
```

If this fails, read [troubleshooting.md](troubleshooting.md).
