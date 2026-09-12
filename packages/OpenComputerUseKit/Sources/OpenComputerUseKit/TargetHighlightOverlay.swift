import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import QuartzCore

/// Best-effort visual marker for the element a tool is about to act on.
///
/// It reuses the same borderless, non-activating panel model as
/// `SoftwareCursorOverlay`, so showing it can never move foreground focus or
/// swallow clicks. The marker is purely advisory: every failure path is a no-op
/// and no tool call ever depends on it.
///
/// Lifetime is deliberate rather than best-effort-at-exit: the ring is cleared
/// before every new action, it fades out on a deadline that does not depend on
/// the main run loop, and a watchdog withdraws it the moment its element or
/// window stops being real (a closed menu is the common case). That is why a
/// menu/popup target also gets a shorter deadline than a regular element.
@MainActor
enum TargetHighlightOverlay {
    /// Time the ring stays fully visible before it fades out. The task contract
    /// is "show before the action, fade 300-600ms later".
    static let defaultDisplayDuration: TimeInterval = 0.45
    private static let minimumVisibleSide: CGFloat = 2

    private static let presenter = TargetHighlightPanelPresenter()
    private static let controller = TargetHighlightLifetimeController(
        presentRing: { target in presenter.present(target) },
        fadeRing: { presenter.fadeOut() },
        withdrawPanel: { presenter.withdraw() },
        sample: { target in livenessSample(for: target) },
        makeTimer: { TargetHighlightDispatchTimer() }
    )

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

    /// Shows the ring for one approach. A new approach always replaces the
    /// previous ring, and anything that cannot be shown clears it as well, so a
    /// stale ring is never left behind.
    static func show(
        localFrame: CGRect?,
        windowBounds: CGRect?,
        targetWindow: CursorTargetWindow?,
        element: AXElementReference? = nil,
        role: String? = nil
    ) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            hide()
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
            hide()
            return
        }

        let ringTarget = TargetHighlightLifetimeController.RingTarget(
            globalRect: globalRect,
            level: targetWindow?.layer ?? 0,
            windowID: targetWindow?.windowID,
            element: element,
            isPopup: targetHighlightIsPopupRole(role) || targetHighlightIsPopupWindow(layer: targetWindow?.layer),
            expectedScreenFrame: element.flatMap { accessibilityScreenFrame(of: $0.element) }
        )

        controller.show(ringTarget)
    }

    static func hide() {
        controller.hide()
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
}

/// Live probe for the watchdog. It only reads: an element whose role no longer
/// resolves is gone, and everything else falls back to "still valid".
@MainActor
private func livenessSample(
    for target: TargetHighlightLifetimeController.RingTarget
) -> TargetHighlightLivenessSample {
    let windowPresent = target.windowID.map { SoftwareCursorOverlay.isWindowPresent($0) } ?? true

    guard let element = target.element?.element else {
        return TargetHighlightLivenessSample(isWindowPresent: windowPresent)
    }

    guard let role = accessibilityString(of: element, attribute: kAXRoleAttribute), !role.isEmpty else {
        return TargetHighlightLivenessSample(isWindowPresent: windowPresent, isElementValid: false)
    }

    return TargetHighlightLivenessSample(
        isWindowPresent: windowPresent,
        isElementValid: true,
        currentScreenFrame: accessibilityScreenFrame(of: element)
    )
}

private func accessibilityString(of element: AXUIElement, attribute: String) -> String? {
    accessibilityValue(of: element, attribute: attribute) as? String
}

/// Element frame in Accessibility (top-left origin) screen space.
func accessibilityScreenFrame(of element: AXUIElement) -> CGRect? {
    guard
        let positionValue = accessibilityValue(of: element, attribute: kAXPositionAttribute),
        let sizeValue = accessibilityValue(of: element, attribute: kAXSizeAttribute),
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
        return nil
    }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
        return nil
    }

    return CGRect(origin: origin, size: size)
}

private func accessibilityValue(of element: AXUIElement, attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }

    return value
}

@MainActor
private final class TargetHighlightPanelPresenter {
    private static let fadeInDuration: TimeInterval = 0.12

    private var panel: NSPanel?
    private var highlightView: TargetHighlightView?

    func present(_ target: TargetHighlightLifetimeController.RingTarget) {
        prepareWindowIfNeeded()

        guard let panel, let highlightView else {
            return
        }

        panel.level = NSWindow.Level(rawValue: target.level)
        panel.setFrame(target.globalRect.insetBy(dx: -4, dy: -4), display: false)
        highlightView.frame = CGRect(origin: .zero, size: panel.frame.size)
        highlightView.needsDisplay = true

        if let windowID = target.windowID, SoftwareCursorOverlay.isWindowPresent(windowID) {
            panel.order(.above, relativeTo: Int(windowID))
        } else {
            panel.orderFront(nil)
        }

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Starts the fade only. Ordering the panel out is the lifetime
    /// controller's hard deadline, so a starved animation can never leave the
    /// panel visible.
    func fadeOut() {
        guard let panel else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = TargetHighlightLifetimeController.defaultFadeOutDuration
            panel.animator().alphaValue = 0
        }
    }

    func withdraw() {
        panel?.orderOut(nil)
    }

    private func prepareWindowIfNeeded() {
        guard panel == nil else {
            return
        }

        let panel = TargetHighlightOverlay.makeTargetHighlightPanel()
        let view = TargetHighlightView(frame: .zero)
        panel.contentView = view

        self.panel = panel
        self.highlightView = view
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
