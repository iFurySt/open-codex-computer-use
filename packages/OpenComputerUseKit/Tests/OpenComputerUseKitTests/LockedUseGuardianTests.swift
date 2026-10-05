import XCTest
@testable import OpenComputerUseKit

final class LockedUseGuardianTests: XCTestCase {
    private let unlocked = LockedUseSession(state: .unlocked, userID: 501, auditSessionID: 10)
    private let locked = LockedUseSession(state: .locked, userID: 501, auditSessionID: 10)

    private func shielding() throws -> LockedUseGuardianPolicy {
        var policy = try LockedUseGuardianPolicy(session: unlocked, now: 100)
        try policy.prepared(topology: "display-1", now: 100)
        return policy
    }

    func testNeverReleaseBeforeQuiescenceAndSameSessionLock() throws {
        var policy = try shielding()
        XCTAssertEqual(policy.stop(.localInput, now: 100), [.requestRelock])
        XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false, now: 100.1), [])
        XCTAssertEqual(policy.phase, .relocking)
        policy.confirmQuiescence()
        let other = LockedUseSession(state: .locked, userID: 502, auditSessionID: 11)
        XCTAssertEqual(try policy.poll(session: other, topology: "", guardsHealthy: false, now: 100.5), [.requestRelock])
        XCTAssertEqual(try policy.poll(session: .init(state: .unavailable, userID: nil, auditSessionID: nil),
            topology: "", guardsHealthy: false, now: 101), [.requestRelock])
        XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false, now: 101.1), [.releaseShield])
        XCTAssertEqual(policy.phase, .finished)
        XCTAssertEqual(policy.stop(.localInput, now: 102), [])
    }

    func testExpiredHeartbeatCannotReviveGuardian() throws {
        var policy = try shielding()
        XCTAssertEqual(try policy.heartbeat(now: 101.5), [.requestRelock])
        XCTAssertEqual(policy.reason, .heartbeatExpired)
        XCTAssertEqual(try policy.heartbeat(now: 101.6), [])
        XCTAssertEqual(policy.phase, .relocking)
    }

    func testDelayedChildPreparationStartsHeartbeatOnlyAfterHealthyRegistration() throws {
        var policy = try LockedUseGuardianPolicy(session: locked, now: 100)
        try policy.prepared(topology: "display-1", now: 103)
        XCTAssertEqual(try policy.heartbeat(now: 103.1), [])
        XCTAssertEqual(try policy.poll(session: locked, topology: "display-1", guardsHealthy: true, now: 104), [])
        XCTAssertEqual(try policy.poll(session: locked, topology: "display-1", guardsHealthy: true, now: 104.6), [.requestRelock])
    }

    func testLockedDrainWaitDoesNotRepeatedlyDismissLoginAndStillRelocksAnUnlock() throws {
        var policy = try shielding()
        XCTAssertEqual(policy.stop(.parentDisconnected, now: 100), [.requestRelock])
        for step in 1...20 {
            XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false,
                now: 100 + Double(step)), [])
        }
        XCTAssertEqual(policy.phase, .relocking)
        XCTAssertEqual(try policy.poll(session: unlocked, topology: "", guardsHealthy: false,
            now: 121), [.requestRelock])
        policy.confirmQuiescence()
        XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false,
            now: 122), [.releaseShield])
    }

    func testNewInFlightActionInvalidatesPreviousQuiescence() throws {
        var policy = try shielding()
        policy.confirmQuiescence()
        policy.requireQuiescence()
        _ = policy.stop(.localInput, now: 100)
        XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false, now: 100.1), [])
        policy.confirmQuiescence()
        XCTAssertEqual(try policy.poll(session: locked, topology: "", guardsHealthy: false, now: 100.2), [.releaseShield])
    }

    func testLeaseExpiresDespiteContinuedHeartbeats() throws {
        var policy = try LockedUseGuardianPolicy(session: unlocked, now: 100, lifetime: 2)
        try policy.prepared(topology: "display-1", now: 100)
        XCTAssertEqual(try policy.heartbeat(now: 101), [])
        XCTAssertEqual(try policy.heartbeat(now: 102), [.requestRelock])
        XCTAssertEqual(policy.reason, .leaseExpired)
    }

    func testDisplayChangeAndGuardFailureStopBeforeMoreWork() throws {
        var policy = try shielding()
        XCTAssertEqual(try policy.poll(session: unlocked, topology: "display-1|display-2", guardsHealthy: true, now: 100.1), [.requestRelock])
        XCTAssertEqual(policy.reason, .displayChanged)
        var broken = try shielding()
        XCTAssertEqual(try broken.poll(session: unlocked, topology: "display-1", guardsHealthy: false, now: 100.1), [.requestRelock])
        XCTAssertEqual(broken.reason, .guardianFailure)
    }

    func testDisconnectRetainsShieldAndRetriesWithoutReleaseDeadline() throws {
        var policy = try shielding()
        policy.confirmQuiescence()
        XCTAssertEqual(policy.stop(.parentDisconnected, now: 100), [.requestRelock])
        XCTAssertEqual(try policy.poll(session: unlocked, topology: "display-1", guardsHealthy: true, now: 100.1), [])
        XCTAssertEqual(try policy.poll(session: unlocked, topology: "display-1", guardsHealthy: true, now: 10000), [.requestRelock])
        XCTAssertEqual(policy.phase, .relocking)
    }

    func testInvalidIdentityAndClockAreRejected() throws {
        XCTAssertThrowsError(try LockedUseGuardianPolicy(session: .init(state: .unavailable, userID: nil, auditSessionID: nil), now: 100))
        XCTAssertThrowsError(try LockedUseGuardianPolicy(session: unlocked, now: 100, lifetime: .infinity))
        var policy = try shielding()
        XCTAssertThrowsError(try policy.heartbeat(now: 99))
        XCTAssertThrowsError(try policy.poll(session: unlocked, topology: "display-1", guardsHealthy: true, now: .nan))
    }
}
