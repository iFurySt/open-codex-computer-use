# Virtual cursor movement parity

- Request: virtual-screen motion looks straight and differs from ordinary OCU.
- Findings: existing implementation omitted CursorVisualDynamicsAnimator position/angle springs and glyph rotation; first target teleported, action delivery did not wait for travel, allowing fast actions to interrupt curves. Path selection alone was not complete reuse.
- Changes: reuse visual dynamics and rendered heading for path selection, animate fresh starts, rotate unchanged OBU artwork, await travel before delivering input. Cancellation from pause/clear/close releases waiters; no global input/activation. Keep virtual-screen clipping and capture exception.
- Verification: deterministic multi-frame curve/rotation/interruption/clear and independent reference-dynamics checks, Swift regression, signed build and safe App restart. Live frame motion verification if a retained display is available, without hotplug stress.
- Status: completed.

## Verification results
- `swift test`: 200 tests, 2 environment-dependent tests skipped, zero failures. New checks sample arc deviation and rotation at capture cadence and compare position/heading against independent ordinary-cursor dynamics calculations.
- Opt-in live AppKit test on the already-owned virtual screen passed: travel completes, clearing cancels travel, and closing cancels travel without blocking the main actor. Enable with `OPEN_COMPUTER_USE_VIRTUAL_CURSOR_LIVE_DISPLAY_ID` pointing to an explicitly supplied virtual screen; this test never creates a display.
- Developer ID release bundle/helper built and strictly verified; the installed App safely restarted into the new build and its private runtime identity confirmed.
- Real GUI Calculator → TextEdit example completed; AX read back `42 × 17 = 714`. Test session ended normally, leaving its empty display available for reuse. No repeated hotplug stress.
- The deterministic frame/rotation checks establish animation-model parity, not pixel-by-pixel captured-video parity or subjective hardware smoothness. Full video trajectory comparison and physical trackpad coverage remain pending.
