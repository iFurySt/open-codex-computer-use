import Foundation
import Security

/// Serialized Broker control plane. The daemon supplies authenticated contexts
/// and monotonic receipt times; requests cannot choose a role, UID or audit ID.
public struct LockedUseBrokerCoordinator: Sendable {
    public enum Role: Sendable { case agent, guardian, plugin }
    public struct Context: Sendable {
        public let id: UUID
        public let role: Role
        public let userID: UInt32
        public let auditSessionID: UInt32
        public init(id: UUID, role: Role, userID: UInt32, auditSessionID: UInt32) {
            self.id = id; self.role = role; self.userID = userID; self.auditSessionID = auditSessionID
        }
    }
    public enum Failure: Error { case denied, staleEvidence, malformed, unavailable }
    private var machine = LockedUseStateMachine()
    private var registry = LockedUsePermitRegistry()
    private let prerequisites: LockedUseStateMachine.Prerequisites
    private var leaseID: UUID?
    private var guardianChallenge: Data?
    private var guardianID: UUID?
    private var pluginID: UUID?
    private var issued: LockedUsePermitRegistry.Permit?
    private var lastReport: TimeInterval = 0
    private var guardEvidence: LockedUseStateMachine.Guards?
    private var observedSession: LockedUseSession?
    private var everGranted = false
    private var observedUnlocked = false
    private var connectionOwner: LockedUseStateMachine.Owner?
    private var receiptTime: TimeInterval = 0
    private var unlockWorkDrained = false
    private var agentEffects: [String] = []
    private var guardianEffects: [String] = []
    public var phase: LockedUseStateMachine.Phase { machine.phase }
    public var owner: LockedUseStateMachine.Owner? { machine.owner ?? connectionOwner }

    public init(enabled: Bool, backendValidated: Bool) {
        prerequisites = .init(enabled: enabled, backendValidated: backendValidated, clientAuthorized: true)
    }

    public mutating func handle(_ message: LockedUseIPCMessage, context: Context,
                                now: TimeInterval) throws -> LockedUseIPCReply {
        _ = try message.validated()
        try tick(now: now)
        switch message.operation {
        case .status:
            // Only the owner may acknowledge a manual unlock, using a native
            // session observation matching its kernel connection identity.
            if isOwner(context), phase == .awaitingManualUnlock, let session = message.session {
                try check(session: session, context: context)
                try apply(machine.observe(session: session, now: now))
            }
            return reply(message, context: context)
        case .begin:
            guard context.role == .agent, let session = message.session else { throw Failure.denied }
            try check(session: session, context: context)
            let owner = LockedUseStateMachine.Owner(connectionID: context.id,
                userID: context.userID, auditSessionID: context.auditSessionID)
            let effects = try machine.begin(owner: owner, session: session, prerequisites: prerequisites, now: now)
            connectionOwner = owner
            leaseID = UUID(); guardianChallenge = try randomToken()
            guardianID = nil; pluginID = nil; issued = nil
            guardEvidence = nil; observedSession = session
            everGranted = false; observedUnlocked = false
            unlockWorkDrained = false
            agentEffects.removeAll(); guardianEffects.removeAll()
            try apply(effects)
            return reply(message, context: context, token: guardianChallenge)
        case .guardianHello:
            guard context.role == .guardian, sameSession(context), guardianID == nil,
                  phase == .preparing, message.leaseID == leaseID,
                  let token = message.token, let challenge = guardianChallenge,
                  equal(token, challenge) else { throw Failure.denied }
            guardianID = context.id; guardianChallenge = nil
            return reply(message, context: context)
        case .guardianReport:
            guard isGuardian(context), message.leaseID == leaseID,
                  let session = message.session, let guards = message.guards else { throw Failure.denied }
            try check(session: session, context: context)
            observedSession = session; guardEvidence = guards; lastReport = now
            if let pending = message.unlockWorkPending { unlockWorkDrained = !pending }
            if everGranted, session.state == .unlocked { observedUnlocked = true }
            if message.stopReason == .physicalInput { try apply(machine.localInput()) }
            else if message.stopReason != nil, let owner {
                try apply(machine.end(owner: owner, reason: .guardLost))
            }
            if phase == .preparing { try apply(machine.guardsPrepared(guards, now: now)) }
            else { try apply(machine.heartbeat(guards, now: now)) }
            try apply(machine.observe(session: session, now: now))
            return reply(message, context: context)
        case .pluginClaim:
            guard context.role == .plugin, sameAuditSession(context), phase == .authorizing,
                  pluginID == nil, let issued else { throw Failure.denied }
            try freshGuards(now: now)
            pluginID = context.id
            return reply(message, context: context, token: issued.nonce)
        case .pluginConsume:
            guard context.role == .plugin, context.id == pluginID, sameAuditSession(context),
                  message.leaseID == leaseID, let token = message.token,
                  let issued, let owner else { throw Failure.denied }
            try freshGuards(now: now)
            _ = try registry.consume(attemptID: issued.attemptID, session: issued.session,
                nonce: token, guardsHealthy: true, now: now)
            try machine.consumePermit(id: issued.attemptID, owner: owner, now: now)
            everGranted = true
            // Authorization granted is still not an active GUI lease.
            return reply(message, context: context, authorized: true)
        case .pluginFinished:
            guard context.role == .plugin, context.id == pluginID else { throw Failure.denied }
            if message.stopReason != nil, let owner { try apply(machine.end(owner: owner, reason: .operationFailed)) }
            return reply(message, context: context)
        case .action:
            guard isOwner(context), message.leaseID == leaseID,
                  let owner, let session = message.session else { throw Failure.denied }
            try check(session: session, context: context)
            try freshGuards(now: now)
            try apply(machine.authorizeAction(owner: owner, session: session, now: now))
            return reply(message, context: context)
        case .end:
            guard isOwner(context), let owner else { throw Failure.denied }
            try apply(machine.end(owner: owner, reason: message.stopReason ?? .turnEnded))
            return reply(message, context: context)
        case .quiesced:
            guard isOwner(context), let owner, message.leaseID == leaseID else { throw Failure.denied }
            // A consumed allow may still be queued in loginwindow. An old lock
            // screen is insufficient; require that unlock actually occurred
            // before accepting the action/transaction drain acknowledgement.
            guard unlockWorkDrained, !everGranted || observedUnlocked else { return reply(message, context: context) }
            try machine.confirmQuiescence(owner: owner)
            if let session = observedSession { try apply(machine.observe(session: session, now: now)) }
            return reply(message, context: context)
        }
    }

