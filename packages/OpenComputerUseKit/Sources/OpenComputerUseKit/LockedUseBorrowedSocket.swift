import Darwin
import Foundation

/// An SCM_RIGHTS duplicate shares the caller's transport. Release only this fd;
/// shutdown would also break the caller. In-flight verification pins its lifetime.
public final class LockedUseBorrowedSocket: @unchecked Sendable {
    public enum Failure: Error { case closed }
    private let lock = NSLock()
    private var fd: Int32
    private var readers = 0
    private var closing = false

    public init(descriptor: Int32) { fd = descriptor }
    public var descriptor: Int32 {
        lock.lock(); defer { lock.unlock() }
        return closing ? -1 : fd
    }

    public func withDescriptor<T>(_ body: (Int32) throws -> T) throws -> T {
        lock.lock()
        guard !closing, fd >= 0 else { lock.unlock(); throw Failure.closed }
        readers += 1
        let current = fd
        lock.unlock()
        defer {
            lock.lock()
            readers -= 1
            let released = closing && readers == 0 ? fd : -1
            if released >= 0 { fd = -1 }
            lock.unlock()
            if released >= 0 { Darwin.close(released) }
        }
        return try body(current)
    }

    public func close() {
        lock.lock()
        closing = true
        let released = readers == 0 ? fd : -1
        if released >= 0 { fd = -1 }
        lock.unlock()
        if released >= 0 { Darwin.close(released) }
    }
    deinit { close() }
}
