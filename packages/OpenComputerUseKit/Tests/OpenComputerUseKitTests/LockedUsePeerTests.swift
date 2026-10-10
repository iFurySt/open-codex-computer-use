import Darwin
import LockedUseNative
import Security
import XCTest
@testable import OpenComputerUseKit

final class LockedUsePeerTests: XCTestCase {
    func testKernelTokenIdentifiesConnectionWithoutRequestMetadata() throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { close(sockets[0]); close(sockets[1]) }
        var peer = OCUPeerIdentity()
        XCTAssertEqual(ocu_copy_peer_identity(sockets[0], &peer), 0)
        XCTAssertEqual(peer.effective_user_id, geteuid())
        XCTAssertEqual(peer.process_id, getpid())
        var sessionID = SecuritySessionId()
        var attributes = SessionAttributeBits()
        XCTAssertEqual(SessionGetInfo(callerSecuritySession, &sessionID, &attributes), errSecSuccess)
        XCTAssertEqual(peer.audit_session_id, sessionID)
    }

    func testUnconnectedDescriptorCannotInventIdentity() {
        XCTAssertThrowsError(try LockedUsePeerIdentity.verified(socket: -1, requirement: "true")) { error in
            guard case LockedUsePeerIdentity.Failure.peerUnavailable = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testSameUserDoesNotSatisfyWrongCodeSignature() {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { close(sockets[0]); close(sockets[1]) }
        XCTAssertThrowsError(try LockedUsePeerIdentity.verified(socket: sockets[0], requirement: "identifier \"dev.unapproved.client\""))
    }
}