    public mutating func tick(now: TimeInterval) throws {
        try registry.expire(now: now)
        receiptTime = now
        try apply(machine.tick(now: now))
    }

    public mutating func disconnected(_ context: Context) throws {
        registry.revoke(connectionID: context.id)
        if isOwner(context), let owner { try apply(machine.end(owner: owner, reason: .disconnected)) }
        else if isGuardian(context) || (context.id == pluginID && !everGranted), let owner {
            try apply(machine.end(owner: owner, reason: .guardLost))
        }
    }

    private func check(session: LockedUseSession, context: Context) throws {
        guard context.userID > 0, context.auditSessionID > 0,
              session.userID == context.userID, session.auditSessionID == context.auditSessionID else { throw Failure.denied }
    }
    private func isOwner(_ context: Context) -> Bool {
        context.role == .agent && context.id == owner?.connectionID && sameSession(context)
    }
    private func sameSession(_ context: Context) -> Bool {
        context.userID == owner?.userID && sameAuditSession(context)
    }
    private func sameAuditSession(_ context: Context) -> Bool {
        context.auditSessionID > 0 && context.auditSessionID == owner?.auditSessionID
    }
    private func isGuardian(_ context: Context) -> Bool {
        context.role == .guardian && context.id == guardianID && sameSession(context)
    }
    private func freshGuards(now: TimeInterval) throws {
        guard now >= lastReport, now - lastReport < 1,
              guardEvidence?.healthy == true, observedSession?.state != .unavailable else { throw Failure.staleEvidence }
    }
    private mutating func apply(_ effects: [LockedUseStateMachine.Effect]) throws {
        for effect in effects {
            switch effect {
            case .prepareGuards: agentEffects.append("prepareGuards")
            case let .issuePermit(permit):
                issued = try registry.issue(attemptID: permit.id, connectionID: permit.owner.connectionID,
                    session: .init(userID: permit.owner.userID, auditSessionID: permit.owner.auditSessionID),
                    guardsHealthy: true, now: receiptTime)
            case .requestUnlock:
                unlockWorkDrained = false
                guardianEffects.append("requestUnlock")
            case .stopActions: agentEffects.append("stopActions")
            case .revokePermit:
                if let issued { registry.revoke(attemptID: issued.attemptID) }
                issued = nil
            case .cancelUnlock: guardianEffects.append("cancelUnlock")
            case .requestRelock: guardianEffects.append("requestRelock")
            case .releaseGuards: guardianEffects.append("releaseGuards")
            }
        }
    }
    private mutating func reply(_ message: LockedUseIPCMessage, context: Context,
                               token: Data? = nil, authorized: Bool = false) -> LockedUseIPCReply {
        var effects: [String] = []
        if isOwner(context) { effects = agentEffects; agentEffects.removeAll() }
        if isGuardian(context) { effects = guardianEffects; guardianEffects.removeAll() }
        let result: LockedUseIPCReply.Result = effects.contains("releaseGuards") ? .release
            : authorized ? .authorized : phase == .active && isOwner(context) ? .active : phase == .relocking ? .relock
            : phase == .idle ? .ok : .waiting
        return .init(id: message.id, result: result, phase: phase,
            leaseID: isOwner(context) || isGuardian(context) || context.id == pluginID ? leaseID : nil,
            token: token, effects: effects)
    }
    private func randomToken() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.unavailable }
        return Data(bytes)
    }
    private func equal(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == 32, rhs.count == 32 else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
