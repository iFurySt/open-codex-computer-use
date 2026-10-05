import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class LockedUseTests: XCTestCase {
    private let owner = LockedUseStateMachine.Owner(connectionID: UUID(), userID: 501, auditSessionID: 1)
    private let ready = LockedUseStateMachine.Prerequisites(enabled: true, backendValidated: true, clientAuthorized: true)
    private let guards = LockedUseStateMachine.Guards(allDisplaysCovered: true, inputTapHealthy: true, watchdogHealthy: true, displayGeneration: 1)

    private func session(_ state: LockedUseSession.State, uid: UInt32 = 501, console: UInt32 = 1) -> LockedUseSession {
        .init(state: state, userID: uid, auditSessionID: console)
    }

    private func active() throws -> LockedUseStateMachine {
        var machine = LockedUseStateMachine()
        XCTAssertEqual(try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100), [.prepareGuards])
        let effects = try machine.guardsPrepared(guards, now: 100.1)
        guard case let .issuePermit(permit) = effects.first else { XCTFail("permit missing"); return machine }
        XCTAssertEqual(effects, [.issuePermit(permit), .requestUnlock])
        XCTAssertEqual(machine.phase, .authorizing)
        try machine.consumePermit(id: permit.id, owner: owner, now: 100.2)
        XCTAssertEqual(machine.phase, .unlocking)
        XCTAssertEqual(try machine.observe(session: session(.unlocked), now: 100.3), [.revokePermit])
        XCTAssertEqual(machine.phase, .active)
        return machine
    }

    func testProtectBeforeIssuingPermitAndRequireObservedUnlock() throws {
        var machine = LockedUseStateMachine()
        _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
        XCTAssertNil(machine.permit)
        XCTAssertThrowsError(try machine.authorizeAction(owner: owner, session: session(.unlocked), now: 100))
        _ = try machine.guardsPrepared(guards, now: 100)
        // An unrelated unlock notification before permit consumption grants nothing.
        XCTAssertEqual(try machine.observe(session: session(.unlocked), now: 100), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.phase, .relocking)
        XCTAssertThrowsError(try machine.authorizeAction(owner: owner, session: session(.unlocked), now: 100))
    }

    func testAuthorizationPrerequisitesFailBeforeAnyEffect() {
        for (prerequisites, expected) in [
            (LockedUseStateMachine.Prerequisites(enabled: false, backendValidated: true, clientAuthorized: true), LockedUseStateMachine.Failure.disabled),
            (.init(enabled: true, backendValidated: false, clientAuthorized: true), .backendUnvalidated),
            (.init(enabled: true, backendValidated: true, clientAuthorized: false), .clientUnauthorized)
        ] {
            var machine = LockedUseStateMachine()
            XCTAssertThrowsError(try machine.begin(owner: owner, session: session(.locked), prerequisites: prerequisites, now: 100)) {
                XCTAssertEqual($0 as? LockedUseStateMachine.Failure, expected)
            }
            XCTAssertEqual(machine.phase, .idle)
            XCTAssertNil(machine.owner)
            XCTAssertNil(machine.permit)
        }
    }

    func testInvalidOrDifferentConsoleCannotStart() {
        for invalid in [session(.unlocked), session(.unavailable), session(.locked, uid: 502), session(.locked, console: 2)] {
            var machine = LockedUseStateMachine()
            XCTAssertThrowsError(try machine.begin(owner: owner, session: invalid, prerequisites: ready, now: 100))
            XCTAssertEqual(machine.phase, .idle)
        }
    }

    func testEveryGuardMustBeHealthyBeforeUnlock() throws {
        for broken in [
            LockedUseStateMachine.Guards(allDisplaysCovered: false, inputTapHealthy: true, watchdogHealthy: true, displayGeneration: 1),
            .init(allDisplaysCovered: true, inputTapHealthy: false, watchdogHealthy: true, displayGeneration: 1),
            .init(allDisplaysCovered: true, inputTapHealthy: true, watchdogHealthy: false, displayGeneration: 1)
        ] {
            var machine = LockedUseStateMachine()
            _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
            XCTAssertEqual(try machine.guardsPrepared(broken, now: 100), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
            XCTAssertNil(machine.permit)
        }
    }

    func testPermitCannotBeReplayedOrConsumedByAnotherClient() throws {
        var machine = LockedUseStateMachine()
        _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 100)
        let permit = try XCTUnwrap(machine.permit)
        let stranger = LockedUseStateMachine.Owner(connectionID: UUID(), userID: 501, auditSessionID: 1)
        XCTAssertThrowsError(try machine.consumePermit(id: permit.id, owner: stranger, now: 100))
        XCTAssertThrowsError(try machine.consumePermit(id: UUID(), owner: owner, now: 100))
        try machine.consumePermit(id: permit.id, owner: owner, now: 100)
        XCTAssertThrowsError(try machine.consumePermit(id: permit.id, owner: owner, now: 100))
    }

    func testExpiredPermitIsNeverConsumed() throws {
        var machine = LockedUseStateMachine()
        _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 100)
        let permit = try XCTUnwrap(machine.permit)
        XCTAssertThrowsError(try machine.consumePermit(id: permit.id, owner: owner, now: permit.deadline))
    }

    func testRelockMustBeConfirmedBeforeUnshielding() throws {
        var machine = try active()
        XCTAssertEqual(try machine.end(owner: owner, reason: .turnEnded), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(try machine.observe(session: session(.unlocked), now: 101), [])
        XCTAssertEqual(try machine.observe(session: session(.unavailable), now: 102), [])
        XCTAssertEqual(machine.retryRelock(), [.requestRelock])
        XCTAssertEqual(try machine.observe(session: session(.locked), now: 102), [])
        try machine.confirmQuiescence(owner: owner)
        XCTAssertEqual(try machine.observe(session: session(.locked), now: 103), [.releaseGuards])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testPhysicalTakeoverSuppressesQueuedUnlockUntilManualUnlock() throws {
        var machine = try active()
        XCTAssertEqual(machine.localInput(), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.localInput(), [])
        XCTAssertThrowsError(try machine.authorizeAction(owner: owner, session: session(.unlocked), now: 101))
        try machine.confirmQuiescence(owner: owner)
        XCTAssertEqual(try machine.observe(session: session(.locked), now: 101), [.releaseGuards])
        XCTAssertEqual(machine.phase, .awaitingManualUnlock)
        XCTAssertThrowsError(try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 102))
        _ = try machine.observe(session: session(.unlocked, uid: 502), now: 103)
        XCTAssertEqual(machine.phase, .awaitingManualUnlock)
        _ = try machine.observe(session: session(.unlocked), now: 104)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testTakeoverDuringPendingUnlockRevokesPermission() throws {
        var machine = LockedUseStateMachine()
        _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 100)
        let permit = try XCTUnwrap(machine.permit)
        XCTAssertEqual(machine.localInput(), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertThrowsError(try machine.consumePermit(id: permit.id, owner: owner, now: 100.1))
        XCTAssertEqual(try machine.observe(session: session(.unlocked), now: 100.2), [])
        XCTAssertEqual(machine.phase, .relocking)
    }

    func testOriginalLockedScreenCannotReleaseGuardsWhileUnlockIsPending() throws {
        var machine = LockedUseStateMachine()
        _ = try machine.begin(owner: owner, session: session(.locked), prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 100)
        _ = machine.localInput()
        XCTAssertEqual(try machine.observe(session: session(.locked), now: 101), [])
        XCTAssertEqual(machine.phase, .relocking)
        let stranger = LockedUseStateMachine.Owner(connectionID: UUID(), userID: 501, auditSessionID: 1)
        XCTAssertThrowsError(try machine.confirmQuiescence(owner: stranger))
        try machine.confirmQuiescence(owner: owner)
        XCTAssertEqual(try machine.observe(session: session(.unlocked), now: 102), [])
        XCTAssertEqual(try machine.observe(session: session(.locked), now: 103), [.releaseGuards])
        XCTAssertEqual(machine.phase, .awaitingManualUnlock)
    }

    func testCompetingClientCannotAcquireOrEndLease() throws {
        var machine = try active()
        let stranger = LockedUseStateMachine.Owner(connectionID: UUID(), userID: 501, auditSessionID: 1)
        XCTAssertThrowsError(try machine.begin(owner: stranger, session: session(.locked), prerequisites: ready, now: 101))
        XCTAssertThrowsError(try machine.end(owner: stranger, reason: .turnEnded))
        XCTAssertThrowsError(try machine.authorizeAction(owner: stranger, session: session(.unlocked), now: 101))
        XCTAssertEqual(machine.phase, .active)
    }

    func testChangedDisplayGenerationRelocksRatherThanAcceptingNewCoverage() throws {
        var machine = try active()
        let newDisplay = LockedUseStateMachine.Guards(allDisplaysCovered: true, inputTapHealthy: true, watchdogHealthy: true, displayGeneration: 2)
        XCTAssertEqual(try machine.heartbeat(newDisplay, now: 101), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.stopReason, .guardLost)
    }

    func testLateHeartbeatCannotResurrectLease() throws {
        var machine = try active()
        XCTAssertEqual(try machine.heartbeat(guards, now: 104), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.phase, .relocking)
    }

    func testIdleTimeoutWithHealthyHeartbeatAndNoFurtherActions() throws {
        var machine = try active()
        for second in 101...130 {
            XCTAssertEqual(try machine.heartbeat(guards, now: Double(second)), [])
        }
        XCTAssertEqual(try machine.tick(now: 130.3), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.stopReason, .idleTimeout)
    }

    func testLeaseHasAbsoluteDeadlineDespiteActivityAndHeartbeats() throws {
        var machine = try active()
        for second in 101...399 {
            _ = try machine.heartbeat(guards, now: Double(second))
            XCTAssertEqual(try machine.authorizeAction(owner: owner, session: session(.unlocked), now: Double(second)), [])
        }
        XCTAssertEqual(try machine.tick(now: 400), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(machine.stopReason, .leaseExpired)
    }

    func testChangedConsoleAtActionBoundaryStopsActions() throws {
        var machine = try active()
        XCTAssertEqual(try machine.authorizeAction(owner: owner, session: session(.unlocked, console: 2), now: 101), [.stopActions, .revokePermit, .cancelUnlock, .requestRelock])
        XCTAssertEqual(try machine.observe(session: session(.locked, console: 2), now: 102), [])
        XCTAssertEqual(machine.phase, .relocking)
    }

    func testMonotonicClockRejectsRollbackAndNonFiniteValues() throws {
        var machine = try active()
        for time in [99, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try machine.tick(now: time)) {
                XCTAssertEqual($0 as? LockedUseStateMachine.Failure, .invalidClock)
            }
        }
    }

    func testSessionParsingRejectsUnknownUnloggedAndOtherUserSessions() {
        let normal: [String: Any] = [
            kCGSessionOnConsoleKey as String: true,
            kCGSessionLoginDoneKey as String: true,
            kCGSessionUserIDKey as String: 501,
            "kCGSSessionAuditIDKey": 1
        ]
        XCTAssertEqual(LockedUseSession.from(dictionary: normal, effectiveUserID: 501, securitySessionID: 1), session(.unlocked))
        var locked = normal
        locked["CGSSessionScreenIsLocked"] = true
        XCTAssertEqual(LockedUseSession.from(dictionary: locked, effectiveUserID: 501, securitySessionID: 1), session(.locked))
        for malformed in [nil, [:], [kCGSessionOnConsoleKey as String: true]] as [[String: Any]?] {
            XCTAssertEqual(LockedUseSession.from(dictionary: malformed, effectiveUserID: 501, securitySessionID: 1).state, .unavailable)
        }
        XCTAssertEqual(LockedUseSession.from(dictionary: normal, effectiveUserID: 502, securitySessionID: 1).state, .unavailable)
        XCTAssertEqual(LockedUseSession.from(dictionary: normal, effectiveUserID: 501, securitySessionID: nil).state, .unavailable)
        XCTAssertEqual(LockedUseSession.from(dictionary: normal, effectiveUserID: 501, securitySessionID: 2).state, .unavailable)
        var withoutAuditKey = normal
        withoutAuditKey.removeValue(forKey: "kCGSSessionAuditIDKey")
        XCTAssertEqual(LockedUseSession.from(dictionary: withoutAuditKey, effectiveUserID: 501, securitySessionID: 1), session(.unlocked))
        for (key, value) in [(kCGSessionLoginDoneKey as String, false as Any), (kCGSessionOnConsoleKey as String, false as Any), ("CGSSessionScreenIsLocked", "false" as Any), (kCGSessionUserIDKey as String, true as Any), ("kCGSSessionAuditIDKey", -1 as Any), (kCGSessionLoginDoneKey as String, 1 as Any)] {
            var invalid = normal
            invalid[key] = value
            XCTAssertEqual(LockedUseSession.from(dictionary: invalid, effectiveUserID: 501, securitySessionID: 1).state, .unavailable)
        }
    }

    func testRealAppSessionGateRejectsLockedAndUnavailableSessions() throws {
        // This test isolates the session gate; an installed system Broker is
        // covered by IPC tests and must not require signing the XCTest host.
        try LockedUseActionScope.withValidator({}, body: {
            try requireUsableComputerUseSession(session(.unlocked))
        })
        XCTAssertThrowsError(try requireUsableComputerUseSession(session(.locked)))
        XCTAssertThrowsError(try requireUsableComputerUseSession(session(.unavailable)))
    }

    func testCLIRoutesAdministrationLocallyAndRejectsMalformedCommands() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["locked-use", "status"]), .lockedUseStatus(json: false))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["locked-use", "status", "--json"]), .lockedUseStatus(json: true))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["locked-use", "--help"]), .help(command: "locked-use"))
        XCTAssertTrue(shouldUseMacOSAppAgentProxy(command: .lockedUseStatus(json: true), proxyDisabled: false, appBundleAvailable: true, runningFromLaunchServicesAppInstance: false))
        for action in ["enable", "disable", "recover", "certify", "settings"] {
            let command = OpenComputerUseCLICommand.lockedUseManagement(action: action, validation: false)
            XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["locked-use", action]), command)
            XCTAssertFalse(shouldUseMacOSAppAgentProxy(command: command, proxyDisabled: false, appBundleAvailable: true, runningFromLaunchServicesAppInstance: false))
        }
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["locked-use", "enable", "--validation"]), .lockedUseManagement(action: "enable", validation: true))
        for arguments in [["status", "--json", "--json"], ["disable", "--validation"], ["enable", "--validation", "extra"], ["authorize-client", "test"], ["uninstall"], ["unknown"], []] {
            XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["locked-use"] + arguments))
        }
    }
}
