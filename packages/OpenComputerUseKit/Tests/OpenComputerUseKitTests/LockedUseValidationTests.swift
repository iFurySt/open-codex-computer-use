import Foundation
@testable import OpenComputerUseKit
import XCTest

final class LockedUseValidationTests: XCTestCase {
    private let evidence = LockedUseComponentValidation.Evidence(osBuild: "TEST1", brokerHash: "aa", guardianHash: "bb", pluginHash: "cc")

    func testCannotPromoteBeforeRelockReleaseAndManualKeychainVerification() {
        var report = LockedUseValidationReport(leaseID: UUID(), evidence: evidence, ownerToken: Data(repeating: 1, count: 32))
        XCTAssertFalse(report.canPromote(current: evidence))
        report.lockedAndReleased = true
        XCTAssertFalse(report.canPromote(current: evidence))
        report.afterManualUnlockPassed = true
        XCTAssertTrue(report.canPromote(current: evidence))
        let changed = LockedUseComponentValidation.Evidence(osBuild: "TEST2", brokerHash: "aa", guardianHash: "bb", pluginHash: "cc")
        XCTAssertFalse(report.canPromote(current: changed))
        let changedBinary = LockedUseComponentValidation.Evidence(osBuild: "TEST1", brokerHash: "new", guardianHash: "bb", pluginHash: "cc")
        XCTAssertFalse(report.canPromote(current: changedBinary))
    }

    func testUnattestedOwnerCannotProducePromotionEvidence() {
        var report = LockedUseValidationReport(leaseID: UUID(), evidence: evidence, ownerToken: Data())
        report.lockedAndReleased = true; report.afterManualUnlockPassed = true
        XCTAssertFalse(report.canPromote(current: evidence))
    }
}
