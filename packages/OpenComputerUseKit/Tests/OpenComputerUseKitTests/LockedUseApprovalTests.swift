import Darwin
import XCTest
import LockedUseNative
@testable import OpenComputerUseKit

final class LockedUseApprovalTests: XCTestCase {
    func testExtendedACLWriteGrantIsRejectedEvenWithPrivateModeBits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-approval-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("approval.json").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o600]))
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(ocu_has_mutating_acl(fd), 0)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow write", path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(ocu_has_mutating_acl(fd), 1)
        XCTAssertEqual(ocu_has_mutating_acl(-1), -1)
    }
    func testRecordsCannotInjectCodeSigningRequirement() throws {
        for identifier in ["client\" or true", "../client", "client\\n", "client\n", "", "client/agent"] {
            XCTAssertThrowsError(try LockedUseClientApprovals.Approval(userID: 501, role: .client,
                signingIdentifier: identifier, teamIdentifier: "ABCDE12345"))
        }
        XCTAssertThrowsError(try LockedUseClientApprovals.Approval(userID: 0, role: .client,
            signingIdentifier: "dev.ocu.client", teamIdentifier: "ABCDE12345"))
        XCTAssertThrowsError(try LockedUseClientApprovals.Approval(userID: 501, role: .client,
            signingIdentifier: "dev.ocu.client", teamIdentifier: "ADHOC"))
    }

    func testDecodedRecordsAreValidatedAgainAndDuplicatesRejected() throws {
        let record = try LockedUseClientApprovals.Approval(userID: 501, role: .client,
            signingIdentifier: "dev.ocu.client", teamIdentifier: "ABCDE12345")
        XCTAssertThrowsError(try LockedUseClientApprovals(approvals: [record, record]))
        let valid = try LockedUseClientApprovals(approvals: [record])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["schemaVersion"] = 999
        XCTAssertThrowsError(try LockedUseClientApprovals.decodeValidated(JSONSerialization.data(withJSONObject: object)))
        object["schemaVersion"] = 1
        var records = try XCTUnwrap(object["approvals"] as? [[String: Any]])
        records[0]["signingIdentifier"] = "anything\" or true"
        object["approvals"] = records
        XCTAssertThrowsError(try LockedUseClientApprovals.decodeValidated(JSONSerialization.data(withJSONObject: object)))
    }

    func testCallerCannotSupplyAlternativeConfigPathOrUserOwnedInstalledApproval() {
        XCTAssertThrowsError(try LockedUseClientApprovals.readSecureFile(components: ["Library", "..", "clients.json"], owner: 0))
        XCTAssertThrowsError(try LockedUseClientApprovals.readSecureFile(components: ["Library", "Application Support", "clients.json"], owner: geteuid()))
    }
}
