import Darwin
import Foundation
import LockedUseNative

/// Fixed-location installer data. Production callers always use owner zero;
/// injected owners are internal and only used by filesystem regression tests.
enum LockedUseSecureStore {
    static func read(components: [String], owner: UInt32 = 0) throws -> Data {
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw LockedUseClientApprovals.Failure.insecureFile
        }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
        defer { close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
            var info = stat()
            guard fstat(next, &info) == 0, info.st_uid == owner, info.st_mode & 0o022 == 0,
                  ocu_has_mutating_acl(next) == 0 else {
                close(next); throw LockedUseClientApprovals.Failure.insecureFile
            }
            close(directory)
            directory = next
        }
        let fd = openat(directory, components.last!, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LockedUseClientApprovals.Failure.inaccessible(errno) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & 0o022 == 0,
              ocu_has_mutating_acl(fd) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= 128 * 1024 else {
            throw LockedUseClientApprovals.Failure.insecureFile
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw LockedUseClientApprovals.Failure.inaccessible(errno)
            }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 128 * 1024 else { throw LockedUseClientApprovals.Failure.insecureFile }
        }
        return data
    }
}
