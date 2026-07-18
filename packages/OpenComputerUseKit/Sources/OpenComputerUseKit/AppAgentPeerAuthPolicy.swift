import Foundation

// Decision for whether a process connecting to the app-agent Unix socket may drive the agent.
//
// The app-agent is a persistent, Accessibility-authorized (TCC) process listening on a
// same-uid Unix socket. Same-uid file permissions alone are not sufficient authentication:
// ANY code running as the user could otherwise connect and reuse the agent's TCC grant as a
// confused deputy (see docs/SECURITY.md). Peer authentication closes that gap by requiring the
// connecting process to be code-signed by the same developer (Team Identifier) as the agent.
public enum AppAgentPeerAuthDecision: Equatable, Sendable {
    // Same uid + Apple-anchored signature carrying the agent's Team Identifier.
    case allow
    // Agent itself is unsigned / ad-hoc signed (e.g. a local `swift build` dev binary), so
    // code-signature validation is not meaningful. Fall back to same-uid trust only.
    case allowUnsignedFallback
    // Connection refused; `reason` is a diagnostic string (never shown to the peer).
    case reject(reason: String)
}

public enum AppAgentPeerAuthPolicy {
    // Pure decision from facts the IO layer (SocketPeerAuthenticator) gathers via
    // getpeereid + LOCAL_PEERTOKEN + Security.framework. Kept pure so it is unit-testable
    // without a live socket peer.
    //
    // - peerUID / selfUID: effective uids of the connecting process and the agent.
    // - agentTeamIdentifier: the agent's own Team Identifier, or nil when the agent is
    //   unsigned/ad-hoc (dev build).
    // - peerSatisfiesAgentRequirement: whether the peer satisfies the code requirement
    //   "Apple-anchored AND leaf Team Identifier == agentTeamIdentifier". Meaningful only
    //   when agentTeamIdentifier is non-nil.
    // - peerTeamIdentifier: the peer's Team Identifier if resolvable, for diagnostics only.
    public static func decide(
        peerUID: uid_t,
        selfUID: uid_t,
        agentTeamIdentifier: String?,
        peerSatisfiesAgentRequirement: Bool,
        peerTeamIdentifier: String?
    ) -> AppAgentPeerAuthDecision {
        guard peerUID == selfUID else {
            return .reject(reason: "peer uid \(peerUID) != agent uid \(selfUID)")
        }

        guard let agentTeam = agentTeamIdentifier, !agentTeam.isEmpty else {
            // Unsigned/ad-hoc agent: nothing to validate a peer signature against. Same-uid
            // (enforced by socket 0600 perms + the check above) is the only available control.
            return .allowUnsignedFallback
        }

        guard peerSatisfiesAgentRequirement else {
            let seen = peerTeamIdentifier ?? "nil"
            return .reject(reason: "peer failed code requirement for team \(agentTeam) (peer team: \(seen))")
        }

        return .allow
    }
}
