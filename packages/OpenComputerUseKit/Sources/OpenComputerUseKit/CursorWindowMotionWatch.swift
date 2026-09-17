import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// The accessibility notifications the overlay watches on its target window.
///
/// Deliberately read-only: a move or a resize is the only thing the overlay has
/// to react to, and none of these notifications changes the target app focus.
/// Activation notifications (`AXRaise` / `AXMain` / `AXFocused`) are not part
/// of this list and must never be added to it.
let cursorWindowMotionNotifications: [String] = [
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
]

/// Opt-out switch for the window-move watch.
///
/// On by default: it is a read-only registration that only re-reads the target
/// window frame, so it cannot change what the user sees in the target app.
func cursorWindowMoveWatchEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_WINDOW_MOVE_WATCH"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return true
    }

    return !["0", "false", "no", "off"].contains(rawValue)
}

/// Whether the overlay currently rests on a different display than the one
/// that owns its target window.
///
/// The cursor is only meaningful on the window it points at, so a mismatch is
/// the fallback trigger: re-derive the point from the live window frame and
/// re-place the panel instead of trusting the old global coordinate.
func cursorOverlayScreenMismatch(
    panelTip: CGPoint?,
    targetWindowOrigin: CGPoint?,
    screenIndexContaining: (CGPoint) -> Int?
) -> Bool {
    guard let panelTip,
          let targetWindowOrigin,
          let panelScreen = screenIndexContaining(panelTip),
          let targetScreen = screenIndexContaining(targetWindowOrigin)
    else {
        // An unknown display is not a mismatch: the overlay stays where it is
        // rather than jumping on a probe that could not answer.
        return false
    }

    return panelScreen != targetScreen
}

/// The target window the overlay watches, carrying the accessibility window
/// element the snapshot was rendered from.
///
/// The element is handed from the snapshot builder (background) to the overlay
/// (main). `AXUIElement` is a thread-safe handle for the read-only registration
/// here, which is what the explicit `@unchecked Sendable` marks.
struct CursorObservedWindow: @unchecked Sendable {
    let pid: pid_t
    let windowID: CGWindowID
    let layer: Int
    let element: AXUIElement
}

/// One live registration. Injected so a window move can be driven in unit
/// tests without a window server.
@MainActor
protocol CursorWindowMotionObserving: AnyObject {
    var isObserving: Bool { get }
    func observe(
        pid: pid_t,
        window: AXUIElement,
        onChange: @escaping @MainActor () -> Void
    )
    func stop()
}

/// Accessibility observer for "the target window moved / changed display".
///
/// The overlay has to follow its window immediately, not just on the next tool
/// call. `NSWindow.didMoveNotification` is in-process only, and polling the
/// window server forever would break the idle-stillness contract, so the event
/// source is the accessibility notification an app posts when a window move or
/// resize ends. Apps are free not to post it, which is why the action path also
/// re-anchors from the live frame.
@MainActor
final class AXWindowMotionObserver: CursorWindowMotionObserving {
    private var observer: AXObserver?
    private var source: CFRunLoopSource?
    private var observedElement: AXUIElement?
    private var onChange: (@MainActor () -> Void)?

    var isObserving: Bool { observer != nil }

    func observe(
        pid: pid_t,
        window: AXUIElement,
        onChange: @escaping @MainActor () -> Void
    ) {
        stop()

        var observer: AXObserver?
        guard AXObserverCreate(pid, cursorWindowMotionCallback, &observer) == .success,
              let observer
        else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = false
        for notification in cursorWindowMotionNotifications {
            if AXObserverAddNotification(observer, window, notification as CFString, refcon) == .success {
                registered = true
            }
        }

        guard registered else {
            return
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.observer = observer
        self.source = source
        self.observedElement = window
        self.onChange = onChange
    }

    func stop() {
        if let observer, let observedElement {
            for notification in cursorWindowMotionNotifications {
                _ = AXObserverRemoveNotification(observer, observedElement, notification as CFString)
            }
        }

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        observer = nil
        source = nil
        observedElement = nil
        onChange = nil
    }

    fileprivate func handleWindowMotion() {
        guard isObserving else {
            return
        }

        onChange?()
    }
}

/// Delivered on the main run loop, where the accessibility run loop source was
/// scheduled, so the main-actor hand-off cannot race with the caller.
private func cursorWindowMotionCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else {
        return
    }

    // Only the address crosses the isolation boundary: the object it points at
    // is alive for as long as the registration, and the callback is delivered
    // on the main run loop the source was scheduled on.
    let address = UInt(bitPattern: UnsafeRawPointer(refcon))
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else {
            return
        }

        Unmanaged<AXWindowMotionObserver>
            .fromOpaque(pointer)
            .takeUnretainedValue()
            .handleWindowMotion()
    }
}
