import Darwin
import Foundation
import OpenComputerUseKit

/// One authenticated Broker connection per app-agent client. Only GUI requests
/// acquire a lease; inventory, diagnostics and protocol discovery do not unlock.
final class LockedUseConnection: @unchecked Sendable {
    private let mutex = NSLock()
    private let clientSocket: Int32
    private var broker: LockedUseIPCClient?
    private var lease: UUID?
    private var guardian: Process?
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var clientDisconnected = false
    private var inFlight = false
    private var validationLease: UUID?

    init(clientSocket: Int32) {
        self.clientSocket = dup(clientSocket)
        if self.clientSocket >= 0 { _ = fcntl(self.clientSocket, F_SETFD, FD_CLOEXEC) }
    }
    deinit { if clientSocket >= 0 { Darwin.close(clientSocket) } }

    func perform<T>(_ body: () throws -> T) throws -> T {
        let session = LockedUseSession.current()
        mutex.lock(); let needsRecovery = stopped && lease == nil; mutex.unlock()
        if needsRecovery && session.state == .unlocked {
            let observer = try LockedUseIPCClient(endpoint: .observer, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
            defer { observer.close() }
            let reply = try observer.request(.init(operation: .status, session: session))
            if reply.phase == .idle { mutex.lock(); stopped = false; mutex.unlock() }
        }
        if session.state == .locked { try acquire(session: session) }
        mutex.lock()
        guard !stopped && !clientDisconnected else { mutex.unlock(); throw ComputerUseError.stateUnavailable("Locked Use stopped. Unlock the Mac normally before starting another session.") }
        let scoped = lease != nil
        inFlight = true
        mutex.unlock()
        defer {
            mutex.lock(); inFlight = false; let drain = stopped; mutex.unlock()
            if drain { acknowledgeDrain() }
        }
        if scoped {
            return try LockedUseActionScope.withValidator({ [self] in try validateAction() }, body: body)
        }
        return try body()
    }

    private func acquire(session: LockedUseSession) throws {
        mutex.lock(); let existing = lease; let denied = stopped || clientDisconnected; mutex.unlock()
        if existing != nil || denied { try validateAction(); return }
        let connection = try LockedUseIPCClient(endpoint: .agent,
            brokerRequirement: LockedUseSigningIdentity.brokerRequirement(), clientSocket: clientSocket)
        let reply = try connection.request(.init(operation: .begin, session: session))
        guard reply.result != .denied, reply.phase == .preparing,
              let lease = reply.leaseID, let token = reply.token else {
            connection.close()
            throw ComputerUseError.stateUnavailable("Locked Use is unavailable. Enable and validate it in Open Computer Use settings.")
        }
        mutex.lock(); broker = connection; self.lease = lease; let disconnected = clientDisconnected; mutex.unlock()
        do {
            guard !disconnected else { throw ComputerUseError.stateUnavailable("Computer Use client disconnected during lease acquisition.") }
            let child = Process()
            // The installer fixes this location; caller arguments cannot select
            // another guardian or executable while holding a capability.
            child.executableURL = URL(fileURLWithPath: "/Library/Application Support/OpenComputerUse/LockedUse/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian")
            child.arguments = ["--broker-guardian"]
            let input = Pipe()
            child.standardInput = input
            let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/OpenComputerUse/LockedUse", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let logURL = directory.appendingPathComponent(UUID().uuidString + ".jsonl")
            let logFD = open(logURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard logFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            let log = FileHandle(fileDescriptor: logFD, closeOnDealloc: true)
            defer { try? log.close() }
            child.standardOutput = log
            child.standardError = FileHandle.nullDevice
            try child.run()
            guardian = child
            try input.fileHandleForWriting.write(contentsOf: LockedUseIPCFrame.encode(LockedUseGuardianBootstrap(leaseID: lease, token: token)))
            try input.fileHandleForWriting.close()
            startPolling()
            let deadline = ProcessInfo.processInfo.systemUptime + 12
            while ProcessInfo.processInfo.systemUptime < deadline {
                let status = try connection.request(.init(operation: .status, leaseID: lease, session: .current()))
                receive(status)
                if status.result == .active { return }
                if status.result == .denied || status.phase == .relocking || status.phase == .awaitingManualUnlock || !child.isRunning { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw ComputerUseError.stateUnavailable("Locked Use could not observe a protected GUI session becoming unlocked.")
        } catch { end(); throw error }
    }

    private func validateAction() throws {
        mutex.lock(); let connection = broker; let lease = lease; let denied = stopped || clientDisconnected; mutex.unlock()
        guard !denied, let connection, let lease else {
            throw ComputerUseError.stateUnavailable("Locked Use lease is no longer active.")
        }
        let reply = try connection.request(.init(operation: .action, leaseID: lease, session: .current()))
        receive(reply)
        guard reply.result == .active else { throw ComputerUseError.stateUnavailable("Locked Use stopped before this GUI action.") }
    }

    func recordValidation(manual: Bool = false) throws {
        mutex.lock(); let lease = manual ? validationLease : lease; mutex.unlock()
        guard let lease else { throw ComputerUseError.stateUnavailable("No native validation lease.") }
        if manual {
            let connection = try LockedUseIPCClient(endpoint: .agent, brokerRequirement: LockedUseSigningIdentity.brokerRequirement(), clientSocket: clientSocket)
            defer { connection.close() }
            let reply = try connection.request(.init(operation: .validationManual, leaseID: lease, session: .current()))
            guard reply.result != .denied else { throw ComputerUseError.stateUnavailable("Validation manual-unlock confirmation denied.") }
        } else {
            try validateAction()
            mutex.lock(); let connection = broker; mutex.unlock()
            let reply = try connection?.request(.init(operation: .validationPassed, leaseID: lease))
            guard reply?.result != .denied, reply != nil else { throw ComputerUseError.stateUnavailable("Validation evidence denied.") }
            mutex.lock(); validationLease = lease; mutex.unlock()
        }
    }

    func end(disconnecting: Bool = false) {
        mutex.lock()
        stopped = lease != nil
        clientDisconnected = clientDisconnected || disconnecting
        let connection = broker; let lease = lease; let drain = !inFlight
        mutex.unlock()
        if let connection, let lease {
            if let reply = try? connection.request(.init(operation: .end, leaseID: lease, stopReason: disconnecting ? .disconnected : .turnEnded)) { receive(reply) }
            if drain { acknowledgeDrain() }
        }
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ocu.locked-use.connection"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [self] in
            mutex.lock(); let connection = broker; let lease = lease; mutex.unlock()
            guard let lease else { return }
            do {
                let active: LockedUseIPCClient
                if let connection { active = connection }
                else {
                    let candidate = try LockedUseIPCClient(endpoint: .agent, brokerRequirement: LockedUseSigningIdentity.brokerRequirement(), clientSocket: clientSocket)
                    let hello = try candidate.request(.init(operation: .ownerRecoveryHello, leaseID: lease, session: .current()))
                    guard hello.result != .denied else { candidate.close(); throw ComputerUseError.stateUnavailable("Broker recovery denied") }
                    mutex.lock(); broker = candidate; mutex.unlock()
                    active = candidate
                }
                let reply = try active.request(.init(operation: .status, leaseID: lease, session: .current()))
                receive(reply)
                mutex.lock(); let drain = stopped && !inFlight; mutex.unlock()
                if drain { acknowledgeDrain() }
            } catch {
                mutex.lock(); stopped = true; let failed = broker; broker = nil; mutex.unlock()
                failed?.close()
                // Guardian independently observes Broker failure and relocks.
                // Do not kill it, its watchdog, or its shields on IPC failure.
            }
        }
        self.timer = timer; timer.resume()
    }

    private func receive(_ reply: LockedUseIPCReply) {
        mutex.lock(); defer { mutex.unlock() }
        if reply.effects.contains("stopActions") || reply.phase == .relocking { stopped = true }
        if reply.phase == .idle || reply.phase == .awaitingManualUnlock {
            timer?.cancel(); timer = nil
            // This acknowledgment follows Guardian's lock observation and drain.
            lease = nil
            if reply.phase == .idle { stopped = false }
            broker?.close(); broker = nil
        }
    }

    private func acknowledgeDrain() {
        mutex.lock(); let connection = broker; let lease = lease; mutex.unlock()
        guard let connection, let lease else { return }
        if let reply = try? connection.request(.init(operation: .quiesced, leaseID: lease)) { receive(reply) }
    }
}
