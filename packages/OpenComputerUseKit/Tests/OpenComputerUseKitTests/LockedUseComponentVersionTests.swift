import XCTest
@testable import OpenComputerUseKit

final class LockedUseComponentVersionTests: XCTestCase {
    func testOldDevelopmentInstallationSuggestsExplicitReinstall() {
        let advice = LockedUseDiagnostics.versionAdvice(installed: "0.0.1", bundled: "1.1.0")
        XCTAssertTrue(advice?.contains("ocu locked-use disable") == true)
        XCTAssertTrue(advice?.contains("ocu locked-use enable") == true)
    }
    func testMatchingOrUnknownVersionsDoNotSuggestReplacingComponents() {
        XCTAssertNil(LockedUseDiagnostics.versionAdvice(installed: "1.1.0", bundled: "1.1.0"))
        XCTAssertNil(LockedUseDiagnostics.versionAdvice(installed: nil, bundled: "1.1.0"))
        XCTAssertNil(LockedUseDiagnostics.versionAdvice(installed: "0.0.1", bundled: nil))
    }
}
