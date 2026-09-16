import AppKit
import XCTest
@testable import OpenComputerUseKit

/// The local overlay showcase exists so "the cursor is not visible" can be told
/// apart from "the cursor was never requested". These tests pin its CLI surface,
/// its single-screen geometry and its hold cap.
final class DebugCursorTests: XCTestCase {
    // MARK: - CLI surface

    func testDebugCursorDefaultsToShowcaseDefaults() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-cursor"]),
            .debugCursor(seconds: VisualCursorDebugShowcase.defaultSeconds, display: nil)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["--debug-cursor"]),
            .debugCursor(seconds: VisualCursorDebugShowcase.defaultSeconds, display: nil)
        )
    }

    func testDebugCursorParsesSecondsAndDisplay() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--seconds", "3.5"]),
            .debugCursor(seconds: 3.5, display: nil)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--display", "2", "--seconds", "2"]),
            .debugCursor(seconds: 2, display: 2)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--help"]),
            .help(command: "debug-cursor")
        )
    }

    func testDebugCursorRejectsBadOptions() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--seconds", "abc"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--seconds", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--display", "0"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--display", "abc"]))
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["debug-cursor", "--nope"]))
    }

    func testDebugCursorNeverGoesThroughTheAppAgentProxy() {
        // It only paints the local cursor, so it must not need the app bundle's
        // automation identity - and must never drive another app.
        XCTAssertFalse(
            shouldUseMacOSAppAgentProxy(
                command: .debugCursor(seconds: 5, display: nil),
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            )
        )
    }

    // MARK: - Single-screen geometry

    func testShowcaseUsesOneScreenCentreAndNeverEnumeratesScreens() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let localFrame = debugCursorTargetLocalFrame(screenStateFrame: screen)

        XCTAssertEqual(localFrame, CGRect(x: 934, y: 548, width: 180, height: 56))
        // The capture rect stays inside the same screen.
        XCTAssertEqual(
            debugCursorCaptureRect(screenStateFrame: screen, localFrame: localFrame),
            CGRect(x: 874, y: 488, width: 300, height: 176)
        )
        XCTAssertTrue(screen.contains(CGRect(origin: localFrame.origin, size: localFrame.size)))
    }

    func testShowcaseFollowsTheScreenOriginForSecondaryDisplays() {
        let secondary = CGRect(x: 2048, y: 0, width: 1512, height: 982)
        let localFrame = debugCursorTargetLocalFrame(screenStateFrame: secondary)
        let capture = debugCursorCaptureRect(screenStateFrame: secondary, localFrame: localFrame)

        XCTAssertEqual(localFrame.origin, CGPoint(x: 666, y: 463))
        XCTAssertEqual(capture.origin, CGPoint(x: 2654, y: 403))
        XCTAssertTrue(secondary.contains(capture))
    }

    func testShowcaseHoldIsCapped() {
        XCTAssertEqual(VisualCursorDebugShowcase.maximumSeconds, 60)
        XCTAssertLessThanOrEqual(VisualCursorDebugShowcase.defaultSeconds, 10)
    }
}
