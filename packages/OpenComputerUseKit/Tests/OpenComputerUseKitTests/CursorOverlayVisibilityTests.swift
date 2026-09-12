import AppKit
import XCTest
@testable import OpenComputerUseKit

/// The cursor has to survive everything the window server does to window
/// ordering. Regression cover for the user report "after a native menu, a focus
/// switch, or the target window closing, the whole arrow is gone".
final class CursorOverlayVisibilityTests: XCTestCase {
    // MARK: - Fake window server

    @MainActor
    private final class FakeCursorPanelHost: CursorOverlayPanelHosting {
        private(set) var isVisible = false
        var alphaValue: CGFloat = 1
        private(set) var frameOrigin: CGPoint?
        private(set) var levels: [NSWindow.Level] = []
        private(set) var orderFrontCount = 0
        private(set) var orderAboveCount = 0
        private(set) var orderOutCount = 0
        private(set) var appliedRenderStateCount = 0

        var windowNumber: Int { 4_242 }
        var cursorRotation: CGFloat { 0 }

        func setLevel(_ level: NSWindow.Level) { levels.append(level) }
        func setFrameOrigin(_ origin: CGPoint) { frameOrigin = origin }
        func orderFront() {
            isVisible = true
            orderFrontCount += 1
        }

        func orderAbove(windowID: CGWindowID) {
            isVisible = true
            orderAboveCount += 1
        }

        func orderOut() {
            isVisible = false
            orderOutCount += 1
        }

        func apply(renderState: CursorVisualRenderState, clickProgress: CGFloat) {
            appliedRenderStateCount += 1
        }
    }

    @MainActor
    private func installFakeEnvironment(
        host: FakeCursorPanelHost,
        isWindowPresent: @escaping (CGWindowID) -> Bool,
        isVisualCursorEnabled: Bool = true,
        canPresentOverlay: Bool = true
    ) {
        SoftwareCursorOverlay.installEnvironmentForTesting(
            CursorOverlayEnvironment(
                isVisualCursorEnabled: isVisualCursorEnabled,
                canPresentOverlay: canPresentOverlay,
                installsActivationObserver: false,
                isWindowPresent: isWindowPresent,
                makePanelHost: { host }
            )
        )
    }

    // MARK: - Level / ordering policy

    func testNormalTargetWindowKeepsTheFloatingOverlayLevel() {
        let plan = cursorPanelOrdering(targetWindow: CursorTargetWindow(windowID: 42, layer: 0))

        XCTAssertEqual(plan.level, .floating)
        XCTAssertGreaterThan(plan.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertNil(plan.anchorWindow, "a normal window must not own the cursor's ordering")
    }

    func testMissingTargetWindowStillKeepsTheOverlayLevel() {
        let plan = cursorPanelOrdering(targetWindow: nil)

        XCTAssertEqual(plan.level, .floating)
        XCTAssertNil(plan.anchorWindow)
    }

    func testFloatingAndMenuTargetsAreAnchoredAboveTheOverlayLevel() {
        let popover = CursorTargetWindow(windowID: 7, layer: 8)
        let menu = CursorTargetWindow(windowID: 9, layer: 101)

        XCTAssertEqual(cursorPanelOrdering(targetWindow: popover).level, NSWindow.Level(rawValue: 8))
        XCTAssertEqual(cursorPanelOrdering(targetWindow: popover).anchorWindow, popover)
        XCTAssertEqual(cursorPanelOrdering(targetWindow: menu).level, NSWindow.Level(rawValue: 101))
        XCTAssertEqual(cursorPanelOrdering(targetWindow: menu).anchorWindow, menu)
    }

    // MARK: - Visibility contract

    @MainActor
    func testCursorStaysVisibleAndStillWhenTheTargetWindowGoesAway() {
        let host = FakeCursorPanelHost()
        var targetIsPresent = true
        installFakeEnvironment(host: host, isWindowPresent: { _ in targetIsPresent })
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        SoftwareCursorOverlay.repositionCursor(
            to: CGPoint(x: 640, y: 400),
            in: CursorTargetWindow(windowID: 42, layer: 0)
        )

        XCTAssertTrue(host.isVisible)
        XCTAssertEqual(host.levels, [.floating])
        let restingOrigin = host.frameOrigin
        XCTAssertNotNil(restingOrigin)
        let orderFrontsAfterShow = host.orderFrontCount

        // A native menu opens, another app is activated, or the target window
        // is hidden by the system: the window server re-stacks every window at
        // the cursor's level and the target window may stop existing entirely.
        targetIsPresent = false
        SoftwareCursorOverlay.workspaceDidActivateApplication()

        XCTAssertTrue(host.isVisible, "a system-level restack must never hide the cursor")
        XCTAssertEqual(host.frameOrigin, restingOrigin, "freezing is fine, vanishing is not")
        XCTAssertEqual(host.orderOutCount, 0)
        XCTAssertEqual(host.levels, [.floating], "the level must not fall back to .normal")
        XCTAssertEqual(host.orderFrontCount, orderFrontsAfterShow + 1)
    }

    @MainActor
    func testCursorStaysVisibleWhenAnotherApplicationTakesFocus() {
        let host = FakeCursorPanelHost()
        installFakeEnvironment(host: host, isWindowPresent: { _ in true })
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        SoftwareCursorOverlay.repositionCursor(
            to: CGPoint(x: 320, y: 240),
            in: CursorTargetWindow(windowID: 42, layer: 0)
        )
        let restingOrigin = host.frameOrigin
        let orderFrontsAfterShow = host.orderFrontCount

        SoftwareCursorOverlay.workspaceDidActivateApplication()

        XCTAssertTrue(host.isVisible)
        XCTAssertEqual(host.frameOrigin, restingOrigin)
        XCTAssertEqual(host.levels, [.floating])
        XCTAssertEqual(host.orderFrontCount, orderFrontsAfterShow + 1)
    }

    @MainActor
    func testOnlyResetTakesTheCursorOffScreen() {
        let host = FakeCursorPanelHost()
        installFakeEnvironment(host: host, isWindowPresent: { _ in true })
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        SoftwareCursorOverlay.repositionCursor(
            to: CGPoint(x: 300, y: 300),
            in: CursorTargetWindow(windowID: 42, layer: 0)
        )
        XCTAssertTrue(host.isVisible)
        let restingOrigin = host.frameOrigin

        // Idle well past the bounded sway beat. The old implementation hid the
        // whole overlay 30 s after the last interaction, which is shorter than
        // a normal model turn; hiding is a turn-boundary decision now.
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        XCTAssertTrue(host.isVisible)
        XCTAssertEqual(host.orderOutCount, 0)
        XCTAssertEqual(host.frameOrigin, restingOrigin)

        SoftwareCursorOverlay.reset()

        XCTAssertFalse(host.isVisible)
        XCTAssertEqual(host.orderOutCount, 1)
    }

    @MainActor
    func testDisabledVisualCursorNeverInstallsAPanelHost() {
        let host = FakeCursorPanelHost()
        installFakeEnvironment(host: host, isWindowPresent: { _ in true }, isVisualCursorEnabled: false)
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        SoftwareCursorOverlay.repositionCursor(to: CGPoint(x: 10, y: 10), in: nil)

        XCTAssertFalse(host.isVisible)
        XCTAssertTrue(host.levels.isEmpty)
        XCTAssertNil(host.frameOrigin)
        XCTAssertEqual(host.appliedRenderStateCount, 0)
    }
}
