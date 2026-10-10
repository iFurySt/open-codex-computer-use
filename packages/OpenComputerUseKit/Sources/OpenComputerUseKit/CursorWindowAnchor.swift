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
        guard liveFrame.width > 0, liveFrame.height > 0 else {
            return nil
        }

        let localX = windowLocalPoint.x.clamped(to: 0...liveFrame.width)
        let localY = windowLocalPoint.y.clamped(to: 0...liveFrame.height)
        return CGPoint(x: liveFrame.minX + localX, y: liveFrame.minY + localY)
    }
}

/// Live frames for target windows.
///
/// `CGWindowListCopyWindowInfo` keeps reporting the pre-move frame for about a
/// second after a window is dragged to another display — measured while fixing
/// this: 83 identical frames at the cursor travel's 120 Hz pump. The
/// accessibility element the snapshot already holds reports the move
/// immediately, so it is the source of truth here and the window list is only a
/// fallback for windows the snapshot never registered.
enum CursorWindowFrameTracker {
    /// Lock-protected box so the tracker can be used from the service thread
    /// and the overlay's main-thread pump alike.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var elements: [CGWindowID: AXUIElement] = [:]
        /// Test seam: consulted before any real lookup.
        var override: ((CGWindowID) -> CGRect?)?
    }

    private static let state = State()

    static func register(windowID: CGWindowID?, element: AXUIElement?) {
        guard let windowID, let element else {
            return
        }

        state.lock.lock()
        defer { state.lock.unlock() }
        state.elements[windowID] = element
    }

    static func forget(windowID: CGWindowID) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.elements.removeValue(forKey: windowID)
    }

    static func forgetAll() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.elements.removeAll()
    }

    static func installFrameOverrideForTesting(_ body: ((CGWindowID) -> CGRect?)?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.override = body
    }

    static func liveFrame(for windowID: CGWindowID) -> CGRect? {
        state.lock.lock()
        let body = state.override
        state.lock.unlock()

        if let body {
            return body(windowID)
        }

        return accessibilityFrame(for: windowID) ?? windowListFrame(for: windowID)
    }

    /// Frame read from the registered accessibility element, which reflects a
    /// move immediately.
    static func accessibilityFrame(for windowID: CGWindowID) -> CGRect? {
        state.lock.lock()
        let element = state.elements[windowID]
        state.lock.unlock()

        guard let element else {
            return nil
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0
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
