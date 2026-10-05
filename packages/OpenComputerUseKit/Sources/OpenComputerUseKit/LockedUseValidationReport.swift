import Foundation

/// Written only by the authenticated root Broker, after the signed native
/// agent has completed its fixed AX/SCK/Keychain fixture validation. Manual
/// physical-screen, input and fault checks still require administrator review.
public struct LockedUseValidationReport: Codable, Sendable {
    public let schemaVersion: Int
    public let leaseID: UUID
    public let evidence: LockedUseComponentValidation.Evidence
    public let ownerToken: Data
    public let guiAndKeychainPassed: Bool
    public var lockedAndReleased: Bool
    public var afterManualUnlockPassed: Bool

    public init(leaseID: UUID, evidence: LockedUseComponentValidation.Evidence, ownerToken: Data) {
        schemaVersion = 1; self.leaseID = leaseID; self.evidence = evidence; self.ownerToken = ownerToken
        guiAndKeychainPassed = true; lockedAndReleased = false; afterManualUnlockPassed = false
    }
    public func canPromote(current: LockedUseComponentValidation.Evidence) -> Bool {
        schemaVersion == 1 && ownerToken.count == 32 && evidence == current
            && guiAndKeychainPassed && lockedAndReleased && afterManualUnlockPassed
    }
    public static func loadInstalled() throws -> Self {
        let bytes = try LockedUseSecureStore.read(components: ["Library", "Application Support", "OpenComputerUse", "LockedUse", "validation-report.json"])
        return try JSONDecoder().decode(Self.self, from: bytes)
    }
}
