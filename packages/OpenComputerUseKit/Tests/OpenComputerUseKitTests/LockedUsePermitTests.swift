import XCTest
@testable import OpenComputerUseKit

final class LockedUsePermitTests: XCTestCase {
    private let session = LockedUsePermitRegistry.Session(userID: 501, auditSessionID: 10)
    private let nonce = Data(repeating: 17, count: 32)

    func testExactlyOnceAndWrongSessionOrNonceCannotConsume() throws {
        var registry = LockedUsePermitRegistry()
        let id = UUID(), connection = UUID()
        let permit = try registry.issue(attemptID: id, connectionID: connection, session: session, guardsHealthy: true, now: 100, nonce: nonce)
        XCTAssertThrowsError(try registry.consume(attemptID: id, session: .init(userID: 502, auditSessionID: 10), nonce: nonce, guardsHealthy: true, now: 100))
        XCTAssertThrowsError(try registry.consume(attemptID: id, session: session, nonce: Data(repeating: 0, count: 32), guardsHealthy: true, now: 100))
        XCTAssertEqual(try registry.consume(attemptID: id, session: session, nonce: nonce, guardsHealthy: true, now: 100), permit)
        XCTAssertThrowsError(try registry.consume(attemptID: id, session: session, nonce: nonce, guardsHealthy: true, now: 100))
        XCTAssertThrowsError(try registry.issue(attemptID: id, connectionID: connection, session: session, guardsHealthy: true, now: 100, nonce: nonce))
    }

    func testExpiryAndLostGuardBurnAttempt() throws {
        for (healthy, time) in [(true, 105.0), (false, 101.0)] {
            var registry = LockedUsePermitRegistry()
            let id = UUID(), connection = UUID()
            _ = try registry.issue(attemptID: id, connectionID: connection, session: session, guardsHealthy: true, now: 100, nonce: nonce)
            XCTAssertThrowsError(try registry.consume(attemptID: id, session: session, nonce: nonce, guardsHealthy: healthy, now: time))
            XCTAssertEqual(registry.pendingCount, 0)
            XCTAssertThrowsError(try registry.issue(attemptID: id, connectionID: connection, session: session, guardsHealthy: true, now: time, nonce: nonce))
        }
    }

    func testDisconnectRevokesOnlyOwnConnectionAndSessionCannotHaveTwoPermits() throws {
        var registry = LockedUsePermitRegistry()
        let id = UUID(), connection = UUID()
        _ = try registry.issue(attemptID: id, connectionID: connection, session: session, guardsHealthy: true, now: 100, nonce: nonce)
        XCTAssertThrowsError(try registry.issue(attemptID: UUID(), connectionID: UUID(), session: session, guardsHealthy: true, now: 100, nonce: nonce))
        registry.revoke(connectionID: UUID())
        XCTAssertEqual(registry.pendingCount, 1)
        registry.revoke(connectionID: connection)
        XCTAssertEqual(registry.pendingCount, 0)
        XCTAssertThrowsError(try registry.consume(attemptID: id, session: session, nonce: nonce, guardsHealthy: true, now: 100))
    }

    func testInvalidClockAndMissingGuardsNeverIssue() throws {
        var registry = LockedUsePermitRegistry()
        XCTAssertThrowsError(try registry.issue(attemptID: UUID(), connectionID: UUID(), session: session, guardsHealthy: false, now: 100, nonce: nonce))
        XCTAssertThrowsError(try registry.issue(attemptID: UUID(), connectionID: UUID(), session: session, guardsHealthy: true, now: 99, nonce: nonce))
        XCTAssertThrowsError(try registry.expire(now: .infinity))
    }
}
