import AppKit
import QuartzCore

/// An actual WindowServer window, confined to one virtual display. It is the only
/// OCU window exempted from the display stream's host-application exclusion.
@MainActor
final class VirtualDisplayCursorOverlay {
    private let panel: VirtualCursorPanel
    private let glyph = CALayer()
    private var motion = VirtualDisplayCursorMotion()
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var closed = false
    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    init(displayID: CGDirectDisplayID) throws {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { throw ComputerUseError.message("Virtual display is not available to AppKit") }
        panel = VirtualCursorPanel(contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true; view.layer?.masksToBounds = true
        glyph.contents = BrowserUseCursorArtwork.image
        glyph.bounds = CGRect(origin: .zero, size: BrowserUseCursorArtwork.size)
        glyph.anchorPoint = BrowserUseCursorArtwork.anchorPoint
        glyph.contentsScale = screen.backingScaleFactor
        glyph.actions = ["position": NSNull(), "hidden": NSNull(), "transform": NSNull()]
        glyph.isHidden = true
        view.layer?.addSublayer(glyph); panel.contentView = view
        // Keep a transparent window registered even while the glyph is hidden,
        // so the capture exception is stable across pause/turn-ended/resume.
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // A removed/rearranged screen may cause WindowServer to relocate
            // windows. Hide immediately; registry validation rebuilds capture.
            MainActor.assumeIsolated { self?.setTarget(nil) }
        }
    }

    func setTarget(_ point: CGPoint?) {
        guard !closed else { return }
        motion.setTarget(point, at: ProcessInfo.processInfo.systemUptime, logicalSize: panel.frame.size)
        render()
        guard motion.isMoving, timer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func render() {
        if let point = motion.sample(at: ProcessInfo.processInfo.systemUptime) {
            glyph.position = CGPoint(x: point.x * panel.frame.width, y: (1 - point.y) * panel.frame.height)
            glyph.isHidden = false
        } else { glyph.isHidden = true }
        if !motion.isMoving { timer?.invalidate(); timer = nil }
    }

    func close() {
        closed = true; timer?.invalidate(); timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        glyph.isHidden = true; panel.orderOut(nil); panel.close()
    }
}

private final class VirtualCursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Same path candidates and timing as the ordinary software cursor, sampled on a monotonic timeline.
/// Stored points are display-local AppKit points; callers use normalized Quartz coordinates.
struct VirtualDisplayCursorMotion {
    private var size = CGSize(width: 1920, height: 1080)
    private var position: CGPoint?
    private var target: CGPoint?
    private var path: CursorMotionPath?
    var isMoving: Bool { path != nil }
    private var began: TimeInterval = 0
    private var duration: CGFloat = 0
    private var progress: CGFloat = 0
    private var spring = CursorMotionSpringState()
    private var forward: CGVector = {
        let heading = visualCursorAppKitForwardHeading(renderRotation: 0)
        return CGVector(dx: cos(heading), dy: sin(heading))
    }()
    mutating func setTarget(_ point: CGPoint?, at time: TimeInterval, logicalSize: CGSize) {
        guard let point, point.x.isFinite, point.y.isFinite, logicalSize.width > 0, logicalSize.height > 0 else {
            self = .init(); return
        }
        _ = sample(at: time)
        if size != logicalSize { self = .init(); size = logicalSize }
        let end = CGPoint(x: min(max(point.x, 0), 1) * size.width, y: (1 - min(max(point.y, 0), 1)) * size.height)
        guard target != end else { return }
        target = end
        guard let start = position, hypot(end.x - start.x, end.y - start.y) > 0.5 else {
            position = end; path = nil; return
        }
        let heading = visualCursorAppKitForwardHeading(renderRotation: 0)
        let candidates = HeadingDrivenCursorMotionModel.makeCandidates(start: start, end: end,
            bounds: CGRect(origin: .zero, size: size), startForward: forward,
            endForward: CGVector(dx: cos(heading), dy: sin(heading)))
        let selected = HeadingDrivenCursorMotionModel.chooseBestCandidate(from: candidates)
        let curve = selected?.path ?? CursorMotionPath(start: start, end: end)
        path = curve
        duration = OfficialCursorMotionModel.calibratedTravelDuration(
            distance: hypot(end.x - start.x, end.y - start.y), measurement: selected?.measurement ?? curve.measure(bounds: nil))
        began = time; progress = 0; spring = .init()
    }
    mutating func sample(at time: TimeInterval) -> CGPoint? {
        if let path {
            let elapsed = max(time - began, 0)
            if elapsed >= Double(duration) {
                position = path.end; self.path = nil
            } else {
                (progress, spring) = CursorMotionProgressAnimator.advance(current: progress, state: spring,
                    to: CGFloat(elapsed) / max(duration, 0.001) * OfficialCursorMotionModel.closeEnoughTime)
                let value = path.sample(at: progress)
                position = value.point; forward = value.tangent
            }
        }
        return position.map { CGPoint(x: min(max($0.x / size.width, 0), 1), y: min(max(1 - $0.y / size.height, 0), 1)) }
    }
}
