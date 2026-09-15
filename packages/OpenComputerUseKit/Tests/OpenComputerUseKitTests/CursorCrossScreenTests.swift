import AppKit
import XCTest
@testable import OpenComputerUseKit

/// Regression cover for the user report "the window was dragged from the
/// external display to the built-in one and the software cursor stayed on the
/// display the window had just left".
///
/// Two failures are pinned here:
/// 1. the action path used the cached snapshot window frame, so every global
///    point (cursor tip, coordinate click, screenshot mapping) kept describing
///    the old screen until the next `get_app_state`;
/// 2. nothing re-placed the overlay while the window moved, so the cursor only
///    caught up on the next tool call.
final class CursorCrossScreenTests: XCTestCase {
    // MARK: - Fake window server

    @MainActor
    private final class FakeCursorPanelHost: CursorOverlayPanelHosting {
        private(set) var isVisible = false
        var alphaValue: CGFloat = 1
        private(set) var frameOrigin: CGPoint?
        private(set) var orderFrontCount = 0
        private(set) var orderOutCount = 0

        var windowNumber: Int { 4_242 }
        var cursorRotation: CGFloat { 0 }

        func setLevel(_ level: NSWindow.Level) {}
        func setFrameOrigin(_ origin: CGPoint) { frameOrigin = origin }
        func orderFront() {
            isVisible = true
            orderFrontCount += 1
        }

        func orderAbove(windowID: CGWindowID) { isVisible = true }

        func orderOut() {
            isVisible = false
            orderOutCount += 1
        }

        func apply(renderState: CursorVisualRenderState, clickProgress: CGFloat) {}
    }

    @MainActor
    private final class FakeWindowMotionObserver: CursorWindowMotionObserving {
        private(set) var isObserving = false
        private(set) var observedPid: pid_t?
        private(set) var observedWindow: AXUIElement?
        private(set) var stopCount = 0
        private var onChange: (@MainActor () -> Void)?

        func observe(pid: pid_t, window: AXUIElement, onChange: @escaping @MainActor () -> Void) {
            isObserving = true
            observedPid = pid
            observedWindow = window
            self.onChange = onChange
        }

        func stop() {
            isObserving = false
            stopCount += 1
            onChange = nil
        }

        /// What the accessibility run loop does when the watched window moved.
        func fireWindowMotion() { onChange?() }
    }

    // MARK: - Fixture displays

    /// Two displays, split inside the real screen so the tip clamp (which uses
    /// the real `NSScreen.screens`) never rewrites an expected point.
    private static let displayA = VisualCursorScreenMapping(
        screenStateFrame: CGRect(x: 0, y: 0, width: 700, height: 600),
        appKitFrame: CGRect(x: 0, y: 0, width: 700, height: 600)
    )
    private static let displayB = VisualCursorScreenMapping(
        screenStateFrame: CGRect(x: 700, y: 0, width: 700, height: 600),
        appKitFrame: CGRect(x: 700, y: 0, width: 700, height: 600)
    )
    private static let displays = [displayA, displayB]
    private static let windowID: CGWindowID = 77
    private static let windowOnA = CGRect(x: 40, y: 60, width: 560, height: 420)
    private static let windowOnB = CGRect(x: 740, y: 60, width: 560, height: 420)
    private static let elementLocalFrame = CGRect(x: 100, y: 80, width: 120, height: 40)

    @MainActor
    private func installFakeEnvironment(
        host: FakeCursorPanelHost,
        liveBounds: @escaping () -> CGRect?,
        observer: FakeWindowMotionObserver,
        isVisualCursorEnabled: Bool = true
    ) {
        SoftwareCursorOverlay.installEnvironmentForTesting(
            CursorOverlayEnvironment(
                isVisualCursorEnabled: isVisualCursorEnabled,
                canPresentOverlay: true,
                installsActivationObserver: false,
                isWindowPresent: { _ in true },
                makePanelHost: { host },
                windowBounds: { _ in liveBounds() },
                screenStateToAppKitPoint: {
                    screenStatePointToAppKitGlobalPoint(
                        fromScreenStatePoint: $0,
                        screenMappings: Self.displays
                    )
                },
                screenIndex: { point in
                    Self.displays.firstIndex { $0.appKitFrame.contains(point) }
                },
                makeWindowMotionObserver: { observer }
            )
        )
    }

    @MainActor
    private func makeTarget() -> VisualCursorTarget? {
        makeVisualCursorTarget(
            localFrame: Self.elementLocalFrame,
            windowBounds: Self.windowOnA,
            targetWindowID: Self.windowID,
            targetWindowLayer: 0,
            screenMappings: Self.displays
        )
    }

