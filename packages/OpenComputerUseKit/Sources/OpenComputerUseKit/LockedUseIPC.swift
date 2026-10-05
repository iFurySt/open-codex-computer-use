import Foundation

/// Local Broker protocol. Endpoint selection and kernel peer validation supply
/// the role/connection identity; neither is accepted from this message body.
public struct LockedUseIPCMessage: Codable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case status, disable, validationPassed, validationManual, begin, beginRecoveryProbe, guardianHello, guardianReport, guardianReleased, watchdogHello, watchdogRecoveryHello, watchdogReport, watchdogReleased, ownerRecoveryHello, guardianRecoveryHello, action, end, quiesced
        case pluginClaim, pluginConsume, pluginFinished
    }
    public let version: Int
    public let id: UUID
    public let operation: Operation
    public let leaseID: UUID?
    public let token: Data?
    public let session: LockedUseSession?
    public let guards: LockedUseStateMachine.Guards?
    public let stopReason: LockedUseStateMachine.StopReason?
    public let unlockWorkPending: Bool?
    public let hasObservedUnlock: Bool?

    public init(id: UUID = UUID(), operation: Operation, leaseID: UUID? = nil,
                token: Data? = nil, session: LockedUseSession? = nil,
                guards: LockedUseStateMachine.Guards? = nil,
                stopReason: LockedUseStateMachine.StopReason? = nil, unlockWorkPending: Bool? = nil, hasObservedUnlock: Bool? = nil) {
        version = 1; self.id = id; self.operation = operation
        self.leaseID = leaseID; self.token = token; self.session = session
        self.guards = guards; self.stopReason = stopReason
        self.unlockWorkPending = unlockWorkPending
        self.hasObservedUnlock = hasObservedUnlock
    }

    public func validated() throws -> Self {
        guard version == 1, token == nil || token?.count == 32 else { throw LockedUseIPCFrame.Failure.malformed }
        return self
    }
}

public struct LockedUseIPCReply: Codable, Sendable {
    public enum Result: String, Codable, Sendable { case ok, denied, waiting, authorized, active, relock, release }
    public let version: Int
    public let id: UUID
    public let result: Result
    public let phase: LockedUseStateMachine.Phase
    public let leaseID: UUID?
    public let token: Data?
    public let effects: [String]
    public let detail: String?
    public let guardsReleased: Bool?
    public let recoveryProbePrepared: Bool?

    public init(id: UUID, result: Result, phase: LockedUseStateMachine.Phase,
                leaseID: UUID? = nil, token: Data? = nil, effects: [String] = [], detail: String? = nil, guardsReleased: Bool? = nil, recoveryProbePrepared: Bool? = nil) {
        version = 1; self.id = id; self.result = result; self.phase = phase
        self.leaseID = leaseID; self.token = token; self.effects = effects; self.detail = detail
        self.guardsReleased = guardsReleased
        self.recoveryProbePrepared = recoveryProbePrepared
    }
}

/// Bounded length-prefix framing; never use readLine/getline in a privileged
/// server. Zero/oversized frames and EOF mid-frame permanently poison a stream.
public struct LockedUseIPCFrame: Sendable {
    public enum Failure: Error { case malformed, oversized, truncated, poisoned }
    public static let maximumPayload = 16 * 1024
    private var buffered = Data()
    private var failed = false

    public init() {}

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(value)
        guard !payload.isEmpty, payload.count <= maximumPayload else { throw Failure.oversized }
        let length = UInt32(payload.count)
        return Data([UInt8(length >> 24), UInt8((length >> 16) & 255),
            UInt8((length >> 8) & 255), UInt8(length & 255)]) + payload
    }

    /// The socket adapter reads at most 4096 bytes per event. A peer sending a
    /// batch cannot force unbounded buffering or one run-loop's worth of work.
    public mutating func append(_ chunk: Data) throws -> [Data] {
        guard !failed else { throw Failure.poisoned }
        do {
            guard chunk.count <= 4096, buffered.count + chunk.count <= Self.maximumPayload + 4096 + 4 else {
                throw Failure.oversized
            }
            buffered.append(chunk)
            var frames: [Data] = []
            while buffered.count >= 4 {
                let length = buffered.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard length > 0 else { throw Failure.malformed }
                guard length <= Self.maximumPayload else { throw Failure.oversized }
                guard buffered.count >= Int(length) + 4 else { break }
                guard frames.count < 16 else { throw Failure.oversized }
                frames.append(Data(buffered.dropFirst(4).prefix(Int(length))))
                buffered.removeFirst(Int(length) + 4)
            }
            return frames
        } catch {
            failed = true
            buffered.removeAll(keepingCapacity: false)
            throw error
        }
    }

    public mutating func finish() throws {
        guard !failed else { throw Failure.poisoned }
        failed = true
        guard buffered.isEmpty else { buffered.removeAll(); throw Failure.truncated }
    }
}
