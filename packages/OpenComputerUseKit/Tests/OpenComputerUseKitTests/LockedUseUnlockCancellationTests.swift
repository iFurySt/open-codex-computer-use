import XCTest
@testable import OpenComputerUseKit

final class LockedUseUnlockCancellationTests: XCTestCase {
    func testCancelledReadonlyWorkCanNeverDispatchALateNativeWrite() {
        let cancellation = LockedUseUnlockCancellation()
        cancellation.cancel()
        XCTAssertTrue(cancellation.quiesced)
        let result = cancellation.performProbe { XCTFail("late UI write"); return 1 }
        XCTAssertNil(result)
        XCTAssertFalse(cancellation.allowsRequest())
    }

    func testAlreadyDispatchedWriteMustReturnBeforeQuiescence() {
        let entered = expectation(description: "write dispatched")
        let finished = expectation(description: "write returned")
        let release = DispatchSemaphore(value: 0)
        let cancellation = LockedUseUnlockCancellation()
        DispatchQueue.global().async {
            _ = cancellation.performProbe { entered.fulfill(); release.wait() }
            finished.fulfill()
        }
        wait(for: [entered], timeout: 1)
        cancellation.cancel()
        XCTAssertFalse(cancellation.quiesced)
        XCTAssertNil(cancellation.performProbe { XCTFail("second UI write"); return 1 })
        release.signal()
        wait(for: [finished], timeout: 1)
        XCTAssertTrue(cancellation.quiesced)
    }
}
