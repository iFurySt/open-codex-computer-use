import Darwin
import Dispatch
import Foundation
import LockedUseNative
import OpenComputerUseKit

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
            // Production validation matching is wired by the signed installer;
            // the explicit administrator-launched validation instance is the
            // only route to exercise an as-yet-unvalidated unlock transaction.
            let server = try BrokerServer(approvals: approvals, enabled: configuration.enabled,
                backendValidated: validation)
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
    private let queue = DispatchQueue(label: "dev.opencomputeruse.locked-use.broker")
    private let approvals: LockedUseClientApprovals
    private var coordinator: LockedUseBrokerCoordinator
    private var listeners: [DispatchSourceRead] = []
    private var connections: [UUID: BrokerConnection] = [:]
    private var timer: DispatchSourceTimer?
    private let instanceLock: Int32

    init(approvals: LockedUseClientApprovals, enabled: Bool, backendValidated: Bool) throws {
        self.approvals = approvals
        coordinator = .init(enabled: enabled, backendValidated: backendValidated)
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
    }

    func start() throws {
        for endpoint in [LockedUseIPCEndpoint.agent, .guardian, .plugin] {
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
            do { try self.coordinator.tick(now: ProcessInfo.processInfo.systemUptime) }
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
                let role: LockedUseBrokerCoordinator.Role = endpoint == .agent ? .agent : endpoint == .guardian ? .guardian : .plugin
                let context = LockedUseBrokerCoordinator.Context(id: UUID(), role: role,
                    userID: identity.userID, auditSessionID: identity.auditSessionID)
                let connection = BrokerConnection(fd: client, endpoint: endpoint, identity: identity, context: context)
                connections[context.id] = connection
                let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
                source.setEventHandler { [weak self, weak connection] in
                    guard let connection, !connection.closed else { return }
                    self?.read(connection)
                }
                connection.readSource = source
                source.resume()
            } catch { Darwin.close(client) }
        }
    }

    private func authenticate(fd: Int32, endpoint: LockedUseIPCEndpoint) throws -> LockedUsePeerIdentity {
        switch endpoint {
        case .agent: return try approvals.verifiedPeer(socket: fd, role: .agent)
        case .guardian: return try approvals.verifiedPeer(socket: fd, role: .guardian)
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
                let reply: LockedUseIPCReply
                do {
                    reply = try coordinator.handle(request, context: connection.context, now: ProcessInfo.processInfo.systemUptime)
                } catch {
                    reply = .init(id: request.id, result: .denied, phase: coordinator.phase,
                        detail: "Request denied by Broker policy")
                }
                connection.pending.append(try LockedUseIPCFrame.encode(reply))
                guard connection.pending.count <= 64 * 1024 else { throw LockedUseIPCFrame.Failure.oversized }
            }
            flush(connection)
        } catch { close(connection) }
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
        try? coordinator.disconnected(connection.context)
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
    init(fd: Int32, endpoint: LockedUseIPCEndpoint, identity: LockedUsePeerIdentity,
         context: LockedUseBrokerCoordinator.Context) {
        self.fd = fd; self.endpoint = endpoint; self.identity = identity; self.context = context
    }
}
