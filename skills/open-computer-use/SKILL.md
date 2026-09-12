---
name: open-computer-use
description: Platform-neutral guidance for using Open Computer Use, the open-source Computer Use MCP server and CLI for macOS, Linux, and Windows. Use when an agent needs to install, verify, troubleshoot, configure, or operate Open Computer Use through its native CLI, stdio MCP server, or direct Computer Use tool calls.
---

# Open Computer Use

## Overview

Open Computer Use exposes Computer Use as a local CLI and stdio MCP server. It is not Codex.app-specific; adapt the commands and MCP config to the agent runtime you are operating in.

The macOS runtime requires macOS 14.0 or later. Windows and Linux use their own platform runtimes and are not subject to this macOS minimum.

It supports the same core tool surface across macOS, Linux, and Windows:
`list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`,
`drag`, `type_text`, `press_key`, and `set_value`.

The macOS runtime additionally implements `select_text`, which selects the given text inside a text
element or places the text cursor before / after it (`selection`: `text`, `cursor_before`,
`cursor_after`). Pass `text` exactly as it appears in the accessibility tree, plus `prefix` /
`suffix` when it is not unique; an ambiguous target fails closed instead of silently selecting the
first match. Windows and Linux runtimes do not implement this tool yet.

## Core Workflow

1. On macOS, run `sw_vers -productVersion` before invoking the CLI and require macOS 14.0 or later. On older versions, explain that the runtime cannot launch; do not recommend `doctor` or permission changes as a fix for binary incompatibility.
2. Check the CLI is installed with `open-computer-use -h` or `ocu -h`. If installation or setup is missing, read [references/installation.md](references/installation.md).
3. On supported macOS versions, run `open-computer-use doctor` before the first real GUI task. If permissions are missing, ask the user to approve Accessibility and Screen Recording in the onboarding UI.
4. Inspect available apps before acting: `open-computer-use call list_apps`.
5. Capture current UI state with `open-computer-use call get_app_state --args '{"app":"TextEdit"}'`. The default state is usually enough for UI operation.
6. When the task needs longer semantic text, such as chat history, email bodies, document text, or long form content, call `get_app_state` with `text_limit: 1000` or `text_limit: "max"`.
7. When visible long pages or lists appear incomplete even after scrolling, call `get_app_state` with a larger `max_tree_nodes` or `max_tree_depth`.
8. Prefer element-targeted actions using `element_index` from the latest `get_app_state` result.
9. For multi-step CLI work, use `open-computer-use call --calls '<json-array>'` so one process can reuse the latest element index mapping.
10. For agent runtimes that support local MCP servers, configure `open-computer-use mcp` or `ocu mcp` and call the exposed Computer Use tools directly. Read [references/usage.md](references/usage.md).
11. If communication, permission, or desktop-session access fails, read [references/troubleshooting.md](references/troubleshooting.md).

## Operating Rules

