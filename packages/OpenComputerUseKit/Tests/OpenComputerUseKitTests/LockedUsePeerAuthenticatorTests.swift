import Dispatch
import XCTest
@testable import OpenComputerUseKit

final class LockedUsePeerAuthenticatorTests: XCTestCase {
    func testSlowSignatureCheckDoesNotBlockControlQueue() {
        let entered = expectation(description: "signature check started")
        let controlRan = expectation(description: "control queue still handles recovery")
        let completed = expectation(description: "verification completed")
        let release = DispatchSemaphore(value: 0)
        let authenticator = LockedUsePeerAuthenticator()
        authenticator.verify({ () -> Int in
            entered.fulfill()
            release.wait()
            return 42
        }, completion: { result in
            XCTAssertEqual(try? result.get(), 42)
            completed.fulfill()
        })
        wait(for: [entered], timeout: 1)
        DispatchQueue(label: "test.broker.control").async { controlRan.fulfill() }
        wait(for: [controlRan], timeout: 1)
        release.signal()
        wait(for: [completed], timeout: 1)
    }
}
