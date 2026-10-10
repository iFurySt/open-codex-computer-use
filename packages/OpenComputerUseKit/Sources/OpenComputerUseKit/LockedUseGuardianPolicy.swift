import Foundation

/// Independent guardian policy. No caller command can stand in for observing
/// the original audit session locked. OS adapters provide evidence, not flags
/// copied from a Computer Use request.
public struct LockedUseGuardianPolicy: Sendable {
    public enum Phase: String, Codable, Sendable { case preparing, shielding, relocking, finished }
    public enum Reason: String, Codable, Sendable {
        case localInput, guardianFailure, parentDisconnected, heartbeatExpired
        case displayChanged, sessionChanged, leaseExpired, stopRequested
    }
    public enum Effect: Equatable, Sendable { case requestRelock, releaseShield }
    public private(set) var phase: Phase = .preparing
    public private(set) var reason: Reason?
    public let session: LockedUseSession
    private let deadline: TimeInterval
    private var lastHeartbeat: TimeInterval
    private var lastNow: TimeInterval
    private var lastRelock: TimeInterval = -.infinity
    private var quiesced = false
    private var lockedAfterDrain = false
    private var localRecoveryRequested = false
    public var localRecoveryReady: Bool { quiesced && lockedAfterDrain && localRecoveryRequested }
    public mutating func requestLocalRecovery() { localRecoveryRequested = true }
    private var topology: String?

    public init(session: LockedUseSession, now: TimeInterval, lifetime: TimeInterval = 300) throws {
        guard now.isFinite, now >= 0, lifetime.isFinite, lifetime > 0, lifetime <= 300,
              session.state != .unavailable, let uid = session.userID, uid > 0,
              let auditID = session.auditSessionID, auditID > 0 else {
            throw LockedUseStateMachine.Failure.invalidSession
        }
        self.session = session
        self.deadline = now + lifetime
        self.lastHeartbeat = now
        self.lastNow = now
    }

    public mutating func prepared(topology: String, now: TimeInterval) throws {
        try clock(now)
        guard phase == .preparing, !topology.isEmpty, now < deadline else {
            throw LockedUseStateMachine.Failure.invalidTransition
        }
        self.topology = topology
        // Startup is bounded separately; the live heartbeat begins only after
        // the child and its protection surface have actually registered.
        lastHeartbeat = now
        phase = .shielding
    }

    /// A heartbeat after expiry is never allowed to restore health.
    public mutating func heartbeat(now: TimeInterval) throws -> [Effect] {
        try clock(now)
        guard phase == .preparing || phase == .shielding else { return [] }
        if now - lastHeartbeat >= 1.5 { return stop(.heartbeatExpired, now: now) }
        if now >= deadline { return stop(.leaseExpired, now: now) }
        lastHeartbeat = now
        return []
    }

    public mutating func stop(_ reason: Reason, now: TimeInterval) -> [Effect] {
        guard phase != .finished else { return [] }
        if phase != .relocking {
            self.reason = reason
            phase = .relocking
        }
        guard !localRecoveryReady, now.isFinite, now >= lastNow, now - lastRelock >= 0.5 else { return [] }
        lastNow = now
        lastRelock = now
        return [.requestRelock]
    }

    public mutating func confirmQuiescence() { quiesced = true }
    public mutating func requireQuiescence() { quiesced = false; lockedAfterDrain = false }

    public mutating func poll(session current: LockedUseSession, topology currentTopology: String,
                              guardsHealthy: Bool, lockPresentationReady: Bool = false, now: TimeInterval) throws -> [Effect] {
        try clock(now)
        guard phase != .finished else { return [] }
        let sameSession = current.userID == session.userID && current.auditSessionID == session.auditSessionID
        if phase == .relocking {
            if sameSession, current.state == .unlocked, localRecoveryReady {
                phase = .finished
                return [.releaseShield]
            }
            if sameSession, current.state == .locked {
                if quiesced { lockedAfterDrain = true }
                if quiesced, lockPresentationReady {
                    phase = .finished
                    return [.releaseShield]
                }
                // Waiting for the action drain is not another lock request.
                // Repeated SPI calls can dismiss the password UI while the
                // user is trying to recover from a failed authorization.
                return []
            }
            return stop(reason ?? .guardianFailure, now: now)
        }
        guard sameSession, current.state != .unavailable else { return stop(.sessionChanged, now: now) }
        guard guardsHealthy else { return stop(.guardianFailure, now: now) }
        if let topology, topology != currentTopology { return stop(.displayChanged, now: now) }
        if now - lastHeartbeat >= 1.5 { return stop(.heartbeatExpired, now: now) }
        if now >= deadline { return stop(.leaseExpired, now: now) }
        return []
    }

    private mutating func clock(_ now: TimeInterval) throws {
        guard now.isFinite, now >= lastNow else { throw LockedUseStateMachine.Failure.invalidClock }
        lastNow = now
    }
}
