import Foundation
import Darwin
import PowerNative

public enum PowerPaths {
    #if DEBUG
    public static let suffix = ".dev"
    #else
    public static let suffix = ""
    #endif
    public static let service = "com.opencomputeruse.power.helper" + suffix
    public static var directory: String { "/tmp/ocu-power-\(getuid())\(suffix)" }
    public static var socket: String { directory + "/control.sock" }
}
public struct PowerRequest: Codable {
    public var operation: String
    public var options: HoldOptions?
    public var id: String?
    public var metrics_query: MetricsQuery?
    public var metrics_configuration: MetricsConfiguration?
    public init(_ operation: String, options: HoldOptions? = nil, id: String? = nil) { self.operation = operation; self.options = options; self.id = id }
}
public struct PowerResponse: Codable {
    public var hold: PowerHold?
    public var status: PowerStatus?
    public var error: String?
    public var metrics: MetricsReport?
    public init(hold: PowerHold? = nil, status: PowerStatus? = nil, error: String? = nil, metrics: MetricsReport? = nil) { self.hold = hold; self.status = status; self.error = error; self.metrics = metrics }
}
private func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw PowerFailure.invalid("Socket path too long") }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}
private func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
    var address = try socketAddress(path)
    return withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
}
private func configure(_ fd: Int32) {
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
}
public func readPowerLine(_ fd: Int32, limit: Int = 65536) throws -> Data? {
    var data = Data(), byte: UInt8 = 0
    while true {
        let count = recv(fd, &byte, 1, 0)
        if count == 0 { if data.isEmpty { return nil }; throw PowerFailure.invalid("Incomplete request") }
        if count < 0 { if errno == EINTR { continue }; throw PowerFailure.backend("Socket read failed") }
        if byte == 10 { return data }
        guard data.count < limit else { throw PowerFailure.invalid("Message exceeds size limit") }
        data.append(byte)
    }
}
public func writePowerLine(_ data: Data, to fd: Int32) throws {
    var framed = data; framed.append(10)
    try framed.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let sent = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            if sent < 0 && errno == EINTR { continue }
            guard sent > 0 else { throw PowerFailure.backend("Socket write failed") }
            offset += sent
        }
    }
}
public final class PowerClient {
    private let fd: Int32
    private let lock = NSLock()
    public init(path: String = PowerPaths.socket) throws {
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PowerFailure.backend("Cannot create client socket") }
        configure(fd)
        do {
            guard try withAddress(path, { connect(fd, $0, $1) }) == 0 else { throw PowerFailure.backend("Power coordinator is not running") }
            var uid: UInt32 = 0
            guard ocu_power_peer_uid(fd, &uid) == 0, uid == getuid() else { throw PowerFailure.backend("Unexpected coordinator owner") }
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        } catch { close(fd); throw error }
    }
    deinit { close(fd) }
    public func request(_ request: PowerRequest) throws -> PowerResponse {
        lock.lock(); defer { lock.unlock() }
        try writePowerLine(JSONEncoder().encode(request), to: fd)
        guard let line = try readPowerLine(fd, limit: 2 * 1024 * 1024) else { throw PowerFailure.backend("Coordinator disconnected") }
        let result = try JSONDecoder().decode(PowerResponse.self, from: line)
        if let error = result.error { throw PowerFailure.backend(error) }
        return result
    }
    public func acquire(_ options: HoldOptions = .init()) throws -> PowerHold {
        guard let hold = try request(.init("acquire", options: options)).hold else { throw PowerFailure.backend("Missing hold response") }
        return hold
    }
    public func status(_ id: String? = nil) throws -> PowerStatus {
        guard let status = try request(.init("status", id: id)).status else { throw PowerFailure.backend("Missing status response") }
        return status
    }
    public func metrics(_ query: MetricsQuery = .init()) throws -> MetricsReport {
        var message = PowerRequest("metrics"); message.metrics_query = query
        guard let result = try request(message).metrics else { throw PowerFailure.backend("Missing metrics response") }; return result
    }
    public func configureMetrics(_ value: MetricsConfiguration) throws -> MetricsReport {
        var message = PowerRequest("metrics_configure"); message.metrics_configuration = value
        guard let result = try request(message).metrics else { throw PowerFailure.backend("Missing metrics response") }; return result
    }
    public func clearMetrics() throws { _ = try request(.init("metrics_clear")) }
    public func release(_ id: String) throws { _ = try request(.init("release", id: id)) }
}
public final class PowerSocketServer {
    public var onShutdown: (() -> Void)?
    public var metricsService: MetricsService?
    public var metricsError: String?
    private let registry: PowerHoldRegistry
    private let path: String
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var connections: Set<Int32> = []
    public init(registry: PowerHoldRegistry, path: String = PowerPaths.socket) { self.registry = registry; self.path = path }
    public func start() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw PowerFailure.backend("Cannot create socket directory") }
        var info = stat()
        guard lstat(directory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw PowerFailure.backend("Unsafe socket directory") }
        // Hold an exclusive process lock for the entire lifetime. Never unlink a live peer's socket.
        let lockFD = open(directory + "/coordinator.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw PowerFailure.backend("Cannot open coordinator lock") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw PowerFailure.backend("Coordinator already running") }
        lockFile = lockFD; configure(lockFD)
        unlink(path)
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0); configure(fd)
        guard fd >= 0, try withAddress(path, { bind(fd, $0, $1) }) == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { stop(); throw PowerFailure.backend("Cannot bind coordinator socket") }
        DispatchQueue.global().async { [self] in
            while true {
                let peer = accept(fd, nil, nil)
                if peer < 0 { break }
                configure(peer)
                var uid: UInt32 = 0
                guard ocu_power_peer_uid(peer, &uid) == 0, uid == getuid() else { close(peer); continue }
                lock.lock()
                if connections.count >= 128 { lock.unlock(); close(peer); continue }
                connections.insert(peer); lock.unlock()
                DispatchQueue.global().async { [self] in serve(peer, uid: uid) }
            }
        }
    }
    private var lockFile: Int32 = -1
    public func stop() {
        lock.lock(); let peers = connections; lock.unlock()
        for peer in peers { Darwin.shutdown(peer, SHUT_RDWR) }
        if fd >= 0 { Darwin.shutdown(fd, SHUT_RDWR); close(fd); fd = -1 }
        if lockFile >= 0 { unlink(path); close(lockFile); lockFile = -1 }
    }
    private func serve(_ peer: Int32, uid: UInt32) {
        let connection = UUID().uuidString
        defer { registry.disconnected(connection); lock.lock(); connections.remove(peer); lock.unlock(); close(peer) }
        do {
            while let data = try readPowerLine(peer) {
                let response: PowerResponse
                do {
                    let request = try JSONDecoder().decode(PowerRequest.self, from: data)
                    switch request.operation {
                    case "metrics", "metrics_configure", "metrics_clear":
                        guard let metricsService else { throw PowerFailure.backend(metricsError ?? "Metrics not initialized") }
                        if request.operation == "metrics_configure" {
                            guard let config = request.metrics_configuration else { throw PowerFailure.invalid("Missing metrics configuration") }
                            try metricsService.configure(config)
                        } else if request.operation == "metrics_clear" { try metricsService.clear() }
                        response = .init(metrics: try metricsService.query(request.metrics_query ?? .init()))
                    case "acquire": response = .init(hold: try registry.acquire(request.options ?? .init(), uid: uid, connectionID: connection))
                    case "status": response = .init(status: try registry.status(uid: uid, id: request.id))
                    case "shutdown":
                        try registry.shutdown(); response = .init(status: try registry.status(uid: uid))
                    case "release":
                        guard let id = request.id else { throw PowerFailure.invalid("release requires an id") }
                        try registry.release(id, uid: uid); response = .init(status: try registry.status(uid: uid, id: id))
                    default: throw PowerFailure.invalid("Unknown operation")
                    }
                } catch { response = .init(error: error.localizedDescription) }
                try writePowerLine(JSONEncoder().encode(response), to: peer)
                if response.error == nil, (try? JSONDecoder().decode(PowerRequest.self, from: data).operation) == "shutdown" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.onShutdown?() }; return
                }
            }
        } catch { /* EOF, malformed framing or slow peer closes its connection-bound holds. */ }
    }
}
