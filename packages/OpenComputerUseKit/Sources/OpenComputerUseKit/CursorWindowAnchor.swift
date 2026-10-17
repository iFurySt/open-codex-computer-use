import ApplicationServices
import CoreGraphics
import Foundation

/// The point a cursor target was derived from, expressed relative to the
/// window frame the snapshot reported.
///
/// A window that moves between the snapshot and the action keeps its
/// window-local geometry, so this is what lets the overlay re-derive the point
/// from the window's live frame instead of drawing on the display the window
/// just left.
struct CursorRestingAnchor: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
    /// Element centre relative to the window's top-left corner, screen-state space.
    let windowLocalPoint: CGPoint
    /// Window frame the anchor was derived from, screen-state space.
    let windowBounds: CGRect

    /// The anchored point re-expressed against a live window frame.
    ///
    /// Returns `nil` when the live frame carries no usable size, so callers can
    /// fall back to the point they already have.
    func screenStatePoint(liveFrame: CGRect) -> CGPoint? {
        guard Self.isUsable(liveFrame), windowLocalPoint.x.isFinite, windowLocalPoint.y.isFinite else {
            return nil
        }

        let localX = windowLocalPoint.x.clamped(to: 0...liveFrame.width)
        let localY = windowLocalPoint.y.clamped(to: 0...liveFrame.height)
        return CGPoint(x: liveFrame.minX + localX, y: liveFrame.minY + localY)
    }

    static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isInfinite && !frame.isNull && frame.origin.x.isFinite && frame.origin.y.isFinite &&
        frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}

/// Live frames for target windows.
///
/// `CGWindowListCopyWindowInfo` keeps reporting the pre-move frame for about a
/// second after a window is dragged to another display — measured while fixing
/// this: 83 identical frames at the cursor travel's 120 Hz pump. The
/// accessibility element the snapshot already holds reports the move
/// immediately, so it is the preferred source. Read it on a serial worker,
/// cache the last usable frame, and limit requests to 30 Hz. The window list is
/// used only when no accessibility element was registered; a failed AX read
/// must not replace a good frame with the window list's stale origin.
enum CursorWindowFrameTracker {
    private final class Source: @unchecked Sendable {
        let windowID: CGWindowID
        let element: AXUIElement?
        init(windowID: CGWindowID, element: AXUIElement?) {
            self.windowID = windowID
            self.element = element
        }
    }

    /// Lock-protected box so the tracker can be used from the service thread
    /// and the overlay's main-thread pump alike.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        // Only one software cursor is displayed. Do not retain every window
        // ever observed by a long-lived App Agent.
        var source: Source?
        var frame: CGRect?
        var nextRefresh: TimeInterval = 0
        var refreshing = false
        /// Test seam: consulted before any real lookup.
        var override: ((CGWindowID) -> CGRect?)?
        var reader: (@Sendable (CGWindowID) -> CGRect?)?
    }

    private static let state = State()
    private static let queue = DispatchQueue(label: "com.ifuryst.ocu.cursor-frame", qos: .userInitiated)
    private static let refreshInterval: TimeInterval = 1 / 30

    static func register(windowID: CGWindowID?, element: AXUIElement?) {
        guard let windowID else {
            return
        }

        state.lock.lock()
        defer { state.lock.unlock() }
        if let existing = state.source, existing.windowID == windowID {
            switch (existing.element, element) {
            case let (lhs?, rhs?) where CFEqual(lhs, rhs): return
            case (nil, nil): return
            default: break
            }
        }
        state.source = Source(windowID: windowID, element: element)
        state.frame = nil
        state.nextRefresh = 0
    }

    static func forget(windowID: CGWindowID) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.source?.windowID == windowID {
            state.source = nil
            state.frame = nil
        }
    }

    static func forgetAll() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.source = nil
        state.frame = nil
        // An in-flight IPC read cannot be cancelled safely. Keep its slot busy
        // until it returns; its result will be discarded by source identity.
    }

    static func installFrameOverrideForTesting(_ body: ((CGWindowID) -> CGRect?)?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.override = body
    }

    static func installFrameReaderForTesting(_ body: (@Sendable (CGWindowID) -> CGRect?)?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.reader = body
    }

    static func liveFrame(for windowID: CGWindowID) -> CGRect? {
        state.lock.lock()
        if let body = state.override {
            state.lock.unlock()
            return body(windowID)
        }
        guard let source = state.source, source.windowID == windowID else {
            state.lock.unlock()
            return nil
        }
        let frame = state.frame
        let now = ProcessInfo.processInfo.systemUptime
        let refresh = !state.refreshing && now >= state.nextRefresh
        let reader = state.reader
        if refresh {
            state.refreshing = true
            state.nextRefresh = now + refreshInterval
        }
        state.lock.unlock()
        if refresh {
            queue.async {
                // Accessibility can block on an unresponsive app. It must not
                // run on the render thread or accumulate a queue of requests.
                let observed: CGRect?
                if let reader { observed = reader(source.windowID) }
                else if let element = source.element { observed = accessibilityFrame(element) }
                else { observed = windowListFrame(for: source.windowID) }
                state.lock.lock()
                if state.source === source, let observed, CursorRestingAnchor.isUsable(observed) {
                    state.frame = observed
                }
                state.refreshing = false
                state.lock.unlock()
            }
        }
        return frame
    }

    /// Frame read from the registered accessibility element, which reflects a
    /// move immediately.
    private static func accessibilityFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              CursorRestingAnchor.isUsable(CGRect(origin: position, size: size))
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    /// Fallback frame from the window server. Kept last because it can report
    /// the pre-move origin for about a second.
    static func windowListFrame(for windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID
        ) as? [[String: Any]],
            let entry = info.first,
            let boundsDictionary = entry[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
            frame.width > 0,
            frame.height > 0
        else {
            return nil
        }

        return frame
    }
}
