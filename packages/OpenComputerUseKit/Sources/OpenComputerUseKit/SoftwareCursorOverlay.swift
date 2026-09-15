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

/// Default window in which a burst of actions is merged into at most one
/// cursor travel animation. `OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS=0`
/// restores one animation per action.
func visualCursorCoalesceWindowMilliseconds(environment: [String: String]) -> Double {
    let defaultMilliseconds = 400.0

    guard
        let rawValue = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawValue.isEmpty
    else {
        return defaultMilliseconds
    }

    guard let milliseconds = Double(rawValue), milliseconds.isFinite, milliseconds >= 0 else {
        return defaultMilliseconds
    }

    return milliseconds
}

func visualCursorCoalesceWindow(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> TimeInterval {
    visualCursorCoalesceWindowMilliseconds(environment: environment) / 1000
}

/// Two points is inside the glyph's own tip noise, so a target that lands that
/// close to the previous one counts as "the cursor is already there".
func visualCursorMoveEpsilonPoints() -> CGFloat {
    2
}

func defaultVisualCursorInitialTipPosition(
    windowOrigin: CGPoint = .zero,
    tipAnchor: CGPoint = SoftwareCursorGlyphMetrics.tipAnchor
) -> CGPoint {
    return CGPoint(
        x: windowOrigin.x + tipAnchor.x,
        y: windowOrigin.y + tipAnchor.y
    )
}

func visualCursorRenderBaseHeading(
    artworkNeutralHeading: CGFloat = SoftwareCursorGlyphMetrics.targetNeutralHeading
) -> CGFloat {
    artworkNeutralHeading
}

func visualCursorAppKitForwardHeading(
    renderRotation: CGFloat,
    artworkNeutralHeading: CGFloat = SoftwareCursorGlyphMetrics.targetNeutralHeading
) -> CGFloat {
    -artworkNeutralHeading - renderRotation
}

func visualCursorRuntimeRenderYAxisMultiplier() -> CGFloat {
    // Window placement uses AppKit global coordinates, but glyph render state is
    // still interpreted as CursorMotion's y-down screen state before drawing.
    -1
}

func visualCursorScreenStateVelocity(
    fromRuntimeVelocity velocity: CGVector,
    yAxisMultiplier: CGFloat
) -> CGVector {
    CGVector(dx: velocity.dx, dy: velocity.dy * yAxisMultiplier)
}

func visualCursorIdleRotationAmplitude() -> CGFloat {
    0.09
}

/// Short beat between the software cursor reaching its target and the next
/// advisory overlay (the target highlight ring) appearing. Codex Computer Use
/// signals cursor movement completion before the real interaction, so the ring
/// must only light up after the pointer visibly lands; the beat stays small
/// enough not to read as tool latency.
func visualCursorArrivalSettleDuration() -> TimeInterval {
    0.12
}

public struct VisualCursorObservationPoint: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(point: CGPoint) {
        x = point.x
        y = point.y
    }
}

public struct VisualCursorObservationSnapshot: Codable, Sendable {
    public let phase: String
    public let tipPosition: VisualCursorObservationPoint?
    public let restingTipPosition: VisualCursorObservationPoint?
    public let rotation: Double?
    public let timestamp: Double

    public init(
        phase: String,
        tipPosition: CGPoint?,
        restingTipPosition: CGPoint?,
        rotation: CGFloat?,
        timestamp: CFTimeInterval
    ) {
        self.phase = phase
        self.tipPosition = tipPosition.map(VisualCursorObservationPoint.init(point:))
        self.restingTipPosition = restingTipPosition.map(VisualCursorObservationPoint.init(point:))
        self.rotation = rotation.map(Double.init)
        self.timestamp = timestamp
    }
}

struct VisualCursorIdlePose {
    let tipPosition: CGPoint
    let angleOffset: CGFloat
}

func visualCursorIdlePose(restingTipPosition: CGPoint, phase: CGFloat) -> VisualCursorIdlePose {
    VisualCursorIdlePose(
        tipPosition: restingTipPosition,
        angleOffset: sin(phase * 0.8) * visualCursorIdleRotationAmplitude()
    )
}

public func visualCursorObservationFileURL(environment: [String: String]) -> URL? {
    guard
        let rawPath = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR_OBSERVATION_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawPath.isEmpty
    else {
        return nil
    }

    return URL(fileURLWithPath: rawPath)
}

public let openComputerUseTurnEndedNotificationName = Notification.Name("com.ifuryst.opencomputeruse.turn-ended")

public func postOpenComputerUseTurnEndedNotification() {
    DistributedNotificationCenter.default().postNotificationName(
        openComputerUseTurnEndedNotificationName,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

@MainActor
public func resetOpenComputerUseVisualCursor() {
    SoftwareCursorOverlay.reset()
}

struct CursorTargetWindow: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
}

/// Where the resting cursor sits inside its target window.
///
/// The global tip is only valid for the window frame it was derived from. The
/// overlay keeps the window-local offset instead, so a window that moves or
/// changes display can be followed by re-deriving the point from the live
/// frame rather than from the screen the cursor happened to be drawn on.
struct CursorRestingAnchor: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
    /// Screen-state (top-left origin) offset of the tip inside the window.
    let windowLocalPoint: CGPoint
    /// Screen-state window frame the offset was resolved against.
    let windowBounds: CGRect
}

