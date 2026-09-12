import CoreGraphics
import Foundation

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
/// Every step is skipped when `OPEN_COMPUTER_USE_VISUAL_CURSOR` disables the
/// visual cursor, so cursor and ring stay coupled.
struct VisualInteractionChoreographer {
    let environment: [String: String]
    let moveCursor: (VisualCursorTarget) -> Void
    let settleCursorArrival: (VisualCursorTarget) -> Void
    let showTargetHighlight: (ElementRecord, AppSnapshot) -> Void

    /// Cursor first, then the arrival beat, then the ring. The caller performs
    /// the real action after this returns.
    func approach(_ target: VisualCursorTarget?, record: ElementRecord, snapshot: AppSnapshot) {
        guard visualCursorEnabled(environment: environment), let target else {
            return
        }

        moveCursor(target)
        settleCursorArrival(target)
        showTargetHighlight(record, snapshot)
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VisualInteractionChoreographer {
        VisualInteractionChoreographer(
            environment: environment,
            moveCursor: { target in
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.moveCursor(to: target.point, in: target.window)
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
            }
        )
    }

    /// Advisory only: the ring is a silent no-op whenever the element frame or
    /// the window visible rect is missing.
    private static func presentTargetHighlight(for record: ElementRecord, snapshot: AppSnapshot) {
        guard let windowBounds = snapshot.windowBounds else {
            return
        }

        let localFrame = record.localFrame
        let targetWindow = snapshot.targetWindowID.map {
            CursorTargetWindow(windowID: $0, layer: snapshot.targetWindowLayer ?? 0)
        }

        VisualCursorSupport.performOnMain {
            TargetHighlightOverlay.show(
                localFrame: localFrame,
                windowBounds: windowBounds,
                targetWindow: targetWindow
            )
        }
    }
}
