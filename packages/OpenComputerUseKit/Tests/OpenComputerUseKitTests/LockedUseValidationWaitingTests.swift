import XCTest
@testable import OpenComputerUseKit

final class LockedUseValidationWaitingTests: XCTestCase {
    private let owner = LockedUseStateMachine.Owner(connectionID: UUID(), userID: 501, auditSessionID: 1)
    private let ready = LockedUseStateMachine.Prerequisites(enabled: true, backendValidated: true, clientAuthorized: true)
    private let guards = LockedUseStateMachine.Guards(allDisplaysCovered: true, inputTapHealthy: true, watchdogHealthy: true, displayGeneration: 1)
    private var session: LockedUseSession { .init(state: .locked, userID: 501, auditSessionID: 1) }

    func testLateClaimGetsFreshPermitWithinOriginalValidationDeadline() throws {
        var machine = LockedUseStateMachine(validationWait: true)
        _ = try machine.begin(owner: owner, session: session, prerequisites: ready, now: 100)
        XCTAssertEqual(machine.startupDeadline, 120)
        XCTAssertEqual(try machine.guardsPrepared(guards, now: 101, deferPermitUntilClaim: true), [.requestUnlock])
        for time in 102...117 { XCTAssertEqual(try machine.heartbeat(guards, now: Double(time)), []) }
        XCTAssertNil(machine.permit)
        _ = try machine.authorizationRequested(now: 118)
        let permit = try XCTUnwrap(machine.permit)
        XCTAssertEqual(permit.deadline, 120)
        try machine.consumePermit(id: permit.id, owner: owner, now: 118.1)
        _ = try machine.observe(session: .init(state: .unlocked, userID: 501, auditSessionID: 1), now: 118.2)
        XCTAssertEqual(machine.phase, .active)
        XCTAssertNil(machine.startupDeadline)
    }
    func testValidationWaitExpiresAndCannotRestart() throws {
        var machine = LockedUseStateMachine(validationWait: true)
        _ = try machine.begin(owner: owner, session: session, prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 101, deferPermitUntilClaim: true)
        for time in 102...119 { _ = try machine.heartbeat(guards, now: Double(time)) }
        XCTAssertTrue(try machine.tick(now: 120).contains(.cancelUnlock))
        XCTAssertNil(machine.permit)
        XCTAssertThrowsError(try machine.authorizationRequested(now: 120.1))
    }
    func testLongWaitStillCancelsOnLocalInput() throws {
        var machine = LockedUseStateMachine(validationWait: true)
        _ = try machine.begin(owner: owner, session: session, prerequisites: ready, now: 100)
        _ = try machine.guardsPrepared(guards, now: 101, deferPermitUntilClaim: true)
        XCTAssertTrue(machine.localInput().contains(.cancelUnlock))
        XCTAssertThrowsError(try machine.authorizationRequested(now: 102))
    }
}
