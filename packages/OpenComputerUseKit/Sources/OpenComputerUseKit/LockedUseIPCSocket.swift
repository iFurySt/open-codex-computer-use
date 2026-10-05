import Darwin
import Foundation

public enum LockedUseIPCEndpoint: String, Sendable {
    case agent, guardian, plugin
    public var path: String {
        "/Library/Application Support/OpenComputerUse/LockedUse/run/\(rawValue).sock"
    }
}

/// Owns one connection. Each synchronous request is serialized and bounded by
/// socket deadlines. A protocol failure permanently closes the connection.
/// GUI adapters must call this outside their AppKit/input event callback.
public final class LockedUseIPCClient: @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32
    private var decoder = LockedUseIPCFrame()
    private let brokerRequirement: String
    public let broker: LockedUsePeerIdentity

    public init(endpoint: LockedUseIPCEndpoint, brokerRequirement: String) throws {
        let fd = try LockedUseIPCSocket.connect(path: endpoint.path)
        do {
            let peer = try LockedUsePeerIdentity.verified(socket: fd, requirement: brokerRequirement)
            guard peer.userID == 0, peer.hardenedRuntime, !peer.permitsCodeInjection else {
                throw LockedUseClientApprovals.Failure.unapproved
            }
            broker = peer
            self.brokerRequirement = brokerRequirement
            descriptor = fd
        } catch { Darwin.close(fd); throw error }
    }

    public func request(_ message: LockedUseIPCMessage) throws -> LockedUseIPCReply {
        mutex.lock(); defer { mutex.unlock() }
        guard descriptor >= 0 else { throw LockedUseIPCFrame.Failure.poisoned }
        do {
            let current = try LockedUsePeerIdentity.verified(socket: descriptor, requirement: brokerRequirement)
            guard current.auditToken == broker.auditToken,
                  current.codeDirectoryHash == broker.codeDirectoryHash,
                  current.userID == 0, current.hardenedRuntime, !current.permitsCodeInjection else {
                throw LockedUseClientApprovals.Failure.unapproved
            }
            _ = try message.validated()
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            try LockedUseIPCSocket.writeAll(try LockedUseIPCFrame.encode(message), descriptor: descriptor, deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                try LockedUseIPCSocket.wait(descriptor: descriptor, events: Int16(POLLIN), deadline: deadline)
                let count = Darwin.read(descriptor, &bytes, bytes.count)
                if count < 0, [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard count > 0 else {
                    if count == 0 { try decoder.finish() }
                    throw POSIXError(.init(rawValue: count == 0 ? ECONNRESET : errno) ?? .EIO)
                }
                let frames = try decoder.append(Data(bytes.prefix(count)))
                guard frames.count <= 1 else { throw LockedUseIPCFrame.Failure.malformed }
                if let frame = frames.first {
                    let reply = try JSONDecoder().decode(LockedUseIPCReply.self, from: frame)
                    guard reply.version == 1, reply.id == message.id,
                          reply.token == nil || reply.token?.count == 32 else { throw LockedUseIPCFrame.Failure.malformed }
                    return reply
                }
            }
        } catch {
            shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor); descriptor = -1
            throw error
        }
    }

    public func close() {
        mutex.lock(); defer { mutex.unlock() }
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor); descriptor = -1
        }
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

public enum LockedUseIPCSocket {
    public static func address(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, !bytes.contains(0), bytes.count < capacity else {
            throw LockedUseIPCFrame.Failure.malformed
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        do {
            try configure(fd)
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            var address = try address(path: path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                try wait(descriptor: fd, events: Int16(POLLOUT), deadline: ProcessInfo.processInfo.systemUptime + 2)
                var failure: Int32 = 0
                var size = socklen_t(MemoryLayout.size(ofValue: failure))
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size) == 0, failure == 0 else {
                    throw POSIXError(.init(rawValue: failure == 0 ? errno : failure) ?? .EIO)
                }
            }
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    public static func configure(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var value: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout.size(ofValue: value))) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(descriptor, SOL_SOCKET, option, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
    }

    public static func wait(descriptor: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, remaining <= 60 else { throw POSIXError(.ETIMEDOUT) }
            var entry = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&entry, 1, Int32(ceil(remaining * 1000)))
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { throw POSIXError(result == 0 ? .ETIMEDOUT : .init(rawValue: errno) ?? .EIO) }
            guard entry.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(.EBADF) }
            return
        }
    }

    public static func writeAll(_ data: Data, descriptor: Int32, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 2) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                try wait(descriptor: descriptor, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0, [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard count > 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
    }
}
