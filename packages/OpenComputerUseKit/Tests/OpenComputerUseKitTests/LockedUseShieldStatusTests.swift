import XCTest
@testable import OpenComputerUseKit

final class LockedUseShieldStatusTests: XCTestCase {
    func testAuthenticationNeverReplacesActiveAndExitFreezesText() {
        var status = LockedUseShieldStatus()
        XCTAssertTrue(status.update(now: 1, startupDeadline: 20, unlocked: false, stopping: false)! == LockedUseShieldStatus.message)
        XCTAssertNil(status.update(now: 2, startupDeadline: 20, unlocked: true, stopping: false))
        for now in 3...23 {
            XCTAssertNil(status.update(now: Double(now), startupDeadline: 20, unlocked: false, stopping: false))
        }
        XCTAssertNil(status.update(now: 24, startupDeadline: 20, unlocked: false, stopping: true))
        XCTAssertNil(status.update(now: 25, startupDeadline: 20, unlocked: true, stopping: false))
    }
    func testBothShieldsUseSameTextAndDeadline() {
        var main = LockedUseShieldStatus(), watchdog = LockedUseShieldStatus()
        for now in 1...5 {
            XCTAssertEqual(main.update(now: Double(now), startupDeadline: 20, unlocked: now >= 3, stopping: now >= 5),
                           watchdog.update(now: Double(now), startupDeadline: 20, unlocked: now >= 3, stopping: now >= 5))
        }
    }
}
