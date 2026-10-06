import XCTest
@testable import OpenComputerUseKit

final class LockedUseClickAllowanceTests: XCTestCase {
    private func accept(_ gate: inout LockedUseClickAllowance, _ button: LockedUseClickAllowance.Button,
        tag: Int64 = 123, sender: Int32 = 42, target: Int32 = 84, window: Int64 = 9,
        x: Double = 10, now: TimeInterval = 11, locked: Bool = true) -> Bool {
        gate.accept(button: button, tag: tag, sender: sender, target: target, window: window,
            x: x, y: 20, now: now, locked: locked)
    }
    func testOneMatchedPairOnly() {
        var gate = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
        XCTAssertTrue(accept(&gate, .down))
        XCTAssertTrue(accept(&gate, .up, now: 11.01))
        XCTAssertFalse(accept(&gate, .down, now: 11.02))
    }
    func testPIDAloneAndInvalidGeometryCannotPass() {
        for invalid in [0, 1, 2, 3, 4, 5] {
            var gate = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
            XCTAssertFalse(accept(&gate, .down, tag: invalid == 0 ? 999 : 123,
                sender: invalid == 1 ? 99 : 42, target: invalid == 2 ? 0 : 84,
                window: invalid == 3 ? 0 : 9, x: invalid == 4 ? .nan : 10,
                locked: invalid != 5))
        }
    }
    func testTakeoverAndExpiryCannotRearm() {
        var gate = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
        XCTAssertFalse(accept(&gate, .down, now: 9))
        XCTAssertFalse(accept(&gate, .down, now: 15))
        gate.revoke()
        XCTAssertFalse(accept(&gate, .down))
        var expired = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
        XCTAssertFalse(accept(&expired, .down, now: 15))
        XCTAssertFalse(accept(&expired, .down, now: 11))
    }
    func testMismatchDuplicateAndLateUpRevokePair() {
        for invalid in [0, 1, 2, 3] {
            var gate = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
            XCTAssertTrue(accept(&gate, .down))
            if invalid == 0 { XCTAssertFalse(accept(&gate, .down)) }
            else {
                XCTAssertFalse(accept(&gate, .up, window: invalid == 1 ? 10 : 9,
                    x: invalid == 2 ? 11 : 10, now: invalid == 3 ? 11.25 : 11.01))
            }
            XCTAssertFalse(accept(&gate, .up, now: 11.02))
        }
        var gate = LockedUseClickAllowance(tag: 123, sender: 42, now: 10)
        XCTAssertFalse(accept(&gate, .up))
        XCTAssertFalse(accept(&gate, .down))
    }
}
