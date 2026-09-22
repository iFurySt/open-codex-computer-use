# JavaScript REPL Computer Use

Open Computer Use ships a Node.js adapter for hosts that want a code-first
Computer Use surface. The adapter exposes two model-facing MCP tools, `js` and
`js_reset`, and keeps the existing native 9-tool MCP server behind it.

## Why this shape

A UI flow usually needs several ordered operations: inspect, act, inspect again,
branch, retry, and verify. Discrete model-facing tool calls pay one model round
trip per operation and repeatedly serialize intermediate state. JavaScript makes
the sequencing local: deterministic actions and the final state read can happen
in one `js` call.

The design follows the current official code-first workflow without copying its
proprietary packages. In the inspected official bundle, the host provides a
general `node_repl` and the Computer Use plugin tells the model to import
`@oai/sky`. Open Computer Use packages the equivalent orchestration boundary as
two plugin-local MCP tools because an arbitrary MCP host does not necessarily
provide that general REPL:

1. a persistent Node.js REPL owns top-level JavaScript bindings and top-level
   `await`;
2. an asynchronous app-bound `cua` API converts JavaScript calls into native MCP
   `tools/call` requests;
3. the existing Swift, Go, and Python-backed runtimes continue to own app
   discovery, screenshots, accessibility, and input;
4. a worker boundary lets the host terminate CPU-bound JavaScript on timeout and
   start a fresh kernel.

## API

```js
var app = await cua.getApp("TextEdit");
await app.click(12);
await app.typeText("Hello");
await app.getAXState();
```

`cua.getApp(...)` accepts the same app name or bundle identifier as the native
runtime and emits the initial accessibility state. The returned binding exposes:

```text
getAXState(options?)
getScreenshot(options?)
getAXStateAndScreenshot(options?)
click(elementIndexOrPoint, options?)
drag([fromX, fromY], [toX, toY])
pressKey(key)
scroll(elementIndex, direction, pages?)
setValue(elementIndex, value)
typeText(text)
performSecondaryAction(elementIndex, action)
```

Discovery is available through `await cua.getState()` and
`await cua.listApps()`. `listApps()` normalizes the native human-readable app
catalog into an array of `{ id, displayName, lastUsedDate?, useCount?,
isRunning? }` objects, while `getState()` returns `{ apps }`. Observation
methods emit their result by default; pass
`{ emit: false }` when code needs the value but the model does not need to see
it. Use `nodeRepl.write(value)` for extra text and
`await nodeRepl.emitImage(image)` for extra images.

Top-level bindings persist across calls. Prefer `var` for reusable names, or use
`js_reset` when the session really needs a fresh lexical scope. Resetting the
REPL does not close applications or erase their UI state.

## Entrypoints

- The Codex plugin manifest uses the REPL launcher by default, so its advertised
  model-facing surface is `js` plus `js_reset`.
- `open-computer-use mcp` remains the native 9-tool compatibility surface for
  other MCP clients.
- The npm CLI also exposes the same runtime directly:

```sh
# One evaluation, then close the Worker and native MCP child.
ocu js 'var apps = await cua.listApps({ emit: false }); nodeRepl.write(apps)'

# Read one evaluation from stdin or a file.
printf '%s' 'nodeRepl.write(6 * 7)' | ocu js -
ocu js --file ./automation.mjs

# Keep bindings for multiple terminal inputs.
ocu repl
```

`ocu js` also accepts `--timeout <milliseconds>` and `--json`. The interactive
REPL supports `.help`, `.editor` / `.end`, `.reset`, and `.exit`; when stdin is
piped, each non-empty line is evaluated in the same persistent session. Use
`nodeRepl.write(value)` for explicit output.

Use `ocu capabilities` for a human-readable preflight or
`ocu capabilities --json` for a stable structured report. The commands remain
visible in `ocu --help` even if the adapter, kernel, or native runtime is
missing; the report marks them unavailable and execution fails with the missing
component and path.

The npm entrypoint itself currently has a `#!/usr/bin/env node` shebang. Once
the launcher is running, `js` and `repl` reuse `process.execPath` and do not
look up a second `node` on PATH. A shell with no Node executable cannot start
the npm command at all; supporting that case requires a future native bootstrap
or bundled Node distribution, not dynamic command hiding.
- The adapter can be run directly for development:

```sh
node scripts/node-repl/open-computer-use-repl.mjs -- \
  ./dist/Open\ Computer\ Use.app/Contents/MacOS/OpenComputerUse mcp
```

## Security boundary

`js` is local Node.js code execution, not a constrained expression language. It
can access the local filesystem, environment, modules, and network with the
permissions of the launching process. Only enable the REPL surface for a host
whose model-code execution policy you trust. The native Computer Use calls still
apply their own password-manager denylist and explicit global-pointer gate.

The native MCP compatibility surface remains available when arbitrary
JavaScript is not an acceptable host boundary.

## Process lifecycle

| Entry | Lifetime | Persistent state |
| --- | --- | --- |
| `ocu js` | One evaluation | A Worker and native MCP child exist only for that invocation. |
| `ocu repl` | Current terminal session | JavaScript bindings and native snapshot state persist until `.reset`, `.exit`, Ctrl-D, or termination. |
| `ocu mcp` | Current stdio MCP connection | Native MCP state persists until stdin EOF or host termination. |
| Codex plugin adapter | Current plugin MCP connection | `js` bindings persist across tool calls until `js_reset` or connection shutdown. |

On macOS, these short-lived CLI layers proxy automation to the hidden
`Open Computer Use.app` permission agent. That app agent may remain resident so
future calls reuse the same permission identity; it is separate from the Node
Worker and native MCP child owned by `js` / `repl`.
