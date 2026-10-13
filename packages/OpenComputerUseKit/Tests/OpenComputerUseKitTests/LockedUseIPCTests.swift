import Foundation
import Darwin
import LockedUseNative
@testable import OpenComputerUseKit
import XCTest

final class LockedUseIPCTests: XCTestCase {
    func testTransferredSocketRetainsKernelPeerAndIsCloseOnExec() throws {
        var channel: [Int32] = [-1, -1], peer: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &channel), 0)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &peer), 0)
        defer { for fd in channel + peer { Darwin.close(fd) } }
        XCTAssertEqual(ocu_send_peer_socket(channel[0], peer[0]), 0)
        let copied = ocu_receive_peer_socket(channel[1])
        XCTAssertGreaterThanOrEqual(copied, 0)
        defer { Darwin.close(copied) }
        XCTAssertNotEqual(fcntl(copied, F_GETFD) & FD_CLOEXEC, 0)
        var identity = OCUPeerIdentity()
        XCTAssertEqual(ocu_copy_peer_identity(copied, &identity), 0)
        XCTAssertEqual(identity.effective_user_id, geteuid())
        XCTAssertEqual(identity.process_id, getpid())
    }

    func testMissingDescriptorAndNonSocketDoNotSupplyPeerIdentity() throws {
        var channel: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &channel), 0)
        defer { for fd in channel { Darwin.close(fd) } }
        var marker: UInt8 = 0x4f
        XCTAssertEqual(Darwin.write(channel[0], &marker, 1), 1)
        XCTAssertEqual(ocu_receive_peer_socket(channel[1]), -1)
        var pipeFDs: [Int32] = [-1, -1]
        XCTAssertEqual(pipe(&pipeFDs), 0)
        defer { for fd in pipeFDs { Darwin.close(fd) } }
        XCTAssertEqual(ocu_send_peer_socket(channel[0], pipeFDs[0]), 0)
        let copied = ocu_receive_peer_socket(channel[1])
        defer { Darwin.close(copied) }
        var identity = OCUPeerIdentity()
        XCTAssertEqual(ocu_copy_peer_identity(copied, &identity), -1)
    }

    func testExpiredRPCDeadlineFailsWithoutWaiting() throws {
        var channel: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &channel), 0)
        defer { for fd in channel { Darwin.close(fd) } }
        XCTAssertThrowsError(try LockedUseIPCSocket.wait(descriptor: channel[0], events: Int16(POLLIN), deadline: ProcessInfo.processInfo.systemUptime - 1))
    }

    func testFragmentedFramesAndCoalescedMessagesRoundTrip() throws {
        let message = LockedUseIPCMessage(operation: .status)
        let encoded = try LockedUseIPCFrame.encode(message)
        var decoder = LockedUseIPCFrame()
        var frames: [Data] = []
        for byte in encoded { frames += try decoder.append(Data([byte])) }
        XCTAssertEqual(frames.count, 1)
        let decoded = try JSONDecoder().decode(LockedUseIPCMessage.self, from: frames[0]).validated()
        XCTAssertEqual(decoded.id, message.id)
        frames = try decoder.append(encoded + encoded)
        XCTAssertEqual(frames.count, 2)
        XCTAssertNoThrow(try decoder.finish())
    }

    func testInvalidLengthsFloodAndTruncatedEOFPoisonStream() throws {
        for input in [Data([0, 0, 0, 0]), Data([0, 1, 0, 0]), Data(repeating: 1, count: 4097)] {
            var decoder = LockedUseIPCFrame()
            XCTAssertThrowsError(try decoder.append(input))
            XCTAssertThrowsError(try decoder.append(Data()))
        }
        var decoder = LockedUseIPCFrame()
        _ = try decoder.append(Data([0, 0, 0, 5, 1]))
        XCTAssertThrowsError(try decoder.finish())
        XCTAssertThrowsError(try decoder.append(Data([2, 3, 4, 5])))
    }

    func testProtocolVersionAndNonceLengthAreNotImplicitlyTrusted() throws {
        XCTAssertThrowsError(try LockedUseIPCMessage(operation: .pluginConsume, token: Data([1])).validated())
        let bad = Data("{\"version\":2,\"id\":\"00000000-0000-0000-0000-000000000001\",\"operation\":\"begin\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LockedUseIPCMessage.self, from: bad).validated())
    }
}
