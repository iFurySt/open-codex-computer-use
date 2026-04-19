import AppKit
import CoreGraphics
import Foundation
import QuartzCore

public enum VisualCursorSupport {
    public static var isEnabled: Bool {
        visualCursorEnabled(environment: ProcessInfo.processInfo.environment)
    }

    static func performOnMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }
}

func visualCursorEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return true
    }

    return !["0", "false", "no", "off"].contains(rawValue)
}

struct CursorTargetWindow: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
}

struct CursorWindowGeometry {
    let windowSize: CGSize
    let tipAnchor: CGPoint

    func origin(forTipPosition tipPosition: CGPoint) -> CGPoint {
        CGPoint(
            x: tipPosition.x - tipAnchor.x,
            y: tipPosition.y - tipAnchor.y
        )
    }

    func tipPosition(forOrigin origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + tipAnchor.x,
            y: origin.y + tipAnchor.y
        )
    }
}

private struct ProcessedCursorImage {
    let image: NSImage
    let tipAnchor: CGPoint
}

private struct CursorArtwork {
    let image: NSImage?
    let geometry: CursorWindowGeometry
    let drawRect: CGRect
    let shadowBlur: CGFloat
    let shadowOffset: CGSize
    let shadowColor: NSColor
    let vectorScale: CGFloat

    static let active: CursorArtwork = loadOfficialSoftwareCursor() ?? fallback

    private static let fallback = CursorArtwork(
        image: nil,
        geometry: CursorWindowGeometry(
            windowSize: CGSize(width: 56, height: 56),
            tipAnchor: CGPoint(x: 10, y: 43)
        ),
        drawRect: CGRect(x: 0, y: 0, width: 56, height: 56),
        shadowBlur: 12,
        shadowOffset: CGSize(width: 0, height: -2),
        shadowColor: NSColor.black.withAlphaComponent(0.24),
        vectorScale: 0.40
    )

    private static func loadOfficialSoftwareCursor() -> CursorArtwork? {
        for bundle in officialCursorBundles() {
            guard let image = bundle.image(forResource: NSImage.Name("SoftwareCursor")),
                  let processed = processOfficialCursor(image)
            else {
                continue
            }

            let targetHeight: CGFloat = 26
            let scale = targetHeight / processed.image.size.height
            let imageSize = CGSize(
                width: processed.image.size.width * scale,
                height: processed.image.size.height * scale
            )
            let margin = NSEdgeInsets(top: 4, left: 3, bottom: 7, right: 5)
            let tipAnchor = CGPoint(
                x: margin.left + (processed.tipAnchor.x * scale),
                y: margin.bottom + (processed.tipAnchor.y * scale)
            )

            return CursorArtwork(
                image: processed.image,
                geometry: CursorWindowGeometry(
                    windowSize: CGSize(
                        width: imageSize.width + margin.left + margin.right,
                        height: imageSize.height + margin.top + margin.bottom
                    ),
                    tipAnchor: tipAnchor
                ),
                drawRect: CGRect(x: margin.left, y: margin.bottom, width: imageSize.width, height: imageSize.height),
                shadowBlur: 17,
                shadowOffset: CGSize(width: 0, height: -3),
                shadowColor: NSColor.black.withAlphaComponent(0.26),
                vectorScale: 0
            )
        }

        return nil
    }

