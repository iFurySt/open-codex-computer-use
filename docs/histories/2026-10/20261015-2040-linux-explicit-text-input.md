# Add explicit Linux keyboard and X11 paste delivery

Agent: Codex; runtime: Linux.

User request: submit scoped improvements for the remaining Linux performance paths.

Draft: explicit delivery paths and protocol tests are ready for review; live desktop validation of selection replacement, Unicode delivery and clipboard-manager behavior is pending.

Keep `type_text` auto delivery as the existing AX-first/keyboard-fallback route. Add explicit `text_method: "keyboard"` and `text_method: "paste"` (REPL `textMethod`). Both require the requested app window to be active and never activate another window. Explicit paste uses the X11 clipboard and Ctrl+V; `paste_key` / `pasteKey` supports terminal Ctrl+Shift+V. Failures never silently fall back to another text target or method. `set_value` remains the route for replacing an explicitly observed editable element's complete value.

Literal `type_text` and `set_value` payloads retain leading/trailing whitespace, newlines, tabs and Unicode at the Go/bridge boundary; routing names/indexes continue to be normalized. The default keyboard path is not claimed to handle all Unicode correctly. Explicit paste changes the clipboard, requires GTK 3 on X11, and services GTK events for one second before asking the desktop clipboard manager to retain the text. That wait is not proof that the target has finished pasting; callers must observe the final UI.

Validation: Linux Go tests, Python tests (16 passed), REPL tests (23 passed), docs and whitespace checks. Tests cover raw Unicode/whitespace payloads, delivery routing, active-window refusal, clipboard contents/shortcut, legacy auto fallback and no fallback after explicit errors. No live GUI selection-replacement success or benchmark is claimed.

Changed areas: Linux native/bridge code and tests, architecture, release and feature documentation, and REPL input-option forwarding/tests.

Full Node suite: 36/37 passed, with the pre-existing macOS lipo-dependent npm packaging test failing on Linux.
