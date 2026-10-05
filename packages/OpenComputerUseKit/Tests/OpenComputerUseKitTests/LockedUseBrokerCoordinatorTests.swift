import Foundation
@testable import OpenComputerUseKit
import XCTest

final class LockedUseBrokerCoordinatorTests: XCTestCase {
    private let agent = LockedUseBrokerCoordinator.Context(id: UUID(), role: .agent, userID: 501, auditSessionID: 42)
    private let guardian = LockedUseBrokerCoordinator.Context(id: UUID(), role: .guardian, userID: 501, auditSessionID: 42)
    private let plugin = LockedUseBrokerCoordinator.Context(id: UUID(), role: .plugin, userID: 88, auditSessionID: 42)
    private let locked = LockedUseSession(state: .locked, userID: 501, auditSessionID: 42)
    private let unlocked = LockedUseSession(state: .unlocked, userID: 501, auditSessionID: 42)
    private let healthy = LockedUseStateMachine.Guards(allDisplaysCovered: true, inputTapHealthy: true, watchdogHealthy: true, displayGeneration: 1)

    private func prepare(_ broker: inout LockedUseBrokerCoordinator) throws -> UUID {
        let begin = try broker.handle(.init(operation: .begin, session: locked), context: agent, now: 1)
        let lease = try XCTUnwrap(begin.leaseID)
        XCTAssertEqual(begin.effects, ["prepareGuards"])
        _ = try broker.handle(.init(operation: .guardianHello, leaseID: lease, token: begin.token), context: guardian, now: 1.1)
        let ready = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: locked, guards: healthy), context: guardian, now: 1.2)
        XCTAssertEqual(ready.effects, ["requestUnlock"])
        return lease
    }

    private func grant(_ broker: inout LockedUseBrokerCoordinator, lease: UUID) throws {
        let claim = try broker.handle(.init(operation: .pluginClaim), context: plugin, now: 1.3)
        let consumed = try broker.handle(.init(operation: .pluginConsume, leaseID: lease, token: claim.token), context: plugin, now: 1.4)
        XCTAssertEqual(consumed.result, .authorized)
        XCTAssertEqual(consumed.phase, .unlocking)
        XCTAssertThrowsError(try broker.handle(.init(operation: .pluginConsume, leaseID: lease, token: claim.token), context: plugin, now: 1.4))
    }

    func testPermitConsumptionDoesNotAuthorizeGUIUntilObservedUnlock() throws {
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        let lease = try prepare(&broker)
        try grant(&broker, lease: lease)
        XCTAssertThrowsError(try broker.handle(.init(operation: .action, leaseID: lease, session: unlocked), context: agent, now: 1.5))
        _ = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: unlocked, guards: healthy, unlockWorkPending: false), context: guardian, now: 1.6)
        let action = try broker.handle(.init(operation: .action, leaseID: lease, session: unlocked), context: agent, now: 1.7)
        XCTAssertEqual(action.result, .active)
        let foreign = LockedUseBrokerCoordinator.Context(id: UUID(), role: .agent, userID: 501, auditSessionID: 42)
        XCTAssertThrowsError(try broker.handle(.init(operation: .action, leaseID: lease, session: unlocked), context: foreign, now: 1.8))
        let status = try broker.handle(.init(operation: .status), context: foreign, now: 1.9)
        XCTAssertNotEqual(status.result, .active)
        XCTAssertNil(status.leaseID)
    }

    func testConsumedAllowAndOriginalLockCannotReleaseGuards() throws {
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        let lease = try prepare(&broker)
        try grant(&broker, lease: lease)
        _ = try broker.handle(.init(operation: .end), context: agent, now: 1.5)
        _ = try broker.handle(.init(operation: .quiesced, leaseID: lease), context: agent, now: 1.6)
        let report = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: locked, guards: healthy), context: guardian, now: 1.7)
        XCTAssertEqual(report.phase, .relocking)
        XCTAssertFalse(report.effects.contains("releaseGuards"))
    }

    func testLateUnlockIsRelockedBeforeReleaseAfterCancellation() throws {
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        let lease = try prepare(&broker)
        try grant(&broker, lease: lease)
        _ = try broker.handle(.init(operation: .end), context: agent, now: 1.5)
        _ = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: unlocked, guards: healthy, unlockWorkPending: false), context: guardian, now: 1.6)
        _ = try broker.handle(.init(operation: .quiesced, leaseID: lease), context: agent, now: 1.7)
        let report = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: locked, guards: healthy), context: guardian, now: 1.8)
        XCTAssertEqual(report.result, .release)
        XCTAssertTrue(report.effects.contains("releaseGuards"))
    }

    func testRoleSessionChallengeAndStaleEvidenceAreRejected() throws {
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        let begin = try broker.handle(.init(operation: .begin, session: locked), context: agent, now: 1)
        let lease = try XCTUnwrap(begin.leaseID)
        XCTAssertThrowsError(try broker.handle(.init(operation: .guardianHello, leaseID: lease, token: Data(repeating: 0, count: 32)), context: guardian, now: 1.1))
        XCTAssertThrowsError(try broker.handle(.init(operation: .guardianHello, leaseID: lease, token: begin.token), context: agent, now: 1.1))
        _ = try broker.handle(.init(operation: .guardianHello, leaseID: lease, token: begin.token), context: guardian, now: 1.2)
        _ = try broker.handle(.init(operation: .guardianReport, leaseID: lease, session: locked, guards: healthy), context: guardian, now: 1.3)
        let wrongSession = LockedUseBrokerCoordinator.Context(id: UUID(), role: .plugin, userID: 88, auditSessionID: 43)
        XCTAssertThrowsError(try broker.handle(.init(operation: .pluginClaim), context: wrongSession, now: 1.4))
        XCTAssertThrowsError(try broker.handle(.init(operation: .pluginClaim), context: plugin, now: 2.4))
    }

    func testDisconnectRevokesPendingPermit() throws {
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        _ = try prepare(&broker)
        try broker.disconnected(agent)
        XCTAssertEqual(broker.phase, .relocking)
        XCTAssertThrowsError(try broker.handle(.init(operation: .pluginClaim), context: plugin, now: 1.4))
    }

    func testUnvalidatedBackendAndForgedSessionCannotBegin() throws {
        var disabled = LockedUseBrokerCoordinator(enabled: true, backendValidated: false)
        XCTAssertThrowsError(try disabled.handle(.init(operation: .begin, session: locked), context: agent, now: 1))
        var broker = LockedUseBrokerCoordinator(enabled: true, backendValidated: true)
        let wrong = LockedUseSession(state: .locked, userID: 502, auditSessionID: 42)
        XCTAssertThrowsError(try broker.handle(.init(operation: .begin, session: wrong), context: agent, now: 1))
        XCTAssertThrowsError(try broker.handle(.init(operation: .begin, session: locked), context: guardian, now: 1))
    }
}
