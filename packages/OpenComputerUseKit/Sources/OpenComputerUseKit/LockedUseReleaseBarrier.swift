import Foundation

/// Continuous presentation evidence is independent of the session lock flag.
public struct LockedUseReleaseBarrier: Sendable {
    private var since: TimeInterval?
    private var fingerprint: String?
    private var lastNow: TimeInterval?
    public init() {}
    public mutating func observe(locked: Bool, presentation: String?, now: TimeInterval) -> Bool {
        guard now.isFinite, lastNow.map({ now >= $0 && now - $0 <= 0.5 }) ?? true else {
            since = nil; fingerprint = nil; lastNow = now.isFinite ? now : nil
            return false
        }
        lastNow = now
        guard locked, let presentation, !presentation.isEmpty else {
            since = nil; fingerprint = nil
            return false
        }
        if fingerprint != presentation { fingerprint = presentation; since = now }
        return now - (since ?? now) >= 1
    }
}
