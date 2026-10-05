# Virtual preview motion and navigation

- Goal: reuse existing curved cursor motion and add local pinch/wheel zoom and pointer drag pan.
- Boundary: nonactivating virtual-screen software window and view-local navigation; no global input, pointer movement, activation, window movement or input forwarding. Cursor target remains the actual delivered action target; animation visualizes delivery, never proves a UI change.
- Implementation: shared HeadingDriven path candidates + Official progress spring; monotonic interruptible cursor timeline in a display-confined transparent panel. Host exclusion has exactly one SCK window exception; preview cursor layer removed. Pure viewport geometry used by Metal; local AppKit gestures, bounded pan/zoom and double-click reset.
- Validation: curve/interruption/clear, transform/backing scale/zoom anchoring/clamps unit tests; Swift regression; signed build and safe App restart. Hardware pinch validation only if available, no repeated display hotplug.
- Status: implementation complete. 197 Swift tests passed (1 skipped), signed bundle verified and safely restarted. Real GUI cursor capture, full Calculator → TextEdit AX verification, wheel zoom, drag pan and double-click reset passed.
- Live validation: used one new display, then retained/reused it after a real desktop layout change paused input; reused negative Quartz coordinates verified. No repeated hotplug loop.
- Remaining coverage: physical trackpad pinch, 2×/multi-display variants and explicit frame-subscriber image assertions need further hardware/integration coverage; not claimed as tested. Gesture/Retina transform and curve containment/interruption are covered by deterministic unit tests.
- User steering: cursor belongs on the actual virtual display, shared by CLI/MCP/frame subscriptions, rather than duplicated in the preview. System pointer remains independent.