/// The window the overlay currently subscribes to for move notifications.
@MainActor
private struct CursorWindowMotionObservation {
    let window: CursorTargetWindow
    let observer: CursorWindowMotionObserving
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

private struct CursorArtwork {
    let geometry: CursorWindowGeometry
    static let active = CursorArtwork(
        geometry: CursorWindowGeometry(
            windowSize: SoftwareCursorGlyphMetrics.windowSize,
            tipAnchor: SoftwareCursorGlyphMetrics.tipAnchor
        ),
    )
}

@MainActor
enum SoftwareCursorOverlay {
    private static let artwork = CursorArtwork.active

    /// Window size and glyph tip anchor; the real panel host sizes its panel
    /// from this, and the injected host in tests never needs it.
    static var artworkGeometry: CursorWindowGeometry { artwork.geometry }
    private static let renderBaseHeading = visualCursorRenderBaseHeading()
    private static let renderYAxisMultiplier = visualCursorRuntimeRenderYAxisMultiplier()
    /// Injected window-server seam. Production talks to a real `NSPanel`;
    /// tests inject a fake so the "visible for the whole turn" contract runs
    /// without a window server.
    private static var environment = CursorOverlayEnvironment.live
    private static var panelHost: CursorOverlayPanelHosting?
    private static var activationObserver: NSObjectProtocol?
    private static var restingTipPosition: CGPoint?
    private static var displayedTipPosition: CGPoint?
    /// Window-local anchor of the resting cursor, kept in step with every
    /// placement so a window move can re-derive the tip.
    private static var restingAnchor: CursorRestingAnchor?
    /// Read-only move watch requested for the action about to run. Armed once
    /// the cursor is actually presented.
    private static var pendingWindowObservation: CursorObservedWindow?
    private static var windowMotionObservation: CursorWindowMotionObservation?
    /// Guards the re-anchor fallback against re-entering the placement it calls.
    private static var isReanchoringFromWindowMotion = false
    private static var visualDynamicsState: CursorVisualDynamicsState?
    private static var idlePhase: CGFloat = 0
    private static var observationPhase = "hidden"
    /// Last render state actually handed to the view. An idle tick keeps
    /// producing the same state once the spring has converged, and redrawing
    /// that is pure churn.
    private static var lastAppliedRenderState: CursorVisualRenderState?
    private static var lastAppliedClickProgress: CGFloat?
    /// Every frame / level / ordering write goes through this gate: equal values
    /// never reach the window server.
    private static let panelWriteGate = CursorPanelWriteGate()
    /// Sole owner of the idle 60 Hz timer. It invalidates the previous timer
    /// before starting a new one, so an action can never leak a second writer.
    private static let idleDriver = CursorIdleDriver()

    static func moveCursor(
        to targetPoint: CGPoint,
        in targetWindow: CursorTargetWindow?,
        anchor: CursorRestingAnchor? = nil
    ) {
        guard environment.isVisualCursorEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        stopIdleAnimation()
        refreshTargetWindowAnchorIfScreenChanged()
        configureOrdering(relativeTo: targetWindow)
        rememberRestingAnchor(anchor, for: targetWindow)

        let constrainedTarget = clampTipPosition(targetPoint)
        let isFreshStart = displayedTipPosition == nil
        let startPoint = displayedTipPosition ?? defaultInitialTipPosition()
        let now = CACurrentMediaTime()
        idleDriver.markInteraction(at: now)

        observationPhase = "moving"
        panelHost?.alphaValue = 1
        if isFreshStart {
            visualDynamicsState = CursorVisualDynamicsAnimator.state(at: startPoint, time: CGFloat(now))
            placeCursor(using: initialRenderState(at: startPoint), clickProgress: 0)
        } else {
            seedVisualDynamicsIfNeeded(at: startPoint, time: now)
            placeCursor(
                using: advanceVisualDynamics(
                    toward: startPoint,
                    at: now
                ),
                clickProgress: 0
            )
        }

        if distanceBetween(startPoint, constrainedTarget) > 2 {
            animateMove(from: startPoint, to: constrainedTarget, relativeTo: targetWindow)
        }
    }