    /// The tip the panel is actually showing, derived from the origin it wrote.
    @MainActor
    private func displayedTip(of host: FakeCursorPanelHost) -> CGPoint {
        let origin = host.frameOrigin ?? .zero
        let tipAnchor = SoftwareCursorOverlay.artworkGeometry.tipAnchor
        return CGPoint(x: origin.x + tipAnchor.x, y: origin.y + tipAnchor.y)
    }

    @MainActor
    private func expectedOrigin(forTipPosition tipPosition: CGPoint) -> CGPoint {
        integralCursorFrameOrigin(
            forTipPosition: tipPosition,
            tipAnchor: SoftwareCursorOverlay.artworkGeometry.tipAnchor
        )
    }

    private var observedWindow: CursorObservedWindow {
        CursorObservedWindow(
            pid: 4_242,
            windowID: Self.windowID,
            layer: 0,
            element: AXUIElementCreateSystemWide()
        )
    }

    // MARK: - Cached snapshot frame

    func testSnapshotWindowReanchorPolicyPinsMoveResizeAndReplacement() {
        let windowID = Self.windowID
        let bounds = Self.windowOnA

        XCTAssertEqual(
            snapshotWindowReanchorAction(
                cachedWindowID: windowID,
                cachedBounds: bounds,
                live: SnapshotWindowGeometry(windowID: windowID, layer: 0, bounds: bounds)
            ),
            .none,
            "an unchanged window must not cost a re-read"
        )

        XCTAssertEqual(
            snapshotWindowReanchorAction(
                cachedWindowID: windowID,
                cachedBounds: bounds,
                live: SnapshotWindowGeometry(windowID: windowID, layer: 0, bounds: Self.windowOnB)
            ),
            .patchGeometry,
            "a window that only moved keeps its window-relative element frames"
        )

        XCTAssertEqual(
            snapshotWindowReanchorAction(
                cachedWindowID: windowID,
                cachedBounds: bounds,
                live: SnapshotWindowGeometry(
                    windowID: windowID,
                    layer: 0,
                    bounds: CGRect(x: 740, y: 60, width: 800, height: 420)
                )
            ),
            .fullRefresh,
            "a resize invalidates the rendered element frames"
        )

        XCTAssertEqual(
            snapshotWindowReanchorAction(
                cachedWindowID: windowID,
                cachedBounds: bounds,
                live: SnapshotWindowGeometry(windowID: 9_999, layer: 0, bounds: bounds)
            ),
            .fullRefresh
        )

        XCTAssertEqual(
            snapshotWindowReanchorAction(cachedWindowID: windowID, cachedBounds: bounds, live: nil),
            .none,
            "an unresolvable window keeps the snapshot the accessibility paths still work with"
        )
    }

    func testReanchoredSnapshotMovesTheWindowFrameButKeepsElementFrames() {
        let record = ElementRecord(
            index: 3,
            identifier: nil,
            element: nil,
            localFrame: Self.elementLocalFrame,
            role: kAXButtonRole as String,
            rawActions: [kAXPressAction as String],
            prettyActions: []
        )
        let snapshot = AppSnapshot(
            app: RunningAppDescriptor(
                name: "Sample Chat",
                bundleIdentifier: "com.example.SampleChat",
                pid: 18_465,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Sample Chat",
            windowBounds: Self.windowOnA,
            targetWindowID: Self.windowID,
            targetWindowLayer: 0,
            windowElement: nil,
            screenshotPNGData: nil,
            mode: .accessibility,
            treeLines: [],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [3: record]
        )

        let reanchored = snapshot.reanchored(
            to: SnapshotWindowGeometry(windowID: Self.windowID, layer: 0, bounds: Self.windowOnB)
        )

        XCTAssertEqual(reanchored.windowBounds, Self.windowOnB)
        XCTAssertEqual(reanchored.targetWindowID, Self.windowID)
        XCTAssertEqual(
            reanchored.elements[3]?.localFrame,
            Self.elementLocalFrame,
            "element frames are window-relative, so a move must not touch them"
        )
    }

    // MARK: - Overlay follows the window

    @MainActor
    func testWindowMotionNotificationReanchorsTheCursorOntoTheNewDisplay() {
        let host = FakeCursorPanelHost()
        let observer = FakeWindowMotionObserver()
        var liveBounds: CGRect? = Self.windowOnA
        installFakeEnvironment(host: host, liveBounds: { liveBounds }, observer: observer)
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        // Screen-state (200,160) is AppKit (200,440): the conversion flips y
        // inside the display frame it lands on.
        XCTAssertEqual(target?.point, CGPoint(x: 200, y: 440))
        XCTAssertEqual(target?.restingAnchor?.windowLocalPoint, CGPoint(x: 160, y: 100))

        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.repositionCursor(
            to: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        XCTAssertTrue(observer.isObserving, "the move watch arms with the first placement")
        XCTAssertEqual(observer.observedPid, 4_242)
        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 200, y: 440)))
        XCTAssertTrue(Self.displayA.appKitFrame.contains(displayedTip(of: host)))

