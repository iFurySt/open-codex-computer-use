import XCTest
@testable import OpenComputerUseKit

final class LockedUseBrokerPollingTests: XCTestCase {
    func testIdleOnlySlowsWhenGuardsAreFullyReleased() {
        for phase in [LockedUseStateMachine.Phase.idle, .awaitingManualUnlock] {
            XCTAssertEqual(LockedUseBrokerPolling.interval(phase: phase, fullyReleased: true), 1)
            XCTAssertEqual(LockedUseBrokerPolling.interval(phase: phase, fullyReleased: false), 0.1)
        }
    }

    func testActiveAndRecoveryPhasesRetainWatchdogCadence() {
        for phase in [LockedUseStateMachine.Phase.preparing, .authorizing, .unlocking, .active, .relocking] {
            XCTAssertEqual(LockedUseBrokerPolling.interval(phase: phase, fullyReleased: true), 0.1)
            XCTAssertEqual(LockedUseBrokerPolling.interval(phase: phase, fullyReleased: false), 0.1)
        }
    }
}
