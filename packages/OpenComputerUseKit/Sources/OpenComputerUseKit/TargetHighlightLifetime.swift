import ApplicationServices
import CoreGraphics
import Dispatch
import Foundation

// MARK: - Lifetime policy

/// Roles that belong to a menu / popup surface. Those elements only exist while
/// the popup is open, so their ring must never outlive the popup.
private let targetHighlightPopupRoles: Set<String> = [
    "AXMenuItem",
    "AXMenu",
    "AXMenuBar",
    "AXMenuBarItem",
]

/// Menu and popup windows float above the normal window level. That is the
/// cheapest signal that the ring is marking a transient surface, so it is
/// treated as a popup even when the element role alone does not say so.
func targetHighlightIsPopupWindow(layer: Int?) -> Bool {
    (layer ?? 0) > 0
}

func targetHighlightIsPopupRole(_ role: String?) -> Bool {
    guard let role = role?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return false
    }

    return targetHighlightPopupRoles.contains(role)
}

/// The ring's own deadline. Regular elements keep the audited "visible, then
/// fade" beat; popups get a shorter one because they can disappear at any
/// moment and a ring left behind reads as a stuck overlay.
func targetHighlightDisplayDuration(
    isPopup: Bool,
    defaultDuration: TimeInterval = 0.45,
    popupDuration: TimeInterval = 0.30
) -> TimeInterval {
    isPopup ? popupDuration : defaultDuration
}

/// Thread-safe transport for `AXUIElement`, a CF type the compiler does not
/// know is `Sendable`. The ring only ever reads it on the main actor, and AX
/// attribute reads are themselves thread-safe, so the box carries it across the
/// actor hop without dragging the whole element record along.
struct AXElementReference: @unchecked Sendable {
    let element: AXUIElement
}

// MARK: - Liveness watchdog

/// One liveness sample of the element the ring is marking.
struct TargetHighlightLivenessSample: Equatable {
    let isWindowPresent: Bool
    let isElementValid: Bool
    /// Current element frame in Accessibility (top-left origin) screen space.
    let currentScreenFrame: CGRect?

    init(
        isWindowPresent: Bool = true,
        isElementValid: Bool = true,
        currentScreenFrame: CGRect? = nil
    ) {
        self.isWindowPresent = isWindowPresent
        self.isElementValid = isElementValid
        self.currentScreenFrame = currentScreenFrame
    }
}

/// The ring may only stay on screen while it still points at the element the
/// action touched. A dead element, a vanished window, or a frame that moved
/// well past the rendered rect all mean the ring is lying, so it is withdrawn
/// on the next watchdog tick instead of waiting for the fade deadline.
func targetHighlightShouldWithdraw(
    expectedScreenFrame: CGRect?,
    sample: TargetHighlightLivenessSample,
    frameTolerance: CGFloat = 8
) -> Bool {
    guard sample.isWindowPresent, sample.isElementValid else {
        return true
    }

    guard let expected = expectedScreenFrame, let current = sample.currentScreenFrame else {
        return false
    }

    return abs(current.origin.x - expected.origin.x) > frameTolerance
        || abs(current.origin.y - expected.origin.y) > frameTolerance
        || abs(current.size.width - expected.size.width) > frameTolerance
        || abs(current.size.height - expected.size.height) > frameTolerance
}

// MARK: - Hard deadline timer

/// One-shot timer for the ring's deadlines.
///
/// This is deliberately not a `Timer` scheduled on the main run loop: the ring
/// must still disappear while the main thread is busy, and a default-mode
/// `Timer` is also starved while the run loop sits in event-tracking mode,
/// which is exactly the state an open native menu puts it in. The deadline
/// therefore elapses on the timer's own queue and the caller hops back to the
/// main actor for the AppKit step.
@MainActor
protocol TargetHighlightTimerScheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void)
    func cancel()
}

@MainActor
final class TargetHighlightDispatchTimer: TargetHighlightTimerScheduling {
    private static let queue = DispatchQueue(
        label: "com.ifuryst.opencomputeruse.target-highlight-deadline",
        qos: .userInitiated
    )

    private var source: DispatchSourceTimer?

    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        cancel()

        let timer = DispatchSource.makeTimerSource(queue: Self.queue)
        timer.schedule(deadline: .now() + max(delay, 0), leeway: .milliseconds(20))
        timer.setEventHandler(handler: action)
        timer.resume()
        source = timer
    }

    func cancel() {
        source?.cancel()
        source = nil
    }
}

// MARK: - Lifetime controller

