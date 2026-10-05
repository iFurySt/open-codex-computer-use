import XCTest
import PowerNative
import Foundation
final class NativeTests: XCTestCase {
    func testDarwinEmptyACLAndExtendedACL() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        XCTAssertEqual(ocu_power_no_extended_acl(path.path), 0)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow write", path.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(ocu_power_no_extended_acl(path.path), -1)
    }
}
