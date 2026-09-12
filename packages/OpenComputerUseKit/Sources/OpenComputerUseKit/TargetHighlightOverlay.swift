import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Best-effort visual marker for the element a tool is about to act on.
///
/// It reuses the same borderless, non-activating panel model as
/// `SoftwareCursorOverlay`, so showing it can never move foreground focus or
/// swallow clicks. The marker is purely advisory: every failure path is a no-op
/// and no tool call ever depends on it.
@MainActor
enum TargetHighlightOverlay {
    /// Time the ring stays fully visible before it fades out. The task contract
    /// is "show before the action, fade 300-600ms later".
    static let defaultDisplayDuration: TimeInterval = 0.45
    private static let fadeInDuration: TimeInterval = 0.12
    private static let fadeOutDuration: TimeInterval = 0.35
    private static let minimumVisibleSide: CGFloat = 2

    private static var panel: NSPanel?
    private static var highlightView: TargetHighlightView?
    private static var hideTimer: Timer?

    private static var canPresentOverlay: Bool {
        !NSScreen.screens.isEmpty
    }

    /// Nothing is drawn unless the element frame actually overlaps the target
    /// window's visible rect; otherwise the ring would land on another window.
    static func showsTargetHighlight(localFrame: CGRect?, windowBounds: CGRect?) -> Bool {
        guard let localFrame, let visibleRect = windowLocalVisibleRect(windowBounds: windowBounds) else {
            return false
        }

        guard
            localFrame.width >= minimumVisibleSide,
            localFrame.height >= minimumVisibleSide,
            localFrame.width.isFinite,
            localFrame.height.isFinite
        else {
            return false
        }

        return localFrame.intersects(visibleRect)
    }

    /// Converts a window-local (top-left origin) rect into an AppKit global rect.
    /// Reuses the shared screen-state -> AppKit mapping instead of re-deriving it.
    static func appKitHighlightRect(
        localFrame: CGRect,
        windowBounds: CGRect,
        screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
    ) -> CGRect? {
        guard localFrame.width > 0, localFrame.height > 0 else {
            return nil
        }

        let stateMin = CGPoint(
            x: windowBounds.minX + localFrame.minX,
            y: windowBounds.minY + localFrame.minY
        )
        let stateMax = CGPoint(
            x: windowBounds.minX + localFrame.maxX,
            y: windowBounds.minY + localFrame.maxY
        )
        let appKitMin = screenStatePointToAppKitGlobalPoint(fromScreenStatePoint: stateMin, screenMappings: screenMappings)
        let appKitMax = screenStatePointToAppKitGlobalPoint(fromScreenStatePoint: stateMax, screenMappings: screenMappings)

        let rect = CGRect(
            x: min(appKitMin.x, appKitMax.x),
            y: min(appKitMin.y, appKitMax.y),
            width: abs(appKitMax.x - appKitMin.x),
            height: abs(appKitMax.y - appKitMin.y)
        )

        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        return rect
    }

    static func show(
        localFrame: CGRect?,
        windowBounds: CGRect?,
        targetWindow: CursorTargetWindow?,
        duration: TimeInterval = defaultDisplayDuration
    ) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        guard
            showsTargetHighlight(localFrame: localFrame, windowBounds: windowBounds),
            let localFrame,
            let windowBounds,
            let visibleRect = windowLocalVisibleRect(windowBounds: windowBounds),
            let globalRect = appKitHighlightRect(
                localFrame: localFrame.intersection(visibleRect),
                windowBounds: windowBounds
            )
        else {
            return
        }

        prepareWindowIfNeeded()
        guard let panel, let highlightView else {
            return
        }

        hideTimer?.invalidate()
        panel.level = NSWindow.Level(rawValue: targetWindow?.layer ?? 0)
        panel.setFrame(globalRect.insetBy(dx: -4, dy: -4), display: false)
        highlightView.frame = CGRect(origin: .zero, size: panel.frame.size)
        highlightView.needsDisplay = true

        if let targetWindow, SoftwareCursorOverlay.isWindowPresent(targetWindow.windowID) {
            panel.order(.above, relativeTo: Int(targetWindow.windowID))
        } else {
            panel.orderFront(nil)
        }

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            panel.animator().alphaValue = 1
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            fadeOut()
        }
    }

    static func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
    }

    /// Exposed for tests: the panel must never become key/main and must never
    /// intercept mouse events, otherwise the ring would steal the very focus the
    /// quiet path is trying to protect.
    static func makeTargetHighlightPanel() -> NSPanel {
        let panel = TargetHighlightPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }

    private static func prepareWindowIfNeeded() {
        guard panel == nil else {
            return
        }

        let panel = makeTargetHighlightPanel()
        let view = TargetHighlightView(frame: .zero)
        panel.contentView = view

        self.panel = panel
        self.highlightView = view
    }

    private static func fadeOut() {
        guard let panel else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        }
    }
}

private final class TargetHighlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TargetHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(2)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor)

        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.drawPath(using: .fillStroke)
    }
}
