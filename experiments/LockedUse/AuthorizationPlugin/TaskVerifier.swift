import Foundation
import Security
import LightweightCodeRequirements

/// Kernel-backed live verification avoids CMS/keychain work in the lock-screen
/// helper. IDs alone are insufficient: require Developer ID validation and
/// live hardened/signature flags, then reject injection entitlements.
@_cdecl("ocu_verify_broker_task")
public func verifyBrokerTask(_ bytes: UnsafeRawPointer?, _ teamBytes: UnsafePointer<CChar>?) -> Int32 {
    guard #available(macOS 14.4, *) else { return -1 }
    guard let bytes, let teamBytes else { return -2 }
    let team = String(cString: teamBytes)
    guard team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return -2 }
    var token = audit_token_t()
    withUnsafeMutableBytes(of: &token) { $0.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: 32)) }
    guard let task = SecTaskCreateWithAuditToken(nil, token) else { return -3 }
    do {
        let requirement = try ProcessCodeRequirement.allOf {
            SigningIdentifier("dev.opencomputeruse.locked-use.broker")
            TeamIdentifier(team)
            ValidationCategory(.developerID)
            ProcessCodeSigningFlags.isSuperset(of: [.isDynamicallyValid, .isSigned, .isHardenedRuntimeEnforced, .isLibraryValidationRequired])
        }
        guard try SecTaskValidateForRequirement(task: task, requirement: requirement) else { return 0 }
        for key in ["get-task-allow", "com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                    "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"] {
            var error: Unmanaged<CFError>?
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
            if error != nil { _ = error?.takeRetainedValue(); return -3 }
            if (value as? NSNumber)?.boolValue == true { return 0 }
        }
        return try SecTaskValidateForRequirement(task: task, requirement: requirement) ? 1 : 0
    } catch { return -3 }
}
