import Foundation
import Security

/// Explicit validation-only experiment. It has no GUI action authorization,
/// guard readiness claims, production evidence, or restart/resume capability.
public struct LockedUseUnshieldedDiagnostic: Sendable {
    public private(set) var phase: LockedUseStateMachine.Phase = .authorizing
    public let leaseID = UUID()
    public let deadline: TimeInterval
    public let owner: LockedUseBrokerCoordinator.Context
    private let session: LockedUseSession
    private var lastNow: TimeInterval
    private var pluginID: UUID?
    private var nonce: Data?
    private var permitDeadline: TimeInterval = 0
    private var consumed = false
    public private(set) var finished = false

    public init(owner: LockedUseBrokerCoordinator.Context, session: LockedUseSession, now: TimeInterval) throws {
        guard owner.role == .guardian, session.state == .locked,
              session.userID == owner.userID, session.auditSessionID == owner.auditSessionID,
              now.isFinite else { throw LockedUseBrokerCoordinator.Failure.denied }
        self.owner = owner; self.session = session; lastNow = now
        deadline = now + 20
    }
    public mutating func tick(now: TimeInterval) throws {
        guard now.isFinite, now >= lastNow else { throw LockedUseBrokerCoordinator.Failure.staleEvidence }
        lastNow = now
        if now >= deadline || nonce != nil && now >= permitDeadline {
            nonce = nil; phase = .awaitingManualUnlock
        }
    }
    public mutating func cancel() { nonce = nil; phase = .awaitingManualUnlock }
    public mutating func handle(_ message: LockedUseIPCMessage, context: LockedUseBrokerCoordinator.Context, now: TimeInterval) throws -> LockedUseIPCReply {
        try tick(now: now)
        switch message.operation {
        case .status:
            if context.id == owner.id {
                guard let observed = message.session, observed.userID == session.userID,
                      observed.auditSessionID == session.auditSessionID else { throw LockedUseBrokerCoordinator.Failure.denied }
            }
        case .pluginClaim:
            guard context.role == .plugin, context.auditSessionID == owner.auditSessionID,
                  phase == .authorizing, pluginID == nil else { throw LockedUseBrokerCoordinator.Failure.denied }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LockedUseBrokerCoordinator.Failure.unavailable }
            nonce = Data(bytes); pluginID = context.id; permitDeadline = min(now + 5, deadline)
            return reply(message, context: context, token: nonce)
        case .pluginConsume:
            guard context.role == .plugin, context.auditSessionID == owner.auditSessionID,
                  context.id == pluginID, phase == .authorizing, now < permitDeadline,
                  message.leaseID == leaseID, let expected = nonce, let token = message.token,
                  token.count == expected.count,
                  zip(token, expected).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else { throw LockedUseBrokerCoordinator.Failure.denied }
            nonce = nil; consumed = true; phase = .unlocking
        case .pluginFinished:
            guard context.role == .plugin, context.id == pluginID else { throw LockedUseBrokerCoordinator.Failure.denied }
            if message.stopReason != nil { cancel() }
        case .endUnshieldedDiagnostic:
            guard context.id == owner.id, message.leaseID == leaseID,
                  let observed = message.session, observed.state == .locked,
                  observed.userID == session.userID, observed.auditSessionID == session.auditSessionID else { throw LockedUseBrokerCoordinator.Failure.denied }
            nonce = nil; finished = true; phase = .idle
        default: throw LockedUseBrokerCoordinator.Failure.denied
        }
        return reply(message, context: context)
    }
    public func reply(_ message: LockedUseIPCMessage, context: LockedUseBrokerCoordinator.Context, token: Data? = nil) -> LockedUseIPCReply {
        .init(id: message.id, result: consumed && phase == .unlocking ? .authorized : .waiting, phase: phase,
              leaseID: context.id == owner.id || context.id == pluginID ? leaseID : nil,
              token: token, detail: "unshieldedDiagnostic", startupDeadline: deadline)
    }
}
