# Open Computer Use Installation

Read this reference when the user asks to install, verify, repair, or explain Open Computer Use setup.

## Platform Requirements

The macOS runtime requires macOS 14.0 or later. Windows and Linux use their own platform runtimes and are not subject to this macOS minimum.

On macOS, verify the system version before attempting to run the CLI:

```sh
sw_vers -productVersion
```

On macOS versions earlier than 14.0, npm installation may succeed but the bundled binary cannot launch. `open-computer-use doctor` and changes to Accessibility or Screen Recording permissions cannot fix this binary incompatibility.

## Install The CLI

Use npm:

```sh
npm install -g open-computer-use
```

Verify:

```sh
open-computer-use -h
ocu -h
open-computer-use call list_apps
```

Supported npm packages expose `ocu` as the short alias. If it is unavailable, use `open-computer-use`.

If the package is already installed and the user asks to update it:

```sh
npm update -g open-computer-use
```

## macOS Permissions

On supported macOS versions, Accessibility and Screen Recording permissions are required before real app state and actions can work.

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
ocu install-codex-mcp
open-computer-use install-claude-mcp
open-computer-use install-gemini-mcp
open-computer-use install-gemini-mcp --scope user
open-computer-use install-opencode-mcp
```

Codex App can also use the plugin installer:

```sh
open-computer-use install-codex-plugin
```

Install into DeepSeek Harness (DSH):

```sh
open-computer-use install-dsh-mcp
ocu install-dsh-mcp

# from a source checkout
./scripts/install-dsh-mcp.sh
```

DSH profiles are composed from patch layers, so the installer writes a delimited
block into `<dsh-home>/profiles/<profile>/cordis.patch.yml` (default profile
`web`, default home `~/.dsh`). The block is replaced in place on every run, so
re-running is idempotent and the rest of the file is untouched. Before writing,
the installer performs an MCP `initialize` plus `tools/list` exchange and
requires the Open Computer Use server identity and a non-empty, valid tool
catalog. It deliberately does not pin a tool count, so compatible OCU releases
can add or reshape tools. An unrelated or broken executable therefore fails
without changing the profile.

This is a compatibility integration through DSH's generic MCP client. It does
not register a first-class DSH computer-use provider or reserve DSH's exclusive
computer-use provider slot. Do not enable another desktop provider in the same
profile unless you deliberately want both independent tool sets to operate the
same desktop.

It also installs two things a DSH host needs beyond the MCP entry:

- **The turn-boundary hook.** Open Computer Use hides its software cursor only at
  a turn boundary, signalled by the MCP `notifications/turn-ended` notification.
  `dsh-mcp-client` never sends that notification, so without the hook the cursor
  stays on screen after the first action of any session or subagent. The
  installer writes `<dsh-home>/ocu-hooks.json` and maps DSH's Stop point onto
  `open-computer-use turn-ended`. Pass `--no-hook` to skip both.
- **Editing the hook later.** DSH's live patch reload only re-applies a row whose
  configuration actually changed, so editing `ocu-hooks.json` on its own leaves
  the running plugin holding its previous command. Change the patch row too (for
  example `defaultTimeoutMs`) to force a re-apply, or restart DSH.
- **The skill.** Copied to `<dsh-home>/skills/open-computer-use`, which DSH scans
  as a user-level skill root, so every new conversation can see it. Pass
  `--no-skill` to skip. An existing skill directory is never overwritten
  silently: when it differs from this checkout the installer leaves it in place
  and says so, and `--force-skill` replaces it while keeping a timestamped
  backup.

Options: `--profile <name>`, `--dsh-home <dir>`, `--command <path>`, `--no-hook`,
`--no-skill`, `--force-skill`. `--command` must be an absolute executable path.
DSH can resolve a bare PATH command, but an absolute path remains stable when a
GUI or background launch receives a different PATH. When the option is omitted,
the installer resolves the current PATH shim and common app/npm locations to an
absolute path, then fails with guidance if it finds nothing. Explicit DSH
installation treats MCP startup failure as a profile activation error rather
than silently starting without the requested tools.

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
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
```

If this fails, read [troubleshooting.md](troubleshooting.md).
