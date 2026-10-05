import Foundation
import IOKit
import PowerNative

public protocol SleepSwitch: AnyObject {
    func read() throws -> Bool
    func set(_ disabled: Bool) throws
}
public protocol RecoveryJournal: AnyObject {
    func load() throws -> Bool?
    func save(original: Bool) throws
    func clear() throws
}
public final class LidLeaseController {
    private struct Lease { let uid: UInt32; let connection: String; var deadline: Double }
    private let lock = NSRecursiveLock()
    private let power: SleepSwitch
    private let journal: RecoveryJournal
    private let clock: () -> Double
    private var leases: [String: Lease] = [:]
    private var startupRecovered = false
    private var recoveryPending = false
    private var original: Bool?
    public private(set) var fault: String?
    public init(power: SleepSwitch, journal: RecoveryJournal, clock: @escaping () -> Double = { PowerClock.now }) {
        self.power = power; self.journal = journal; self.clock = clock
    }
    public func recoverOnStartup() throws {
        lock.lock(); defer { lock.unlock() }
        do {
            original = try journal.load()
            recoveryPending = original != nil
            if recoveryPending { try restore() }
            startupRecovered = true; fault = nil
        } catch { fault = error.localizedDescription; throw error }
    }
    public func handle(_ request: HelperRequest, uid: UInt32, connection: String) -> HelperResponse {
        lock.lock(); defer { lock.unlock() }
        do {
            try expireAndCheck()
            switch request.operation {
            case "acquire":
                guard !recoveryPending else { throw PowerFailure.backend("Recovery must finish before acquiring a lid lease") }
                guard leases.count < 128 else { throw PowerFailure.invalid("Helper lease limit reached") }
                if leases.isEmpty {
                    guard try !power.read() else { throw PowerFailure.backend("Sleep is already disabled by another owner") }
                    do { try journal.save(original: false) }
                    catch {
                        original = try? journal.load(); recoveryPending = original != nil
                        if recoveryPending { try? restore() }
                        throw error
                    }
                    original = false; recoveryPending = true
                    do { try power.set(true); guard try power.read() else { throw PowerFailure.backend("Sleep override did not take effect") } }
                    catch { try? restore(); throw error }
                    recoveryPending = false
                }
                let token = UUID().uuidString
                leases[token] = .init(uid: uid, connection: connection, deadline: clock() + 30)
                fault = nil
                return .init(lease: token, sleepDisabled: true)
            case "renew":
                guard let token = request.lease, var lease = leases[token], lease.uid == uid, lease.connection == connection else { throw PowerFailure.invalid("Unknown or expired lid lease") }
                lease.deadline = clock() + 30; leases[token] = lease
                fault = nil
                return .init(lease: token, sleepDisabled: true)
            case "release":
                guard let token = request.lease, let lease = leases[token], lease.uid == uid, lease.connection == connection else { throw PowerFailure.invalid("Unknown or expired lid lease") }
                leases.removeValue(forKey: token)
                if leases.isEmpty { recoveryPending = true; try restore() }
                return .init(sleepDisabled: try power.read())
            case "disconnect":
                leases = leases.filter { $0.value.connection != connection }
                if leases.isEmpty && original != nil { recoveryPending = true; try restore() }
                return .init(sleepDisabled: try power.read())
            case "status": return .init(sleepDisabled: try power.read(), error: fault)
            default: throw PowerFailure.invalid("Unsupported helper operation")
            }
        } catch {
            let message = error.localizedDescription
            if recoveryPending || !startupRecovered { fault = message }
            return .init(error: message)
        }
    }
    public func tick() {
        lock.lock(); defer { lock.unlock() }
        do { try expireAndCheck() } catch { fault = error.localizedDescription }
    }
    public func shutdown() throws {
        lock.lock(); defer { lock.unlock() }
        leases.removeAll()
        if original != nil { recoveryPending = true; try restore() }
    }
    private func expireAndCheck() throws {
        if !startupRecovered { try recoverOnStartup() }
        if recoveryPending { try restore() }
        if try !leases.isEmpty && !power.read() {
            // Another tool has already restored sleep. Do not reassert our override.
            leases.removeAll(); recoveryPending = true
            try restore()
            throw PowerFailure.backend("External sleep setting change detected; leases revoked")
        }
        leases = leases.filter { $0.value.deadline > clock() }
        if leases.isEmpty && original != nil { recoveryPending = true; try restore() }
    }
    private func restore() throws {
        guard let value = original else { recoveryPending = false; return }
        if try power.read() != value { try power.set(value) }
        guard try power.read() == value else { throw PowerFailure.backend("Sleep restoration could not be confirmed") }
        try journal.clear(); original = nil; recoveryPending = false; fault = nil
    }
}

