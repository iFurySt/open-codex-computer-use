import AppKit
import CoreGraphics
import Foundation
import QuartzCore

// MARK: - Idle knobs

/// How long the cursor may keep its post-action idle sway after the last
/// explicit action.
///
/// The sway is a *bounded* beat, not a permanent animation driver: an idle
/// overlay must end up absolutely static, so the 60 Hz timer is invalidated the
/// moment the window elapses. `0` freezes the glyph as soon as the action
/// settles. Invalid values fall back to the default.
func visualCursorIdleSwayWindowMilliseconds(environment: [String: String]) -> Double {
    let defaultMilliseconds = 1000.0

    guard
        let rawValue = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR_IDLE_SWAY_MS"]?
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

func visualCursorIdleSwayWindow(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> TimeInterval {
    visualCursorIdleSwayWindowMilliseconds(environment: environment) / 1000
}

/// Opt-in counters for field diagnosis. They are the only way to prove from the
/// outside that idle ticks stop touching the panel, so they are dumped on
/// hide/reset instead of being sampled live.
func visualCursorDebugStatsEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
    guard
        let rawValue = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR_DEBUG_STATS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
        !rawValue.isEmpty
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

// MARK: - Frame origin alignment

/// The overlay writes whole-point frame origins.
///
/// The glyph is driven by a spring, so its tip keeps moving by fractions of a
/// point long after the animation looks finished. Writing those sub-pixel
/// origins hands the window server a new frame every tick, which it quantises
/// onto the backing store — the arrow visibly snaps by a device pixel at every
/// boundary crossing. Rounding to integral points removes that class of
/// shiver, and the caller then skips the write entirely when nothing changed.
func integralCursorFrameOrigin(
    forTipPosition tipPosition: CGPoint,
    tipAnchor: CGPoint
) -> CGPoint {
    CGPoint(
        x: (tipPosition.x - tipAnchor.x).rounded(),
        y: (tipPosition.y - tipAnchor.y).rounded()
    )
}

/// The panel is restacked when the overlay is shown or when its target window
/// changed — never on a bare tick. Forcing a reorder for a live, unchanged
/// target window restacks the panel on every 60 Hz tick, which is exactly the
/// window-server churn the idle contract forbids.
func shouldReorderCursorPanel(
    activeTargetWindow: CursorTargetWindow?,
    effectiveTargetWindow: CursorTargetWindow?,
    panelIsVisible: Bool
) -> Bool {
    activeTargetWindow != effectiveTargetWindow || panelIsVisible == false
}

// MARK: - Panel write gate

/// Remembers the last panel state the overlay wrote so a repeated tick with
/// unchanged numbers performs no AppKit call at all.
///
/// This is the "equal values are a no-op" half of the stillness contract: the
/// idle path keeps producing the same integral origin for a resting cursor, and
/// every one of those writes has to disappear before it reaches the window
/// server. Counters double as the debug surface.
@MainActor
final class CursorPanelWriteGate {
    struct FrameWrite: Equatable {
        let origin: CGPoint
        let didChange: Bool
    }

    private(set) var lastFrameOrigin: CGPoint?
    private(set) var lastLevel: NSWindow.Level?
    /// Target window the panel is currently ordered above, or `nil` when the
    /// panel is only ordered front.
    private(set) var activeTargetWindow: CursorTargetWindow?

    private(set) var frameWriteCount = 0
    private(set) var skippedFrameWriteCount = 0
    private(set) var levelWriteCount = 0
    private(set) var reorderCount = 0
    private(set) var skippedReorderCount = 0

    func frameWrite(forTipPosition tipPosition: CGPoint, tipAnchor: CGPoint) -> FrameWrite {
        let origin = integralCursorFrameOrigin(forTipPosition: tipPosition, tipAnchor: tipAnchor)

        guard lastFrameOrigin != origin else {
            skippedFrameWriteCount += 1
            return FrameWrite(origin: origin, didChange: false)
        }

        lastFrameOrigin = origin
        frameWriteCount += 1
        return FrameWrite(origin: origin, didChange: true)
    }

    func levelWrite(for level: NSWindow.Level) -> Bool {
        guard lastLevel != level else {
            return false
        }

        lastLevel = level
        levelWriteCount += 1
        return true
    }

    /// Returns whether the panel still has to be ordered. A live, unchanged
    /// target window keeps the panel where it is.
    func markOrdering(activeTargetWindow newTargetWindow: CursorTargetWindow?, panelIsVisible: Bool) -> Bool {
        guard shouldReorderCursorPanel(
            activeTargetWindow: activeTargetWindow,
            effectiveTargetWindow: newTargetWindow,
            panelIsVisible: panelIsVisible
        ) else {
            skippedReorderCount += 1
            return false
        }

        activeTargetWindow = newTargetWindow
        reorderCount += 1
        return true
    }

    /// A hidden panel forgets its frame and its ordering: showing it again must
    /// write both, otherwise a re-shown cursor would keep a stale origin.
    func reset() {
        lastFrameOrigin = nil
        lastLevel = nil
        activeTargetWindow = nil
    }
}

// MARK: - Idle driver

/// One scheduled idle tick that can be cancelled.
@MainActor
protocol CursorIdleTimerHandling: AnyObject {
    var isRunning: Bool { get }
    func invalidate()
}

/// The real 60 Hz run-loop timer behind the cursor's post-action beat.
@MainActor
final class CursorRunLoopIdleTimer: CursorIdleTimerHandling {
    private let timer: Timer

    init(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    var isRunning: Bool {
        timer.isValid
    }

    func invalidate() {
        timer.invalidate()
    }
}

/// Owns the idle contract of the software cursor.
///
/// Two rules live here, because both are about the same failure:
///
/// 1. Only one idle timer may exist. The overlay used to overwrite its timer
///    reference, so every `settle` + `pulseClick` pair left an orphaned 60 Hz
///    writer behind that could never be stopped again; the shared idle phase was
///    then advanced by several timers per frame, which is what turned the
///    intended smooth sway into an irregular twitch.
/// 2. A tick may only run inside the bounded beat after the last explicit
///    action. Outside it the driver invalidates itself and later ticks are
///    dropped without touching the panel.
@MainActor
final class CursorIdleDriver {
    /// Matches the 60 Hz feel of the glyph.
    static let tickInterval: TimeInterval = 1 / 60

    private let now: () -> CFTimeInterval
    private let makeTimer: (TimeInterval, @escaping @MainActor () -> Void) -> any CursorIdleTimerHandling

    private var timer: (any CursorIdleTimerHandling)?
    private(set) var lastInteractionAt: CFTimeInterval?
    private(set) var idleTickCount = 0
    private(set) var suppressedIdleTickCount = 0
    private(set) var invalidatedTimerCount = 0

    init(
        now: @escaping () -> CFTimeInterval = { CACurrentMediaTime() },
        makeTimer: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> any CursorIdleTimerHandling = { interval, tick in
            CursorRunLoopIdleTimer(interval: interval, tick: tick)
        }
    ) {
        self.now = now
        self.makeTimer = makeTimer
    }

    var isIdleAnimationRunning: Bool {
        timer?.isRunning ?? false
    }

    /// Anchors the idle window. Called for every explicit cursor action.
    func markInteraction(at time: CFTimeInterval) {
        lastInteractionAt = time
    }

    /// Whether an idle tick is still allowed at `time`. No interaction yet, a
    /// closed window, or an already elapsed window all mean "do nothing".
    func shouldPumpIdleAnimation(at time: CFTimeInterval, window: TimeInterval) -> Bool {
        guard window > 0, let lastInteractionAt else {
            return false
        }

        return time - lastInteractionAt <= window
    }

    /// Starts the post-action idle beat, invalidating whatever timer was
    /// running before — starting twice must never leave two writers alive.
    func startIdleAnimation(
        now time: CFTimeInterval,
        window: TimeInterval,
        tick: @escaping @MainActor () -> Void
    ) {
        stopIdleAnimation()

        timer = makeTimer(Self.tickInterval) { [weak self] in
            guard let self else {
                return
            }

            guard self.shouldPumpIdleAnimation(at: self.now(), window: window) else {
                self.suppressedIdleTickCount += 1
                self.stopIdleAnimation()
                return
            }

            self.idleTickCount += 1
            tick()
        }
    }

    func stopIdleAnimation() {
        guard let timer else {
            return
        }

        timer.invalidate()
        invalidatedTimerCount += 1
        self.timer = nil
    }
}

// MARK: - Debug counters

struct CursorOverlayDebugStats: Equatable {
    var frameWrites = 0
    var skippedFrameWrites = 0
    var levelWrites = 0
    var reorders = 0
    var skippedReorders = 0
    var idleTicks = 0
    var suppressedIdleTicks = 0
    var invalidatedIdleTimers = 0
}

func cursorOverlayDebugStatsLine(_ stats: CursorOverlayDebugStats) -> String {
    "[open-computer-use] cursor overlay stats"
        + " frameWrites=\(stats.frameWrites)"
        + " skippedFrameWrites=\(stats.skippedFrameWrites)"
        + " levelWrites=\(stats.levelWrites)"
        + " reorders=\(stats.reorders)"
        + " skippedReorders=\(stats.skippedReorders)"
        + " idleTicks=\(stats.idleTicks)"
        + " suppressedIdleTicks=\(stats.suppressedIdleTicks)"
        + " invalidatedIdleTimers=\(stats.invalidatedIdleTimers)"
}