    private static func officialCursorBundles() -> [Bundle] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/plugins/cache/openai-bundled/computer-use", isDirectory: true)

        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sortedVersions = versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }

        let bundlePaths = sortedVersions.flatMap { versionURL in
            [
                versionURL.appendingPathComponent("Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle", isDirectory: true),
                versionURL.appendingPathComponent("Codex Computer Use.app/Contents/Resources/Package_SlimCore.bundle", isDirectory: true),
            ]
        }

        return bundlePaths.compactMap { Bundle(path: $0.path) }
    }

    private static func processOfficialCursor(_ image: NSImage) -> ProcessedCursorImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            return nil
        }

        let highlightThreshold: CGFloat = 0.83
        let tint = NSColor(calibratedWhite: 0.92, alpha: 1).usingColorSpace(.deviceRGB) ?? NSColor.white
        let tintRed = UInt8(tint.redComponent * 255)
        let tintGreen = UInt8(tint.greenComponent * 255)
        let tintBlue = UInt8(tint.blueComponent * 255)

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var tipPixel = CGPoint.zero
        var tipScore = -CGFloat.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                guard alpha > 0.08, brightness > highlightThreshold else {
                    continue
                }

                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y)
                maxY = Swift.max(maxY, y)

                let score = (CGFloat(y) * 3) - CGFloat(x)
                if score > tipScore {
                    tipScore = score
                    tipPixel = CGPoint(x: x, y: y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        let padding = 3
        minX = Swift.max(0, minX - padding)
        minY = Swift.max(0, minY - padding)
        maxX = Swift.min(width - 1, maxX + padding)
        maxY = Swift.min(height - 1, maxY + padding)

        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1

        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: croppedWidth,
            pixelsHigh: croppedHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let bitmapData = output.bitmapData else {
            return nil
        }

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                let whiteness = CGFloat.clamped((brightness - highlightThreshold) / (1 - highlightThreshold), lower: 0, upper: 1)
                let resultAlpha = UInt8((alpha * whiteness) * 255)

                let localX = x - minX
                let localY = y - minY
                let offset = (localY * output.bytesPerRow) + (localX * 4)
                bitmapData[offset] = tintRed
                bitmapData[offset + 1] = tintGreen
                bitmapData[offset + 2] = tintBlue
                bitmapData[offset + 3] = resultAlpha
            }
        }

        let processed = NSImage(size: CGSize(width: croppedWidth, height: croppedHeight))
        processed.addRepresentation(output)

        return ProcessedCursorImage(
            image: processed,
            tipAnchor: CGPoint(
                x: tipPixel.x - CGFloat(minX),
                y: tipPixel.y - CGFloat(minY)
            )
        )
    }
}

@MainActor
enum SoftwareCursorOverlay {
    private static let artwork = CursorArtwork.active
    private static let baseHeading = 3 * CGFloat.pi / 4
    private static var panel: CursorPanel?
    private static var cursorView: SoftwareCursorView?
    private static var restingTipPosition: CGPoint?
    private static var displayedTipPosition: CGPoint?
    private static var activeTargetWindow: CursorTargetWindow?
    private static var visualDynamicsState: CursorVisualDynamicsState?
    private static var idleTimer: Timer?
    private static var hideTimer: Timer?
    private static var idlePhase: CGFloat = 0

    static func moveCursor(to targetPoint: CGPoint, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        stopIdleAnimation()
        cancelPendingHide()
        configureOrdering(relativeTo: targetWindow)

        let constrainedTarget = clampTipPosition(targetPoint)
        let startPoint = displayedTipPosition ?? defaultAppearancePoint(for: constrainedTarget)
        let now = CACurrentMediaTime()

        panel?.alphaValue = 1
        seedVisualDynamicsIfNeeded(at: startPoint, time: now)
        placeCursor(
            using: advanceVisualDynamics(
                toward: startPoint,
                at: now
            ),
            clickProgress: 0
        )

        if distanceBetween(startPoint, constrainedTarget) > 2 {
            animateMove(from: startPoint, to: constrainedTarget, relativeTo: targetWindow)
        }
    }

    static func pulseClick(at targetPoint: CGPoint, clickCount: Int, mouseButton: MouseButtonKind, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        configureOrdering(relativeTo: targetWindow)
        let constrainedTarget = clampTipPosition(targetPoint)
        let now = CACurrentMediaTime()
        seedVisualDynamicsIfNeeded(at: constrainedTarget, time: now)
        restingTipPosition = constrainedTarget
        animateClickPulse(at: constrainedTarget, clickCount: max(clickCount, 1), mouseButton: mouseButton)
        startIdleAnimation()
        scheduleHide(after: 0.55)
    }

    static func settle(at targetPoint: CGPoint, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        configureOrdering(relativeTo: targetWindow)
        let constrainedTarget = clampTipPosition(targetPoint)
        restingTipPosition = constrainedTarget
        placeCursor(
            using: advanceVisualDynamics(
                toward: constrainedTarget,
                at: CACurrentMediaTime()
            ),
            clickProgress: 0
        )
        startIdleAnimation()
        scheduleHide(after: 0.45)
    }

    static func reset() {
        stopIdleAnimation()
        cancelPendingHide()
        displayedTipPosition = nil
        restingTipPosition = nil
        activeTargetWindow = nil
        visualDynamicsState = nil
        panel?.orderOut(nil)
    }

    private static var canPresentOverlay: Bool {
        !NSScreen.screens.isEmpty
    }

