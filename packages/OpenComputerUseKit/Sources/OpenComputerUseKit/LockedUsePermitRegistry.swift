import Foundation
import Security

/// Broker-side one-shot capability registry. The plugin supplies the kernel
/// verified session; clients cannot choose a UID/session in an IPC body.
/// This registry is deliberately independent of authorization return values.
public struct LockedUsePermitRegistry: Sendable {
    public struct Session: Equatable, Codable, Sendable {
        public let userID: UInt32
        public let auditSessionID: UInt32
        public init(userID: UInt32, auditSessionID: UInt32) {
            self.userID = userID; self.auditSessionID = auditSessionID
        }
    }
    public struct Permit: Equatable, Sendable {
        public let nonce: Data
        public let attemptID: UUID
        public let connectionID: UUID
        public let session: Session
        public let deadline: TimeInterval
    }
    public enum Failure: Error { case invalidClock, invalidPermit, unavailable, duplicateAttempt }
    private var permits: [UUID: Permit] = [:]
    private var retired: Set<UUID> = []
    private var lastNow: TimeInterval = 0
    public init() {}

    public mutating func issue(attemptID: UUID, connectionID: UUID, session: Session,
                               guardsHealthy: Bool, now: TimeInterval) throws -> Permit {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.unavailable }
        return try issue(attemptID: attemptID, connectionID: connectionID, session: session,
                         guardsHealthy: guardsHealthy, now: now, nonce: Data(bytes))
    }

    mutating func issue(attemptID: UUID, connectionID: UUID, session: Session,
                               guardsHealthy: Bool, now: TimeInterval, nonce: Data) throws -> Permit {
        try clock(now)
        guard guardsHealthy, session.userID > 0, session.auditSessionID > 0,
              nonce.count == 32, permits.count < 32, retired.count < 4096 else { throw Failure.unavailable }
        guard permits[attemptID] == nil, !retired.contains(attemptID),
              !permits.values.contains(where: { $0.session == session }) else { throw Failure.duplicateAttempt }
        let permit = Permit(nonce: nonce, attemptID: attemptID, connectionID: connectionID,
            session: session, deadline: now + LockedUseStateMachine.permitLifetime)
        permits[attemptID] = permit
        return permit
    }

    /// Authentication of the plugin's Apple SecurityAgent identity must precede
    /// this operation. A consumed/expired/revoked attempt is never reusable.
    public mutating func consume(attemptID: UUID, session: Session, nonce: Data,
                                 guardsHealthy: Bool, now: TimeInterval) throws -> Permit {
        try clock(now)
        guard let permit = permits[attemptID] else { throw Failure.invalidPermit }
        if now >= permit.deadline || !guardsHealthy {
            retire(attemptID)
            throw Failure.invalidPermit
        }
        guard permit.session == session, constantTimeEqual(nonce, permit.nonce) else { throw Failure.invalidPermit }
        retire(attemptID)
        return permit
    }

    public mutating func revoke(connectionID: UUID) {
        for permit in Array(permits.values) where permit.connectionID == connectionID { retire(permit.attemptID) }
    }
    public mutating func revoke(attemptID: UUID) {
        if permits[attemptID] != nil { retire(attemptID) }
    }
    public mutating func expire(now: TimeInterval) throws {
        try clock(now)
        for permit in Array(permits.values) where now >= permit.deadline { retire(permit.attemptID) }
    }
    public var pendingCount: Int { permits.count }

    private mutating func retire(_ id: UUID) {
        permits.removeValue(forKey: id)
        retired.insert(id)
    }
    private mutating func clock(_ now: TimeInterval) throws {
        guard now.isFinite, now >= lastNow else { throw Failure.invalidClock }
        lastNow = now
    }
    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == 32, rhs.count == 32 else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
