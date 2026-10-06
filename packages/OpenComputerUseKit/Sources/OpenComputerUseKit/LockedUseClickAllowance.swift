import Foundation

/// Inherited-pipe capability for a single loginwindow click, never a PID-only
/// exemption. Hardware takeover is monitored separately and revokes this gate.
public struct LockedUseClickAllowance: Sendable {
    public enum Button: Sendable { case down, up }
    public enum Rejection: String, Sendable { case inactive, timing, capability, source, target, sequence }
    public private(set) var rejection: Rejection?
    private let tag: Int64
    private let sender: Int32
    private let deadline: TimeInterval
    private let began: TimeInterval
    private var down: (target: Int32, window: Int64, x: Double, y: Double, at: TimeInterval)?
    private var revoked = false

    public init(tag: Int64, sender: Int32, now: TimeInterval) {
        self.tag = tag; self.sender = sender; deadline = now + 5; began = now
        revoked = tag == 0 || sender <= 0 || !now.isFinite
    }
    public mutating func revoke() { revoked = true; down = nil }
    public mutating func accept(button: Button, tag candidate: Int64, sender candidateSender: Int32,
        target: Int32, window: Int64, x: Double, y: Double, now: TimeInterval, locked: Bool) -> Bool {
        rejection = nil
        guard !revoked else { rejection = .inactive; return false }
        guard locked, now.isFinite, now >= began, now < deadline else { rejection = .timing; revoke(); return false }
        guard candidate == tag else { rejection = .capability; return false }
        guard candidateSender == sender else { rejection = .source; return false }
        guard target > 0, window > 0, x.isFinite, y.isFinite else { rejection = .target; return false }
        switch button {
        case .down:
            guard down == nil else { rejection = .sequence; revoke(); return false }
            down = (target, window, x, y, now)
            return true
        case .up:
            guard let down, down.target == target, down.window == window, down.x == x, down.y == y,
                  now >= down.at, now - down.at < 0.25 else { rejection = .sequence; revoke(); return false }
            revoke()
            return true
        }
    }
}
