# computer-use-cli

Small Go CLI for probing Codex desktop-control tooling.

This directory is intended to be run from `scripts/computer-use-cli/` inside the repo:

```bash
cd scripts/computer-use-cli
go run . list-tools
go run . call list_apps
go run . call-seq --calls-file /tmp/calls.json
```

It supports two transports:

- `direct`: talk to a stdio MCP server directly with the official Go MCP SDK transport layer.
- `app-server`: talk to `codex app-server`, create an ephemeral thread, then proxy `mcpServer/tool/call` through the signed Codex host.

`auto` is the default:

- for the official bundled proprietary `computer-use`, it uses `app-server`
- for explicitly provided non-Sky binaries such as `open-computer-use`, it uses `direct`

## Commands

```bash
go run . resolve-server
go run . list-tools
go run . call list_apps
go run . call get_app_state --args '{"app":"Feishu"}'
go run . call-seq --calls-file /tmp/calls.json
```

Explicit transport examples:

```bash
go run . list-tools --transport app-server
go run . call list_apps --transport app-server
go run . call list_apps --transport direct --server-bin /path/to/open-computer-use
go run . call-seq --transport app-server --calls-file /tmp/calls.json
```

Flags can appear either before or after the tool name for `call`:

```bash
go run . call --server-bin /path/to/server list_apps
go run . call list_apps --server-bin /path/to/server
```

`call` creates a fresh ephemeral app-server thread per invocation. If you need `get_app_state`
followed by one or more action tools in the same official `computer-use` session, use
`call-seq` with a JSON array:

```json
[
  {"tool": "get_app_state", "args": {"app": "TextEdit"}},
  {"tool": "set_value", "args": {"app": "TextEdit", "element_index": "2", "value": "cursor probe 01\ncursor probe 02"}},
  {"tool": "scroll", "args": {"app": "TextEdit", "element_index": "1", "direction": "down", "pages": 1}}
]
```

This repo includes a ready-to-run example at
`examples/textedit-overlay-seq.json`.
That sample covers all 9 official tools against `TextEdit`, and it intentionally
repeats `get_app_state` between state-changing actions because the official
bundled `computer-use` invalidates the cached app state after each mutation.
Before running it, make sure `TextEdit` already has a normal document window open;
otherwise `get_app_state` may only expose the application root and the hard-coded
`element_index` values in the sample will no longer line up.

For a smaller cursor-comparison path, use
`examples/textedit-set-value-click-raise-seq.json`.
That sample stays on the `set_value -> click -> Raise` flow so the same calls file
can be pointed at both the official bundled `computer-use` and the local
`open-computer-use` binary.

## Default target

By default, the CLI auto-discovers the official bundled `computer-use` plugin under:

```text
~/.codex/plugins/cache/openai-bundled/computer-use/<version>
```

You can override that with:

```bash
COMPUTER_USE_PLUGIN_ROOT=/path/to/plugin-root
COMPUTER_USE_SERVER_BIN=/path/to/server-binary
```

or the equivalent flags:

```bash
--plugin-root /path/to/plugin-root
--server-bin /path/to/server-binary
```

For app-server mode, you can also override the Codex host binary:

```bash
CODEX_APP_SERVER_BIN=/Applications/Codex.app/Contents/Resources/codex
go run . call list_apps --transport app-server
```

## Verified behavior in this workspace

- Direct mode successfully connects to the local `open-computer-use` stdio server and can both `list-tools` and `call list_apps`.
- Direct mode against the official bundled proprietary `computer-use` exits during initialization when launched outside Codex.
- That same failure reproduces with the official Go SDK example client `examples/client/listfeatures`, so the issue is not specific to this CLI.
- App-server mode successfully calls the official bundled `computer-use` tools through the signed Codex host. `list_apps` works in this workspace.

Example working invocation against `open-computer-use`:

```bash
go run . list-tools \
  --transport direct \
  --server-bin ~/.codex/plugins/cache/open-computer-use-local/open-computer-use/0.1.22/scripts/launch-open-computer-use.sh
```

Example working comparison flow against a local repo build:

```bash
swift build --product OpenComputerUse
cd scripts/computer-use-cli
go run . call-seq \
  --transport direct \
  --plugin-root ../.. \
  --server-bin ../../.build/debug/OpenComputerUse \
  --calls-file examples/textedit-set-value-click-raise-seq.json
```

Example working invocation against the official bundled `computer-use`:

```bash
go run . call list_apps --transport app-server
go run . call-seq --transport app-server --calls-file /tmp/calls.json
```
