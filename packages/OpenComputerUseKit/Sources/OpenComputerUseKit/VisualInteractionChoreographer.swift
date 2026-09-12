import CoreGraphics
import Foundation
import QuartzCore

/// What one `approach` did with the software cursor.
///
/// The overlay is advisory, so the only thing callers need to know is whether
/// this action was allowed to animate: a coalesced burst must stay completely
/// animation-free, including the click pulse.
enum VisualCursorApproach: Equatable {
    /// The target changed and the coalescing window was open: the travel
    /// animation and the arrival beat played.
    case animated
    /// The target changed inside the coalescing window: the cursor was placed
    /// on it without replaying the travel animation.
    case repositioned
    /// The cursor was already on the target: no move, no arrival beat.
    case held
    /// Nothing happened (visual cursor disabled, or the action has no target).
    case skipped

    /// A coalesced or skipped step never pulses; `held` still does, because the
    /// pulse marks the click itself rather than cursor travel.
    var playsClickPulse: Bool {
        self == .animated || self == .held
    }
}

/// Remembers where and when the software cursor last travelled, so a burst of
/// actions cannot replay the travel animation on every step.
///
/// Codex Computer Use animates every element-scoped action. That reads as "the
/// cursor is drifting everywhere" when an agent fills a 33-field form: one
/// Bezier flight plus a 120ms arrival beat per field. The coalescer keeps the
/// overlay truthful while making a burst cost at most one animation per
/// `OPEN_COMPUTER_USE_VISUAL_CURSOR_COALESCE_MS` window.
final class VisualCursorMoveCoalescer: @unchecked Sendable {
    /// One process-wide gate, because the overlay it describes
    /// (`SoftwareCursorOverlay`) is a process-wide singleton: when the overlay
    /// hides or resets, the remembered target must be dropped with it.
    static let shared = VisualCursorMoveCoalescer()

    private let lock = NSLock()
    private var lastMoveTarget: CGPoint?
    private var lastMoveAt: TimeInterval?

    /// Target of the last cursor placement, animated or not.
    var lastTarget: CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        return lastMoveTarget
    }

    /// When the last *animation* started. Coalesced placements deliberately do
    /// not move it: the window is anchored to the last real animation, which is
    /// what bounds the animation rate.
    var lastAnimatedAt: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return lastMoveAt
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastMoveTarget = nil
        lastMoveAt = nil
    }

    func decide(
        target: CGPoint,
        now: TimeInterval,
        coalesceWindow: TimeInterval = visualCursorCoalesceWindow(),
        moveEpsilon: CGFloat = visualCursorMoveEpsilonPoints()
    ) -> VisualCursorApproach {
        lock.lock()
        defer { lock.unlock() }

        if let lastMoveTarget, distance(lastMoveTarget, target) <= moveEpsilon {
            // Same target. Keep the anchor of the last real move so a slow
            // drift of sub-epsilon targets cannot walk the cursor away.
            return .held
        }

        if let lastMoveAt, coalesceWindow > 0, now - lastMoveAt < coalesceWindow {
            lastMoveTarget = target
            return .repositioned
        }

        lastMoveTarget = target
        lastMoveAt = now
        return .animated
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

/// Drives the two advisory overlays for an element-scoped action in the order
/// Codex Computer Use uses.
///
/// The reverse-engineering notes record that the official service moves its
/// software cursor to the element first, signals cursor movement completion,
/// and only then performs the real interaction
/// (`docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`:
/// `Move cursor to ...` / `Start Bezier cursor animation ...` /
/// `Signal cursor movement completion ...` before `Moving mouse to ...` /
/// `Clicking at ...`). The highlight ring therefore must never lead the
/// pointer: the cursor flies to the target, settles there, and only then does
/// the ring mark the element the real action is about to touch.
///
/// Travel itself is debounced, see `VisualCursorMoveCoalescer`: an action on
/// the element the cursor already covers only re-shows the ring, and a burst
/// inside the coalescing window places the cursor without animating it.
///
/// Every step is skipped when `OPEN_COMPUTER_USE_VISUAL_CURSOR` disables the
/// visual cursor, so cursor and ring stay coupled.
struct VisualInteractionChoreographer {
    let environment: [String: String]
    let moveCursor: (VisualCursorTarget) -> Void
    /// Places the cursor on the target without the Bezier travel. Used for the
    /// coalesced case, where an animation would defeat the debounce.
    var repositionCursor: (VisualCursorTarget) -> Void = { _ in }
    let settleCursorArrival: (VisualCursorTarget) -> Void
    let showTargetHighlight: (ElementRecord, AppSnapshot) -> Void
    /// Injected so the coalescing window is testable without sleeping.
    var now: () -> TimeInterval = { CACurrentMediaTime() }
    var coalescer: VisualCursorMoveCoalescer = VisualCursorMoveCoalescer()

    /// Cursor first, then the arrival beat, then the ring. The caller performs
    /// the real action after this returns.
    @discardableResult
    func approach(
        _ target: VisualCursorTarget?,
        record: ElementRecord,
        snapshot: AppSnapshot
    ) -> VisualCursorApproach {
        guard visualCursorEnabled(environment: environment), let target else {
            return .skipped
        }

        let decision = coalescer.decide(
            target: target.point,
            now: now(),
            coalesceWindow: visualCursorCoalesceWindow(environment: environment),
            moveEpsilon: visualCursorMoveEpsilonPoints()
        )

        switch decision {
        case .animated:
            moveCursor(target)
            settleCursorArrival(target)
        case .repositioned:
            repositionCursor(target)
        case .held, .skipped:
            break
        }

        showTargetHighlight(record, snapshot)
        return decision
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        coalescer: VisualCursorMoveCoalescer = .shared
    ) -> VisualInteractionChoreographer {
        VisualInteractionChoreographer(
            environment: environment,
            moveCursor: { target in
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.moveCursor(to: target.point, in: target.window)
                }
            },
            repositionCursor: { target in
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.repositionCursor(to: target.point, in: target.window)
                }
            },
            settleCursorArrival: { target in
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.settle(at: target.point, in: target.window)
                    SoftwareCursorOverlay.waitForArrivalSettle()
                }
            },
            showTargetHighlight: { record, snapshot in
                presentTargetHighlight(for: record, snapshot: snapshot)
            },
            now: { CACurrentMediaTime() },
            coalescer: coalescer
        )
    }

    /// Advisory only: the ring is a silent no-op whenever the element frame or
    /// the window visible rect is missing.
    private static func presentTargetHighlight(for record: ElementRecord, snapshot: AppSnapshot) {
        guard let windowBounds = snapshot.windowBounds else {
            return
        }

        // Copy everything the main-actor hop needs out of the task-isolated
        // record instead of sending the record itself across actors.
        let localFrame = record.localFrame
        let element = record.element.map(AXElementReference.init)
        let role = record.role
        let targetWindow = snapshot.targetWindowID.map {
            CursorTargetWindow(windowID: $0, layer: snapshot.targetWindowLayer ?? 0)
        }

        VisualCursorSupport.performOnMain {
            TargetHighlightOverlay.show(
                localFrame: localFrame,
                windowBounds: windowBounds,
                targetWindow: targetWindow,
                element: element,
                role: role
            )
        }
    }
}
