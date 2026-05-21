# Codebase Gap Analysis: Stage Manager Background Control

**Repo:** https://github.com/iFurySt/open-codex-computer-use  
**Date:** 2026-05-21  
**Goal:** Identify exactly where to add "virtual mouse in background app, no focus steal" for Stage Manager.

---

## Quick Verdict

The repo has already done the hard research. The background click technique using `CGEventSetWindowLocation` + CGEvent fields 91/92 + `postToPid` is **documented but not yet implemented** in the actual Swift code. There are 5 concrete gaps.

See `docs/references/codex-computer-use-reverse-engineering/background-click-free-tooling.md` for the reverse-engineering that proves this technique works.

---

## Current Architecture (relevant layers)

```
MCP tool call
    ↓
ComputerUseToolDispatcher.swift   — routes tool name → ComputerUseService
    ↓
ComputerUseService.swift          — orchestrates snapshot + action
    ↓
InputSimulation.swift             — CGEvent / AX action dispatch
AccessibilitySnapshot.swift       — window discovery, AX tree, screenshot
```

---

## Gap 1 — `get_app_state` forces focus steal for Stage Manager apps

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`  
**Line:** ~359

```swift
// CURRENT — only queries onscreen windows
guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? ...
```

**Problem:** Stage Manager background strip apps are NOT in `optionOnScreenOnly`. When the window isn't found, the recovery path at line ~192 kicks in:

```swift
recovered = runningApplication.unhide() || recovered
recovered = runningApplication.activate(options: [.activateAllWindows]) || recovered  // ← FOCUS STEAL
```

**Fix:** Change to query ALL windows and match the target PID's layer-0 window regardless of onscreen status. Skip the `activate()` recovery path when found via off-screen lookup.

```swift
// PROPOSED
let options: CGWindowListOption = [.excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { ... }
// then filter by pid, layer == 0, area >= 20_000 as before
// if window found off-screen: use it for AX tree but skip activate()
```

**Caveat:** Screenshot capture will return a blank frame for off-screen Stage Manager windows. AX tree traversal still works — AX operates on the process's accessibility tree, not visual state.

---

## Gap 2 — `clickTargeted` missing `CGEventSetWindowLocation` + window fields

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`  
**Line:** ~70–80 (`clickTargeted`) and ~220–241 (`postMouseEventToPid`)

**Current `postMouseEventToPid`:**
```swift
private static func postMouseEventToPid(..., pid: pid_t) throws {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                               mouseCursorPosition: point, mouseButton: button) else { ... }
    event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    event.postToPid(pid)      // ← sends to process but WITHOUT window targeting
}
```

**Problem:** Without setting CGEvent fields 91/92 (window-under-pointer, event-target-window) and calling the private `CGEventSetWindowLocation`, the background window does NOT reliably receive `mouseDown/mouseUp`. The repo's own `background-click-free-tooling.md` reverse-engineered this and confirmed it's the critical path.

**Fix — new `clickBackgrounded` function in `InputSimulation.swift`:**

```swift
// Resolve private symbol at runtime — avoids hard link dependency
typealias CGEventSetWindowLocationFn = @convention(c) (CGEvent, CGPoint) -> Void

static func clickBackgrounded(
    at screenPoint: CGPoint,
    windowID: CGWindowID,
    windowBounds: CGRect,
    button: MouseButtonKind,
    clickCount: Int,
    pid: pid_t
) throws {
    guard let sym = dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation"),
          let setWindowLocation = unsafeBitCast(sym, to: CGEventSetWindowLocationFn?.self) else {
        // Graceful fallback when private symbol is unavailable (future macOS)
        try clickTargeted(at: screenPoint, button: button, clickCount: clickCount, pid: pid)
        return
    }

    let localPoint = CGPoint(
        x: screenPoint.x - windowBounds.origin.x,
        y: screenPoint.y - windowBounds.origin.y
    )
    let windowIDValue = Int64(windowID)

    for _ in 0..<max(clickCount, 1) {
        guard let nsDown = NSEvent.mouseEvent(
            with: button.nsDownType,
            location: screenPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: Int(windowID),
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: button == .left ? 1.0 : 0.0
        ), let down = nsDown.cgEvent,
        let nsUp = NSEvent.mouseEvent(
            with: button.nsUpType,
            location: screenPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: Int(windowID),
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0.0
        ), let up = nsUp.cgEvent else {
            throw ComputerUseError.message("Failed to create background mouse events.")
        }

        // field 91 = window under pointer, field 92 = event target window
        down.setIntegerValueField(CGEventField(rawValue: 91)!, value: windowIDValue)
        down.setIntegerValueField(CGEventField(rawValue: 92)!, value: windowIDValue)
        up.setIntegerValueField(CGEventField(rawValue: 91)!, value: windowIDValue)
        up.setIntegerValueField(CGEventField(rawValue: 92)!, value: windowIDValue)

        down.location = screenPoint
        up.location = screenPoint

        // Critical: window-local point enables reliable delivery to off-screen window
        setWindowLocation(down, localPoint)
        setWindowLocation(up, localPoint)

        down.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.03)
        up.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.03)
    }
}
```

**Wire-up in `ComputerUseService.swift`:** When the snapshot has a `targetWindowID` and `windowBounds`, prefer `clickBackgrounded` over `clickTargeted` in the coordinate click path.

---

## Gap 3 — Screenshot returns blank for Stage Manager background windows

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`  
**Line:** ~396 (`captureImage(windowID:bounds:)`)

```swift
private static func captureImage(windowID: CGWindowID, bounds: CGRect) -> CGImage? {
    CGWindowListCreateImage(CGRect.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming)
}
```

**Current behavior:** For Stage Manager background windows, `CGWindowListCreateImage` returns a blank/empty frame.

**Fix options (best → worst):**
1. **No screenshot for background apps** — return AX tree only, omit `image` block, add note: `"screenshot unavailable: app is in Stage Manager background"`. Honest, doesn't block AX-tree path.
2. **ScreenCaptureKit thumbnail** — macOS 14+ `SCShareableContent`, but Stage Manager background windows still don't appear.
3. **Switch Stage temporarily** — bring app to front, screenshot, switch back. ~300ms round-trip, visible flicker.

**Recommended:** Option 1.

---

## Gap 4 — `drag` has no background path

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`  
**Line:** ~122 (`dragGlobally`)

No `dragTargeted` equivalent exists. Always moves the real mouse.

**Fix:** Add `dragBackgrounded(from:to:windowID:windowBounds:pid:)` using the same `CGEventSetWindowLocation` approach as Gap 2, posting `leftMouseDown` → `leftMouseDragged` × 10 → `leftMouseUp` all via `postToPid` with fields 91/92 set.

---

## Gap 5 — `type_text` gated on foreground focused element

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`  
**Line:** ~583

```swift
guard try canTypeTextUsingKeyboardFallback(in: snapshot) else {
    throw ComputerUseError.stateUnavailable("type_text requires a focused editable text element...")
}
```

**Current:** `CGEvent.postToPid` keyboard dispatch is already background-safe, but the gate `canTypeTextUsingKeyboardFallback` blocks it when no focused AX element exists — which is the case for Stage Manager background apps.

**Fix — add activate-temporarily fallback after AXValue attempt:**

```swift
if !canTypeTextUsingKeyboardFallback(in: snapshot) {
    // Try AXValue direct set first (no focus needed)
    if let focusedElement = snapshot.focusedElement, isEditableTextRole(of: focusedElement) {
        try InputSimulation.setValueViaAX(element: focusedElement, text: text)
        return snapshotResult(...)
    }
    // Fallback: temporarily activate, type, restore
    let originalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    NSRunningApplication(processIdentifier: snapshot.app.pid)?.activate(options: [])
    Thread.sleep(forTimeInterval: 0.08)
    try InputSimulation.typeText(text, pid: snapshot.app.pid)
    if let orig = originalPID {
        NSRunningApplication(processIdentifier: orig)?.activate(options: [])
    }
}
```

---

## What Already Works (no changes needed)

| Tool | Background-safe? | Mechanism |
|---|---|---|
| `press_key` | ✅ | `CGEvent.postToPid` — keyboard events direct to PID |
| `type_text` (AXValue path) | ✅ | `AXUIElementSetAttributeValue` when element is settable |
| `click` AX element path | ✅ if AX accessible | `AXPress` / `AXConfirm` via AX actions |
| `scroll` targeted | ✅ | `scrollTargeted` uses `postToPid` |
| `set_value` | ✅ | Pure `AXUIElementSetAttributeValue` |

---

## Priority Order for Implementation

| # | Change | File | Effort | Value |
|---|---|---|---|---|
| 1 | Drop `optionOnScreenOnly`, skip `activate()` for off-screen windows | `AccessibilitySnapshot.swift` | Small | **High** — unblocks all other tools |
| 2 | Add `clickBackgrounded` with `CGEventSetWindowLocation` + fields 91/92 | `InputSimulation.swift` | Medium | **High** — true virtual click |
| 3 | Wire `clickBackgrounded` into `ComputerUseService.click()` when windowID known | `ComputerUseService.swift` | Small | **High** — connects 1+2 |
| 4 | Return AX-only result (no screenshot) when window is off-screen | `AccessibilitySnapshot.swift` | Tiny | Medium — honest fallback |
| 5 | `type_text` activate-temporarily fallback | `ComputerUseService.swift` | Small | Medium — needed for text input |
| 6 | `dragBackgrounded` | `InputSimulation.swift` | Medium | Low — drag rarely needed |

---

## Key Risk: `CGEventSetWindowLocation` is private API

Resolved at runtime via `dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation")`. If the symbol is missing (future macOS), code gracefully falls back to `clickTargeted`. Binary stays distributable without linking against private frameworks.

The repo's own research doc notes this limitation explicitly — treat this as an implementation detail, not an architectural dependency.

---

## Unresolved Questions

1. Does the AX tree remain accessible for Stage Manager background apps (layer 0, off-screen)? Needs live testing on Sequoia 15.4+.
2. Do CGEvent fields 91/92 accept raw `Int64(CGWindowID)` directly, or must they come from `NSEvent.mouseEvent(windowNumber:)`? The reverse-engineering doc suggests both paths work but NSEvent-backed is more reliable.
3. Has Sequoia 15.4+ tightened `CGEventSetWindowLocation` behavior or the off-screen CGWindowList query?
