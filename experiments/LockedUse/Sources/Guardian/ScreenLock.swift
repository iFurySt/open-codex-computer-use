import Darwin
import Foundation

/// This private SPI requests a lock; only session observation confirms it.
/// Kept outside GUI tool dispatch and never used as an unlock primitive.
final class ScreenLock {
    private let handle: UnsafeMutableRawPointer?
    private let function: (@convention(c) () -> Void)?

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW | RTLD_LOCAL)
        if let handle, let symbol = dlsym(handle, "SACLockScreenImmediate") {
            function = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)
        } else { function = nil }
    }
    var available: Bool { function != nil }
    func request() { function?() }
    deinit { if let handle { dlclose(handle) } }
}

/// Small inherited-pipe protocol. No public socket or arbitrary path is opened.
/// EOF, excess input and unknown bytes are failures, never permission to unlock.
final class HeartbeatPipe {
    let descriptor: Int32
    private(set) var failed = false
    init(_ descriptor: Int32) {
        self.descriptor = descriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 { failed = true }
    }
    func drain(allowed: Set<UInt8>) -> [UInt8] {
        guard !failed else { return [] }
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count == 0 { failed = true; return [] }
        if count < 0 {
            if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { failed = true }
            return []
        }
        let result = Array(buffer.prefix(count))
        if count == buffer.count || result.contains(where: { !allowed.contains($0) }) { failed = true; return [] }
        return result
    }
    static func send(_ byte: UInt8, to descriptor: Int32) -> Bool {
        var value = byte
        return Darwin.write(descriptor, &value, 1) == 1
    }
}
