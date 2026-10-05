import Darwin
import Dispatch
import Foundation
import LockedUseNative
import OpenComputerUseKit
import os
import Security

@main
enum BrokerMain {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2,
                  ["--serve", "--serve-validation"].contains(CommandLine.arguments[1]), geteuid() == 0 else {
                throw BrokerError.message("Usage: OpenComputerUseLockedUseBroker --serve | --serve-validation (administrator installed service only)")
            }
            let approvals = try LockedUseClientApprovals.loadInstalled()
            let configuration = try LockedUseBrokerConfiguration.loadInstalled()
            let validation = CommandLine.arguments[1] == "--serve-validation"
            let team = try LockedUseSigningIdentity.current().teamIdentifier!
            let evidence = try LockedUseComponentValidation.current(team: team)
            let matched = configuration.matchesValidation(osBuild: evidence.osBuild,
                brokerHash: evidence.brokerHash, guardianHash: evidence.guardianHash, pluginHash: evidence.pluginHash)
            let server = try BrokerServer(approvals: approvals, enabled: configuration.enabled,
                backendValidated: validation || matched)
            try server.start()
            withExtendedLifetime(server) { dispatchMain() }
        } catch {
            // Never log bodies, capabilities, AX content or peer credentials.
            fputs("Locked Use Broker startup failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

enum BrokerError: Error { case message(String) }

/// All mutable state lives on this one queue, independent of GUI tool actions.
private final class BrokerServer: @unchecked Sendable {
    private let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "Broker")
    private let queue = DispatchQueue(label: "dev.opencomputeruse.locked-use.broker")
    private let approvals: LockedUseClientApprovals
    private var coordinator: LockedUseBrokerCoordinator
    private var listeners: [DispatchSourceRead] = []
    private var connections: [UUID: BrokerConnection] = [:]
    private var timer: DispatchSourceTimer?
    private var lastPolicyCheck: TimeInterval = 0
    private var policyInvalidated = false
    private var validationReport: LockedUseValidationReport?
    private var lastValidationData: Data?
    private var recoverySeed: LockedUseRecoveryRecord?
    private var ownerClientToken: Data?
    private var lastRecoveryData: Data?
    private let instanceLock: Int32

    init(approvals: LockedUseClientApprovals, enabled: Bool, backendValidated: Bool) throws {
        self.approvals = approvals
        coordinator = .init(enabled: enabled, backendValidated: backendValidated, requiresWatchdog: true)
        try Self.validateRunDirectory()
        let fd = open("/Library/Application Support/OpenComputerUse/LockedUse/run/broker.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BrokerError.message("instance lock unavailable") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, ocu_has_mutating_acl(fd) == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd); throw BrokerError.message("instance already running or insecure lock file")
        }
        instanceLock = fd
        let bootID = try LockedUseComponentValidation.bootSessionID()
        recoverySeed = try LockedUseRecoveryRecord.loadInstalled()
        if let record = recoverySeed, record.bootSessionID != bootID {
            // A kernel reboot destroys the old GUI session and queued native
            // authorization work. A new completed login is a separate epoch.
            guard unlink("/Library/Application Support/OpenComputerUse/LockedUse/lease-recovery.json") == 0 else { throw BrokerError.message("old boot recovery fence unavailable") }
            recoverySeed = nil
        }
        ownerClientToken = recoverySeed?.originalClientToken
        coordinator = .init(enabled: enabled, backendValidated: backendValidated, requiresWatchdog: true, recovery: recoverySeed, bootSessionID: bootID)
    }

    func start() throws {
        try checkInstallationPolicy()
        for endpoint in [LockedUseIPCEndpoint.agent, .guardian, .plugin, .observer, .admin] {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw BrokerError.message("socket unavailable") }
            do {
                try Self.removeStaleEndpoint(endpoint.path)
                try LockedUseIPCSocket.configure(fd)
                guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw BrokerError.message("nonblocking socket unavailable") }
                var address = try LockedUseIPCSocket.address(path: endpoint.path)
                // Never unlink an unknown/still-running service's socket.
                let bound = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard bound == 0, chmod(endpoint.path, 0o666) == 0, listen(fd, 16) == 0 else {
                    throw BrokerError.message("endpoint already exists or cannot be secured")
                }
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                source.setEventHandler { [weak self] in self?.accept(fd: fd, endpoint: endpoint) }
                source.setCancelHandler { Darwin.close(fd) }
                listeners.append(source)
                source.resume()
            } catch { Darwin.close(fd); throw error }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do {
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastPolicyCheck >= 1 {
                    try self.checkInstallationPolicy(); self.lastPolicyCheck = now
                }
                for connection in Array(self.connections.values) where connection.endpoint == .agent && connection.clientDescriptor < 0 && now - connection.created > 2 {
                    self.close(connection)
                }
                if let owner = self.coordinator.owner,
                   let connection = self.connections[owner.connectionID], !connection.clientInvalidated {
                    do { try self.verifyOriginalClient(connection) }
                    catch {
                        connection.clientInvalidated = true
                        try self.coordinator.disconnected(connection.context)
                    }
                }
                try self.coordinator.tick(now: now)
                if let guardian = self.coordinator.recordedGuardian, kill(guardian.processID, 0) != 0, errno == ESRCH {
                    try self.coordinator.guardianProcessExited()
                }
                if let owner = self.coordinator.recordedOwner, kill(owner.processID, 0) != 0, errno == ESRCH {
                    try self.coordinator.ownerProcessExited()
                }
                try self.persistRecovery()
                try self.persistValidation()
            }
            catch { self.stopAll() }
        }
        self.timer = timer
        timer.resume()
    }

    private func accept(fd: Int32, endpoint: LockedUseIPCEndpoint) {
        for _ in 0..<16 {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 { return }
            guard connections.count < 64 else { Darwin.close(client); continue }
            do {
                try LockedUseIPCSocket.configure(client)
                guard fcntl(client, F_SETFL, O_NONBLOCK) == 0 else { throw BrokerError.message("client socket unavailable") }
                let identity = try authenticate(fd: client, endpoint: endpoint)
                let role: LockedUseBrokerCoordinator.Role = endpoint == .agent ? .agent : endpoint == .guardian ? .guardian : (endpoint == .observer || endpoint == .admin) ? .observer : .plugin
                let old = [coordinator.recordedOwner, coordinator.recordedGuardian, coordinator.recordedWatchdog]
                    .compactMap { $0 }.first { $0.role == role && $0.auditToken == identity.auditToken && $0.codeHash == identity.codeDirectoryHash }
                let context = LockedUseBrokerCoordinator.Context(id: old?.id ?? UUID(), role: role,
                    userID: identity.userID, auditSessionID: identity.auditSessionID, auditToken: identity.auditToken,
                    processID: identity.processID, codeHash: identity.codeDirectoryHash)
                if let previous = connections[context.id] { close(previous) }
                let connection = BrokerConnection(fd: client, endpoint: endpoint, identity: identity, context: context)
                connections[context.id] = connection
                let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
                source.setEventHandler { [weak self, weak connection] in
                    guard let connection, !connection.closed else { return }
                    self?.read(connection)
                }
                connection.readSource = source
                source.resume()
            } catch { logger.notice("peerRejected endpoint=\(endpoint.rawValue, privacy: .public)"); Darwin.close(client) }
        }
    }

    private func authenticate(fd: Int32, endpoint: LockedUseIPCEndpoint) throws -> LockedUsePeerIdentity {
        switch endpoint {
        case .agent: return try approvals.verifiedPeer(socket: fd, role: .agent)
        case .guardian: return try approvals.verifiedPeer(socket: fd, role: .guardian)
        case .observer: return try approvals.verifiedPeer(socket: fd, role: .client)
        case .admin:
            guard let team = try LockedUseSigningIdentity.current().teamIdentifier else { throw BrokerError.message("signer unavailable") }
            let requirement = "identifier \"dev.opencomputeruse.locked-use.installer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            let peer = try LockedUsePeerIdentity.verified(socket: fd, requirement: requirement)
            guard peer.userID == 0, peer.hardenedRuntime, !peer.permitsCodeInjection else { throw BrokerError.message("untrusted installer") }
            return peer
        case .plugin:
            // SecurityAgent is Apple signed, not signed by the application's
            // Developer ID team. Never substitute a user-provided requirement.
            let requirement = "anchor apple and (identifier \"com.apple.SecurityAgentHelper.arm64\" or identifier \"com.apple.SecurityAgentHelper.x86_64\")"
            let peer = try LockedUsePeerIdentity.verified(socket: fd, requirement: requirement)
            guard peer.auditSessionID > 0, !peer.permitsCodeInjection else { throw BrokerError.message("untrusted authorization helper") }
            return peer
        }
    }

    private func read(_ connection: BrokerConnection) {
        if connection.endpoint == .agent && connection.clientDescriptor < 0 {
            let fd = ocu_receive_peer_socket(connection.fd)
            if fd < 0, [EAGAIN, EWOULDBLOCK, EINTR].contains(errno) { return }
            guard fd >= 0 else { close(connection); return }
            do {
                var native = OCUPeerIdentity()
                guard ocu_copy_peer_identity(fd, &native) == 0, native.effective_user_id == connection.identity.userID,
                      native.audit_session_id == connection.identity.auditSessionID else { throw BrokerError.message("client session mismatch") }
                let token = withUnsafeBytes(of: native.audit_token) { Data($0) }
                let client = try? approvals.verifiedPeer(socket: fd, role: .client)
                guard client != nil || coordinator.recordedOwner?.auditToken == connection.identity.auditToken && ownerClientToken == token else {
                    throw BrokerError.message("client not approved for this epoch")
                }
                connection.clientDescriptor = fd; connection.clientIdentity = client; connection.clientAuditToken = token
            } catch { Darwin.close(fd); close(connection) }
            return
        }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(connection.fd, &bytes, bytes.count)
        if count < 0, [EAGAIN, EWOULDBLOCK, EINTR].contains(errno) { return }
        guard count > 0 else { close(connection); return }
        do {
            let current = try authenticate(fd: connection.fd, endpoint: connection.endpoint)
            guard current.auditToken == connection.identity.auditToken,
                  current.codeDirectoryHash == connection.identity.codeDirectoryHash else { throw BrokerError.message("peer changed") }
            for frame in try connection.decoder.append(Data(bytes.prefix(count))) {
                let request = try JSONDecoder().decode(LockedUseIPCMessage.self, from: frame).validated()
                // Keep the authenticated agent alive to revoke and acknowledge
                // drainage after its original native client has exited.
                if connection.endpoint == .admin && ![LockedUseIPCMessage.Operation.status, .disable].contains(request.operation) { throw BrokerError.message("invalid installer request") }
                if connection.endpoint == .observer && request.operation != .status { throw BrokerError.message("observer cannot mutate") }
                let previousPhase = coordinator.phase
                let reply: LockedUseIPCReply
                do {
                    if [.begin, .pluginClaim, .pluginConsume].contains(request.operation) { try checkInstallationPolicy() }
                    if connection.endpoint == .agent && [.begin, .action, .validationPassed, .validationManual].contains(request.operation) {
                        do { try verifyOriginalClient(connection) }
                        catch {
                            connection.clientInvalidated = true
                            try coordinator.disconnected(connection.context)
                            throw error
                        }
                    }
                    reply = try coordinator.handle(request, context: connection.context, now: ProcessInfo.processInfo.systemUptime)
                } catch {
                    reply = .init(id: request.id, result: .denied, phase: coordinator.phase,
                        detail: "Request denied by Broker policy")
                }
                if previousPhase != coordinator.phase {
                    logger.notice("phase=\(self.coordinator.phase.rawValue, privacy: .public)")
                }
                if reply.result == .denied { logger.notice("denied operation=\(request.operation.rawValue, privacy: .public) sessionMatches=\(connection.context.auditSessionID == self.coordinator.owner?.auditSessionID, privacy: .public) auditUserMatches=\(connection.identity.auditUserID == self.coordinator.owner?.userID, privacy: .public)") }
                // Persist before exposing a consumed authorization or active
                // GUI lease. No permit nonce is ever saved or restored.
                try persistRecovery()
                if reply.result != .denied, request.operation == .validationPassed, let leaseID = request.leaseID {
                    let team = try LockedUseSigningIdentity.current().teamIdentifier!
                    validationReport = .init(leaseID: leaseID, evidence: try LockedUseComponentValidation.current(team: team), ownerToken: connection.identity.auditToken)
                }
                if reply.result != .denied, request.operation == .validationManual {
                    guard var report = validationReport, report.leaseID == request.leaseID,
                          report.ownerToken == connection.identity.auditToken, report.lockedAndReleased else { throw BrokerError.message("validation owner mismatch") }
                    report.afterManualUnlockPassed = true; validationReport = report
                }
                try persistValidation()
                connection.pending.append(try LockedUseIPCFrame.encode(reply))
                guard connection.pending.count <= 64 * 1024 else { throw LockedUseIPCFrame.Failure.oversized }
            }
            flush(connection)
        } catch { close(connection) }
    }

    private func persistRecovery() throws {
        if let context = coordinator.recordedOwner,
           let token = connections[context.id]?.clientAuditToken { ownerClientToken = token }
        let path = "/Library/Application Support/OpenComputerUse/LockedUse/lease-recovery.json"
        if let token = ownerClientToken, let record = coordinator.recoveryRecord(clientToken: token) {
            _ = try record.validated()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(record)
            if data == lastRecoveryData { return }
            try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
            guard chmod(path, 0o600) == 0 else { throw BrokerError.message("recovery file unavailable") }
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw BrokerError.message("recovery file unavailable") }
            let synced = fsync(fd); Darwin.close(fd)
            guard synced == 0 else { throw BrokerError.message("recovery durability unavailable") }
            lastRecoveryData = data
        } else if lastRecoveryData != nil || recoverySeed != nil {
            if unlink(path) != 0, errno != ENOENT { throw BrokerError.message("recovery fence removal failed") }
            lastRecoveryData = nil; recoverySeed = nil
        } else { return }
        let directory = open("/Library/Application Support/OpenComputerUse/LockedUse", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw BrokerError.message("recovery directory unavailable") }
        let synced = fsync(directory); Darwin.close(directory)
        guard synced == 0 else { throw BrokerError.message("recovery directory durability unavailable") }
    }

    private func persistValidation() throws {
        guard var report = validationReport else { return }
        if coordinator.isFullyReleased, [.idle, .awaitingManualUnlock].contains(coordinator.phase),
           coordinator.recordedOwner?.auditToken == report.ownerToken {
            report.lockedAndReleased = true
        }
        validationReport = report
        // A Broker restart loses incomplete proof; it never certifies resumed
        // recovery as a successful fresh unlock test.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let path = "/Library/Application Support/OpenComputerUse/LockedUse/validation-report.json"
        let data = try encoder.encode(report)
        if data == lastValidationData { return }
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        guard chmod(path, 0o600) == 0 else { throw BrokerError.message("validation record unavailable") }
        lastValidationData = data
    }

    private func checkInstallationPolicy() throws {
        guard !policyInvalidated else { return }
        do {
            guard try LockedUseAuthorizationRules.installedRulesObserved() else {
                throw BrokerError.message("authentication policy changed")
            }
        } catch {
            try coordinator.invalidateInstallation()
            policyInvalidated = true
            logger.error("installationPolicyInvalidated")
        }
    }

    private func verifyOriginalClient(_ connection: BrokerConnection) throws {
        guard !connection.clientInvalidated, let previous = connection.clientIdentity else { throw BrokerError.message("client unavailable") }
        let client = try approvals.verifiedPeer(socket: connection.clientDescriptor, role: .client)
        guard client.auditToken == previous.auditToken,
              client.codeDirectoryHash == previous.codeDirectoryHash else { throw BrokerError.message("client changed") }
    }

    private func flush(_ connection: BrokerConnection) {
        guard !connection.closed else { return }
        while !connection.pending.isEmpty {
            let count = connection.pending.withUnsafeBytes { buffer in
                Darwin.write(connection.fd, buffer.baseAddress, buffer.count)
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                if connection.writeSource == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: connection.fd, queue: queue)
                    source.setEventHandler { [weak self, weak connection] in
                        guard let connection, !connection.closed else { return }
                        self?.flush(connection)
                    }
                    connection.writeSource = source
                    source.resume()
                }
                return
            }
            guard count > 0 else { close(connection); return }
            connection.pending.removeFirst(count)
        }
        connection.writeSource?.cancel()
        connection.writeSource = nil
    }

    private func close(_ connection: BrokerConnection) {
        guard !connection.closed else { return }
        connection.closed = true
        if connection.clientDescriptor >= 0 { Darwin.close(connection.clientDescriptor); connection.clientDescriptor = -1 }
        try? coordinator.disconnected(connection.context)
        try? persistRecovery()
        connection.readSource?.cancel(); connection.writeSource?.cancel()
        shutdown(connection.fd, SHUT_RDWR); Darwin.close(connection.fd)
        connections.removeValue(forKey: connection.context.id)
    }
    private func stopAll() { for connection in Array(connections.values) { close(connection) } }

    private static func validateRunDirectory() throws {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw BrokerError.message("root directory unavailable") }
        defer { Darwin.close(fd) }
        for component in ["Library", "Application Support", "OpenComputerUse", "LockedUse", "run"] {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw BrokerError.message("installer runtime directory missing") }
            var info = stat()
            guard fstat(next, &info) == 0, info.st_uid == 0,
                  info.st_mode & 0o022 == 0, ocu_has_mutating_acl(next) == 0 else {
                Darwin.close(next); throw BrokerError.message("insecure runtime directory")
            }
            Darwin.close(fd); fd = next
        }
    }

    /// The exclusive instance lock prevents this service's restart from racing
    /// another copy. The enclosing path is root owned and not user writable.
    private static func removeStaleEndpoint(_ path: String) throws {
        var before = stat()
        if lstat(path, &before) != 0 {
            guard errno == ENOENT else { throw BrokerError.message("endpoint inspection failed") }
            return
        }
        guard before.st_uid == 0, before.st_mode & S_IFMT == S_IFSOCK else {
            throw BrokerError.message("unknown object at endpoint")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrokerError.message("endpoint probe unavailable") }
        defer { Darwin.close(fd) }
        try LockedUseIPCSocket.configure(fd)
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw BrokerError.message("endpoint probe unavailable") }
        var address = try LockedUseIPCSocket.address(path: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result < 0, errno == ECONNREFUSED else { throw BrokerError.message("endpoint in use") }
        var after = stat()
        guard lstat(path, &after) == 0, after.st_ino == before.st_ino,
              after.st_dev == before.st_dev, after.st_uid == 0,
              after.st_mode & S_IFMT == S_IFSOCK, unlink(path) == 0 else {
            throw BrokerError.message("endpoint changed during restart")
        }
    }
    deinit { Darwin.close(instanceLock) }
}

private final class BrokerConnection: @unchecked Sendable {
    let fd: Int32
    let endpoint: LockedUseIPCEndpoint
    let identity: LockedUsePeerIdentity
    let context: LockedUseBrokerCoordinator.Context
    var decoder = LockedUseIPCFrame()
    var pending = Data()
    var readSource: DispatchSourceRead?
    var writeSource: DispatchSourceWrite?
    var closed = false
    let created = ProcessInfo.processInfo.systemUptime
    var clientAuditToken: Data?
    var clientInvalidated = false
    var clientDescriptor: Int32 = -1
    var clientIdentity: LockedUsePeerIdentity?
    init(fd: Int32, endpoint: LockedUseIPCEndpoint, identity: LockedUsePeerIdentity,
         context: LockedUseBrokerCoordinator.Context) {
        self.fd = fd; self.endpoint = endpoint; self.identity = identity; self.context = context
    }
}
