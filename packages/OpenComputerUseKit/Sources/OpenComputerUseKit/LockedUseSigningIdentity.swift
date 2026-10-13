import Darwin
import Foundation

public enum LockedUseSigningIdentity {
    /// Read the running signed code through a kernel audit-token socketpair.
    /// Environment variables, claimed bundle identifiers and mutable paths
    /// cannot select the Broker's signing team.
    public static func current() throws -> LockedUsePeerIdentity {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw LockedUseClientApprovals.Failure.unapproved
        }
        defer { Darwin.close(descriptors[0]); Darwin.close(descriptors[1]) }
        let peer = try LockedUsePeerIdentity.verified(socket: descriptors[0], requirement: "anchor apple generic")
        guard peer.processID == getpid(), peer.userID == geteuid(), peer.hardenedRuntime,
              !peer.permitsCodeInjection, let team = peer.teamIdentifier,
              team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
            throw LockedUseClientApprovals.Failure.unapproved
        }
        return peer
    }

    public static func brokerRequirement() throws -> String {
        let peer = try current()
        return "identifier \"dev.opencomputeruse.locked-use.broker\" and anchor apple generic and certificate leaf[subject.OU] = \"\(peer.teamIdentifier!)\""
    }
}
