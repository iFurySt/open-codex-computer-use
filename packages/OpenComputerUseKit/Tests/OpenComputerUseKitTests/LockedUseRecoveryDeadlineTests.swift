import XCTest
@testable import OpenComputerUseKit

final class LockedUseRecoveryDeadlineTests: XCTestCase {
    func testWedgedRPCQueueAndRepeatedRetriesCannotExtendRecoveryDeadline() {
        let expired = expectation(description: "independent recovery")
        let deadline = LockedUseRecoveryDeadline { expired.fulfill() }
        let rpc = DispatchQueue(label: "test.wedged-rpc")
        let release = DispatchSemaphore(value: 0)
        rpc.async { release.wait() }
        defer { release.signal(); deadline.cancel() }
        deadline.arm(after: 0.05)
        for _ in 0..<20 { deadline.arm(after: 5) }
        wait(for: [expired], timeout: 1)
    }

    func testCompletedCleanupCancelsExpiration() {
        let expired = expectation(description: "no expiration after cleanup")
        expired.isInverted = true
        let deadline = LockedUseRecoveryDeadline { expired.fulfill() }
        deadline.arm(after: 0.05)
        deadline.cancel()
        wait(for: [expired], timeout: 0.15)
    }

    func testEarlierFailureShortensAcquisitionDeadline() {
        let expired = expectation(description: "shortened recovery")
        let deadline = LockedUseRecoveryDeadline { expired.fulfill() }
        defer { deadline.cancel() }
        deadline.arm(after: 5)
        deadline.arm(after: 0.05)
        wait(for: [expired], timeout: 1)
    }
}
