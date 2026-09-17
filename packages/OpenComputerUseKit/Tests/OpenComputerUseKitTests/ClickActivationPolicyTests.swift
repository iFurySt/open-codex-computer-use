import XCTest
@testable import OpenComputerUseKit

/// `click` must not raise, main or focus anything unless the caller explicitly
/// opted into window recovery. Cover for the residual "OCU still steals focus"
/// report, whose remaining source was the activation-only AX fallback.
final class ClickActivationPolicyTests: XCTestCase {
    func testActivationFallbackIsOffByDefault() {
        XCTAssertFalse(activationOnlyClickFallbackAllowed(allowWindowRecovery: nil, environment: [:]))
        XCTAssertFalse(activationOnlyClickFallbackAllowed(allowWindowRecovery: false, environment: [:]))
        XCTAssertFalse(
            activationOnlyClickFallbackAllowed(
                allowWindowRecovery: nil,
                environment: ["OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY": "0"]
            )
        )
        XCTAssertEqual(defaultSnapshotRecoveryPolicy, .readOnly)
    }

    func testActivationFallbackRequiresAnExplicitOptIn() {
        XCTAssertTrue(activationOnlyClickFallbackAllowed(allowWindowRecovery: true, environment: [:]))
        XCTAssertTrue(
            activationOnlyClickFallbackAllowed(
                allowWindowRecovery: nil,
                environment: ["OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY": "1"]
            )
        )
        // An explicit per-call false wins over the process-level opt-in.
        XCTAssertFalse(
            activationOnlyClickFallbackAllowed(
                allowWindowRecovery: false,
                environment: ["OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY": "1"]
            )
        )
    }

    func testActivationFallbackOnlyEverAppliesToWindowRoleElements() {
        XCTAssertTrue(canUseActivationOnlyClickFallback(role: "AXWindow"))
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: nil))
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: "AXButton"))
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: "AXMenuItem"))
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: "AXStaticText"))
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: "AXRow"))
    }

    func testActivationFallbackSharesTheWindowRecoverySwitch() {
        for rawValue in ["1", "true", "yes", "on", " TRUE "] {
            XCTAssertTrue(
                activationOnlyClickFallbackAllowed(
                    allowWindowRecovery: nil,
                    environment: ["OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY": rawValue]
                ),
                rawValue
            )
        }

        for rawValue in ["0", "false", "no", "off", "", "maybe"] {
            XCTAssertFalse(
                activationOnlyClickFallbackAllowed(
                    allowWindowRecovery: nil,
                    environment: ["OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY": rawValue]
                ),
                rawValue
            )
        }
    }
}