        // The user drags the window to the second display.
        liveBounds = Self.windowOnB
        observer.fireWindowMotion()

        XCTAssertEqual(
            host.frameOrigin,
            expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)),
            "the cursor re-derives its tip from the live window frame"
        )
        XCTAssertTrue(
            Self.displayB.appKitFrame.contains(displayedTip(of: host)),
            "the cursor has to end up on the display the window moved to"
        )
        XCTAssertTrue(host.isVisible, "crossing displays must never hide the cursor")
        XCTAssertEqual(host.orderOutCount, 0)
    }

    @MainActor
    func testPreActionFallbackReanchorsWhenNoNotificationArrived() {
        let host = FakeCursorPanelHost()
        let observer = FakeWindowMotionObserver()
        var liveBounds: CGRect? = Self.windowOnA
        installFakeEnvironment(host: host, liveBounds: { liveBounds }, observer: observer)
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.repositionCursor(
            to: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        // The app never posts AXWindowMoved: only the live frame knows.
        liveBounds = Self.windowOnB
        SoftwareCursorOverlay.refreshTargetWindowAnchorIfScreenChanged()

        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)))
        XCTAssertTrue(host.isVisible)
        XCTAssertEqual(host.orderOutCount, 0)
    }

    /// The travel loop keeps writing frames, so the move notification alone
    /// cannot redirect it. This pins the frame check that stops a cursor from
    /// flying to the display the window just left.
    func testTravelAbortsOnlyWhenTheLiveFrameActuallyChanged() {
        let onA = CGRect(x: 0, y: 0, width: 800, height: 600)
        let onB = CGRect(x: -1400, y: 200, width: 800, height: 600)

        XCTAssertFalse(cursorTravelMustAbort(startFrame: onA, liveFrame: onA))
        XCTAssertTrue(cursorTravelMustAbort(startFrame: onA, liveFrame: onB))
        XCTAssertTrue(
            cursorTravelMustAbort(startFrame: onA, liveFrame: CGRect(x: 0, y: 0, width: 900, height: 600))
        )
        // Unknown geometry is not a change: the accessibility paths need no frame.
        XCTAssertFalse(cursorTravelMustAbort(startFrame: nil, liveFrame: onB))
        XCTAssertFalse(cursorTravelMustAbort(startFrame: onA, liveFrame: nil))
    }

    /// End-to-end over the real travel loop: the window frame changes between
    /// the frame the travel started from and the first frame it draws, and the
    /// cursor has to end up on the live frame instead of finishing the path.
    @MainActor
    func testTravelLandsOnTheLiveFrameWhenTheWindowMovesMidTravel() {
        let host = FakeCursorPanelHost()
        let observer = FakeWindowMotionObserver()
        var boundsReads = 0
        installFakeEnvironment(
            host: host,
            liveBounds: {
                boundsReads += 1
                return boundsReads <= 1 ? Self.windowOnA : Self.windowOnB
            },
            observer: observer
        )
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.moveCursor(
            to: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)))
        XCTAssertTrue(host.isVisible)
        XCTAssertEqual(host.orderOutCount, 0)
    }

    /// The window list keeps reporting the pre-move frame for about a second
    /// (measured on the reporting machine: 83 identical frames), so the
    /// accessibility notification is the only signal that reaches a travel
    /// while it is still running.
    ///
    /// The notification is delivered on the first `pumpFrame()`, which keeps
    /// this deterministic without depending on travel duration.
    @MainActor
    func testTravelAbortsWhenTheMoveNotificationArrivesMidTravel() {
        let host = FakeCursorPanelHost()
        var liveBounds: CGRect? = Self.windowOnA
        installFakeEnvironment(host: host, liveBounds: { liveBounds }, observer: FakeWindowMotionObserver())
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)

        DispatchQueue.main.async {
            liveBounds = Self.windowOnB
            SoftwareCursorOverlay.targetWindowDidMove()
        }

        SoftwareCursorOverlay.moveCursor(
            to: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)))
        XCTAssertTrue(host.isVisible)
    }

    /// The action pipeline is move -> settle -> action, and that settle uses the
    /// target point derived from the snapshot taken *before* the window moved.
    /// Without re-deriving it, the settle re-places the cursor on the display
    /// the window just left and undoes the travel abort. This was the step that
    /// still failed on the reporting machine after the travel abort alone.
    @MainActor
    func testSettleUsesTheLiveFrameWhenTheWindowMovedAfterTheSnapshot() {
        let host = FakeCursorPanelHost()
        var liveBounds: CGRect? = Self.windowOnB
        installFakeEnvironment(host: host, liveBounds: { liveBounds }, observer: FakeWindowMotionObserver())
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.settle(
            at: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)))
    }

    /// `pulseClick` follows the same settle, so the click feedback must not be
    /// drawn on the old display either.
    @MainActor
    func testPulseClickUsesTheLiveFrameWhenTheWindowMovedAfterTheSnapshot() {
        let host = FakeCursorPanelHost()
        var liveBounds: CGRect? = Self.windowOnB
        installFakeEnvironment(host: host, liveBounds: { liveBounds }, observer: FakeWindowMotionObserver())
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.pulseClick(
            at: target?.point ?? .zero,
            clickCount: 1,
            mouseButton: .left,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )

        XCTAssertEqual(host.frameOrigin, expectedOrigin(forTipPosition: CGPoint(x: 900, y: 440)))
    }

    func testScreenMismatchOnlyFiresWhenBothDisplaysAreKnown() {
        let screenIndex: (CGPoint) -> Int? = { point in
            point.x < 700 ? 0 : 1
        }

        XCTAssertFalse(
            cursorOverlayScreenMismatch(
                panelTip: CGPoint(x: 200, y: 160),
                targetWindowOrigin: CGPoint(x: 40, y: 60),
                screenIndexContaining: screenIndex
            )
        )
        XCTAssertTrue(
            cursorOverlayScreenMismatch(
                panelTip: CGPoint(x: 200, y: 160),
                targetWindowOrigin: CGPoint(x: 740, y: 60),
                screenIndexContaining: screenIndex
            )
        )
        XCTAssertFalse(
            cursorOverlayScreenMismatch(
                panelTip: nil,
                targetWindowOrigin: CGPoint(x: 740, y: 60),
                screenIndexContaining: screenIndex
            ),
            "an unknown overlay screen is not a mismatch"
        )
    }

    // MARK: - Zero activation, zero cost by default

    func testTheMoveWatchOnlyEverRegistersReadOnlyNotifications() {
        XCTAssertEqual(cursorWindowMotionNotifications, [kAXWindowMovedNotification, kAXWindowResizedNotification])

        let activationNotifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification,
        ]
        for notification in activationNotifications {
            XCTAssertFalse(
                cursorWindowMotionNotifications.contains(notification),
                notification
            )
        }
    }

    func testTheMoveWatchIsOnByDefaultAndCanBeSwitchedOff() {
        XCTAssertTrue(cursorWindowMoveWatchEnabled(environment: [:]))

        for rawValue in ["0", "false", "no", "off", " OFF "] {
            XCTAssertFalse(
                cursorWindowMoveWatchEnabled(environment: ["OPEN_COMPUTER_USE_WINDOW_MOVE_WATCH": rawValue]),
                rawValue
            )
        }

        for rawValue in ["1", "true", "yes", "on"] {
            XCTAssertTrue(
                cursorWindowMoveWatchEnabled(environment: ["OPEN_COMPUTER_USE_WINDOW_MOVE_WATCH": rawValue]),
                rawValue
            )
        }
    }

    @MainActor
    func testDisabledVisualCursorNeverArmsTheMoveWatch() {
        let host = FakeCursorPanelHost()
        let observer = FakeWindowMotionObserver()
        installFakeEnvironment(
            host: host,
            liveBounds: { Self.windowOnA },
            observer: observer,
            isVisualCursorEnabled: false
        )
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.repositionCursor(to: CGPoint(x: 200, y: 160), in: nil)

        XCTAssertFalse(observer.isObserving)
        XCTAssertNil(host.frameOrigin)
    }

    @MainActor
    func testResetDropsTheMoveWatch() {
        let host = FakeCursorPanelHost()
        let observer = FakeWindowMotionObserver()
        installFakeEnvironment(host: host, liveBounds: { Self.windowOnA }, observer: observer)
        defer { SoftwareCursorOverlay.installEnvironmentForTesting(.live) }

        let target = makeTarget()
        SoftwareCursorOverlay.observeTargetWindow(observedWindow)
        SoftwareCursorOverlay.repositionCursor(
            to: target?.point ?? .zero,
            in: CursorTargetWindow(windowID: Self.windowID, layer: 0),
            anchor: target?.restingAnchor
        )
        XCTAssertTrue(observer.isObserving)

        SoftwareCursorOverlay.reset()

        XCTAssertFalse(observer.isObserving)
        XCTAssertFalse(host.isVisible)
    }
}
