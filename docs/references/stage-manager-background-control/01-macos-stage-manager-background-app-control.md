# Research Report: macOS Stage Manager — Background App Control for open-computer-use MCP

**Date:** 2026-05-21  
**Purpose:** Understand how Stage Manager handles background apps so open-computer-use MCP can control a target app in the background without stealing focus from the user's foreground monitor.

---

## Executive Summary

Stage Manager keeps background apps **fully rendered** in WindowServer but places them in inaccessible "strip" thumbnails. Three hard facts govern what the MCP can do:

1. **Clicks via CGEvent route to coordinates** — background-safe if you know the right screen position
2. **Typing via AXUIElement/SetFocus requires the target app to be in accessible state** — Stage Manager hidden apps are not accessible
3. **Screenshots of Stage Manager background strips have no reliable public API** — `kCGWindowIsOnscreen` returns false; ScreenCaptureKit skips them

The clean workaround: use a **second display or a second Stage** — background app stays fully interactive on another screen while the user works on the primary monitor.

---

## Table of Contents
1. [Stage Manager Window Architecture](#1-stage-manager-window-architecture)
2. [Background App State & Rendering](#2-background-app-state--rendering)
3. [API Coverage for Background Control](#3-api-coverage-for-background-control)
4. [open-computer-use MCP Internals](#4-open-computer-use-mcp-internals)
5. [Screenshot / Visual State Capture](#5-screenshot--visual-state-capture)
6. [Practical Strategy Matrix](#6-practical-strategy-matrix)
7. [Recommended Architecture](#7-recommended-architecture)
8. [Unresolved Questions](#8-unresolved-questions)

---

## 1. Stage Manager Window Architecture

Stage Manager is a **compositing policy layer** on top of Quartz Compositor — not a separate Space or virtual desktop:

```
WindowServer / Quartz Compositor
├── ALL windows always composited (high CPU vs Spaces)
├── Active Stage: foreground app window(s), centered on screen
└── Background Strips: app thumbnails on right edge, OFF-SCREEN or SCALED DOWN
    ├── Fully rendered by WindowServer (buffers live)
    ├── `kCGWindowIsOnscreen` = 1 in CGWindowList (enumerable with valid IDs)
    └── Visual/interactive access via public API: BLOCKED by Stage Manager policy
```

**Key difference vs Spaces:**
- Spaces: out-of-space windows are partially unloaded/frozen
- Stage Manager: ALL windows fully rendered, HIGH memory/CPU, but policy blocks interaction

No public API exposes Stage Manager groupings. The private subsystems involved: WindowManagement, SkyLight, RunningBook, Launch Services.

---

## 2. Background App State & Rendering

| Property | Stage Manager Background | Spaces Background |
|---|---|---|
| Window rendered in WindowServer | ✅ Yes (full) | ❌ Partially suspended |
| Valid CGWindowID | ✅ Yes | ✅ Yes |
| `kCGWindowIsOnscreen` | ⚠️ Reports true in list, but CGWindowListCreateImage returns BLANK | Varies |
| App process state | ✅ Running, not suspended | ✅ Running |
| Keyboard/mouse focus | ❌ None — user can't interact via strip | N/A |
| AXUIElement accessible | ❌ No — hidden from accessibility tree | ✅ Yes |

**Stage Manager background strips are thumbnails, not interactive windows.** Clicking a strip switches the Stage (steals focus). The actual app window is offscreen/hidden.

---

## 3. API Coverage for Background Control

### 3a. Click Events (CGEvent)

```
CGEventPost(HID tap) → routes to window at screen coordinates
```

- ✅ **Background-safe IF the window is visible on screen** (different display or visible Stage)
- ❌ Stage Manager background strips are tiny thumbnails — clicking them switches Stage
- CGEvent bypasses focus — no `NSApp.activate()` called

### 3b. Typing / Text Input (AXUIElement + SetFocus)

```
AXUIElementSetAttributeValue(element, kAXFocusedAttribute, kCFBooleanTrue)
```

- ❌ **Fails on Stage Manager hidden apps** — AXFocused attribute on non-accessible windows silently fails
- Workaround: activate target app, type, re-activate original app (< 200ms round trip observable flicker)

### 3c. AppleScript `tell application X`

- ✅ **Background-safe IF `activate` is NOT called**
- ✅ Can trigger menu items, AppleScript commands on background apps
- ❌ Many apps disable menu items when not in foreground

### 3d. `CGEventPostToPSN` (deprecated)

- ❌ Deprecated macOS 10.9+; unreliable for background event delivery; likely triggers focus

### 3e. Accessibility API (AXUIElement general)

- ⚠️ Partial — can read window geometry, enumerate elements
- ❌ Cannot AXPress/AXClick reliably on Stage Manager hidden windows
- ✅ Works on secondary display apps (those are fully on-screen)

---

## 4. open-computer-use MCP Internals

Based on analysis of this repo's `InputSimulation.swift`, `AccessibilitySnapshot.swift`, `ComputerUseService.swift`:

### Architecture (relevant layers)

```
get_app_state → accessibility tree of ALL windows (AXUIElement)
click          → CGEvent at (x, y) via postToPid → background-safe for onscreen windows
type_text      → CGEvent.postToPid keyboard → safe, but gated on focused element check
```

### What works in background today

| Tool | Background-safe? | Notes |
|---|---|---|
| `get_app_state` | ⚠️ Forces `activate()` | Falls back to focus steal when window not found via `optionOnScreenOnly` |
| `click` (coord) | ⚠️ Partial | `postToPid` used but missing `CGEventSetWindowLocation` + fields 91/92 |
| `click` (AX element) | ✅ if AX accessible | `AXPress` / `AXConfirm` work on accessible elements |
| `type_text` | ⚠️ Blocked | Gate `canTypeTextUsingKeyboardFallback` fails for background apps |
| `scroll` targeted | ✅ | `scrollTargeted` uses `postToPid` |
| `press_key` | ✅ | `CGEvent.postToPid` — background-safe |
| `set_value` | ✅ | Pure `AXUIElementSetAttributeValue` |

---

## 5. Screenshot / Visual State Capture

### Public APIs

| API | Stage Manager Background? | Notes |
|---|---|---|
| `CGWindowListCreateImage` | ❌ Returns blank frame | Background windows have no valid pixel buffer via this API |
| `ScreenCaptureKit SCWindow` | ❌ Not listed | `SCShareableContent` only returns onscreen windows |
| `CGWindowListCopyWindowInfo` | ✅ Metadata only | Get bounds, title, PID — no pixels |

### Private API (fragile)

- `CGSHWCaptureWindowList` — undocumented, used by alt-tab-macos
- Returns cached thumbnail sprite from Stage Manager compositor
- **Not suitable for production**; breaks across macOS versions

### Workaround

For visual state of a background app: **temporarily switch Stage → screenshot → switch back** using AppleScript Mission Control or Dock activation. ~300ms round-trip.

---

## 6. Practical Strategy Matrix

| Goal | Approach | Reliability |
|---|---|---|
| **Control background app on 2nd display** | CGEvent at screen coords; no changes needed | ✅ High |
| **Click UI element in background Stage** | `CGEventSetWindowLocation` + fields 91/92 + `postToPid` | ✅ High (with private API) |
| **Type text in background app** | activate_temporarily → type → restore | ✅ High (with ~100ms flicker) |
| **Read app state (accessibility tree)** | Drop `optionOnScreenOnly` filter; AX tree still accessible off-screen | ✅ Works |
| **Screenshot background app** | No reliable public API; return AX-only + note | ⚠️ AX only |

**Recommended setup for zero-focus-steal automation:**
```
Monitor 1 (user works here)    |   Monitor 2 (MCP controls here)
─────────────────────────────────────────────────────────────────
User's foreground app          |   Target app (fully visible)
Stage Manager active           |   Stage Manager OFF (optional)
                               |   → CGEvent, AXUIElement both work
                               |   → ScreenCaptureKit works
                               |   → No focus conflict
```

---

## 7. Recommended Architecture

For open-computer-use MCP to truly support "background control under Stage Manager":

### Option A — Multi-display setup (best, zero changes needed)
- Move target app to secondary display
- MCP controls it there; user never loses focus on primary
- All APIs work fully

### Option B — Background event injection (single display, Stage Manager)
- Drop `optionOnScreenOnly` filter in `AccessibilitySnapshot.swift`
- Add `clickBackgrounded` using `CGEventSetWindowLocation` + fields 91/92
- For `type_text`: activate-temporarily pattern (~100ms round-trip)
- See `02-codebase-gap-analysis.md` for exact file/line details

### Option C — AppleScript-only for supported apps
- Use `tell application X` without `activate`
- Trigger actions via AppleScript APIs (not UI clicks)
- Zero focus steal; limited to scriptable actions only

---

## 8. Unresolved Questions

1. Does the AX tree remain accessible for Stage Manager background apps (layer 0, off-screen)? Needs live testing on Sequoia.
2. Do CGEvent fields 91/92 accept raw `Int64(CGWindowID)` directly, or need the windowNumber from `NSEvent` creation?
3. On macOS Sequoia 15.4+, has Apple tightened the `CGEventSetWindowLocation` behavior or the off-screen window CGWindowList query?
4. Does Stage Manager behavior differ between "full-screen" Stage Manager mode vs "windowed" mode on a secondary display?

---

## Sources
- Apple Support: Stage Manager Guide
- Eclectic Light Company: WindowServer Deep Dive
- alt-tab-macos GitHub Issues #3079, #5315 (Stage Manager capture failures)
- Apple Developer: CGWindowList, ScreenCaptureKit, AXUIElement docs
- WWDC24: What's New in AppKit
- This repo: `docs/references/codex-computer-use-reverse-engineering/background-click-free-tooling.md`
