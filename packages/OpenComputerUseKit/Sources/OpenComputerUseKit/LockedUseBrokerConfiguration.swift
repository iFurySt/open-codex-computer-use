import Foundation

/// Administrator-owned configuration. Enabled and validation evidence are
/// independent: installation/enrollment alone cannot validate session unlock.
public struct LockedUseBrokerConfiguration: Codable, Sendable {
    public let schemaVersion: Int
    public let enabled: Bool
    public let validatedOSBuild: String?
    public let validatedBrokerHash: String?
    public let validatedGuardianHash: String?
    public let validatedPluginHash: String?

    public init(enabled: Bool, validatedOSBuild: String? = nil,
                validatedBrokerHash: String? = nil, validatedGuardianHash: String? = nil,
                validatedPluginHash: String? = nil) {
        schemaVersion = 1; self.enabled = enabled; self.validatedOSBuild = validatedOSBuild
        self.validatedBrokerHash = validatedBrokerHash; self.validatedGuardianHash = validatedGuardianHash
        self.validatedPluginHash = validatedPluginHash
    }

    public static func loadInstalled() throws -> Self {
        let data = try LockedUseSecureStore.read(components: ["Library", "Application Support", "OpenComputerUse", "LockedUse", "configuration.json"])
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw LockedUseClientApprovals.Failure.invalidRecord }
        return value
    }

    public func matchesValidation(osBuild: String, brokerHash: String, guardianHash: String, pluginHash: String) -> Bool {
        enabled && !osBuild.isEmpty && !brokerHash.isEmpty && !guardianHash.isEmpty && !pluginHash.isEmpty
            && validatedOSBuild == osBuild && validatedBrokerHash == brokerHash
            && validatedGuardianHash == guardianHash && validatedPluginHash == pluginHash
    }
}
