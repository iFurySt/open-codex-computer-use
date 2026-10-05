import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Security

public struct LockedUseSession: Equatable, Codable, Sendable {
    public enum State: String, Codable, Sendable { case locked, unlocked, unavailable }
    public let state: State
    public let userID: UInt32?
    public let auditSessionID: UInt32?

    public init(state: State, userID: UInt32?, auditSessionID: UInt32?) {
        self.state = state
        self.userID = userID
        self.auditSessionID = auditSessionID
    }

    public static func current() -> LockedUseSession {
        var sessionID = SecuritySessionId()
        var attributes = SessionAttributeBits()
        guard SessionGetInfo(callerSecuritySession, &sessionID, &attributes) == errSecSuccess,
              attributes.contains(.sessionHasGraphicAccess) else {
            return .init(state: .unavailable, userID: nil, auditSessionID: nil)
        }
        return from(dictionary: CGSessionCopyCurrentDictionary() as? [String: Any], effectiveUserID: geteuid(), securitySessionID: sessionID)
    }

    static func from(dictionary: [String: Any]?, effectiveUserID: UInt32, securitySessionID: UInt32?) -> LockedUseSession {
        guard let dictionary,
              boolean(dictionary[kCGSessionOnConsoleKey as String]) == true,
              boolean(dictionary[kCGSessionLoginDoneKey as String]) == true,
              let uid = unsignedNumber(dictionary[kCGSessionUserIDKey as String]),
              let auditID = securitySessionID, auditID != 0,
              uid == effectiveUserID, uid != 0 else {
            return .init(state: .unavailable, userID: nil, auditSessionID: nil)
        }
        if let observedAuditID = dictionary["kCGSSessionAuditIDKey"], unsignedNumber(observedAuditID) != auditID {
            return .init(state: .unavailable, userID: uid, auditSessionID: nil)
        }
        // SessionGetInfo provides the stable audit-session identity. The documented
        // kCGSessionConsoleSetKey is absent on some current systems; do not invent
        // a default console ID or reject an otherwise completed GUI login.
        // This WindowServer key is undocumented. Its absence in a completed GUI
        // login is the usual unlocked representation; malformed values fail closed.
        let locked: Bool
        if let value = dictionary["CGSSessionScreenIsLocked"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                return .init(state: .unavailable, userID: uid, auditSessionID: auditID)
            }
            locked = number.boolValue
        } else {
            locked = false
        }
        return .init(state: locked ? .locked : .unlocked, userID: uid, auditSessionID: auditID)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func unsignedNumber(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(UInt32.max), value.rounded(.towardZero) == value else { return nil }
        return UInt32(value)
    }
}

public struct LockedUseDiagnostics: Codable, Sendable {
    public let schemaVersion: Int
    public let stage: String
    public let enabled: Bool
    public let available: Bool
    public let session: LockedUseSession
    public let accessibility: Bool
    public let screenRecording: Bool
    public let inputMonitoring: Bool
    public let pluginInstalled: Bool
    public let brokerInstalled: Bool
    public let otherAuthorizationPlugins: [String]
    public let blockers: [String]

    /// Never enables the experimental backend from environment variables, files
    /// written by the user, or the presence of another vendor's authorization plugin.
    public static func current() -> LockedUseDiagnostics {
        let pluginsPath = "/Library/Security/SecurityAgentPlugins"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: pluginsPath)) ?? []
        let ownPlugin = "OpenComputerUseAuthorizationPlugin.bundle"
        let others = entries.filter { $0.hasSuffix(".bundle") && $0 != ownPlugin }.sorted()
        return .init(
            schemaVersion: 1, stage: "experimental-preflight", enabled: false, available: false,
            session: .current(), accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess(), inputMonitoring: CGPreflightListenEventAccess(),
            pluginInstalled: entries.contains(ownPlugin),
            brokerInstalled: FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/OpenComputerUseLockedUseBroker"),
            otherAuthorizationPlugins: others,
            blockers: [
                "The loginwindow unlock backend has not passed live validation; automatic unlock is unavailable.",
                "The independent display/input guardian and privileged Broker are not implemented.",
                "The production loginwindow flow and Keychain preservation require live validation; isolated plugin loading does not validate session unlocking."
            ]
        )
    }

    public var summary: String {
        "Locked Use: stage=\(stage), enabled=\(enabled), available=\(available), session=\(session.state.rawValue)\n"
            + "Input Monitoring: \(inputMonitoring ? "granted" : "missing")\n"
            + "Other authorization plugins: \(otherAuthorizationPlugins.isEmpty ? "none detected" : otherAuthorizationPlugins.joined(separator: ", "))\n"
            + blockers.joined(separator: "\n")
    }

    public func jsonText() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Used by fresh snapshots and cached real-app snapshots. Fixture state is not a
/// desktop and remains usable in headless CI. Inventory never triggers unlocking.
func requireUsableComputerUseSession(_ session: LockedUseSession = .current()) throws {
    switch session.state {
    case .unlocked:
        return
    case .locked:
        throw ComputerUseError.stateUnavailable("The Mac is locked. Locked Use is not available until its loginwindow backend and independent guardian pass live validation. Unlock the Mac manually; run `ocu locked-use status --json` for diagnostics.")
    case .unavailable:
        throw ComputerUseError.stateUnavailable("No completed GUI session for the current console user is available. Computer Use cannot operate a login, switched-user, or unknown session.")
    }
}
