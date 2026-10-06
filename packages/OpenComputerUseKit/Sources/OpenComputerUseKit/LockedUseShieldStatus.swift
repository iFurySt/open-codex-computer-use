import Foundation

/// Display-only state shared by both shields; never authorizes GUI actions.
public struct LockedUseShieldStatus: Sendable {
    public static let message = "Open Computer Use is Using Your Mac\nPress any key or click to unlock"
    private var stopping = false
    private var lastMessage: String?
    public init() {}

    /// The protected presentation remains fixed across authentication and
    /// operation. Exit latches, freezing the last rendered frame during drain.
    public mutating func update(now: TimeInterval, startupDeadline: TimeInterval?,
                                unlocked: Bool, stopping: Bool) -> String? {
        self.stopping = self.stopping || stopping
        guard !self.stopping, lastMessage == nil else { return nil }
        lastMessage = Self.message
        return Self.message
    }
}
