import AppKit
import XCTest
@testable import OpenComputerUseKit

/// The local overlay showcase exists so "the ring is not visible" can be told
/// apart from "the ring was never requested". These tests pin its CLI surface,
/// its single-screen geometry and its debug logging gate.
final class DebugHighlightTests: XCTestCase {
    // MARK: - CLI surface

    func testDebugHighlightDefaultsToShowcaseDefaults() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-highlight"]),
            .debugHighlight(seconds: VisualCursorDebugShowcase.defaultSeconds, display: nil)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["--debug-highlight"]),
            .debugHighlight(seconds: VisualCursorDebugShowcase.defaultSeconds, display: nil)
        )
    }

    func testDebugHighlightParsesSecondsAndDisplay() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--seconds", "3.5"]),
            .debugHighlight(seconds: 3.5, display: nil)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--display", "2", "--seconds", "2"]),
            .debugHighlight(seconds: 2, display: 2)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--help"]),
            .help(command: "debug-highlight")
        )
    }

    func testDebugHighlightRejectsBadOptions() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--seconds", "abc"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--seconds", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--display", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--display", "abc"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-highlight", "--nope"]))
    }

    func testDebugHighlightNeverGoesThroughTheAppAgentProxy() {
        // It only paints local overlays, so it must not need the app bundle's
        // automation identity - and must never drive another app.
        XCTAssertFalse(
            shouldUseMacOSAppAgentProxy(
                command: .debugHighlight(seconds: 5, display: nil),
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            )
        )
    }

    // MARK: - Single-screen geometry

    func testShowcaseRingsOneScreenCentreAndNeverEnumeratesScreens() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let localFrame = debugHighlightTargetLocalFrame(screenStateFrame: screen)

        XCTAssertEqual(localFrame, CGRect(x: 934, y: 548, width: 180, height: 56))
        // The capture rect stays inside the same screen.
        XCTAssertEqual(
            debugHighlightCaptureRect(screenStateFrame: screen, localFrame: localFrame),
            CGRect(x: 874, y: 488, width: 300, height: 176)
        )
        XCTAssertTrue(screen.contains(CGRect(origin: localFrame.origin, size: localFrame.size)))
    }

    func testShowcaseFollowsTheScreenOriginForSecondaryDisplays() {
        let secondary = CGRect(x: 2048, y: 0, width: 1512, height: 982)
        let localFrame = debugHighlightTargetLocalFrame(screenStateFrame: secondary)
        let capture = debugHighlightCaptureRect(screenStateFrame: secondary, localFrame: localFrame)

        XCTAssertEqual(localFrame.origin, CGPoint(x: 666, y: 463))
        XCTAssertEqual(capture.origin, CGPoint(x: 2654, y: 403))
        XCTAssertTrue(secondary.contains(capture))
    }

    // MARK: - Debug logging gate

    func testHighlightDebugLoggingIsOptIn() {
        XCTAssertFalse(targetHighlightDebugEnabled(environment: [:]))
        XCTAssertFalse(targetHighlightDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT": "0"]))
        XCTAssertTrue(targetHighlightDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT": "1"]))
        XCTAssertTrue(targetHighlightDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT": " YES "]))
    }

    // MARK: - Debug-only hold does not move the audited lifetime

    func testDisplayDurationOverrideIsOffByDefault() {
        let audited = TargetHighlightLifetimeController.RingTarget(
            globalRect: .zero,
            level: 0,
            windowID: nil,
            element: nil,
            isPopup: false,
            expectedScreenFrame: nil
        )
        XCTAssertEqual(audited.displayDuration, 0.45, accuracy: 0.0001)

        var held = audited
        held.displayDurationOverride = 5
        XCTAssertEqual(held.displayDuration, 5, accuracy: 0.0001)
    }

    func testShowcaseHoldIsCapped() {
        XCTAssertEqual(VisualCursorDebugShowcase.maximumSeconds, 60)
        XCTAssertLessThanOrEqual(VisualCursorDebugShowcase.defaultSeconds, 10)
    }
}
