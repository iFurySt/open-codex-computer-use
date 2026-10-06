import Foundation

/// Passed only through the launcher-owned inherited pipe, never argv/env.
/// Kernel signing/audit validation still precedes challenge consumption.
public struct LockedUseGuardianBootstrap: Codable, Sendable {
    public let leaseID: UUID
    public let token: Data
    public let clickTag: Int64?
    public let startupDeadline: TimeInterval?
    public init(leaseID: UUID, token: Data, clickTag: Int64? = nil, startupDeadline: TimeInterval? = nil) throws {
        guard token.count == 32 else { throw LockedUseIPCFrame.Failure.malformed }
        self.leaseID = leaseID; self.token = token
        self.clickTag = clickTag
        self.startupDeadline = startupDeadline
    }
}