/// Owns the ring's lifetime: at most one visible ring, a hard deadline, and a
/// liveness watchdog. The AppKit work is injected so the whole contract is
/// unit-testable without a window server.
@MainActor
final class TargetHighlightLifetimeController {
    static let defaultFadeOutDuration: TimeInterval = 0.35
    /// How often the ring re-checks that it still points at a live element.
    static let watchdogInterval: TimeInterval = 0.22
    /// Slack between the fade finishing and the unconditional `orderOut`.
    static let hardWithdrawSlack: TimeInterval = 0.05

    /// Everything the ring needs to stay truthful, captured when it is shown.
    struct RingTarget {
        let globalRect: CGRect
        let level: Int
        let windowID: CGWindowID?
        let element: AXElementReference?
        let isPopup: Bool
        /// Element frame at show time, in Accessibility screen space.
        let expectedScreenFrame: CGRect?
        /// Debug-only hold. Production leaves this nil so the audited
        /// 450ms / popup 300ms beat is the only policy.
        var displayDurationOverride: TimeInterval?

        var displayDuration: TimeInterval {
            displayDurationOverride ?? targetHighlightDisplayDuration(isPopup: isPopup)
        }
    }

    private let fadeOutDuration: TimeInterval
    private let presentRing: (RingTarget) -> Void
    private let fadeRing: () -> Void
    private let withdrawPanel: () -> Void
    private let sample: (RingTarget) -> TargetHighlightLivenessSample
    private let makeTimer: () -> TargetHighlightTimerScheduling

    private var visibleTarget: RingTarget?
    private var generation = 0
    private var ttlTimer: (any TargetHighlightTimerScheduling)?
    private var hardTimer: (any TargetHighlightTimerScheduling)?
    private var watchdogTimer: (any TargetHighlightTimerScheduling)?

    var isVisible: Bool {
        visibleTarget != nil
    }

    init(
        fadeOutDuration: TimeInterval = TargetHighlightLifetimeController.defaultFadeOutDuration,
        presentRing: @escaping (RingTarget) -> Void,
        fadeRing: @escaping () -> Void,
        withdrawPanel: @escaping () -> Void,
        sample: @escaping (RingTarget) -> TargetHighlightLivenessSample,
        makeTimer: @escaping () -> TargetHighlightTimerScheduling
    ) {
        self.fadeOutDuration = fadeOutDuration
        self.presentRing = presentRing
        self.fadeRing = fadeRing
        self.withdrawPanel = withdrawPanel
        self.sample = sample
        self.makeTimer = makeTimer
    }

    /// Shows `target` after clearing whatever ring was on screen: a new action
    /// always replaces the previous ring instead of stacking overlays.
    func show(_ target: RingTarget) {
        clear()

        visibleTarget = target
        presentRing(target)

        let generation = self.generation
        let displayDuration = target.displayDuration

        let ttl = makeTimer()
        ttlTimer = ttl
        ttl.schedule(after: displayDuration, Self.onMain { [weak self] in
            guard let self, self.generation == generation else {
                return
            }

            self.fadeRing()
            self.watchdogTimer?.cancel()
            self.watchdogTimer = nil
        })

        // Independent of the fade animation: even when the animation never
        // completes (busy main thread, tracking run loop), the panel is gone
        // by `displayDuration + fade + slack`.
        let hard = makeTimer()
        hardTimer = hard
        hard.schedule(after: displayDuration + fadeOutDuration + Self.hardWithdrawSlack, Self.onMain { [weak self] in
            guard let self, self.generation == generation else {
                return
            }

            self.clear()
        })

        armWatchdog(generation: generation)
    }

    func hide() {
        clear()
    }

    private func armWatchdog(generation: Int) {
        let timer = makeTimer()
        watchdogTimer = timer
        timer.schedule(after: Self.watchdogInterval, Self.onMain { [weak self] in
            guard let self, self.generation == generation, let target = self.visibleTarget else {
                return
            }

            if targetHighlightShouldWithdraw(
                expectedScreenFrame: target.expectedScreenFrame,
                sample: self.sample(target)
            ) {
                self.clear()
                return
            }

            self.armWatchdog(generation: generation)
        })
    }

    private func clear() {
        generation += 1
        let hadRing = visibleTarget != nil
        visibleTarget = nil

        ttlTimer?.cancel()
        ttlTimer = nil
        hardTimer?.cancel()
        hardTimer = nil
        watchdogTimer?.cancel()
        watchdogTimer = nil

        if hadRing {
            withdrawPanel()
        }
    }

    /// Deadlines elapse off the main run loop, so every AppKit effect hops back
    /// to the main actor here.
    private static func onMain(_ body: @escaping @MainActor () -> Void) -> @Sendable () -> Void {
        {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    body()
                }
            }
        }
    }
}
