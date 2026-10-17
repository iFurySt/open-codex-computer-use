import Darwin
import Foundation
import Security

/// Validation is tied to the OS build and each installed executable's signed
/// code hash. Replacing a component or updating macOS invalidates the evidence.
public enum LockedUseComponentValidation {
    public struct Evidence: Codable, Equatable, Sendable {
        public let osBuild: String
        public let brokerHash: String
        public let guardianHash: String
        public let pluginHash: String
    }
    public static func bootSessionID() throws -> String {
        let value = try kernelString("kern.bootsessionuuid")
        guard UUID(uuidString: value) != nil else { throw LockedUseClientApprovals.Failure.unapproved }
        return value
    }
    private static func kernelString(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1, size <= 128 else { throw LockedUseClientApprovals.Failure.unapproved }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { throw LockedUseClientApprovals.Failure.unapproved }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    public static func current(team: String) throws -> Evidence {
        guard team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { throw LockedUseClientApprovals.Failure.unapproved }
        let osBuild = try kernelString("kern.osversion")
        let base = "/Library/Application Support/OpenComputerUse/LockedUse/"
        return try .init(osBuild: osBuild,
            brokerHash: hash(path: base + "OCULockService", id: "dev.opencomputeruse.locked-use.broker", team: team),
            guardianHash: hash(path: base + "OCU Guardian.app", id: "dev.opencomputeruse.locked-use.guardian.dev", team: team),
            pluginHash: hash(path: "/Library/Security/SecurityAgentPlugins/OCULockAuth.bundle", id: "dev.opencomputeruse.locked-use.authorization", team: team))
    }
    private static func hash(path: String, id: String, team: String) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { throw LockedUseClientApprovals.Failure.unapproved }
        var requirement: SecRequirement?
        let text = "identifier \"\(id)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess else { throw LockedUseClientApprovals.Failure.unapproved }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any], let hash = info[kSecCodeInfoUnique as String] as? Data else { throw LockedUseClientApprovals.Failure.unapproved }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
