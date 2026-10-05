## 2026-10-05 | Task: Move software cursor onto the virtual screen and add preview navigation

### Execution Context
- Agent: `/root`, Codex desktop; model label not exposed by runtime.

### User request
Reuse the existing curved cursor motion; support preview pinch/wheel zoom and drag pan. Put the software cursor on the actual virtual display instead of rendering another cursor in the preview.

### Changes
- One display-confined transparent, nonactivating, mouse-ignoring NSPanel per capture. Reuses OBU cursor artwork/hotspot and existing HeadingDriven path selection / Official spring timing; interrupts from current position, clamps to display, runs its timer only during travel.
- SCK host exclusion has exactly one verified cursor-window exception. Frame subscriptions include cursor; Metal preview no longer overlays it. Window-level tool screenshots keep their existing filtering.
- Pause/lock/desktop changes clear the glyph; screen-parameter notifications hide it immediately. Stop closes the panel before holder teardown, so normal unplug cannot migrate a visible cursor to a physical screen.
- Pure viewport transform supports anchored 0.25–8× pinch/wheel zoom, bounded drag pan, double-click and Original size reset. No target input forwarding or snapshot-coordinate changes.
- Architecture, frontend, virtual-display design, quality notes and completed execution plan updated.

### Validation
- `swift test`: 197 tests, 1 skipped, zero failures. Four new tests cover nonstraight movement, interruption, clearing, bounds, zoom anchoring, Retina sizing, pan clamps and reset.
- Developer ID release bundle and nested helper built and strictly verified; normal runtime termination and safe restart performed.
- Live GUI observed captured software cursor with no duplicate preview layer. Calculator → TextEdit example produced 714 and AX read back `42 × 17 = 714`; wheel zoom, drag pan and double-click reset passed.
- A desktop layout change triggered the existing safety pause. Test session cleaned normally, display retained/reused at negative Quartz coordinates. No repeated hotplug stress.
- Physical pinch, full 2×/multi-screen coverage and frame-subscriber image assertions remain unverified; deterministic geometry checks do not replace these hardware checks.

### Files
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayCapture.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayPreviewGeometry.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/VirtualDisplayPreviewTests.swift`

### Follow-up: trackpad two-finger pan
- User clarified two-finger scrolling should behave like pointer dragging. Precise scroll events and gesture/momentum phases now share the drag pan path, including horizontal/vertical movement and existing bounds. Pinch and conventional mouse wheel continue zooming.
- AppKit already applies natural-scrolling preferences; only the vertical axis is converted into the unflipped preview's coordinate space. No preference changes or input forwarding.
- Swift regression and signed release build passed; App safely restarted. Physical trackpad gesture validation remains pending.
