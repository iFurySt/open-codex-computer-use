import Darwin
import Foundation
import LockedUseNative
import Security

/// Identity extracted from the connected socket, validated against a designated
/// signing requirement. Same UID, a PID, or a claimed bundle ID is insufficient.
public struct LockedUsePeerIdentity: Sendable {
    public let auditToken: Data
    public let userID: UInt32
    public let auditUserID: UInt32
    public let auditSessionID: UInt32
    public let processID: Int32
    public let signingIdentifier: String
    public let teamIdentifier: String?
    public let codeDirectoryHash: Data
    public let designatedRequirement: String
    public let hardenedRuntime: Bool
    public let permitsCodeInjection: Bool

    public enum Failure: Error { case peerUnavailable(Int32), signingUnavailable(OSStatus), invalidSignature(OSStatus), malformedIdentity }

    /// The requirement must come from administrator-owned installation config
    /// or an explicit client approval. Never accept it in the peer's payload.
    public static func verified(socket descriptor: Int32, requirement: String) throws -> LockedUsePeerIdentity {
        var native = OCUPeerIdentity()
        guard ocu_copy_peer_identity(descriptor, &native) == 0 else { throw Failure.peerUnavailable(errno) }
        let token = withUnsafeBytes(of: native.audit_token) { Data($0) }
        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: token] as CFDictionary
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard guestStatus == errSecSuccess, let guest else { throw Failure.signingUnavailable(guestStatus) }
        var expected: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(requirement as CFString, [], &expected)
        guard requirementStatus == errSecSuccess, let expected else { throw Failure.signingUnavailable(requirementStatus) }
        let validity = SecCodeCheckValidity(guest, [], expected)
        guard validity == errSecSuccess else { throw Failure.invalidSignature(validity) }
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(guest, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else { throw Failure.signingUnavailable(staticStatus) }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation), &info)
        guard infoStatus == errSecSuccess, let info = info as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let hash = info[kSecCodeInfoUnique as String] as? Data,
              let designated = info[kSecCodeInfoDesignatedRequirement as String],
              CFGetTypeID(designated as CFTypeRef) == SecRequirementGetTypeID() else {
            throw Failure.signingUnavailable(infoStatus)
        }
        // Values above originate from Security.framework, never client metadata.
        let designatedRef = designated as! SecRequirement
        var requirementText: CFString?
        let textStatus = SecRequirementCopyString(designatedRef, [], &requirementText)
        guard textStatus == errSecSuccess, let text = requirementText as String?,
              native.process_id > 0 else { throw Failure.malformedIdentity }
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let dangerous = ["com.apple.security.get-task-allow", "get-task-allow",
            "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.allow-unsigned-executable-memory"]
        let injection = dangerous.contains { (entitlements[$0] as? NSNumber)?.boolValue == true }
        // Verify the live code once more after extracting on-disk metadata.
        let rechecked = SecCodeCheckValidity(guest, [], expected)
        guard rechecked == errSecSuccess else { throw Failure.invalidSignature(rechecked) }
        return .init(auditToken: token, userID: native.effective_user_id, auditUserID: native.audit_user_id, auditSessionID: native.audit_session_id,
            processID: native.process_id, signingIdentifier: identifier,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            codeDirectoryHash: hash, designatedRequirement: text,
            hardenedRuntime: flags & SecCodeSignatureFlags.runtime.rawValue != 0, permitsCodeInjection: injection)
    }
}
