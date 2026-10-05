import Foundation
@testable import OpenComputerUseKit
import XCTest

final class LockedUseIPCTests: XCTestCase {
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