    private static func prepareWindowIfNeeded() {
        guard panel == nil else {
            return
        }

        let panel = CursorPanel(
            contentRect: CGRect(origin: .zero, size: artwork.geometry.windowSize),
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

        let view = SoftwareCursorView(frame: CGRect(origin: .zero, size: artwork.geometry.windowSize), artwork: artwork)
        panel.contentView = view

        self.panel = panel
        self.cursorView = view
    }

    private static func configureOrdering(relativeTo targetWindow: CursorTargetWindow?) {
        guard let panel else {
            return
        }

        let effectiveTargetWindow = targetWindow.flatMap { targetWindow in
            isWindowPresent(targetWindow.windowID) ? targetWindow : nil
        }

        let desiredLevel = NSWindow.Level(rawValue: effectiveTargetWindow?.layer ?? 0)
        if panel.level != desiredLevel {
            panel.level = desiredLevel
        }

        if activeTargetWindow != effectiveTargetWindow || panel.isVisible == false {
            if let effectiveTargetWindow {
                panel.order(.above, relativeTo: Int(effectiveTargetWindow.windowID))
            } else {
                panel.orderFront(nil)
            }
            activeTargetWindow = effectiveTargetWindow
        }
    }

    private static func animateMove(from start: CGPoint, to end: CGPoint, relativeTo targetWindow: CursorTargetWindow?) {
        let candidate = bestMotionCandidate(from: start, to: end, relativeTo: targetWindow)
        let path = candidate.path
        // Binary-backed geometry and spring shape are used directly, but the final
        // wall-clock duration is still calibrated locally because the official
        // transaction-level duration mapping has not been fully recovered yet.
        let duration = OfficialCursorMotionModel.calibratedTravelDuration(
            distance: distanceBetween(start, end),
            measurement: candidate.measurement
        )
        let springTargetDuration = OfficialCursorMotionModel.closeEnoughTime
        let startTime = CACurrentMediaTime()
        var progress: CGFloat = 0
        var springState = CursorMotionSpringState()

        while true {
            refreshActiveOrderingIfNeeded()

            let elapsed = CGFloat(CACurrentMediaTime() - startTime)
            let normalizedElapsed = (elapsed / max(duration, 0.001)).clamped(to: 0...1)
            let springTime = normalizedElapsed * springTargetDuration
            (progress, springState) = CursorMotionProgressAnimator.advance(
                current: progress,
                state: springState,
                to: springTime
            )

            let sample = path.sample(at: progress)
            placeCursor(
                using: advanceVisualDynamics(
                    toward: sample.point,
                    at: CACurrentMediaTime()
                ),
                clickProgress: 0
            )

            if normalizedElapsed >= 1 || CursorMotionProgressAnimator.isCloseEnough(progress: progress) {
                break
            }

            pumpFrame()
        }

        placeCursor(
            using: advanceVisualDynamics(
                toward: end,
                at: CACurrentMediaTime()
            ),
            clickProgress: 0
        )
    }

    private static func bestMotionCandidate(from start: CGPoint, to end: CGPoint, relativeTo targetWindow: CursorTargetWindow?) -> CursorMotionCandidate {
        let bounds = motionBounds(from: start, to: end)
        let candidates = HeadingDrivenCursorMotionModel.makeCandidates(
            start: start,
            end: end,
            bounds: bounds,
            startForward: currentForwardVector(),
            endForward: restingForwardVector()
        )
        let defaultCandidate = HeadingDrivenCursorMotionModel.chooseBestCandidate(from: candidates)
            ?? CursorMotionCandidate(
                identifier: "legacy-fallback",
                kind: .base,
                side: 0,
                tableAScale: nil,
                tableBScale: nil,
                path: CursorMotionPath(start: start, end: end),
                measurement: CursorMotionPath(start: start, end: end).measure(bounds: bounds),
                score: 0
            )

        guard let targetWindow else {
            return defaultCandidate
        }

        let excludingWindowNumber = max(panel?.windowNumber ?? 0, 0)
        let evaluations = candidates.map { candidate in
            (
                candidate: candidate,
                hitCount: windowConstraintHitCount(
                    for: candidate.path,
                    relativeTo: targetWindow,
                    excludingWindowNumber: excludingWindowNumber
                )
            )
        }

        let totalSampleCount = candidates.first?.path.sampledConstraintPoints().count ?? 0
        let bestHitCount = evaluations.map(\.hitCount).max() ?? 0

        if bestHitCount == totalSampleCount, bestHitCount > 0 {
            return evaluations
                .filter { $0.hitCount == bestHitCount }
                .map(\.candidate)
                .sorted(by: candidatePreference)
                .first ?? defaultCandidate
        }

        if bestHitCount > 0 {
            return evaluations
                .filter { $0.hitCount == bestHitCount }
                .map(\.candidate)
                .sorted(by: candidatePreference)
                .first ?? defaultCandidate
        }

        return defaultCandidate
    }

    private static func currentForwardVector() -> CGVector {
        let renderRotation = cursorView?.rotation ?? 0
        return forwardVector(renderRotation: renderRotation)
    }

    private static func restingForwardVector() -> CGVector {
        forwardVector(renderRotation: 0)
    }

    private static func forwardVector(renderRotation: CGFloat) -> CGVector {
        let angle = baseHeading + renderRotation
        return CGVector(dx: cos(angle), dy: sin(angle))
    }

    private static func windowConstraintHitCount(
        for path: CursorMotionPath,
        relativeTo targetWindow: CursorTargetWindow,
        excludingWindowNumber: Int
    ) -> Int {
        path.sampledConstraintPoints().reduce(into: 0) { result, point in
            if windowID(at: point, excludingWindowNumber: excludingWindowNumber) == targetWindow.windowID {
                result += 1
            }
        }
    }

    private static func motionBounds(from start: CGPoint, to end: CGPoint) -> CGRect? {
        let startScreen = screen(containing: start) ?? NSScreen.main ?? NSScreen.screens.first
        let endScreen = screen(containing: end) ?? startScreen

        switch (startScreen, endScreen) {
        case let (startScreen?, endScreen?) where startScreen === endScreen:
            return startScreen.visibleFrame
        case let (startScreen?, endScreen?):
            return startScreen.visibleFrame.union(endScreen.visibleFrame)
        case let (screen?, nil), let (nil, screen?):
            return screen.visibleFrame
        default:
            return nil
        }
    }

    private static func candidatePreference(_ lhs: CursorMotionCandidate, _ rhs: CursorMotionCandidate) -> Bool {
        if lhs.measurement.staysInBounds != rhs.measurement.staysInBounds {
            return lhs.measurement.staysInBounds && !rhs.measurement.staysInBounds
        }
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.identifier < rhs.identifier
    }

    private static func windowID(at point: CGPoint, excludingWindowNumber: Int) -> CGWindowID? {
        let windowNumber = NSWindow.windowNumber(
            at: NSPoint(x: point.x, y: point.y),
            belowWindowWithWindowNumber: excludingWindowNumber
        )

        guard windowNumber > 0 else {
            return nil
        }

        return CGWindowID(windowNumber)
    }

    private static func isWindowPresent(_ windowID: CGWindowID) -> Bool {
        guard windowID != 0,
              let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        else {
            return false
        }

        return !windowInfo.isEmpty
    }

    private static func refreshActiveOrderingIfNeeded() {
        guard let activeTargetWindow, !isWindowPresent(activeTargetWindow.windowID) else {
            return
        }

        configureOrdering(relativeTo: nil)
    }

    private static func animateClickPulse(at point: CGPoint, clickCount: Int, mouseButton: MouseButtonKind) {
        let pulseBias: CGFloat = mouseButton == .right ? 0.82 : 1

        for pulse in 0..<clickCount {
            let duration = 0.16
            let startTime = CACurrentMediaTime()

            while true {
                let elapsed = CACurrentMediaTime() - startTime
                let rawProgress = min(max(elapsed / duration, 0), 1)
                let clickProgress = sin(rawProgress * .pi) * pulseBias

                placeCursor(
                    using: advanceVisualDynamics(
                        toward: point,
                        at: CACurrentMediaTime()
                    ),
                    clickProgress: clickProgress
                )

                if rawProgress >= 1 {
                    break
                }

                pumpFrame()
            }

            if pulse < clickCount - 1 {
                pause(for: 0.05)
            }
        }

        placeCursor(
            using: advanceVisualDynamics(
                toward: point,
                at: CACurrentMediaTime()
            ),
            clickProgress: 0
        )
    }

    private static func startIdleAnimation() {
        guard canPresentOverlay, let restingTipPosition else {
            return
        }

        idlePhase = 0
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard panel != nil, cursorView != nil else {
                    return
                }

                refreshActiveOrderingIfNeeded()

                idlePhase += 0.05
                let targetTipPosition = CGPoint(
                    x: restingTipPosition.x + (sin(idlePhase) * 1.6),
                    y: restingTipPosition.y + (cos(idlePhase * 0.47) * 0.7)
                )
                let idleAngleOffset = sin(idlePhase * 0.8) * 0.03

                placeCursor(
                    using: advanceVisualDynamics(
                        toward: targetTipPosition,
                        idleAngleOffset: idleAngleOffset,
                        at: CACurrentMediaTime()
                    ),
                    clickProgress: 0
                )
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer

        placeCursor(
            using: advanceVisualDynamics(
                toward: restingTipPosition,
                at: CACurrentMediaTime()
            ),
            clickProgress: 0
        )
    }

    private static func stopIdleAnimation() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private static func scheduleHide(after delay: TimeInterval) {
        cancelPendingHide()
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                hideOverlay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private static func cancelPendingHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private static func hideOverlay() {
        guard let panel else {
            return
        }

        stopIdleAnimation()
        cancelPendingHide()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.alphaValue = 1
                displayedTipPosition = nil
                restingTipPosition = nil
                activeTargetWindow = nil
                visualDynamicsState = nil
            }
        }
    }