public final class PMSetSleepSwitch: SleepSwitch {
    public init() {}
    private func command(_ args: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = args
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
        process.standardOutput = pipe; process.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw PowerFailure.backend("pmset timed out")
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { throw PowerFailure.backend("pmset failed with exit \(process.terminationStatus)") }
        return String(decoding: output, as: UTF8.self)
    }
    public func read() throws -> Bool {
        let text = try command(["-g"])
        let lines = text.split(separator: "\n").map { $0.split(whereSeparator: { $0.isWhitespace }) }
        let values = lines.filter { $0.first == "SleepDisabled" }
        let preference: Bool
        if values.isEmpty { preference = false }
        else {
            guard values.count == 1, values[0].count == 2, ["0", "1"].contains(values[0][1]) else { throw PowerFailure.backend("Unrecognized SleepDisabled preference") }
            preference = values[0][1] == "1"
        }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerFailure.backend("Power root domain unavailable") }
        defer { IOObjectRelease(root) }
        if let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
            guard value.boolValue == preference else { throw PowerFailure.backend("SleepDisabled preference and running kernel state disagree") }
        } else { throw PowerFailure.backend("Kernel SleepDisabled confirmation unavailable") }
        return preference
    }
    public func set(_ disabled: Bool) throws { _ = try command(["-a", "disablesleep", disabled ? "1" : "0"]) }
}
public final class FileRecoveryJournal: RecoveryJournal {
    private let directory: String
    private var path: String { directory + "/recovery" + PowerPaths.suffix + ".json" }
    private var ownershipFD: Int32 = -1
    deinit { if ownershipFD >= 0 { close(ownershipFD) } }
    private func claimOwnership() throws {
        if ownershipFD >= 0 { return }
        let lockPath = directory + "/system.lock"
        let fd = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw PowerFailure.backend("Cannot open system power lock") }
        guard ocu_power_secure_root_file(lockPath) == 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw PowerFailure.backend("Another power helper owns system sleep or lock permissions are unsafe") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC); ownershipFD = fd
    }
    private struct Record: Codable { let version: Int; let original: Bool }
    public init(directory: String = "/Library/Application Support/OpenComputerUsePower") { self.directory = directory }
    private func prepare() throws {
        guard geteuid() == 0 else { throw PowerFailure.backend("Recovery journal requires root") }
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw PowerFailure.backend("Cannot create recovery directory") }
        var info = stat()
        guard lstat(directory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == 0, info.st_mode & 0o077 == 0, ocu_power_secure_root_directory(directory) == 0 else { throw PowerFailure.backend("Unsafe recovery directory") }
    }
    public func load() throws -> Bool? {
        try prepare()
        var info = stat()
        if lstat(path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw PowerFailure.backend("Cannot inspect recovery journal")
        }
        try claimOwnership()
        guard ocu_power_secure_root_file(path) == 0 else { throw PowerFailure.backend("Unsafe recovery journal") }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard record.version == 1 else { throw PowerFailure.backend("Unsupported recovery journal") }
        return record.original
    }
    public func save(original: Bool) throws {
        try prepare()
        try claimOwnership()
        guard try load() == nil else { throw PowerFailure.backend("Unfinished recovery journal exists") }
        let temporary = directory + "/" + UUID().uuidString + ".tmp"
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw PowerFailure.backend("Cannot create recovery journal") }
        defer { close(fd); unlink(temporary) }
        let data = try JSONEncoder().encode(Record(version: 1, original: original))
        try data.withUnsafeBytes { bytes in
            guard write(fd, bytes.baseAddress, bytes.count) == bytes.count, fsync(fd) == 0 else { throw PowerFailure.backend("Cannot persist recovery journal") }
        }
        guard rename(temporary, path) == 0 else { throw PowerFailure.backend("Cannot publish recovery journal") }
        try syncDirectory()
    }
    public func clear() throws {
        try prepare()
        if unlink(path) != 0 && errno != ENOENT { throw PowerFailure.backend("Cannot clear recovery journal") }
        try syncDirectory()
        if ownershipFD >= 0 { close(ownershipFD); ownershipFD = -1 }
    }
    private func syncDirectory() throws {
        let fd = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PowerFailure.backend("Cannot open recovery directory") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw PowerFailure.backend("Cannot sync recovery directory") }
    }
}
