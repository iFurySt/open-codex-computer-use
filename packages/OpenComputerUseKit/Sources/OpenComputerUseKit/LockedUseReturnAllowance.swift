import Foundation

/// A separate inherited capability for exactly one unmodified Return pair.
/// Never grants general keyboard access or exempts events by PID alone.
public struct LockedUseReturnAllowance: Sendable {
    public enum Rejection: String, Sendable { case inactive, timing, capability, source, target, key, sequence }
    public private(set) var rejection: Rejection?
    private let tag: Int64
    private let sender: Int32
    private let session: LockedUseSession
    private let began: TimeInterval
    private var down: (target: Int32, at: TimeInterval)?
    private var revoked = false
    public init(tag: Int64, sender: Int32, session: LockedUseSession, now: TimeInterval) {
        self.tag = tag; self.sender = sender; self.session = session; began = now
        revoked = tag == 0 || sender <= 0 || session.state != .locked || !now.isFinite
    }
    public mutating func revoke() { revoked = true; down = nil }
    public mutating func accept(isDown: Bool, tag candidate: Int64, sender source: Int32,
        target: Int32, keyCode: Int64, repeated: Bool, modified: Bool,
        session observed: LockedUseSession, now: TimeInterval) -> Bool {
        rejection = nil
        guard !revoked else { rejection = .inactive; return false }
        guard observed == session, now.isFinite, now >= began, now < began + 5 else {
            rejection = .timing; revoke(); return false
        }
        guard candidate == tag else { rejection = .capability; return false }
        guard source == sender else { rejection = .source; return false }
        guard target > 0 else { rejection = .target; return false }
        guard keyCode == 36, !repeated, !modified else { rejection = .key; revoke(); return false }
        if isDown {
            guard down == nil else { rejection = .sequence; revoke(); return false }
            down = (target, now); return true
        }
        guard let down, down.target == target, now >= down.at, now - down.at < 0.25 else {
            rejection = .sequence; revoke(); return false
        }
        revoke(); return true
    }
}
