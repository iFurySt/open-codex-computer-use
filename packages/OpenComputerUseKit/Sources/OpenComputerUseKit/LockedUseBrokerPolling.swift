import Foundation

/// Idle services need policy observation, but no 100 ms lease watchdog.
/// Incomplete guard release always retains the recovery cadence.
public enum LockedUseBrokerPolling {
    public static func interval(phase: LockedUseStateMachine.Phase, fullyReleased: Bool) -> TimeInterval {
        fullyReleased && (phase == .idle || phase == .awaitingManualUnlock) ? 1 : 0.1
    }
}
