import Darwin
import Foundation
import LockedUseNative
@testable import OpenComputerUseKit
import XCTest

final class LockedUsePrivateRecordTests: XCTestCase {
    func testAtomicRecordIsPrivateAndRemovesInheritedReadACL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-private-record-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow read,file_inherit", directory.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let bytes = Data("isolated-test-record".utf8)
        try LockedUsePrivateRecord.write(bytes, directory: directory, name: "record.json", owner: geteuid())
        let path = directory.appendingPathComponent("record.json").path
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var info = stat()
        XCTAssertEqual(fstat(fd, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertEqual(ocu_has_any_acl(fd), 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
        try LockedUsePrivateRecord.write(Data("updated".utf8), directory: directory, name: "record.json", owner: geteuid())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["record.json"])
    }

    func testWriterRejectsUntrustedDirectoryAndNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-private-record-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o777])
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(chmod(directory.path, 0o777), 0)
        XCTAssertThrowsError(try LockedUsePrivateRecord.write(Data([1]), directory: directory, name: "record.json", owner: geteuid()))
        XCTAssertThrowsError(try LockedUsePrivateRecord.write(Data([1]), directory: directory, name: "../outside", owner: geteuid()))
    }
}
