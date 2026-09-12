import AppKit
import Foundation

/// Local-only overlay showcase: draws the software cursor at a fixed point on
/// **one** screen for a few seconds.
///
/// It exists because "the cursor is not visible" cannot be told apart from "the
/// cursor was never requested" by reading a tool result. The showcase is the
/// self-check for that question and for the cursor's look: it performs no AX
/// call, posts no event and activates no application, so it can run while a
/// real acceptance round is in progress.
///
/// The cursor (with its click pulse) is the whole macOS visual contract, the
/// same one the official Codex Computer Use binary ships.
///
/// Single-screen contract: exactly one screen is chosen (`--display N`, 1-based
/// like `screencapture -D`, default `NSScreen.main`). This entry never loops
/// over `NSScreen.screens` to build one panel per display - one process owns
/// exactly one cursor panel, placed on that screen.
///
/// CLI entry: `open-computer-use debug-cursor [--seconds N] [--display N]`.
@MainActor
public enum VisualCursorDebugShowcase {
    /// Size of the fake anchor rect the cursor points at, in the middle of the
    /// screen.
    nonisolated(unsafe) public static let targetSize = CGSize(width: 180, height: 56)
    /// Default hold, long enough to run `screencapture` a few times.
    nonisolated(unsafe) public static let defaultSeconds: TimeInterval = 5
    /// Hard cap so a stuck showcase can never occupy the user's screen.
    nonisolated(unsafe) public static let maximumSeconds: TimeInterval = 60

    @discardableResult
    public static func run(seconds: TimeInterval, display: Int? = nil) throws -> String {
        let screen = try resolveScreen(display: display)
        let hold = min(max(seconds, 0.5), maximumSeconds)

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        // Every exit path - normal, thrown or terminated - takes the overlay
        // off the screen before the process goes away.
        defer {
            SoftwareCursorOverlay.reset()
        }

        let screenStateFrame = screenStateFrame(for: screen)
        let localFrame = debugCursorTargetLocalFrame(screenStateFrame: screenStateFrame)

        // Target-state point for the cursor tip: inside the fake element, on the
        // same side a real click would land.
        let tipStatePoint = CGPoint(
            x: screenStateFrame.minX + localFrame.minX + (localFrame.width * 0.35),
            y: screenStateFrame.minY + localFrame.midY
        )
        let cursorTarget = makeVisualCursorTarget(
            at: tipStatePoint,
            targetWindowID: nil,
            targetWindowLayer: nil
        )

        SoftwareCursorOverlay.repositionCursor(to: cursorTarget.point, in: nil)

        // Screen-state rect is also the space `screencapture -R` uses, so the
        // printed rectangle can be pasted straight into a capture command.
        let captureRect = debugCursorCaptureRect(
            screenStateFrame: screenStateFrame,
            localFrame: localFrame
        )
        let summary = [
            "debug-cursor seconds=\(String(format: "%.1f", hold))",
            "display=\(NSScreen.screens.firstIndex(of: screen).map { $0 + 1 } ?? 1)",
            "target=\(describeRect(localFrame.offsetBy(dx: screenStateFrame.minX, dy: screenStateFrame.minY)))",
            "capture=\(describeRect(captureRect))",
            "screen=\(describeRect(screenStateFrame))",
        ].joined(separator: " ")
        print(summary)
        fflush(stdout)

        let deadline = Date().addingTimeInterval(hold)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return summary
    }

    /// Exactly one screen is ever selected. `display` is 1-based to match
    /// `screencapture -D`; `nil` follows `NSScreen.main`.
    static func resolveScreen(display: Int?) throws -> NSScreen {
        guard let display else {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                throw ComputerUseError.stateUnavailable("debug-cursor needs at least one attached screen")
            }

            return screen
        }

        guard display >= 1, display <= NSScreen.screens.count else {
            throw ComputerUseError.stateUnavailable(
                "debug-cursor --display must be between 1 and \(NSScreen.screens.count)"
            )
        }

        return NSScreen.screens[display - 1]
    }

    /// `NSScreen.frame` is AppKit (bottom-left origin) space, while element
    /// frames, window bounds and `screencapture -R` all use the CoreGraphics
    /// top-left display space.
    private static func screenStateFrame(for screen: NSScreen) -> CGRect {
        guard
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return screen.frame
        }

        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    }

    private static func describeRect(_ rect: CGRect) -> String {
        "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
    }
}

/// Fake anchor rect in window-local (top-left origin) space, centred on the
/// given screen-state frame. Pure so the showcase placement is testable.
func debugCursorTargetLocalFrame(
    screenStateFrame: CGRect,
    targetSize: CGSize = VisualCursorDebugShowcase.targetSize
) -> CGRect {
    CGRect(
        x: (screenStateFrame.width - targetSize.width) / 2,
        y: (screenStateFrame.height - targetSize.height) / 2,
        width: targetSize.width,
        height: targetSize.height
    )
}

/// Screen-state rectangle to hand to `screencapture -R`: the anchor rect plus
/// room for the cursor artwork and its fog. `screencapture` uses the same
/// top-left display space.
func debugCursorCaptureRect(
    screenStateFrame: CGRect,
    localFrame: CGRect,
    padding: CGFloat = 60
) -> CGRect {
    localFrame
        .insetBy(dx: -padding, dy: -padding)
        .offsetBy(dx: screenStateFrame.minX, dy: screenStateFrame.minY)
}