    /// Places the cursor on `targetPoint` without the Bezier travel.
    ///
    /// Used when consecutive actions are coalesced: the cursor has to be on the
    /// new target before the highlight ring appears, but replaying the travel
    /// animation for every step is what makes a long form look like the cursor
    /// is drifting everywhere. The visual-dynamics state is re-seeded on the
    /// target so the glyph cannot spring-glide in from its previous position.
    static func repositionCursor(
        to targetPoint: CGPoint,
        in targetWindow: CursorTargetWindow?,
        anchor: CursorRestingAnchor? = nil
    ) {
        guard environment.isVisualCursorEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        stopIdleAnimation()
        refreshTargetWindowAnchorIfScreenChanged()
        configureOrdering(relativeTo: targetWindow)
        rememberRestingAnchor(anchor, for: targetWindow)

        let constrainedTarget = clampTipPosition(targetPoint)
        let now = CACurrentMediaTime()
        idleDriver.markInteraction(at: now)
        visualDynamicsState = CursorVisualDynamicsAnimator.state(at: constrainedTarget, time: CGFloat(now))
        restingTipPosition = constrainedTarget
        observationPhase = "repositioned"
        panelHost?.alphaValue = 1
        placeCursor(using: initialRenderState(at: constrainedTarget), clickProgress: 0)
        startIdleAnimation()
    }

    static func pulseClick(
        at targetPoint: CGPoint,
        clickCount: Int,
        mouseButton: MouseButtonKind,
        in targetWindow: CursorTargetWindow?,
        anchor: CursorRestingAnchor? = nil
    ) {
        guard environment.isVisualCursorEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        configureOrdering(relativeTo: targetWindow)
        rememberRestingAnchor(anchor, for: targetWindow)
        let constrainedTarget = clampTipPosition(
            liveTargetPoint(targetPoint, window: targetWindow, anchor: anchor)
        )
        let now = CACurrentMediaTime()
        idleDriver.markInteraction(at: now)
        seedVisualDynamicsIfNeeded(at: constrainedTarget, time: now)
        restingTipPosition = constrainedTarget
        observationPhase = "pulse"
        animateClickPulse(at: constrainedTarget, clickCount: max(clickCount, 1), mouseButton: mouseButton)
        startIdleAnimation()
    }

    static func settle(
        at targetPoint: CGPoint,
        in targetWindow: CursorTargetWindow?,
        anchor: CursorRestingAnchor? = nil
    ) {
        guard environment.isVisualCursorEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        configureOrdering(relativeTo: targetWindow)
        rememberRestingAnchor(anchor, for: targetWindow)
        let constrainedTarget = clampTipPosition(
            liveTargetPoint(targetPoint, window: targetWindow, anchor: anchor)
        )
        idleDriver.markInteraction(at: CACurrentMediaTime())
        restingTipPosition = constrainedTarget
        observationPhase = "settling"
        placeCursor(
            using: advanceVisualDynamics(
                toward: constrainedTarget,
                at: CACurrentMediaTime()
            ),
            clickProgress: 0
        )
        startIdleAnimation()
    }

    /// Pumps the main run loop for a short beat after `moveCursor` so the
    /// arrival frame renders before the next overlay appears. Callers must
    /// already be on the main thread, matching `moveCursor` / `settle`.
    static func waitForArrivalSettle(duration: TimeInterval = visualCursorArrivalSettleDuration()) {
        guard environment.isVisualCursorEnabled, canPresentOverlay else {
            return
        }

        let deadline = CACurrentMediaTime() + max(duration, 0)
        while CACurrentMediaTime() < deadline {
            pumpFrame()
        }
    }

    /// The only place the cursor leaves the screen besides
    /// `OPEN_COMPUTER_USE_VISUAL_CURSOR=0`: the turn boundary (`turn-ended`) or
    /// an explicit reset. There is deliberately no inactivity timer — a turn
    /// routinely idles for minutes between tool calls, and a cursor that fades
    /// out mid-turn reads as a lost cursor.
    static func reset() {
        stopIdleAnimation()
        // The gate remembers where the cursor last travelled; a reset hides the
        // cursor, so the next action must animate again.
        VisualCursorMoveCoalescer.shared.reset()
        forgetPresentationState()
        writeObservationSnapshot(tipPosition: nil, rotation: nil)
        dumpDebugStatsIfEnabled()
        panelHost?.orderOut()
    }

    /// Test seam: installs `environment` and drops any previously installed
    /// panel host, so a fake can never leak into the live window-server path.
    static func installEnvironmentForTesting(_ environment: CursorOverlayEnvironment) {
        reset()
        panelHost = nil
        Self.environment = environment
    }

    /// A hidden cursor owns no presentation state: the next show must write the
    /// frame, the level and the ordering again instead of trusting stale values.
    private static func forgetPresentationState() {
        displayedTipPosition = nil
        restingTipPosition = nil
        restingAnchor = nil
        visualDynamicsState = nil
        lastAppliedRenderState = nil
        lastAppliedClickProgress = nil
        isReanchoringFromWindowMotion = false
        stopWindowMotionObservation()
        panelWriteGate.reset()
        observationPhase = "hidden"
    }

