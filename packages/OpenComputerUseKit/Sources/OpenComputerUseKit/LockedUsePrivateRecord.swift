import Darwin
import Foundation
import LockedUseNative

/// Private from creation through atomic publication, independent of launchd's
/// umask. Never publish a readable capability-bearing journal then chmod it.
public enum LockedUsePrivateRecord {
    public static func writeInstalled(_ data: Data, name: String) throws {
        guard geteuid() == 0, ["lease-recovery.json", "validation-report.json"].contains(name) else {
            throw LockedUseClientApprovals.Failure.insecureFile
        }
        try write(data, directory: URL(fileURLWithPath: "/Library/Application Support/OpenComputerUse/LockedUse"), name: name, owner: 0)
    }

    static func write(_ data: Data, directory: URL, name: String, owner: UInt32) throws {
        guard !data.isEmpty, data.count <= 128 * 1024, !name.contains("/"), name != ".", name != ".." else {
            throw LockedUseClientApprovals.Failure.insecureFile
        }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
        defer { Darwin.close(parent) }
        var info = stat()
        guard fstat(parent, &info) == 0, info.st_uid == owner, info.st_mode & 0o022 == 0,
              ocu_has_mutating_acl(parent) == 0 else { throw LockedUseClientApprovals.Failure.insecureFile }
        let temporary = ".private-" + UUID().uuidString
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
        defer { Darwin.close(fd); _ = unlinkat(parent, temporary, 0) }
        guard ocu_remove_extended_acl(fd) == 0, fchmod(fd, 0o600) == 0 else { throw LockedUseClientApprovals.Failure.insecureFile }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(parent, temporary, parent, name) == 0, fsync(parent) == 0 else {
            throw LockedUseClientApprovals.Failure.inaccessible(errno)
        }
    }
}
