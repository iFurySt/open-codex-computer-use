import Darwin
import XCTest
@testable import OpenComputerUseKit

final class LockedUsePeerRevalidationTests: XCTestCase {
    func testKernelRecheckAcceptsSameLivePeerAndRejectsForgedHashOrToken() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Kernel requirements need macOS 14.4") }
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
        // Test executable can be ad hoc signed; production admission retains
        // its administrator-supplied Apple/Developer ID requirement.
        let peer = try LockedUsePeerIdentity.verified(socket: sockets[0], requirement: "true")
        XCTAssertEqual(try peer.revalidated(socket: sockets[0]).auditToken, peer.auditToken)
        func changed(hash: Data, token: Data) -> LockedUsePeerIdentity {
            .init(auditToken: token, userID: peer.userID, auditUserID: peer.auditUserID,
                  auditSessionID: peer.auditSessionID, processID: peer.processID,
                  signingIdentifier: peer.signingIdentifier, teamIdentifier: peer.teamIdentifier,
                  codeDirectoryHash: hash, designatedRequirement: peer.designatedRequirement,
                  hardenedRuntime: peer.hardenedRuntime, permitsCodeInjection: peer.permitsCodeInjection)
        }
        XCTAssertThrowsError(try changed(hash: Data(repeating: 0, count: peer.codeDirectoryHash.count),
                                        token: peer.auditToken).revalidated(socket: sockets[0]))
        XCTAssertThrowsError(try changed(hash: peer.codeDirectoryHash,
                                        token: Data(repeating: 0, count: peer.auditToken.count)).revalidated(socket: sockets[0]))
        XCTAssertThrowsError(try peer.revalidated(socket: -1))
    }
}
