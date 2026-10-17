import Foundation

/// Cancellation fences future native writes even if a readonly signature/AX
/// lookup is stuck. An already dispatched write remains pending until return.
public final class LockedUseUnlockCancellation: @unchecked Sendable {
    private let mutex = NSLock()
    private var cancelled = false
    private var activeProbe = false
    public init() {}
    public func cancel() { mutex.lock(); cancelled = true; mutex.unlock() }
    public func allowsRequest() -> Bool { mutex.lock(); defer { mutex.unlock() }; return !cancelled }
    public var quiesced: Bool { mutex.lock(); defer { mutex.unlock() }; return cancelled && !activeProbe }
    public func performProbe<T>(_ operation: () -> T) -> T? {
        mutex.lock()
        guard !cancelled && !activeProbe else { mutex.unlock(); return nil }
        activeProbe = true; mutex.unlock()
        defer { mutex.lock(); activeProbe = false; mutex.unlock() }
        return operation()
    }
}