- Treat the target desktop as the user's real session. Do not inspect password managers, unrelated private content, or sensitive apps unless the user explicitly asked for that task.
- Ask before sending, deleting, purchasing, approving, uploading, or making other externally visible changes.
- Do not assume Codex.app plugin helpers are available. Use the installed `open-computer-use` / `ocu` CLI or an explicit MCP config.
- Always run `get_app_state` before using `element_index`; do not guess indexes across sessions or after large UI changes.
- Prefer semantic actions and `set_value` for editable controls. Use coordinate `click`, `scroll`, and `drag` only when the element tree does not expose a safer target.
- On macOS, do not enable `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` unless the user explicitly requested `click_method: "global"`, a `drag` that must drive a window-server drag session (window move, drag-select text, Finder drag-and-drop), or other diagnostic behavior that may move the real pointer. Without it `drag` reports `Drag delivered via app_post` and those operations have no effect; see `references/usage.md` for alternatives. In the default `auto` click method, set `OPEN_COMPUTER_USE_AUTO_SKY_CLICK=1` to attempt one `sky_click` between the accessibility and `app_post` paths; a failed attempt falls back and it never escalates to `global`.
- The macOS runtime is quiet by default: it never unhides, activates, or raises the target app on its own, and it scrolls an out-of-view `element_index` into place before `click` / `set_value` / `select_text`. If a call returns `Apple event error -10005: cgWindowNotFound`, ask the user to move that window to the current Space or unminimize it. Only pass `allow_window_recovery: true` (or set `OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY=1` for the server process) when pulling the app to the foreground is acceptable; that same switch is the only way to enable the activation-only AX fallback (`AXRaise` / `AXMain` / `AXFocused`), which is off by default so a default `click` never raises, mains or focuses a window. Set `OPEN_COMPUTER_USE_SCROLL_TARGET_INTO_VIEW=0` to disable the automatic scroll-into-view. The macOS visual surface is exactly the official one: a software cursor with a fog halo, Bezier travel and a click pulse - there is no target highlight. It is on by default; set `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` (also `false`, `no`, or `off`) to turn it off. Cursor travel is debounced the same way: repeating an action on the element the cursor already covers only keeps the cursor in place, and actions inside a 400ms window are merged into one travel animation (`OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS`; set it to `0` to restore one animation per action). The overlay is idle-static: after the last action it keeps a bounded 1s micro-wobble and then freezes outright (no frame, level or stacking updates at all), tunable with `OPEN_COMPUTER_USE_VISUAL_CURSOR_IDLE_SWAY_MS` (default `1000` ms; `0` freezes immediately; `OPEN_COMPUTER_USE_VISUAL_CURSOR_DEBUG_STATS=1` dumps the write/tick counters when the cursor hides). The cursor stays on screen for the whole turn: it never hides on an inactivity timer, keeps a `.floating` panel level so another app taking focus cannot bury it, and only `turn-ended` / an explicit reset / `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` remove it. Cursor visibility is self-checkable without touching another app: `open-computer-use debug-cursor [--seconds N] [--display N]` paints the software cursor on one screen (1-based `--display`, default main screen; capped at 60s; always cleans up) and prints the screen-state rect for `screencapture -R`. The cursor also follows its window: the target window frame is re-read from the window server before every action, so a window dragged to another display re-anchors the cursor instead of leaving it on the screen it just left, and while the cursor is on screen a read-only accessibility watch on the target window (`AXWindowMoved` / `AXWindowResized`; `OPEN_COMPUTER_USE_WINDOW_MOVE_WATCH=0` disables it) re-places it as soon as a move or resize ends (measured: moving the target window to another display moved the overlay X from `-1453` to `256/259`, and back to `-1453` on return, with no further click in between).
- The macOS runtime's opt-in click and recovery paths are measured; keep their default off-state. `allow_window_recovery: true` unminimizes or unhides the target window at its previous frame and the click then succeeds, but it also activates that app: frontmost changes to it, which interrupts the user's foreground. An explicit `click_method: "sky_click"` is safe for in-page content buttons (no error, unchanged Chromium renderer PIDs, unchanged frontmost) but must not be used for app navigation or sidebar links, where it has repeatedly crashed the Chromium renderer with error code 5 (recover with a toolbar reload); navigation uses the default AXPress click. `click_method: "global"` (requires `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`) really moves the system pointer - measured from `(1392.56, 991.32)` on one display to `(-1050, 453.5)` on another, where it stayed - and changes frontmost; leave it disabled by default and validate it only in an isolated instance (separate agent socket namespace plus a separate agent, cleaned up immediately), never in a shared or production session.
- On Windows and Linux, confirm the command is running inside the logged-in desktop session before assuming GUI automation is available.

## Common CLI Actions

```sh
open-computer-use -h
ocu -h
open-computer-use doctor
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":1000}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":"max"}'
open-computer-use call get_app_state --args '{"app":"Google Chrome","max_tree_nodes":3000,"max_tree_depth":96}'
open-computer-use call click --args '{"app":"TextEdit","element_index":"0"}'
open-computer-use call type_text --args '{"app":"TextEdit","text":"Hello from Open Computer Use"}'
```

For a short sequence that reuses state in one process:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}
]'
```

## MCP Usage

For runtimes that can launch local MCP servers over stdio, use:

```toml
[mcp_servers.open_computer_use]
command = "open-computer-use"
args = ["mcp"]
```

Read [references/usage.md](references/usage.md) for JSON config examples, direct tool-call patterns, and platform notes.

## References

- [references/installation.md](references/installation.md): one-time CLI install, agent MCP install commands, and macOS permissions.
- [references/usage.md](references/usage.md): MCP config, direct CLI calls, sequencing, and platform behavior.
- [references/troubleshooting.md](references/troubleshooting.md): permission, desktop-session, app discovery, and action failures.
