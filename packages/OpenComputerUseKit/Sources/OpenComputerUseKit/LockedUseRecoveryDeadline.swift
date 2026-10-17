import Dispatch
import Foundation

/// Independent of the RPC queue and its socket/signature deadlines. Repeated
/// failures can shorten this deadline, never postpone it. The owner decides
/// how to stop its own process; this helper never kills another process.
public final class LockedUseRecoveryDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ocu.locked-use.recovery-deadline")
    private var timer: DispatchSourceTimer?
    private var deadline: UInt64?
    private var generation: UInt64 = 0
    private let expired: @Sendable () -> Void

    public init(expired: @escaping @Sendable () -> Void) { self.expired = expired }

    public func arm(after seconds: TimeInterval) {
        precondition(seconds.isFinite && seconds > 0)
        let next = DispatchTime.now() + seconds
        lock.lock(); defer { lock.unlock() }
        if let deadline, deadline <= next.uptimeNanoseconds { return }
        timer?.cancel()
        generation &+= 1
        let expected = generation
        deadline = next.uptimeNanoseconds
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: next, leeway: .milliseconds(10))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == expected, self.deadline != nil else { self.lock.unlock(); return }
            self.timer?.cancel(); self.timer = nil; self.deadline = nil
            self.lock.unlock()
            self.expired()
        }
        timer = source
        source.resume()
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        timer?.cancel(); timer = nil; deadline = nil
    }

    deinit { timer?.cancel() }
}
