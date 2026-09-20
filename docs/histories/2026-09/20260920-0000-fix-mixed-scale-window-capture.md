## [2026-09-20 00:00] | Task: Fix quarter-size window screenshots

### 🤖 Execution Context
* **Agent ID**: Codex
* **Base Model**: gpt-5.6-sol
* **Runtime**: Codex desktop on macOS

### 📥 User Query
> Computer Use window streams sometimes show the captured content only in the top-left quarter of the frame.

### 🛠 Changes Overview
**Scope:** macOS ScreenCaptureKit window capture, tests, architecture docs, and release notes.

**Key Actions:**
- **[Coordinate-space fix]**: resolve the window's display with `CGDisplayBounds`, which shares Quartz coordinates with `CGWindow` bounds, instead of intersecting those bounds with AppKit `NSScreen.frame`.
- **[Spanning-window behavior]**: choose the display containing the largest part of a window when it crosses display boundaries.
- **[Regression proof]**: add mixed Retina / non-Retina layout tests and preserve screenshot-pixel coordinate mapping behavior.

### 🧠 Design Intent (Why)
ScreenCaptureKit does not scale a 1x window into a mistakenly requested 2x output when `scalesToFit` is disabled. Mixing AppKit and Quartz global coordinates could therefore select a Retina scale for a non-Retina window and return a 2x canvas whose content occupied only the top-left quarter. Display selection now stays in one coordinate system.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-09/20260919-2233-fix-mixed-scale-window-capture.md`
