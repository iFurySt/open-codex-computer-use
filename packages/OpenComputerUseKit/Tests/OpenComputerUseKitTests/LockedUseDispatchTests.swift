import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class LockedUseDispatchTests: XCTestCase {
    private enum Revoked: Error { case lease }

    func testLeasedCapturePolicyIsClearedOnThrow() {
        XCTAssertFalse(LockedUseActionScope.requiresScreenCaptureKit)
        XCTAssertThrowsError(try LockedUseActionScope.withValidator({}, body: {
            XCTAssertTrue(LockedUseActionScope.requiresScreenCaptureKit)
            throw Revoked.lease
        }))
        XCTAssertFalse(LockedUseActionScope.requiresScreenCaptureKit)
    }

    func testRevokedLeaseStopsSkyInputBeforeResolvingTargetOrTouchingSPI() throws {
        guard LockedUseSession.current().state == .unlocked else {
            throw XCTSkip("Requires a completed unlocked console session; no input is emitted")
        }
        // These targets deliberately do not exist. A revoked lease must be
        // reported before capability, process or window checks can run.
        let click = SkyClickTarget(screenPoint: .zero, windowPoint: .zero,
                                   windowBounds: .zero, windowID: 0, pid: -1)
        let keyboard = SkyKeyboardTarget(windowID: 0, pid: -1)
        let actions: [() throws -> Void] = [
            { try SkyClickDispatcher.click(target: click, clickCount: 1) },
            { try SkyKeyboardDispatcher.typeText(target: keyboard, text: "probe") },
            { try SkyKeyboardDispatcher.pressKey(target: keyboard, key: "cmd+a") }
        ]
        for action in actions {
            try LockedUseActionScope.withValidator({ throw Revoked.lease }, body: {
                XCTAssertThrowsError(try action()) { error in
                    XCTAssertTrue(error is Revoked)
                }
            })
        }
    }
}
