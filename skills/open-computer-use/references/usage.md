# Open Computer Use Usage

Read this reference when the task requires direct Computer Use tool calls, MCP configuration, or platform-specific behavior.

## MCP Server

For MCP clients that support stdio servers:

```toml
[mcp_servers.open_computer_use]
command = "open-computer-use"
args = ["mcp"]
```

Supported npm packages also expose `ocu` as a short alias, so `ocu mcp` is equivalent when available.

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
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call set_value --args '{"app":"TextEdit","element_index":"1","value":"Draft"}'
```

Use `--calls` for short action sequences that need to reuse the same process state:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"click","args":{"app":"TextEdit","element_index":"1"}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"Hello"}}
]'
```

Use `--calls-file` when the sequence is too large for a readable shell command:

```sh
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5
```

## Text Limits

Snapshot text is truncated to 500 characters by default and ends with `...` when truncation happens. This keeps normal UI state compact for agent planning and element-targeted actions.

Use a larger text limit when the task depends on longer semantic text, such as chat histories, email bodies, document text, or long form content. Use `max` only when complete text is required:

```sh
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":1000}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":"max"}'
open-computer-use snapshot --text-limit 1000 TextEdit
open-computer-use snapshot --text-limit max TextEdit
```

The same `text_limit` tool argument and `--text-limit` snapshot flag apply on macOS, Linux, and Windows. `text_limit` accepts a positive integer or the string `"max"`.

Action tools return refreshed app state with the default 500 character text limit. If longer text is still needed after an action, run `get_app_state` again with `text_limit: 1000` or `text_limit: "max"`.

## Larger Tree Budgets

Accessibility tree rendering defaults to 1200 nodes and 64 levels on macOS, Linux, and Windows. This keeps normal snapshots bounded while preserving most interactive UI.

Use a larger tree budget when a visible long page, list, table, or web app appears incomplete even after scrolling:

```sh
open-computer-use call get_app_state --args '{"app":"Google Chrome","max_tree_nodes":3000,"max_tree_depth":96}'
open-computer-use snapshot --max-tree-nodes 3000 --max-tree-depth 96 "Google Chrome"
```

`max_tree_nodes` and `max_tree_depth` must be positive integers. They only affect explicit `get_app_state` and `snapshot` calls; action tools still return refreshed state with the default tree budget.

## Choosing Targets

- Prefer app names or bundle identifiers returned by `list_apps`.
- Run `get_app_state` immediately before element-targeted actions.
- Re-run `get_app_state` after navigation, modal changes, page reloads, or failed actions.
- Use coordinate actions only when the rendered tree does not expose the target as an element.

## Choosing a Click Method

`click_method` is optional. Omitting it uses `auto`, which preserves the platform's existing semantic-first behavior. Explicit methods never fall back to a different implementation:

- `accessibility`: only invoke the element's accessibility action and require `element_index`.
- `app_post`: bypass accessibility and post a mouse event directly to the target app/window without moving the system pointer. Supported on macOS and Windows.
- `sky_click`: use the macOS private SkyLight background-window path with target-only synthetic focus and a Chromium primer click. It supports left single/double click on a current, on-screen window in the same Space and does not move the system pointer, deactivate the foreground app, change its key/first-responder state, or raise the target window. Its action-result snapshot refresh is read-only. Supported on macOS only.
- `global`: bypass accessibility and use the desktop's global pointer path. Supported on macOS and Linux, and requires `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` because it may move the real pointer or change foreground focus.

Use `app_post` for an exact blank-area or overlay click that must not be redirected to an accessibility descendant:

```sh
open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"app_post"}'
```

Use `sky_click` when Chromium ignores `app_post` and the current target window is covered by another window:

```sh
open-computer-use call get_app_state --args '{"app":"Google Chrome"}'
open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"sky_click"}'
```

Run `get_app_state` again after the target window moves, closes, changes Space, becomes hidden, or is minimized. `sky_click` is an explicit private-SPI mode: unavailable symbols, a stale window id, unsupported button/count, or failed delivery return an error without falling back to another click implementation.

Use `global` only after explicitly enabling the process-level safety gate:

```sh
OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"global"}'
```

Keep the environment override scoped as narrowly as possible. While it remains enabled, the existing `auto` route may also choose the global pointer path after accessibility cannot handle a click.

Windows returns an unsupported error for `sky_click` and `global`; Linux returns an unsupported error for `app_post` and `sky_click`. An unsupported or failed explicit method does not fall back to `auto`.

## Platform Notes

### macOS

The macOS runtime uses Accessibility, ScreenCaptureKit, app-posted input events, and an explicit private-SkyLight `sky_click` route. It normally avoids moving the user's real pointer. The visual cursor overlay is part of the Open Computer Use experience and can be disabled by the surrounding runtime only when needed. Private SkyLight symbols and raw event fields are not API-stable; re-validate `sky_click` after macOS upgrades.

### Windows

The Windows runtime uses UI Automation and Win32 message fallbacks. It must run in a logged-in desktop session. A detached SSH or service context may start the CLI but fail to see top-level windows.

### Linux

The Linux runtime uses AT-SPI2 through the desktop session bus. It must run in a logged-in graphical session with usable accessibility services. Wayland screenshot and coordinate input support is compositor-dependent and best-effort.

## Safety

Pause and ask the user before actions that affect external systems or sensitive local state, including sending messages, submitting forms, deleting files, approving prompts, uploading files, or interacting with password managers.
