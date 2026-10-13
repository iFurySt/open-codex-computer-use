import Foundation
@testable import OpenComputerUseKit
import XCTest

final class LockedUseAuthorizationRulesTests: XCTestCase {
    private func data(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testDefaultFallbackAndUnrelatedFieldsSurviveRoundTrip() throws {
        let before = try data(["class": "rule", "rule": ["use-login-window-ui"], "version": 1,
            "comment": "existing comment", "shared": false, "created": 10.5, "modified": 20.5])
        let plan = try LockedUseAuthorizationRules.planInstallation(current: before)
        let installed = try object(plan.installed)
        XCTAssertEqual(installed["rule"] as? [String], [LockedUseAuthorizationRules.remoteRight, "use-login-window-ui"])
        XCTAssertEqual(installed["comment"] as? String, "existing comment")
        XCTAssertEqual(installed["shared"] as? Bool, false)
        XCTAssertTrue(try LockedUseAuthorizationRules.installationStillApplicable(current: before, plan: plan))
        XCTAssertTrue(try LockedUseAuthorizationRules.installationObserved(current: plan.installed, plan: plan))
        let restored = try object(LockedUseAuthorizationRules.planUninstallation(current: plan.installed, plan: plan))
        XCTAssertEqual(restored["rule"] as? [String], ["use-login-window-ui"])
        XCTAssertNil(restored["k-of-n"])
    }

    func testPlatformSSOAndExistingOrderArePreserved() throws {
        let before = try data(["class": "rule", "k-of-n": 1, "rule": ["psso-screensaver", "enterprise-fallback"]])
        let plan = try LockedUseAuthorizationRules.planInstallation(current: before)
        XCTAssertEqual(try object(plan.installed)["rule"] as? [String],
            [LockedUseAuthorizationRules.remoteRight, "psso-screensaver", "enterprise-fallback"])
    }

    func testExternalChangesRefuseRestoreAndInstallation() throws {
        let before = try data(["class": "rule", "rule": ["use-login-window-ui"]])
        let plan = try LockedUseAuthorizationRules.planInstallation(current: before)
        var changed = try object(plan.installed)
        changed["rule"] = [LockedUseAuthorizationRules.remoteRight, "psso-screensaver"]
        XCTAssertThrowsError(try LockedUseAuthorizationRules.planUninstallation(current: data(changed), plan: plan))
        XCTAssertFalse(try LockedUseAuthorizationRules.installationStillApplicable(current: data(changed), plan: plan))
    }

    func testMalformedOrDifferentThresholdNeverWeakensPolicy() throws {
        let inputs: [[String: Any]] = [
            ["class": "user", "rule": ["use-login-window-ui"]],
            ["class": "rule", "rule": ["a", "b"], "k-of-n": 2],
            ["class": "rule", "rule": ["a"], "k-of-n": true],
            ["class": "rule", "rule": []],
            ["class": "rule", "rule": ["a", "a"]],
            ["class": "rule", "rule": [""]],
            ["class": "rule", "rule": ["a"], "k-of-n": "1"],
        ]
        for input in inputs { XCTAssertThrowsError(try LockedUseAuthorizationRules.planInstallation(current: data(input))) }
        XCTAssertThrowsError(try LockedUseAuthorizationRules.planInstallation(current: Data()))
    }

    func testOwnReferenceIsNeverDuplicatedOrSilentlyClaimed() throws {
        let current = try data(["class": "rule", "rule": [LockedUseAuthorizationRules.remoteRight, "use-login-window-ui"]])
        XCTAssertThrowsError(try LockedUseAuthorizationRules.planInstallation(current: current))
    }

    func testTamperedPersistedPlanIsRejected() throws {
        let before = try data(["class": "rule", "rule": ["use-login-window-ui"]])
        let plan = try LockedUseAuthorizationRules.planInstallation(current: before)
        let encoded = try JSONEncoder().encode(plan)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["installed"] = try data(["class": "rule", "rule": ["allow"]]).base64EncodedString()
        let changed = try JSONDecoder().decode(LockedUseAuthorizationRules.Plan.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try LockedUseAuthorizationRules.planUninstallation(current: plan.installed, plan: changed))
    }

    func testAuthDatabaseTimestampsDoNotInvalidateSemanticComparison() throws {
        let before = try data(["class": "rule", "rule": ["use-login-window-ui"]])
        let plan = try LockedUseAuthorizationRules.planInstallation(current: before)
        var observed = try object(plan.installed)
        observed["created"] = 10.5
        observed["modified"] = 999.5
        XCTAssertTrue(try LockedUseAuthorizationRules.installationObserved(current: data(observed), plan: plan))
        XCTAssertNoThrow(try LockedUseAuthorizationRules.planUninstallation(current: data(observed), plan: plan))
    }
}
