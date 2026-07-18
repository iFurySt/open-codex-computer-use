import Darwin
import Foundation
import OpenComputerUseKit
import Security

// Authenticates a process connecting to the app-agent Unix socket. Gathers peer facts via
// getpeereid (same-uid) + LOCAL_PEERTOKEN (audit token) + Security.framework code-signing, then
// delegates the trust decision to the pure AppAgentPeerAuthPolicy. See that type for rationale.
enum SocketPeerAuthenticator {
    // The agent's own Team Identifier, resolved once. nil for unsigned/ad-hoc dev builds.
    static let agentTeamIdentifier: String? = resolveSelfTeamIdentifier()

    // The agent's own bundle identifier (nil when not running from a bundle). Used to pin the
    // peer requirement to this specific app — the legit CLI client runs from the same app bundle.
    static let agentBundleIdentifier: String? = Bundle.main.bundleIdentifier

    // Human-readable enforcement state for diagnostics — makes the silent same-uid fallback
    // (unsigned/ad-hoc agent) observable instead of only a one-time stderr line.
    static var statusDescription: String {
        if let team = agentTeamIdentifier, !team.isEmpty {
            return "active (same-uid + code-signature pin, team \(team))"
        }
        return "same-uid only — agent unsigned/ad-hoc, code-signature pin INACTIVE"
    }

    static func authenticate(fileDescriptor fd: Int32) -> AppAgentPeerAuthDecision {
        var peerUID = uid_t()
        var peerGID = gid_t()
        guard getpeereid(fd, &peerUID, &peerGID) == 0 else {
            return .reject(reason: "getpeereid failed: \(String(cString: strerror(errno)))")
        }

        let team = agentTeamIdentifier
        // Only evaluate the (relatively costly) signature path when the agent is signed; an
        // unsigned agent falls back to same-uid trust regardless of the peer's signature.
        if let team, !team.isEmpty {
            let peer = resolvePeerSignature(fd: fd, requiredTeamIdentifier: team)
            return AppAgentPeerAuthPolicy.decide(
                peerUID: peerUID,
                selfUID: getuid(),
                agentTeamIdentifier: team,
                peerSatisfiesAgentRequirement: peer.satisfiesRequirement,
                peerTeamIdentifier: peer.teamIdentifier
            )
        }

        return AppAgentPeerAuthPolicy.decide(
            peerUID: peerUID,
            selfUID: getuid(),
            agentTeamIdentifier: team,
            peerSatisfiesAgentRequirement: false,
            peerTeamIdentifier: nil
        )
    }

    // Resolve the connecting peer's SecCode from its audit token, then check it against a
    // requirement pinning Apple's anchor and the agent's Team Identifier.
    private static func resolvePeerSignature(
        fd: Int32,
        requiredTeamIdentifier team: String
    ) -> (satisfiesRequirement: Bool, teamIdentifier: String?) {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        let readResult = withUnsafeMutablePointer(to: &token) { pointer in
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, pointer, &length)
        }
        guard readResult == 0, length == socklen_t(MemoryLayout<audit_token_t>.size) else {
            return (false, nil)
        }

        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes: [CFString: Any] = [kSecGuestAttributeAudit: tokenData]
        var peerCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &peerCode) == errSecSuccess,
              let code = peerCode
        else {
            return (false, nil)
        }

        // Requirement: Apple-issued anchor AND the leaf certificate's Team Identifier (subject.OU)
        // equals the agent's — the standard cross-binary "same developer" pin (a self-signed or
        // differently-signed binary cannot satisfy it). When the agent runs from a bundle we also
        // pin the bundle identifier, narrowing "any binary from this team" to this specific app.
        //
        // NOTE (documented in docs/SECURITY.md): this authenticates the connecting PROCESS, not who
        // invoked it. A same-uid actor can still exec the legitimate signed CLI as a relay, so this
        // is defense-in-depth, not a same-uid confused-deputy fix.
        var requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        if let bundleID = Self.agentBundleIdentifier, !bundleID.isEmpty {
            requirementString = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        var requirement: SecRequirement?
        let satisfies: Bool
        if SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess {
            satisfies = SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        } else {
            satisfies = false
        }

        return (satisfies, teamIdentifier(of: code))
    }

    private static func teamIdentifier(of code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var informationCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &informationCF) == errSecSuccess,
              let information = informationCF as? [String: Any]
        else {
            return nil
        }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func resolveSelfTeamIdentifier() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else {
            return nil
        }
        return teamIdentifier(of: selfCode)
    }
}

// Process-global one-shot stderr notice when the agent runs unsigned and falls back to
// same-uid-only peer trust, so operators know strong peer authentication is inactive.
final class UnsignedPeerFallbackNotice: @unchecked Sendable {
    static let shared = UnsignedPeerFallbackNotice()
    private let lock = NSLock()
    private var emitted = false

    func emitIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !emitted else { return }
        emitted = true
        fputs("[open-computer-use] app-agent is unsigned/ad-hoc — socket peer authentication falls back to same-uid trust only (code-signature pinning inactive). Ship a signed build for full peer authentication.\n", stderr)
    }
}
