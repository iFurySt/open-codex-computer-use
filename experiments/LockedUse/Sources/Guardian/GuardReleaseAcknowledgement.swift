import Foundation
import OpenComputerUseKit
import os

/// Called only after a guard's own drain/presentation barrier closed its
/// windows. Reauthenticate the same audit-token/code identity for the ACK;
/// a failed periodic report must not make terminal cleanup silently vanish.
enum GuardReleaseAcknowledgement {
    static func send(bootstrap: LockedUseGuardianBootstrap, watchdog: Bool, observedUnlock: Bool) -> Bool {
        let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "GuardRelease")
        let role = watchdog ? "watchdog" : "main"
        for attempt in 1...3 {
            do {
                let client = try LockedUseIPCClient(endpoint: .guardian, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
                defer { client.close() }
                let hello = try client.request(.init(operation: watchdog ? .watchdogRecoveryHello : .guardianRecoveryHello,
                    leaseID: bootstrap.leaseID, session: .current(), hasObservedUnlock: observedUnlock))
                guard hello.result != .denied else { throw GuardianError.message("Release identity rejected") }
                let reply = try client.request(.init(operation: watchdog ? .watchdogReleased : .guardianReleased,
                    leaseID: bootstrap.leaseID))
                guard reply.result != .denied else { throw GuardianError.message("Release acknowledgment rejected") }
                logger.notice("releaseAcknowledged role=\(role, privacy: .public) attempt=\(attempt, privacy: .public)")
                return true
            } catch {
                logger.notice("releaseRetry role=\(role, privacy: .public) attempt=\(attempt, privacy: .public)")
            }
        }
        return false
    }
}