    private static func defaultAppearancePoint(for targetPoint: CGPoint) -> CGPoint {
        clampTipPosition(
            CGPoint(
                x: targetPoint.x + 72,
                y: targetPoint.y - 54
            )
        )
    }

    private static func seedVisualDynamicsIfNeeded(at tipPosition: CGPoint, time: CFTimeInterval) {
        guard visualDynamicsState == nil else {
            return
        }

        visualDynamicsState = CursorVisualDynamicsAnimator.state(
            at: tipPosition,
            time: CGFloat(time)
        )
    }

    private static func advanceVisualDynamics(
        toward targetTipPosition: CGPoint,
        idleAngleOffset: CGFloat = 0,
        at time: CFTimeInterval
    ) -> CursorVisualRenderState {
        let clampedTarget = clampTipPosition(targetTipPosition)
        seedVisualDynamicsIfNeeded(at: clampedTarget, time: time)

        let result = CursorVisualDynamicsAnimator.advance(
            state: visualDynamicsState ?? CursorVisualDynamicsAnimator.state(at: clampedTarget, time: CGFloat(time)),
            targetTipPosition: clampedTarget,
            targetTime: CGFloat(time),
            idleAngleOffset: idleAngleOffset,
            baseHeading: baseHeading
        )
        visualDynamicsState = result.state
        return result.renderState
    }

