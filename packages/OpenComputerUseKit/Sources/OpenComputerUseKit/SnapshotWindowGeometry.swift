import CoreGraphics
import Foundation

/// Window-server geometry of one window, in screen-state (top-left origin)
/// coordinates - the same space as `AppSnapshot.windowBounds` and every
/// element frame derived from it.
struct SnapshotWindowGeometry: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
}

/// What has to happen to a cached snapshot whose target window moved.
enum SnapshotWindowReanchor: Equatable {
    /// The live frame matches the cached one: the snapshot is still current.
    case none
    /// Same window, same size, new origin. Element frames are window-relative,
    /// so patching the window frame is enough to re-derive every global point.
    case patchGeometry
    /// Different size, or a different window entirely: the rendered element
    /// frames and the screenshot scale cannot be trusted any more.
    case fullRefresh
}

/// The service caches one snapshot per app so an action does not have to
/// repeat `get_app_state`. The window itself is never cached: the user can
/// drag it to another display between two actions, and a stale frame is what
/// drew the software cursor - and any coordinate click - on the old screen.
///
/// A pure decision so the "moved / resized / replaced" cases are pinned by
/// unit tests instead of a live multi-display rig.
func snapshotWindowReanchorAction(
    cachedWindowID: CGWindowID?,
    cachedBounds: CGRect?,
    live: SnapshotWindowGeometry?
) -> SnapshotWindowReanchor {
    guard let live else {
        // Nothing resolvable right now (window minimized, on another Space, or
        // the app is gone). Keep the cached snapshot: the accessibility action
        // paths do not need a frame at all, and dropping it would fail closed
        // on a window the tool can still drive.
        return .none
    }

    guard let cachedBounds, cachedWindowID == live.windowID else {
        return .fullRefresh
    }

    if cachedBounds == live.bounds {
        return .none
    }

    return cachedBounds.size == live.bounds.size ? .patchGeometry : .fullRefresh
}

extension AppSnapshot {
    /// The same snapshot with a freshly read window frame. Element frames stay
    /// untouched: they are window-relative, so only the frame moved.
    func reanchored(to geometry: SnapshotWindowGeometry) -> AppSnapshot {
        AppSnapshot(
            app: app,
            windowTitle: windowTitle,
            windowBounds: geometry.bounds,
            targetWindowID: geometry.windowID,
            targetWindowLayer: geometry.layer,
            windowElement: windowElement,
            screenshotPNGData: screenshotPNGData,
            mode: mode,
            treeLines: treeLines,
            focusedSummary: focusedSummary,
            focusedElement: focusedElement,
            selectedText: selectedText,
            elements: elements
        )
    }
}

/// Live geometry of the window the snapshot was built from.
///
/// Matched by window id first, so a moved or resized window is re-read even
/// when it is not the frontmost window of its app any more. Only when that id
/// is unknown does this fall back to the frontmost on-screen window of the
/// same app, which is the same choice `SnapshotBuilder` makes.
func currentWindowGeometry(
    for app: RunningAppDescriptor,
    windowID: CGWindowID?,
    windowTitle: String?
) -> SnapshotWindowGeometry? {
    if let windowID, let exact = windowGeometry(forWindowID: windowID) {
        return exact
    }

    guard let best = preferredWindowCaptureCandidate(
        WindowCapture.visibleCandidates(for: app.pid),
        titleHint: windowTitle
    ) else {
        return nil
    }

    return SnapshotWindowGeometry(windowID: best.windowID, layer: best.layer, bounds: best.bounds)
}

/// One window by id, on screen or not.
///
/// `.optionIncludingWindow` is what makes this usable while the user is
/// dragging: it reports the window frame regardless of which display, Space or
/// stacking position the window currently has.
func windowGeometry(forWindowID windowID: CGWindowID) -> SnapshotWindowGeometry? {
    guard windowID != 0,
          let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
          let info = infoList.first,
          let number = info[kCGWindowNumber as String] as? NSNumber,
          let layer = info[kCGWindowLayer as String] as? Int,
          let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
    else {
        return nil
    }

    return SnapshotWindowGeometry(
        windowID: CGWindowID(number.uint32Value),
        layer: layer,
        bounds: bounds
    )
}

/// Frame-only probe used by the overlay when the target window reports a move.
func currentWindowBounds(for windowID: CGWindowID) -> CGRect? {
    windowGeometry(forWindowID: windowID)?.bounds
}
