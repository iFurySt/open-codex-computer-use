import Foundation

/// Display-only state shared by both shields; never authorizes GUI actions.
public struct LockedUseShieldStatus: Sendable {
    private var observedUnlock = false
    private var stopping = false
    private var lastMessage: String?
    public init() {}

    /// Each stage advances only. A later locked sample must not show the
    /// authentication countdown again while the relock barrier drains.
    public mutating func update(now: TimeInterval, startupDeadline: TimeInterval?,
                                unlocked: Bool, stopping: Bool) -> String? {
        self.stopping = self.stopping || stopping
        // Freeze the last rendered frame while both processes drain. A new
        // label layout just before either window closes creates a visible pop.
        guard !self.stopping else { return nil }
        observedUnlock = observedUnlock || unlocked
        let detail: String
        if observedUnlock {
            detail = "正在操作，完成后将锁屏"
        } else if let deadline = startupDeadline, deadline.isFinite, now.isFinite {
            let remaining = max(0, min(20, ceil(deadline - now)))
            detail = "等待系统认证：剩余 \(Int(remaining)) 秒"
        } else {
            detail = "正在准备保护"
        }
        let message = "Open Computer Use · 保护中\n\(detail)\n移动鼠标或按键可返回锁屏"
        guard message != lastMessage else { return nil }
        lastMessage = message
        return message
    }
}
