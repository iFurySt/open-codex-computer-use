import XCTest
@testable import OpenComputerUseKit

final class LockedUseReturnAllowanceTests: XCTestCase {
    private let session = LockedUseSession(state: .locked, userID: 501, auditSessionID: 42)
    private func gate() -> LockedUseReturnAllowance { .init(tag: 123, sender: 10, session: session, now: 1) }
    private func send(_ g: inout LockedUseReturnAllowance, down: Bool = true, tag: Int64 = 123,
        sender: Int32 = 10, target: Int32 = 20, code: Int64 = 36, repeated: Bool = false,
        modified: Bool = false, observed: LockedUseSession? = nil, now: Double = 2) -> Bool {
        g.accept(isDown: down, tag: tag, sender: sender, target: target, keyCode: code,
                 repeated: repeated, modified: modified, session: observed ?? session, now: now)
    }
    func testExactlyOnePairInEachIndependentFilter() {
        var main = gate(), watchdog = gate()
        for down in [true, false] {
            XCTAssertTrue(send(&main, down: down, now: down ? 2 : 2.01))
            XCTAssertTrue(send(&watchdog, down: down, now: down ? 2 : 2.01))
        }
        XCTAssertFalse(send(&main)); XCTAssertFalse(send(&watchdog))
    }
    func testPIDWithoutCapabilityCannotPass() {
        var g = gate(); XCTAssertFalse(send(&g, tag: 0))
        XCTAssertFalse(send(&g, sender: 11)); XCTAssertFalse(send(&g, target: 0))
    }
    func testOtherKeysModifiersAndRepeatsRevoke() {
        for i in 0..<3 {
            var g = gate()
            XCTAssertFalse(send(&g, code: i == 0 ? 37 : 36, repeated: i == 1, modified: i == 2))
            XCTAssertFalse(send(&g))
        }
    }
    func testSessionChangesAndExpiryRevoke() {
        for observed in [LockedUseSession(state: .unlocked, userID: 501, auditSessionID: 42),
                         LockedUseSession(state: .locked, userID: 502, auditSessionID: 42),
                         LockedUseSession(state: .locked, userID: 501, auditSessionID: 43)] {
            var g = gate(); XCTAssertFalse(send(&g, observed: observed)); XCTAssertFalse(send(&g))
        }
        for now in [0.0, 6.0, Double.nan] {
            var g = gate(); XCTAssertFalse(send(&g, now: now)); XCTAssertFalse(send(&g))
        }
    }
    func testOrderingTargetAndPairDeadline() {
        for i in 0..<4 {
            var g = gate()
            if i == 0 { XCTAssertFalse(send(&g, down: false)) }
            else {
                XCTAssertTrue(send(&g))
                XCTAssertFalse(send(&g, down: i == 1, target: i == 2 ? 21 : 20, now: i == 3 ? 2.25 : 2.01))
            }
            XCTAssertFalse(send(&g, down: false, now: 2.02))
        }
    }
    func testTakeoverRevokesBothPairsAndOldBootstrapHasNoReturn() throws {
        var g = gate(); g.revoke(); XCTAssertFalse(send(&g))
        let bootstrap = try LockedUseGuardianBootstrap(leaseID: UUID(), token: Data(repeating: 0, count: 32))
        let restored = try JSONDecoder().decode(LockedUseGuardianBootstrap.self, from: JSONEncoder().encode(bootstrap))
        XCTAssertNil(restored.returnTag)
    }
}
