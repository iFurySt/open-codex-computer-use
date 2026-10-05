import XCTest
@testable import OpenComputerUseKit

final class LockedUsePolicyMonitorTests: XCTestCase {
    func testWedgedAuthorizationServerDoesNotBlockRecoveryQueueAndExpiresPermits() {
        let entered = expectation(description: "policy read entered")
        let release = DispatchSemaphore(value: 0)
        let monitor = LockedUsePolicyMonitor { entered.fulfill(); release.wait(); return true }
        defer { release.signal() }
        let started = ProcessInfo.processInfo.systemUptime
        monitor.refresh(now: started)
        wait(for: [entered], timeout: 1)
        for _ in 0..<100 { monitor.refresh(); XCTAssertEqual(monitor.status(), .pending) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
        XCTAssertEqual(monitor.status(now: started + LockedUsePolicyMonitor.maximumAge), .stale)
    }

    func testFailedObservationCannotAuthorize() {
        let returned = expectation(description: "check ran")
        let monitor = LockedUsePolicyMonitor { returned.fulfill(); return false }
        monitor.refresh()
        wait(for: [returned], timeout: 1)
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while monitor.status() == .pending && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertEqual(monitor.status(), .invalid)
    }
}
