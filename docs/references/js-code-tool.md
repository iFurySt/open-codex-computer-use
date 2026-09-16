# The `js` code tool

`js` exposes the Computer Use actions as a synchronous JavaScript API so a model
composes a whole flow (snapshot, find an element, act, verify, loop, retry) in
one tool call instead of one call per action. It reduces round trips and lets the
model branch on accessibility state locally. It complements the discrete tools;
it does not replace them.

## Runtime

- **Engine:** JavaScriptCore, hosted in-process in the MCP server. macOS only.
  On a build without JavaScriptCore the tool returns a stable unsupported error.
- **Synchronous by design:** every action runs in-process, so there are no
  promises and no top-level await. `cua.click(...)` returns when the action has
  run.
- **Scope and persistence:** each `js` call runs in its own function scope, so
  `let`/`const` never collide across calls. Assign to `globalThis` for a value
  that must survive to the next call; `js_reset` clears all `globalThis` bindings
  and re-initializes the API.
- **Output:** `write(value)` appends to the result text (objects are
  JSON-stringified); `console.log(...)` does the same with a trailing newline.
  `emitImage(base64)` attaches an image to the result. Return values are not
  auto-printed; use `write`.
- **Timeout:** `timeout_ms` bounds execution (default 30000 ms). A runaway script
  is terminated. The limit is enforced through JavaScriptCore's execution
  time-limit function, which the framework exports but declares only in a private
  header; the shim `OpenComputerUseJavaScriptShim` restates the prototype.

## The `cua` API

Every method throws on a tool error (catch it with try/catch). Methods return the
tool's text; `cua.call` returns the full `{text, images}`.

```
cua.listApps()
cua.getAppState(app, opts?)                       // accessibility tree text
cua.click(app, {element_index?, x?, y?, click_method?})
cua.type(app, text, {key_method?})
cua.pressKey(app, key, {key_method?})
cua.scroll(app, direction, element_index, pages?)
cua.drag(app, from_x, from_y, to_x, to_y)
cua.setValue(app, element_index, value)
cua.secondaryAction(app, element_index, action)
cua.screenshot(app, opts?)                        // returns tree text, emits the screenshot
cua.call(tool, args)                              // low-level: {text, images}
```

## Example

```
const tree = cua.getAppState("Notes");
write(tree);
cua.type("Notes", "Composed in one round trip");
```

## Safety

The runtime binds only the Computer Use actions; JavaScriptCore exposes nothing
else (no filesystem, no network). `cua.call` refuses `js` and `js_reset`, so a
script cannot re-enter the runtime. The actions it can drive are the same ones
the discrete tools expose.
