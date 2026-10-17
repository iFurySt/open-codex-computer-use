import Foundation
import Security
import LightweightCodeRequirements

// Linked only into the build-time diagnostic executable, never the plugin.
@_cdecl("ocu_diagnose_broker_task")
public func diagnoseBrokerTask(_ bytes: UnsafeRawPointer?, _ teamBytes: UnsafePointer<CChar>?) -> Int32 {
    guard #available(macOS 14.4, *), let bytes, let teamBytes else { return -1 }
    var token = audit_token_t()
    withUnsafeMutableBytes(of: &token) { $0.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: 32)) }
    guard let task = SecTaskCreateWithAuditToken(nil, token) else { return -2 }
    do {
        let checks = try [
            ProcessCodeRequirement.allOf { SigningIdentifier("dev.opencomputeruse.locked-use.broker") },
            ProcessCodeRequirement.allOf { TeamIdentifier(String(cString: teamBytes)) },
            ProcessCodeRequirement.allOf { ValidationCategory(.developerID) },
            ProcessCodeRequirement.allOf { ProcessCodeSigningFlags.isSuperset(of: [.isDynamicallyValid]) },
            ProcessCodeRequirement.allOf { ProcessCodeSigningFlags.isSuperset(of: [.isSigned]) },
            ProcessCodeRequirement.allOf { ProcessCodeSigningFlags.isSuperset(of: [.isHardenedRuntimeEnforced]) },
            ProcessCodeRequirement.allOf { ProcessCodeSigningFlags.isSuperset(of: [.isLibraryValidationRequired]) }
        ]
        var failed: Int32 = 0
        for (index, check) in checks.enumerated() {
            if try !SecTaskValidateForRequirement(task: task, requirement: check) { failed |= 1 << index }
        }
        return failed
    } catch { return -3 }
}