    /// Optional field diagnosis: the counters are the only outside proof that an
    /// idle overlay stopped touching the panel.
    private static func dumpDebugStatsIfEnabled() {
        guard visualCursorDebugStatsEnabled() else {
            return
        }

        let stats = CursorOverlayDebugStats(
            frameWrites: panelWriteGate.frameWriteCount,
            skippedFrameWrites: panelWriteGate.skippedFrameWriteCount,
            levelWrites: panelWriteGate.levelWriteCount,
            reorders: panelWriteGate.reorderCount,
            skippedReorders: panelWriteGate.skippedReorderCount,
            idleTicks: idleDriver.idleTickCount,
            suppressedIdleTicks: idleDriver.suppressedIdleTickCount,
            invalidatedIdleTimers: idleDriver.invalidatedTimerCount
        )
        fputs("\(cursorOverlayDebugStatsLine(stats))\n", stderr)
    }

    private static var canPresentOverlay: Bool {
        environment.canPresentOverlay
    }

    private static func prepareWindowIfNeeded() {
        guard panelHost == nil else {
            return
        }

        panelHost = environment.makePanelHost()
        installActivationObserverIfNeeded()
    }

    /// Another app becoming active is the moment the window server re-stacks
    /// every window at the cursor's level. The cursor must survive it, so the
    /// panel is re-asserted front — without touching its frame and without
    /// waiting for the next tool call.
    private static func installActivationObserverIfNeeded() {
        guard environment.installsActivationObserver, activationObserver == nil else {
            return
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                workspaceDidActivateApplication()
            }
        }
    }

    /// Internal rather than private so the contract is unit-testable without
    /// posting a real workspace notification.
    static func workspaceDidActivateApplication() {
        reassertCursorVisibility()
    }

    /// Unconditional re-assert of "the cursor is on screen right now". It never
    /// writes a frame and never changes the level; it only re-orders the panel
    /// so a system-level restack cannot leave it behind another app's windows.
    private static func reassertCursorVisibility() {
        guard let panelHost, panelHost.isVisible, displayedTipPosition != nil else {
            return
        }

        if let anchor = panelWriteGate.activeTargetWindow,
           environment.isWindowPresent(anchor.windowID)
        {
            panelHost.orderAbove(windowID: anchor.windowID)
            return
        }

        panelHost.orderFront()
    }

    // MARK: - Window move / display change

    /// Read-only move watch for the window the next action targets.
    ///
    /// Called from the service with the accessibility element the snapshot was
    /// rendered from. It is only a request: the watch is armed once a cursor is
    /// actually presented, and dropped with the presentation state.
    static func observeTargetWindow(_ observed: CursorObservedWindow) {
        guard environment.isVisualCursorEnabled, canPresentOverlay, observed.windowID != 0 else {
            return
        }

        pendingWindowObservation = observed
        armWindowMotionObservationIfNeeded(for: CursorTargetWindow(windowID: observed.windowID, layer: observed.layer))
    }

    private static func armWindowMotionObservationIfNeeded(for targetWindow: CursorTargetWindow?) {
        guard panelHost != nil,
              let pending = pendingWindowObservation,
              pending.windowID == targetWindow?.windowID
        else {
            return
        }

        if let active = windowMotionObservation, active.window.windowID == pending.windowID {
            return
        }

        windowMotionObservation?.observer.stop()
        windowMotionObservation = nil

        guard let observer = environment.makeWindowMotionObserver() else {
            return
        }

        observer.observe(pid: pending.pid, window: pending.element) {
            targetWindowDidMove()
        }
        windowMotionObservation = CursorWindowMotionObservation(
            window: CursorTargetWindow(windowID: pending.windowID, layer: pending.layer),
            observer: observer
        )
    }

    private static func stopWindowMotionObservation() {
        windowMotionObservation?.observer.stop()
        windowMotionObservation = nil
        pendingWindowObservation = nil
    }

    /// Internal rather than private so the follow-the-window contract is
    /// unit-testable without a real accessibility observer.
    static func targetWindowDidMove() {
        // Bumped before the guards below: a travel has to be able to abort even
        // when the resting anchor no longer matches.
        windowMotionGeneration &+= 1

        // `applyLiveWindowAnchor` re-checks that the resting anchor belongs to
        // this window, so a placement for another target can never drag the
        // cursor to a stale window.
        guard let window = windowMotionObservation?.window,
              restingAnchor?.windowID == window.windowID,
              panelHost?.isVisible == true
        else {
            return
        }

        guard let liveBounds = environment.windowBounds(window.windowID) else {
            return
        }

        guard liveBounds != restingAnchor?.windowBounds else {
            return
        }

        applyLiveWindowAnchor(liveBounds, window: window)
    }

    /// Counts accessibility move notifications, so a travel that is already
    /// running can tell that the window moved under it.
    private static var windowMotionGeneration = 0

