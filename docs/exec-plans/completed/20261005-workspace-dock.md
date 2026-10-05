# Workspace app Dock

- Goal: preview-bottom native Dock for only managed windows currently inside the selected virtual display. No manual preview input yet.
- Scope: native app icons, click to raise a verified managed window, multiple-window context menu, selection indicator and hover feedback. Preview overlay only, fixed size under zoom; not included in frame subscriptions.
- Boundary: GUI-only manual raise serialized with registry operations, no application activate, no global events/cursor movement; validate PID birth/window scope/frame, verify z-order and pause if foreground changes. Existing tools still reject AXRaise.
- Validation: membership regression and Swift tests; signed build, exact-runtime restart and live two-app click/focus verification if available. Do not repeatedly hotplug displays.
- Status: implementation completed; live acceptance pending user unlock.

## Results
- Dock overlay implemented with cached native icons, hover feedback, current selection indicator and multiple-window context menu. It stays independent of preview zoom and raw capture.
- Shared-state membership only includes fully in-display managed windows. Manual raise checks live identity and geometry, verifies overlapping managed-window z-order and invalidates snapshot layout version; unexpected focus changes pause automation. No Agent activation fallback was added.
- `swift test`: 202 tests, 2 skipped, zero failures; after final cache invalidation adjustment, 34 virtual-display tests, 1 skipped, zero failures.
- Developer ID App/helper build and strict signature verification passed; own exact runtime quit normally and restarted into the installed build. Other worktree runtimes were left alone; no display was hotplugged.
- Computer Use reported the Mac locked, so visual layout, actual two-app switching, multiple-window menu and foreground preservation are not claimed as validated. User was asked to unlock; these hardware checks remain in quality notes.
