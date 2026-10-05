import Foundation
import Darwin

/// A durable revocation fence, never a reusable authorization permit. Recovery
/// can only drain/relock the old epoch and then require a normal manual unlock.
public struct LockedUseRecoveryRecord: Codable, Sendable {
    public let schemaVersion: Int
    public let bootSessionID: String
    public let leaseID: UUID
    public let owner: LockedUseBrokerCoordinator.Context
    public let originalClientToken: Data
    public let guardian: LockedUseBrokerCoordinator.Context?
    public let watchdog: LockedUseBrokerCoordinator.Context?
    public let watchdogChallenge: Data?
    public let everGranted: Bool
    public let observedUnlocked: Bool
    public let agentDrained: Bool
    public let fullyReleased: Bool

    public init(leaseID: UUID, owner: LockedUseBrokerCoordinator.Context, originalClientToken: Data,
                guardian: LockedUseBrokerCoordinator.Context?, watchdog: LockedUseBrokerCoordinator.Context?,
                watchdogChallenge: Data?, everGranted: Bool, observedUnlocked: Bool,
                agentDrained: Bool, fullyReleased: Bool, bootSessionID: String = UUID().uuidString) {
        schemaVersion = 1; self.bootSessionID = bootSessionID; self.leaseID = leaseID; self.owner = owner; self.originalClientToken = originalClientToken
        self.guardian = guardian; self.watchdog = watchdog; self.watchdogChallenge = watchdogChallenge
        self.everGranted = everGranted; self.observedUnlocked = observedUnlocked
        self.agentDrained = agentDrained; self.fullyReleased = fullyReleased
    }

    public func validated() throws -> Self {
        func valid(_ context: LockedUseBrokerCoordinator.Context) -> Bool {
            context.userID > 0 && context.auditSessionID > 0 && context.processID > 0
                && context.auditToken.count == 32 && !context.codeHash.isEmpty && context.codeHash.count <= 64
        }
        guard schemaVersion == 1, UUID(uuidString: bootSessionID) != nil, valid(owner), owner.role == .agent,
              originalClientToken.count == 32,
              guardian.map({ valid($0) && $0.role == .guardian && $0.userID == owner.userID && $0.auditSessionID == owner.auditSessionID }) ?? true,
              watchdog.map({ valid($0) && $0.role == .guardian && $0.userID == owner.userID && $0.auditSessionID == owner.auditSessionID }) ?? true,
              watchdogChallenge == nil || watchdogChallenge?.count == 32,
              guardian?.id != owner.id, watchdog?.id != owner.id,
              guardian == nil || watchdog == nil || guardian?.id != watchdog?.id,
              !fullyReleased || guardian == nil && watchdog == nil,
              !fullyReleased || !everGranted || observedUnlocked && agentDrained else { throw LockedUseBrokerCoordinator.Failure.malformed }
        return self
    }

    public static func loadInstalled() throws -> Self? {
        do {
            let data = try LockedUseSecureStore.read(components: ["Library", "Application Support", "OpenComputerUse", "LockedUse", "lease-recovery.json"], privateFile: true)
            return try JSONDecoder().decode(Self.self, from: data).validated()
        } catch LockedUseClientApprovals.Failure.inaccessible(let code) where code == ENOENT { return nil }
    }
}
