import AppKit
import CryptoKit
import Foundation
import OpenComputerUseKit
import Security
import os

/// Fixed real GUI target; no host-supplied app, index, image or "passed" flag.
enum LockedUseNativeValidation {
    static func run(probe: LockedUseKeychainProbe) throws {
        let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "NativeValidation")
        logger.notice("fixtureValidationStarted")
        let identifier = "dev.opencomputeruse.locked-use.fixture.dev"
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard apps.count == 1, let path = apps.first?.bundleURL,
              let team = try LockedUseSigningIdentity.current().teamIdentifier else {
            throw ComputerUseError.stateUnavailable("Launch the signed Locked Use Native Fixture first.")
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let expression = "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(path as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw ComputerUseError.stateUnavailable("Native validation fixture signer is not approved.")
        }
        let service = ComputerUseService()
        // This fixed assertion parses a complete tree. Normal agent output may
        // be an incremental AX diff after the action's own read-back.
        let before = try service.getAppState(app: identifier, snapshotMode: .full)
        guard let text = before.primaryText else { throw LockedUseKeychainProbe.Failure.verification }
        let buttons = text.split(separator: "\n").filter {
            $0.contains("Increment Counter") && $0.contains("locked-use-validation-increment")
        }
        guard buttons.count == 1, let index = buttons[0].split(whereSeparator: { $0.isWhitespace }).first,
              Int(index) != nil else { throw LockedUseKeychainProbe.Failure.verification }
        let counter = try counterValue(text)
        logger.notice("fixtureBeforeCaptured counter=\(counter, privacy: .public)")
        _ = try service.click(app: identifier, elementIndex: String(index), x: nil, y: nil,
                              clickCount: 1, mouseButton: "left", clickMethod: .accessibility)
        let after = try service.getAppState(app: identifier, snapshotMode: .full)
        let afterCounter = try counterValue(after.primaryText ?? "")
        let imageChanged = try imageHash(before) != imageHash(after)
        logger.notice("fixtureReadBack counter=\(afterCounter, privacy: .public) imageChanged=\(imageChanged, privacy: .public)")
        guard afterCounter == counter + 1, imageChanged else { throw LockedUseKeychainProbe.Failure.verification }
        logger.notice("fixtureChanged counterIncremented=true imageChanged=true")
        try probe.verify()
        logger.notice("isolatedKeychainVerified dataProtectionIncluded=\(probe.includesDataProtection, privacy: .public)")
    }

    private static func counterValue(_ text: String) throws -> Int {
        let regex = try NSRegularExpression(pattern: #"Counter: ([0-9]+)"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: text),
              let value = Int(text[range]), value < Int.max else { throw LockedUseKeychainProbe.Failure.verification }
        return value
    }
    private static func imageHash(_ result: ToolCallResult) throws -> Data {
        guard let content = result.asDictionary["content"] as? [[String: Any]],
              let base64 = content.first(where: { $0["type"] as? String == "image" })?["data"] as? String,
              let image = Data(base64Encoded: base64), !image.isEmpty else {
            throw ComputerUseError.stateUnavailable("Real ScreenCaptureKit validation image missing.")
        }
        return Data(SHA256.hash(data: image))
    }
}
