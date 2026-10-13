import Foundation
@testable import OpenComputerUseKit
import XCTest

final class LockedUseUnshieldedDiagnosticTests: XCTestCase {
    private let owner = LockedUseBrokerCoordinator.Context(id: UUID(), role: .guardian, userID: 501, auditSessionID: 42)
    private let plugin = LockedUseBrokerCoordinator.Context(id: UUID(), role: .plugin, userID: 88, auditSessionID: 42)
    private let locked = LockedUseSession(state: .locked, userID: 501, auditSessionID: 42)

    func testUnshieldedEntryRequiresValidationAndNeverAuthorizesActionsOrEvidence() throws {
        var production = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        XCTAssertThrowsError(try production.handle(.init(operation: .beginUnshieldedDiagnostic, session: locked), context: owner, now: 1))
        var diagnostic = LockedUseBrokerCoordinator(enabled: true, backendValidated: false, requiresWatchdog: true, validationMode: true)
        let begin = try diagnostic.handle(.init(operation: .beginUnshieldedDiagnostic, session: locked), context: owner, now: 1)
        XCTAssertEqual(begin.detail, "unshieldedDiagnostic")
        XCTAssertEqual(begin.phase, .authorizing)
        XCTAssertTrue(diagnostic.isFullyReleased)
        XCTAssertNil(diagnostic.recordedGuardian)
        XCTAssertNil(diagnostic.recordedWatchdog)
        for operation in [LockedUseIPCMessage.Operation.action, .validationPassed, .begin, .beginRecoveryProbe, .guardianReport] {
            XCTAssertThrowsError(try diagnostic.handle(.init(operation: operation, leaseID: begin.leaseID, session: locked), context: owner, now: 1.1))
        }
        XCTAssertNil(diagnostic.recoveryRecord(clientToken: Data(repeating: 0, count: 32)))
    }
    func testSameAuditSingleUsePermitAndNoResumeAfterExpiry() throws {
        var probe = try LockedUseUnshieldedDiagnostic(owner: owner, session: locked, now: 100)
        let foreign = LockedUseBrokerCoordinator.Context(id: UUID(), role: .plugin, userID: 88, auditSessionID: 43)
        XCTAssertThrowsError(try probe.handle(.init(operation: .pluginClaim), context: foreign, now: 118))
        let claim = try probe.handle(.init(operation: .pluginClaim), context: plugin, now: 118)
        XCTAssertEqual(claim.token?.count, 32)
        XCTAssertThrowsError(try probe.handle(.init(operation: .pluginClaim), context: plugin, now: 118.1))
        let consume = LockedUseIPCMessage(operation: .pluginConsume, leaseID: claim.leaseID, token: claim.token)
        XCTAssertEqual(try probe.handle(consume, context: plugin, now: 119).result, .authorized)
        XCTAssertThrowsError(try probe.handle(consume, context: plugin, now: 119.1))
        try probe.tick(now: 120)
        XCTAssertEqual(probe.phase, .awaitingManualUnlock)
        _ = try probe.handle(.init(operation: .status, session: locked), context: owner, now: 121)
        XCTAssertThrowsError(try probe.handle(.init(operation: .pluginClaim), context: plugin, now: 121))
    }
    func testFiveSecondPermitAndCancellationCannotRearm() throws {
        var probe = try LockedUseUnshieldedDiagnostic(owner: owner, session: locked, now: 0)
        let claim = try probe.handle(.init(operation: .pluginClaim), context: plugin, now: 1)
        XCTAssertThrowsError(try probe.handle(.init(operation: .pluginConsume, leaseID: claim.leaseID, token: claim.token), context: plugin, now: 6))
        XCTAssertEqual(probe.phase, .awaitingManualUnlock)
        probe.cancel()
        XCTAssertThrowsError(try probe.handle(.init(operation: .pluginClaim), context: plugin, now: 7))
    }
    func testEndRequiresSameOriginalLockedSessionAndCoordinatorReturnsIdle() throws {
        var coordinator = LockedUseBrokerCoordinator(enabled: true, backendValidated: false, validationMode: true)
        let begin = try coordinator.handle(.init(operation: .beginUnshieldedDiagnostic, session: locked), context: owner, now: 1)
        let wrong = LockedUseSession(state: .locked, userID: 502, auditSessionID: 42)
        XCTAssertThrowsError(try coordinator.handle(.init(operation: .endUnshieldedDiagnostic, leaseID: begin.leaseID, session: wrong), context: owner, now: 2))
        let end = try coordinator.handle(.init(operation: .endUnshieldedDiagnostic, leaseID: begin.leaseID, session: locked), context: owner, now: 2)
        XCTAssertEqual(end.phase, .idle)
        XCTAssertEqual(coordinator.phase, .idle)
    }
    func testWrongOwnerSessionAndClockRegressionAreDenied() throws {
        XCTAssertThrowsError(try LockedUseUnshieldedDiagnostic(owner: plugin, session: locked, now: 0))
        var probe = try LockedUseUnshieldedDiagnostic(owner: owner, session: locked, now: 100)
        XCTAssertThrowsError(try probe.tick(now: 99))
        let wrong = LockedUseSession(state: .locked, userID: 501, auditSessionID: 43)
        XCTAssertThrowsError(try probe.handle(.init(operation: .status, session: wrong), context: owner, now: 100))
    }
}
