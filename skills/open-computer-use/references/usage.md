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
select_text   (macOS runtime only)
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

### Stable selectors

`element_index` only describes the snapshot it came from: every action re-renders the tree and
the indices move. When a target has a stable name, pass `selector` to `click` or `set_value`
instead of reading the tree again:

```sh
open-computer-use call set_value --args '{"app":"Google Chrome","selector":"textbox[name=用途]","value":"draft"}'
open-computer-use call click --args '{"app":"Google Chrome","selector":"button[name=检查变更]"}'
```

Accepted forms: `role[name=NAME]`, `[name=NAME]`, `[role=ROLE][name=NAME]` or a bare `NAME`.
Role aliases (`button`, `textfield`, `textbox`, `combobox`, `text`, `link`, `listbox`,
`checkbox`, …), exact AX roles and the localized role text shown in the tree all match. The name
is matched against the element title, description, value, identifier and placeholder: exact
matches win, a unique prefix match is accepted, and two unrelated matches fail closed with the
candidate list instead of guessing. `selector` cannot be combined with `element_index`.

A fail-closed message is authoritative, not a transient glitch: if the candidates it lists are all
popup items while your target lives behind an open overlay, the background is hidden from the
accessibility tree and no retry will find it. Finish the overlay interaction first (verified against
Chromium + Radix: a background heading stays unresolvable until the popup closes).

### Popups and overlays

`get_app_state` renders the focused window and, when the app has opened an overlay that lives in
its own subtree (native popover, sheet, menu, floating/dialog window), appends it after a
`--- popup ---` marker. One read then covers both the window content and the popup options; a
snapshot without an open popup is unchanged.

A trailing `--- popup note ---` means something different: the app itself is hiding the content
behind the popup from the accessibility tree (Chromium does this for the document around an open
Radix/ARIA popup), so the background `element_index` values are temporarily unavailable. Finish
the popup interaction (choose an option, or press Escape) and then act on the content behind it
with `selector` — repeatedly re-reading the tree will not bring it back.

The two markers are independent, and both may be absent while an overlay is open: a Chromium
listbox whose options are reachable inside the web area renders as the web area's only child, so the
options are complete (selected item included) even though every background field is gone. Treat
"options present" as the success signal for this shape; a missing `--- popup ---`/`note` does not
mean the read failed.

### Pre-flight: the target window must be on an active display

Reading and acting are geometry-dependent even on pure accessibility paths:

- A window parked at coordinates no current display covers (a window plan that remembered a second
  monitor which has since been rearranged, or a harness log line like `readback differs, not retried`)
  gets an incomplete tree: the browser chrome still renders while the web area (`HTML 内容`) is
  simply absent. Fixing the window position is the fix; retrying the action is not.
- The software cursor is drawn at the mapped target point. It is ON by default (set
  `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` to disable) and the screen mapping returns the raw point when it
  falls inside no screen, so an off-display window makes the cursor appear on an unrelated screen.
  Treat a cursor on the wrong screen as a geometry warning, not a rendering quirk.
- The physical pointer does NOT move unless the process sets
  `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`; the default accessibility/app-post paths leave
  the user's cursor where it is.

Order of operations before the first action: check geometry, move the window onto an active display,
then require the target subtree in a fresh `get_app_state`.

```sh
# 1. where is the window, and does any active display cover it?
osascript -e 'tell application "System Events" to tell process "Google Chrome" to get {position, size} of window 1'

# 2. if it is outside every screen, move it onto one
osascript -e 'tell application "Google Chrome" to set bounds of front window to {120, 120, 1350, 940}'

# 3. only then read, and require the target subtree (for a page: `HTML 内容`) to be present
```

A snapshot that exposes only chrome (toolbar, tabs) is a geometry/frontmost signal, not a snapshot to
act on.

When the window really does lie outside every active display, `get_app_state` now says so itself with a
trailing `--- display note --- window is off all active displays …` line, and coordinate/cursor helpers
skip drawing points they cannot map. Note that macOS (and Chromium) clamp window moves so a window
cannot be parked off every screen by dragging: the state arises from a display being removed, asleep
or rearranged while the window keeps its old coordinates, which is exactly how the harness window plan
went stale. A window on a secondary display is still "on a display" and must not produce the note.

A window dragged to another display *while the cursor is travelling* aborts that travel: the cursor is
re-placed on the window's live frame instead of finishing the path towards the screen the window just
left. The `settle` and click pulse that follow the travel re-derive their point from the same live frame,
so the cursor is not put back on the old display afterwards. Both use the window's accessibility element
for that frame, because `CGWindowListCopyWindowInfo` can keep reporting the pre-move frame for about a
second (measured: 83 identical travel frames). Reading no frame at all (window minimized, hidden, or moved to another Space) is not a change, so
the accessibility action paths keep working.

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

## Drag Delivery

`drag` has no method parameter. On macOS the path it takes is decided by the same process-level gate that authorizes `click_method: "global"`:

- Gate unset (default): mouse move / down / dragged / up events are posted directly to the target process with `CGEvent.postToPid`. The system pointer does not move and foreground focus is unchanged. Because the events never pass through the window server, this path cannot start a window-server drag session: window moves, drag-selecting text, and Finder drag-and-drop return without error but have no visible effect.
- `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` set for the server process: the drag uses the global pointer path, which drives window-server drag sessions but may move the real pointer and change foreground focus.

Every non-fixture `drag` result includes a text item that begins `Drag delivered via app_post` or `Drag delivered via global pointer path`, so a default drag that did nothing is legible instead of looking like success. For an MCP server the variable belongs in the server entry's `env`, not in the calling shell, and the server must be restarted afterwards.

When the gate is not enabled, treat window-server drags as unavailable and reach the same outcome another way: copy or move files with a shell command instead of a Finder drag, use `set_value` or keyboard selection instead of drag-selecting text, and use the app's own window controls instead of dragging a title bar.

## Platform Notes

### macOS

The macOS runtime uses Accessibility, ScreenCaptureKit, app-posted input events, and an explicit private-SkyLight `sky_click` route. It normally avoids moving the user's real pointer. The visual cursor overlay is part of the Open Computer Use experience and can be disabled by the surrounding runtime only when needed. Private SkyLight symbols and raw event fields are not API-stable; re-validate `sky_click` after macOS upgrades.

### Windows

The Windows runtime uses UI Automation and Win32 message fallbacks. It must run in a logged-in desktop session. A detached SSH or service context may start the CLI but fail to see top-level windows.

### Linux

The Linux runtime uses AT-SPI2 through the desktop session bus. It must run in a logged-in graphical session with usable accessibility services. Wayland screenshot and coordinate input support is compositor-dependent and best-effort.

## Safety

Pause and ask the user before actions that affect external systems or sensitive local state, including sending messages, submitting forms, deleting files, approving prompts, uploading files, or interacting with password managers.
