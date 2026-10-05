import Darwin
import Foundation

/// Physical monitor identities must not depend on transient runtime namespaces.
/// Share a bounded pool across OCU bundles; skip every serial already held or online.
enum VirtualDisplayIdentity {
    static let slotCount: UInt32 = 32
    static let serialBase: UInt32 = 0x4f430000

    /// Serialize slot selection through helper readiness across runtime namespaces.
    /// Kernel locks release automatically if the creating runtime crashes.
    static func withCreationLock<T>(_ body: () throws -> T) throws -> T {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/OpenComputerUse", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("virtual-display-identity.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ComputerUseError.message("Cannot open virtual display identity lock") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFREG else {
            throw ComputerUseError.message("Invalid virtual display identity lock owner or type")
        }
        let deadline = Date(timeIntervalSinceNow: 15)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else {
                throw ComputerUseError.message("Timed out waiting for virtual display identity allocation")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    static func serial(slot: UInt32) -> UInt32 {
        precondition(slot < slotCount)
        return serialBase + slot
    }

    static func availableSerial(occupied: Set<UInt32>) throws -> UInt32 {
        for slot in UInt32(0)..<slotCount {
            let candidate = serial(slot: slot)
            if !occupied.contains(candidate) { return candidate }
        }
        throw ComputerUseError.message("All 32 virtual display identity slots are occupied; reuse or release an existing display")
    }
}
