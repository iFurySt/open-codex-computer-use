import Darwin
import Foundation
import LockedUseNative

/// Administrator-controlled approval records. These records authorize a
/// signing identity; they never declare the unlock backend validated or enable
/// a lease. No password, username, path, or environment override is stored.
public struct LockedUseClientApprovals: Codable, Sendable {
    public enum Role: String, Codable, Sendable { case client, agent, guardian }
    public struct Approval: Codable, Equatable, Sendable {
        public let id: UUID
        public let userID: UInt32
        public let role: Role
        public let signingIdentifier: String
        public let teamIdentifier: String

        public init(id: UUID = UUID(), userID: UInt32, role: Role,
                    signingIdentifier: String, teamIdentifier: String) throws {
            self.id = id; self.userID = userID; self.role = role
            self.signingIdentifier = signingIdentifier; self.teamIdentifier = teamIdentifier
            try validate()
        }

        public func requirement() throws -> String {
            // validate() restricts both interpolated values to a safe alphabet.
            try validate()
            return "identifier \"\(signingIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        }

        fileprivate func validate() throws {
            func alphanumeric(_ byte: UInt8) -> Bool {
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            }
            guard userID > 0, userID < UInt32.max,
                  (2...255).contains(signingIdentifier.utf8.count),
                  signingIdentifier.utf8.first.map(alphanumeric) == true,
                  signingIdentifier.utf8.allSatisfy({ alphanumeric($0) || $0 == 45 || $0 == 46 }),
                  teamIdentifier.utf8.count == 10,
                  teamIdentifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
                throw Failure.invalidRecord
            }
        }
    }
    public enum Failure: Error { case invalidRecord, insecureFile, inaccessible(Int32), unapproved }
    public let schemaVersion: Int
    public let approvals: [Approval]

    public init(approvals: [Approval]) throws {
        self.schemaVersion = 1
        self.approvals = approvals
        try validate()
    }

    public static func loadInstalled() throws -> LockedUseClientApprovals {
        try readSecureFile(components: ["Library", "Application Support", "OpenComputerUse", "LockedUse", "clients.json"], owner: 0)
    }

    public func verifiedPeer(socket descriptor: Int32, role: Role) throws -> LockedUsePeerIdentity {
        try validate()
        // Every candidate uses a root-approved signing requirement. The payload
        // cannot select a role, UID or requirement for the Broker to trust.
        for record in approvals where record.role == role {
            if let peer = try? LockedUsePeerIdentity.verified(socket: descriptor, requirement: record.requirement()),
               peer.userID == record.userID, peer.auditSessionID > 0,
               peer.hardenedRuntime, !peer.permitsCodeInjection,
               peer.signingIdentifier == record.signingIdentifier, peer.teamIdentifier == record.teamIdentifier {
                return peer
            }
        }
        throw Failure.unapproved
    }

    private func validate() throws {
        guard schemaVersion == 1, approvals.count <= 64,
              Set(approvals.map(\.id)).count == approvals.count else { throw Failure.invalidRecord }
        var identities = Set<String>()
        for approval in approvals {
            try approval.validate()
            guard identities.insert("\(approval.userID):\(approval.role):\(approval.teamIdentifier):\(approval.signingIdentifier)").inserted else {
                throw Failure.invalidRecord
            }
        }
    }

    static func decodeValidated(_ data: Data) throws -> LockedUseClientApprovals {
        guard data.count <= 128 * 1024 else { throw Failure.insecureFile }
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        try decoded.validate()
        return decoded
    }

    /// Walk with openat/O_NOFOLLOW; lstat followed by open would introduce a
    /// symlink race. All enclosing directories must have the trusted owner and
    /// no group/other write permission. Tests inject an alternate trusted owner;
    /// the installed production entry point always uses root (UID zero).
    static func readSecureFile(components: [String], owner: UInt32) throws -> LockedUseClientApprovals {
        try decodeValidated(LockedUseSecureStore.read(components: components, owner: owner))
    }
}