    private static func placeCursor(using renderState: CursorVisualRenderState, clickProgress: CGFloat) {
        guard let panel, let cursorView else {
            return
        }

        panel.setFrameOrigin(artwork.geometry.origin(forTipPosition: renderState.tipPosition))
        cursorView.rotation = renderState.rotation
        cursorView.cursorBodyOffset = renderState.cursorBodyOffset
        cursorView.fogOffset = renderState.fogOffset
        cursorView.fogOpacity = renderState.fogOpacity
        cursorView.fogScale = renderState.fogScale
        cursorView.clickProgress = clickProgress
        cursorView.needsDisplay = true
        displayedTipPosition = renderState.tipPosition
    }

    private static func clampTipPosition(_ tipPosition: CGPoint) -> CGPoint {
        guard let screen = screen(containing: tipPosition) ?? NSScreen.main ?? NSScreen.screens.first else {
            return tipPosition
        }

        let visibleFrame = screen.visibleFrame
        let minX = visibleFrame.minX + artwork.geometry.tipAnchor.x
        let maxX = visibleFrame.maxX - (artwork.geometry.windowSize.width - artwork.geometry.tipAnchor.x)
        let minY = visibleFrame.minY + artwork.geometry.tipAnchor.y
        let maxY = visibleFrame.maxY - (artwork.geometry.windowSize.height - artwork.geometry.tipAnchor.y)

        return CGPoint(
            x: tipPosition.x.clamped(to: minX...maxX),
            y: tipPosition.y.clamped(to: minY...maxY)
        )
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func pumpFrame() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1 / 120))
    }

    private static func pause(for duration: TimeInterval) {
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < duration {
            pumpFrame()
        }
    }

    private static func distanceBetween(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

private final class CursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SoftwareCursorView: NSView {
    private let artwork: CursorArtwork

    var rotation: CGFloat = 0
    var cursorBodyOffset: CGVector = CGVector(dx: 0, dy: 0)
    var fogOffset: CGVector = CGVector(dx: 0, dy: 0)
    var fogOpacity: CGFloat = 0.12
    var fogScale: CGFloat = 1
    var clickProgress: CGFloat = 0

    init(frame frameRect: NSRect, artwork: CursorArtwork) {
        self.artwork = artwork
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

        let motionCompression = min(hypot(cursorBodyOffset.dx, cursorBodyOffset.dy) * 0.01, 0.02)
        let compression = (clickProgress * 0.05) + motionCompression
        let scaleX = 1 - compression
        let scaleY = 1 + (compression * 0.24)

        let anchor = artwork.geometry.tipAnchor
        let context = NSGraphicsContext.current?.cgContext
        let fogRect = CGRect(
            x: anchor.x - (12 * fogScale) + fogOffset.dx,
            y: anchor.y - (51 * fogScale) + fogOffset.dy,
            width: 24 * fogScale,
            height: 8 * fogScale
        )
        let fogOval = NSBezierPath(ovalIn: fogRect)
        NSGraphicsContext.saveGraphicsState()
        let ovalShadow = NSShadow()
        ovalShadow.shadowBlurRadius = (10 * fogScale) + (clickProgress * 2)
        ovalShadow.shadowOffset = CGSize(width: 0, height: -1)
        ovalShadow.shadowColor = NSColor.white.withAlphaComponent(fogOpacity * 0.55)
        ovalShadow.set()
        NSColor.white.withAlphaComponent(fogOpacity).setFill()
        fogOval.fill()
        NSGraphicsContext.restoreGraphicsState()

        context?.saveGState()
        context?.translateBy(x: cursorBodyOffset.dx, y: cursorBodyOffset.dy)
        context?.translateBy(x: anchor.x, y: anchor.y)
        context?.rotate(by: rotation)
        context?.scaleBy(x: scaleX, y: scaleY)
        context?.translateBy(x: -anchor.x, y: -anchor.y)

        if let image = artwork.image {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = artwork.shadowBlur + (clickProgress * 4)
            shadow.shadowOffset = artwork.shadowOffset
            shadow.shadowColor = artwork.shadowColor
            shadow.set()
            image.draw(in: artwork.drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let shadowPath = cursorPath(anchor: anchor, scale: artwork.vectorScale, xOffset: 2, yOffset: -2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = artwork.shadowBlur + (clickProgress * 5)
            shadow.shadowOffset = artwork.shadowOffset
            shadow.shadowColor = artwork.shadowColor
            shadow.set()
            NSColor.black.withAlphaComponent(0.22).setFill()
            shadowPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            let path = cursorPath(anchor: anchor, scale: artwork.vectorScale, xOffset: 0, yOffset: 0)
            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.97, alpha: 0.92),
                NSColor(calibratedWhite: 0.84, alpha: 0.90),
            ])!
            gradient.draw(in: path, angle: -78)

            NSColor(calibratedWhite: 1, alpha: 0.85).setStroke()
            path.lineWidth = 1.0
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }

        context?.restoreGState()

        if clickProgress > 0.01 {
            let ringRadius = 4 + (clickProgress * 7)
            let ringRect = CGRect(
                x: anchor.x - ringRadius,
                y: anchor.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            let ring = NSBezierPath(ovalIn: ringRect)
            NSColor.white.withAlphaComponent(0.22 * (1 - clickProgress * 0.45)).setStroke()
            ring.lineWidth = 1.0
            ring.stroke()
        }
    }

    private func cursorPath(anchor: CGPoint, scale: CGFloat, xOffset: CGFloat, yOffset: CGFloat) -> NSBezierPath {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: -79 * scale),
            CGPoint(x: 20 * scale, y: -60 * scale),
            CGPoint(x: 32 * scale, y: -91 * scale),
            CGPoint(x: 47 * scale, y: -84 * scale),
            CGPoint(x: 35 * scale, y: -55 * scale),
            CGPoint(x: 63 * scale, y: -50 * scale),
        ]

        let translated = points.map {
            CGPoint(
                x: anchor.x + $0.x + xOffset,
                y: anchor.y + $0.y + yOffset
            )
        }

        let path = NSBezierPath()
        path.move(to: translated[0])
        for point in translated.dropFirst() {
            path.line(to: point)
        }
        path.close()
        return path
    }
}
