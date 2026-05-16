# Open Computer Use Usage

Read this reference when the task requires direct Computer Use tool calls, MCP configuration, or platform-specific behavior.

## MCP Server

For MCP clients that support stdio servers:

```toml
[mcp_servers.open_computer_use]
command = "open-computer-use"
args = ["mcp"]
```

Equivalent JSON shape:

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

The MCP server exposes:

```text
list_apps
get_app_state
click
perform_secondary_action
scroll
drag
type_text
press_key
set_value
```

## Direct CLI Tool Calls

Use `call` for one-off checks:

```sh
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call set_value --args '{"app":"TextEdit","element_index":1,"value":"Draft"}'
```

Use `--calls` for short action sequences that need to reuse the same process state:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"click","args":{"app":"TextEdit","element_index":1}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"Hello"}}
]'
```

Use `--calls-file` when the sequence is too large for a readable shell command:

```sh
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5
```

## Choosing Targets

- Prefer app names or bundle identifiers returned by `list_apps`.
- Run `get_app_state` immediately before element-targeted actions.
- Re-run `get_app_state` after navigation, modal changes, page reloads, or failed actions.
- Use coordinate actions only when the rendered tree does not expose the target as an element.

## Platform Notes

### macOS

The macOS runtime uses Accessibility, ScreenCaptureKit, and targeted input events. It normally avoids moving the user's real pointer. The visual cursor overlay is part of the Open Computer Use experience and can be disabled by the surrounding runtime only when needed.

### Windows

The Windows runtime uses UI Automation and Win32 message fallbacks. It must run in a logged-in desktop session. A detached SSH or service context may start the CLI but fail to see top-level windows.

### Linux

The Linux runtime uses AT-SPI2 through the desktop session bus. It must run in a logged-in graphical session with usable accessibility services. Wayland screenshot and coordinate input support is compositor-dependent and best-effort.

## Safety

Pause and ask the user before actions that affect external systems or sensitive local state, including sending messages, submitting forms, deleting files, approving prompts, uploading files, or interacting with password managers.
