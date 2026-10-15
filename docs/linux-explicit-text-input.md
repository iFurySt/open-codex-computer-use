# Add explicit Linux keyboard and X11 paste delivery

Draft: explicit delivery paths and protocol tests are ready for review; live desktop validation of selection replacement, Unicode delivery and clipboard-manager behavior is pending.

Keep `type_text` auto delivery as the existing AX-first/keyboard-fallback route. Add explicit `text_method: "keyboard"` and `text_method: "paste"` (REPL `textMethod`). Both require the requested app window to be active and never activate another window. Explicit paste uses the X11 clipboard and Ctrl+V; `paste_key` / `pasteKey` supports terminal Ctrl+Shift+V. Failures never silently fall back to another text target or method. `set_value` remains the route for replacing an explicitly observed editable element's complete value.

Literal `type_text` and `set_value` payloads retain leading/trailing whitespace, newlines, tabs and Unicode at the Go/bridge boundary; routing names/indexes continue to be normalized. The default keyboard path is not claimed to handle all Unicode correctly. Explicit paste changes the clipboard, requires GTK 3 on X11, and services GTK events for one second before asking the desktop clipboard manager to retain the text. That wait is not proof that the target has finished pasting; callers must observe the final UI.

Validation: Linux Go tests, Python tests (16 passed), REPL tests (23 passed), docs and whitespace checks. Tests cover raw Unicode/whitespace payloads, delivery routing, active-window refusal, clipboard contents/shortcut, legacy auto fallback and no fallback after explicit errors. No live GUI selection-replacement success or benchmark is claimed.


## Explicit usage

```js
await app.typeText("short text", { textMethod: "keyboard" });
await app.typeText("  中文🙂\n\t ", { textMethod: "paste" });
await terminal.typeText("print(42)\n", { textMethod: "paste", pasteKey: "ctrl+shift+v" });
// To replace a specific field entirely, inspect AX first, then:
await app.setValue(freshElementIndex, "replacement");
```

The explicit keyboard/paste modes use the current selection/caret according to
the target app's normal input behavior. Selection replacement is a live desktop
acceptance item, not something demonstrated by mocked clipboard tests. Re-read
the UI before continuing after an input failure or before reporting success.