    /// Screen-state frame of the observed window, read from its accessibility
    /// element instead of the window list.
    private static func observedWindowFrameFromAccessibility() -> CGRect? {
        guard let element = pendingWindowObservation?.element else {
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
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    /// The window's current frame, preferring the accessibility element (which
    /// reflects a move immediately) over the window list (measured lagging by
    /// about a second).
    private static func liveWindowFrame(for windowID: CGWindowID) -> CGRect? {
        observedWindowFrameFromAccessibility() ?? environment.windowBounds(windowID)
    }

    /// Re-derive a cursor point that was computed from a snapshot taken before
    /// the target window moved.
    private static func liveTargetPoint(
        _ targetPoint: CGPoint,
        window: CursorTargetWindow?,
        anchor: CursorRestingAnchor?
    ) -> CGPoint {
        guard let window,
              let anchor,
              anchor.windowID == window.windowID,
              let liveFrame = liveWindowFrame(for: window.windowID),
              liveFrame != anchor.windowBounds,
              liveFrame.width > 0,
              liveFrame.height > 0
        else {
            return targetPoint
        }

        let localPoint = CGPoint(
            x: anchor.windowLocalPoint.x.clamped(to: 0...liveFrame.width),
            y: anchor.windowLocalPoint.y.clamped(to: 0...liveFrame.height)
        )
        let screenStatePoint = CGPoint(x: liveFrame.minX + localPoint.x, y: liveFrame.minY + localPoint.y)
        return environment.screenStateToAppKitPoint(screenStatePoint)
    }

    /// Stop a travel whose window moved under it, and land the cursor on the
    /// window instead of finishing the path towards the screen it just left.
    private static func abortTravelOntoObservedWindow(_ targetWindow: CursorTargetWindow?) {
        guard let window = targetWindow,
              let frame = liveWindowFrame(for: window.windowID),
              frame.width > 0,
              frame.height > 0
        else {
            return
        }

        let localPoint: CGPoint
        if let anchor = restingAnchor, anchor.windowID == window.windowID {
            localPoint = CGPoint(
                x: anchor.windowLocalPoint.x.clamped(to: 0...frame.width),
                y: anchor.windowLocalPoint.y.clamped(to: 0...frame.height)
            )
        } else {
            localPoint = CGPoint(x: frame.width / 2, y: frame.height / 2)
        }

        isReanchoringFromWindowMotion = true
        defer { isReanchoringFromWindowMotion = false }

        repositionCursor(
            to: environment.screenStateToAppKitPoint(
                CGPoint(x: frame.minX + localPoint.x, y: frame.minY + localPoint.y)
            ),
            in: window,
            anchor: CursorRestingAnchor(
                windowID: window.windowID,
                layer: window.layer,
                windowLocalPoint: localPoint,
                windowBounds: frame
            )
        )
    }

    /// Fallback for a move no notification ever reported.
    ///
    /// Apps are free not to post `AXWindowMoved`, so before every action the
    /// overlay re-checks the one invariant the user actually sees: the cursor
    /// has to be on the display that owns the target window. A mismatch
    /// re-derives the tip from the live frame and re-places the panel.
    static func refreshTargetWindowAnchorIfScreenChanged() {
        guard !isReanchoringFromWindowMotion,
              let anchor = restingAnchor,
              let window = windowMotionObservation?.window,
              window.windowID == anchor.windowID,
              panelHost?.isVisible == true,
              let displayedTipPosition
        else {
            return
        }

        guard let liveBounds = environment.windowBounds(anchor.windowID) else {
            return
        }

        guard cursorOverlayScreenMismatch(
            panelTip: displayedTipPosition,
            targetWindowOrigin: environment.screenStateToAppKitPoint(liveBounds.origin),
            screenIndexContaining: environment.screenIndex
        ) else {
            return
        }

        applyLiveWindowAnchor(liveBounds, window: window)
    }

    /// Re-derives the resting tip from the live window frame and re-places the
    /// cursor on the window own display. Never hides the overlay: a window that
    /// crossed displays keeps its cursor, just on the right screen.
    private static func applyLiveWindowAnchor(_ liveBounds: CGRect, window: CursorTargetWindow) {
        guard let anchor = restingAnchor, anchor.windowID == window.windowID else {
            return
        }

        // A resize can leave the old window-local offset outside the window;
        // keep the cursor on the window instead of pointing at nothing.
        let windowLocalPoint = CGPoint(
            x: anchor.windowLocalPoint.x.clamped(to: 0...max(liveBounds.width, 0)),
            y: anchor.windowLocalPoint.y.clamped(to: 0...max(liveBounds.height, 0))
        )
        let screenStatePoint = CGPoint(
            x: liveBounds.minX + windowLocalPoint.x,
            y: liveBounds.minY + windowLocalPoint.y
        )
        let appKitPoint = environment.screenStateToAppKitPoint(screenStatePoint)

        isReanchoringFromWindowMotion = true
        defer { isReanchoringFromWindowMotion = false }
        repositionCursor(
            to: appKitPoint,
            in: window,
            anchor: CursorRestingAnchor(
                windowID: window.windowID,
                layer: window.layer,
                windowLocalPoint: windowLocalPoint,
                windowBounds: liveBounds
            )
        )
    }

    /// A placement that carries no anchor (debug entry, fixture path) must not
    /// erase the anchor an action already established.
    private static func rememberRestingAnchor(
        _ anchor: CursorRestingAnchor?,
        for targetWindow: CursorTargetWindow?
    ) {
        guard let anchor, anchor.windowID == targetWindow?.windowID else {
            return
        }

        restingAnchor = anchor
    }

    /// Levels and restacks the panel for an explicit show or target-window
    /// change.
    ///
    /// None of this may happen on an idle tick: the write gate turns both the
    /// level write and the restack into no-ops while the target window is
    /// unchanged, and `refreshActiveOrderingIfNeeded` no longer forces one.
    private static func configureOrdering(relativeTo targetWindow: CursorTargetWindow?) {
        guard let panelHost else {
            return
        }

        armWindowMotionObservationIfNeeded(for: targetWindow)

        let effectiveTargetWindow = targetWindow.flatMap { targetWindow in
            environment.isWindowPresent(targetWindow.windowID) ? targetWindow : nil
        }
        let ordering = cursorPanelOrdering(
            targetWindow: effectiveTargetWindow,
            baseLevel: cursorOverlayBaseLevel
        )

        if panelWriteGate.levelWrite(for: ordering.level) {
            panelHost.setLevel(ordering.level)
        }

        guard panelWriteGate.markOrdering(
            activeTargetWindow: ordering.anchorWindow,
            panelIsVisible: panelHost.isVisible
        ) else {
            return
        }

        if let anchorWindow = ordering.anchorWindow {
            panelHost.orderAbove(windowID: anchorWindow.windowID)
        } else {
            panelHost.orderFront()
        }
    }

    private static func animateMove(from start: CGPoint, to end: CGPoint, relativeTo targetWindow: CursorTargetWindow?) {
        let candidate = bestMotionCandidate(from: start, to: end, relativeTo: targetWindow)
        let path = candidate.path
        // Use the recovered official progress spring timing instead of the older
        // distance-compressed local duration, otherwise medium and long moves feel
        // noticeably faster than the bundled app.
        let duration = OfficialCursorMotionModel.calibratedTravelDuration(
            distance: distanceBetween(start, end),
            measurement: candidate.measurement
        )
        let springTargetDuration = OfficialCursorMotionModel.closeEnoughTime
        let startTime = CACurrentMediaTime()
        var progress: CGFloat = 0
        var springState = CursorMotionSpringState()
        let startFrame = targetWindow.flatMap { environment.windowBounds($0.windowID) }
        let startGeneration = windowMotionGeneration

        while true {
            refreshActiveOrderingIfNeeded()

            if windowMotionGeneration != startGeneration {
                abortTravelOntoObservedWindow(targetWindow)
                return
            }

            // The travel holds the main thread, so the move notification that
            // already re-anchored the resting cursor cannot stop it: the next
            // frame would write the stale sample back. Detect the frame change
            // here, land on the live frame and abandon the rest of the path.
            if let window = targetWindow {
                let liveFrame = environment.windowBounds(window.windowID)
                if cursorTravelMustAbort(startFrame: startFrame, liveFrame: liveFrame), let liveFrame {
                    applyLiveWindowAnchor(liveFrame, window: window)
                    refreshTargetWindowAnchorIfScreenChanged()
                    return
                }
            }

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

        let excludingWindowNumber = max(panelHost?.windowNumber ?? 0, 0)
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
        let renderRotation = panelHost?.cursorRotation ?? 0
        return forwardVector(renderRotation: renderRotation)
    }

    private static func restingForwardVector() -> CGVector {
        forwardVector(renderRotation: 0)
    }

    private static func forwardVector(renderRotation: CGFloat) -> CGVector {
        let angle = visualCursorAppKitForwardHeading(renderRotation: renderRotation)
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

    /// Whether the window the cursor wants to float above still exists.
    static func isWindowPresent(_ windowID: CGWindowID) -> Bool {
        guard windowID != 0,
              let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        else {
            return false
        }

        return !windowInfo.isEmpty
    }

    /// Only reacts to the target window going away. It deliberately does not
    /// restack the panel above a live target window: doing that once per frame
    /// is what reads as the arrow twitching, and it would re-order the overlay
    /// on every idle tick.
    private static func refreshActiveOrderingIfNeeded() {
        guard let activeTargetWindow = panelWriteGate.activeTargetWindow else {
            return
        }

        guard !isWindowPresent(activeTargetWindow.windowID) else {
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

    /// Starts the bounded post-action idle beat.
    ///
    /// The tick is a no-op outside the beat: no ordering refresh, no level
    /// change, and the frame write disappears as soon as the resting origin stops
    /// changing. `CursorIdleDriver` invalidates the timer the moment the beat
    /// ends and guarantees only one timer can ever be alive.
    private static func startIdleAnimation() {
        // Stop first: the guard below can bail out, and a driver left running
        // after that would keep writing the panel forever.
        stopIdleAnimation()

        guard canPresentOverlay, let restingTipPosition else {
            return
        }

        observationPhase = "idle"
        idlePhase = 0

        let now = CACurrentMediaTime()
        idleDriver.startIdleAnimation(now: now, window: visualCursorIdleSwayWindow()) {
            guard panelHost != nil else {
                return
            }

            guard let restingTipPosition = SoftwareCursorOverlay.restingTipPosition else {
                return
            }

            observationPhase = "idle"
            idlePhase += 0.05
            let idlePose = visualCursorIdlePose(
                restingTipPosition: restingTipPosition,
                phase: idlePhase
            )

            placeCursor(
                using: advanceVisualDynamics(
                    toward: idlePose.tipPosition,
                    idleAngleOffset: idlePose.angleOffset,
                    at: CACurrentMediaTime()
                ),
                clickProgress: 0
            )
        }

        placeCursor(
            using: advanceVisualDynamics(
                toward: restingTipPosition,
                at: now
            ),
            clickProgress: 0
        )
    }

    private static func stopIdleAnimation() {
        idleDriver.stopIdleAnimation()
    }

    private static func defaultInitialTipPosition() -> CGPoint {
        defaultVisualCursorInitialTipPosition(
            windowOrigin: .zero,
            tipAnchor: artwork.geometry.tipAnchor
        )
    }

    private static func initialRenderState(at tipPosition: CGPoint) -> CursorVisualRenderState {
        CursorVisualRenderState(
            tipPosition: tipPosition,
            rotation: 0,
            cursorBodyOffset: CGVector(dx: 0, dy: 0),
            fogOffset: CGVector(dx: 0, dy: 0),
            fogOpacity: CursorVisualDynamicsConfiguration.officialInspired.fogOpacityBase,
            fogScale: 1
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
            baseHeading: renderBaseHeading,
            renderYAxisMultiplier: renderYAxisMultiplier
        )
        visualDynamicsState = result.state
        return result.renderState
    }

    /// The only place the overlay writes a frame.
    ///
    /// The origin is aligned to whole points and skipped when it did not change,
    /// and the view is only re-rasterised when the render state itself changed —
    /// moving the panel is enough to move the glyph, because the drawing is
    /// bounds-relative. Together those make a converged idle cursor perform zero
    /// window-server work per tick.
    private static func placeCursor(using renderState: CursorVisualRenderState, clickProgress: CGFloat) {
        guard let panelHost else {
            return
        }

        let frameWrite = panelWriteGate.frameWrite(
            forTipPosition: renderState.tipPosition,
            tipAnchor: artwork.geometry.tipAnchor
        )
        if frameWrite.didChange {
            panelHost.setFrameOrigin(frameWrite.origin)
        }

        if renderState != lastAppliedRenderState || clickProgress != lastAppliedClickProgress {
            panelHost.apply(renderState: renderState, clickProgress: clickProgress)
            lastAppliedRenderState = renderState
            lastAppliedClickProgress = clickProgress
        }

        displayedTipPosition = renderState.tipPosition
        writeObservationSnapshot(
            tipPosition: renderState.tipPosition,
            rotation: renderState.rotation
        )
    }

    private static func writeObservationSnapshot(tipPosition: CGPoint?, rotation: CGFloat?) {
        guard
            let url = visualCursorObservationFileURL(environment: ProcessInfo.processInfo.environment)
        else {
            return
        }

        let snapshot = VisualCursorObservationSnapshot(
            phase: observationPhase,
            tipPosition: tipPosition,
            restingTipPosition: restingTipPosition,
            rotation: rotation,
            timestamp: CACurrentMediaTime()
        )

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Observation is debug-only and must not affect tool execution.
        }
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

// MARK: - Window-server seam

/// Everything SoftwareCursorOverlay needs from the window server.
///
/// The overlay owns *when* the cursor is on screen; the host only performs the
/// AppKit call. Keeping that boundary explicit is what lets the "visible for the
/// whole turn" contract run in unit tests without a real panel.
@MainActor
protocol CursorOverlayPanelHosting: AnyObject {
    var isVisible: Bool { get }
    var alphaValue: CGFloat { get set }
    var windowNumber: Int { get }
    var cursorRotation: CGFloat { get }

    func setLevel(_ level: NSWindow.Level)
    func setFrameOrigin(_ origin: CGPoint)
    func orderFront()
    func orderAbove(windowID: CGWindowID)
    func orderOut()
    func apply(renderState: CursorVisualRenderState, clickProgress: CGFloat)
}

/// The real host: one borderless, click-through, never-key panel.
@MainActor
final class CursorPanelHost: CursorOverlayPanelHosting {
    private let panel: CursorPanel
    private let cursorView: SoftwareCursorView

    init(windowSize: CGSize) {
        let panel = CursorPanel(
            contentRect: CGRect(origin: .zero, size: windowSize),
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

        let view = SoftwareCursorView(frame: CGRect(origin: .zero, size: windowSize))
        panel.contentView = view

        self.panel = panel
        self.cursorView = view
    }

    var isVisible: Bool { panel.isVisible }
    var windowNumber: Int { panel.windowNumber }
    var cursorRotation: CGFloat { cursorView.rotation }

    var alphaValue: CGFloat {
        get { panel.alphaValue }
        set { panel.alphaValue = newValue }
    }

    func setLevel(_ level: NSWindow.Level) { panel.level = level }
    func setFrameOrigin(_ origin: CGPoint) { panel.setFrameOrigin(origin) }
    func orderFront() { panel.orderFront(nil) }
    func orderAbove(windowID: CGWindowID) { panel.order(.above, relativeTo: Int(windowID)) }
    func orderOut() { panel.orderOut(nil) }

    func apply(renderState: CursorVisualRenderState, clickProgress: CGFloat) {
        cursorView.rotation = renderState.rotation
        cursorView.cursorBodyOffset = renderState.cursorBodyOffset
        cursorView.fogOffset = renderState.fogOffset
        cursorView.fogOpacity = renderState.fogOpacity
        cursorView.fogScale = renderState.fogScale
        cursorView.clickProgress = clickProgress
        cursorView.needsDisplay = true
    }
}

/// Injected inputs of the overlay. Production uses the live environment; tests
/// replace the panel host and the window-presence probe to drive activation /
/// target-window loss without a window server.
@MainActor
struct CursorOverlayEnvironment {
    var isVisualCursorEnabled: Bool
    var canPresentOverlay: Bool
    var installsActivationObserver: Bool
    var isWindowPresent: (CGWindowID) -> Bool
    var makePanelHost: () -> CursorOverlayPanelHosting
    /// Live frame of the target window, on screen or not. Injected so a window
    /// move can be driven in tests without a window server.
    var windowBounds: (CGWindowID) -> CGRect? = { _ in nil }
    /// Screen-state point to AppKit global point, the same conversion the
    /// service uses to place the cursor.
    var screenStateToAppKitPoint: (CGPoint) -> CGPoint = { $0 }
    /// Which display contains a point, or nil when none does.
    var screenIndex: (CGPoint) -> Int? = { _ in nil }
    /// Nil when the read-only move watch is switched off.
    var makeWindowMotionObserver: () -> CursorWindowMotionObserving? = { nil }

    static var live: CursorOverlayEnvironment {
        CursorOverlayEnvironment(
            isVisualCursorEnabled: VisualCursorSupport.isEnabled,
            canPresentOverlay: !NSScreen.screens.isEmpty,
            installsActivationObserver: true,
            isWindowPresent: { SoftwareCursorOverlay.isWindowPresent($0) },
            makePanelHost: { CursorPanelHost(windowSize: SoftwareCursorOverlay.artworkGeometry.windowSize) },
            windowBounds: { currentWindowBounds(for: $0) },
            screenStateToAppKitPoint: { screenStatePointToAppKitGlobalPoint(fromScreenStatePoint: $0) },
            screenIndex: { point in NSScreen.screens.firstIndex { $0.frame.contains(point) } },
            makeWindowMotionObserver: {
                cursorWindowMoveWatchEnabled() ? AXWindowMotionObserver() : nil
            }
        )
    }
}

// MARK: - Panel level / ordering policy

/// Base level of the cursor panel.
///
/// The overlay must never sit at .normal: this process is an accessory app that
/// is never active, so a normal-level panel belongs to the inactive window group
/// — the window server puts the frontmost app's windows above it on the first
/// activation change — and it also inherits the fate of any foreign window it was
/// ordered above. .floating keeps the cursor above every normal window of every
/// app while staying below the system menu levels (mainMenu 24 / popUpMenu 101),
/// which still draw in front.
let cursorOverlayBaseLevel = NSWindow.Level.floating

/// Where the cursor panel has to sit for one show / target-window change.
struct CursorPanelOrdering: Equatable {
    let level: NSWindow.Level
    /// Non-nil only when the target window itself floats at or above the base
    /// level (menus, popovers, panels). Ordering relative to a window in a
    /// *lower* level would make the cursor's visibility depend on that window.
    let anchorWindow: CursorTargetWindow?
}

func cursorPanelOrdering(
    targetWindow: CursorTargetWindow?,
    baseLevel: NSWindow.Level = cursorOverlayBaseLevel
) -> CursorPanelOrdering {
    guard let targetWindow, targetWindow.layer >= baseLevel.rawValue else {
        return CursorPanelOrdering(level: baseLevel, anchorWindow: nil)
    }

    return CursorPanelOrdering(
        level: NSWindow.Level(rawValue: targetWindow.layer),
        anchorWindow: targetWindow
    )
}

private final class CursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SoftwareCursorView: NSView {
    var rotation: CGFloat = 0
    var cursorBodyOffset: CGVector = CGVector(dx: 0, dy: 0)
    var fogOffset: CGVector = CGVector(dx: 0, dy: 0)
    var fogOpacity: CGFloat = 0.12
    var fogScale: CGFloat = 1
    var clickProgress: CGFloat = 0

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

        SoftwareCursorGlyphRenderer.draw(
            in: bounds,
            context: context,
            state: SoftwareCursorGlyphRenderState(
                rotation: rotation,
                cursorBodyOffset: cursorBodyOffset,
                fogOffset: fogOffset,
                fogOpacity: fogOpacity,
                fogScale: fogScale,
                clickProgress: clickProgress
            )
        )
    }
}
