import XCTest
@testable import OpenComputerUseKit

final class VirtualDisplayPreviewTests: XCTestCase {
    private let image = CGSize(width: 1920, height: 1080)
    private let view = CGSize(width: 960, height: 540)

    func testZoomKeepsImagePointUnderPointerAndPanCannotLoseImage() {
        var viewport = VirtualDisplayViewport()
        let anchor = CGPoint(x: 600, y: 300)
        viewport.magnify(by: 2, at: anchor, image: image, view: view, originalSize: false, backingScale: 2)
        let rect = viewport.imageRect(image: image, view: view, originalSize: false, backingScale: 2)
        XCTAssertEqual((anchor.x - rect.minX) / rect.width, anchor.x / view.width, accuracy: 0.0001)
        XCTAssertEqual((anchor.y - rect.minY) / rect.height, anchor.y / view.height, accuracy: 0.0001)
        viewport.drag(by: CGPoint(x: 10000, y: -10000), image: image, view: view, originalSize: false, backingScale: 2)
        let panned = viewport.imageRect(image: image, view: view, originalSize: false, backingScale: 2)
        XCTAssertEqual(panned.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(panned.maxY, view.height, accuracy: 0.0001)
        viewport.reset()
        XCTAssertEqual(viewport.imageRect(image: image, view: view, originalSize: false, backingScale: 2), CGRect(origin: .zero, size: view))
    }

    func testOriginalPixelsRespectBackingScaleAndZoomIsBounded() {
        var viewport = VirtualDisplayViewport()
        XCTAssertEqual(viewport.imageRect(image: image, view: view, originalSize: true, backingScale: 2).size, view)
        viewport.magnify(by: 100, at: CGPoint(x: 480, y: 270), image: image, view: view, originalSize: true, backingScale: 2)
        XCTAssertEqual(viewport.zoom, 8)
        viewport.magnify(by: 0.0001, at: .zero, image: image, view: view, originalSize: true, backingScale: 2)
        XCTAssertEqual(viewport.zoom, 0.25)
        XCTAssertEqual(viewport.pan, .zero)
        viewport.magnify(by: .nan, at: .zero, image: image, view: view, originalSize: true, backingScale: 2)
        XCTAssertEqual(viewport.zoom, 0.25)
    }

    func testCurvedMotionHasIntermediateFramesAndRetargetsWithoutJump() throws {
        var motion = VirtualDisplayCursorMotion()
        let start = CGPoint(x: 0.2, y: 0.3), end = CGPoint(x: 0.8, y: 0.7)
        motion.setTarget(start, at: 10, logicalSize: image)
        motion.setTarget(end, at: 10, logicalSize: image)
        XCTAssertTrue(motion.isMoving)
        let middle = try XCTUnwrap(motion.sample(at: 10.1))
        XCTAssertNotEqual(middle, start); XCTAssertNotEqual(middle, end)
        let deviation = (end.x - start.x) * (middle.y - start.y) - (end.y - start.y) * (middle.x - start.x)
        XCTAssertGreaterThan(abs(deviation), 0.00001, "Motion should follow a curve rather than interpolate a straight line")
        motion.setTarget(CGPoint(x: 0.4, y: 0.9), at: 10.1, logicalSize: image)
        let interrupted = try XCTUnwrap(motion.sample(at: 10.1))
        XCTAssertEqual(interrupted.x, middle.x, accuracy: 0.0001)
        XCTAssertEqual(interrupted.y, middle.y, accuracy: 0.0001)
        XCTAssertEqual(motion.sample(at: 20), CGPoint(x: 0.4, y: 0.9))
        XCTAssertFalse(motion.isMoving)
        motion.setTarget(nil, at: 20, logicalSize: image)
        XCTAssertNil(motion.sample(at: 20)); XCTAssertFalse(motion.isMoving)
    }

    func testMotionRemainsInsideDisplayAndNewDisplayDoesNotReuseOldPosition() throws {
        var motion = VirtualDisplayCursorMotion()
        motion.setTarget(CGPoint(x: 0.01, y: 0.01), at: 0, logicalSize: image)
        motion.setTarget(CGPoint(x: 2, y: -1), at: 0, logicalSize: image)
        for tick in 0...100 {
            let point = try XCTUnwrap(motion.sample(at: Double(tick) / 100))
            XCTAssertTrue((0...1).contains(point.x)); XCTAssertTrue((0...1).contains(point.y))
        }
        motion.setTarget(CGPoint(x: 0.5, y: 0.5), at: 2, logicalSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(motion.sample(at: 2), CGPoint(x: 0.5, y: 0.5))
        XCTAssertFalse(motion.isMoving)
    }

    func testFreshOverlayAnimatesInsteadOfTeleportingAndTurnsAtCaptureCadence() throws {
        var motion = VirtualDisplayCursorMotion()
        let target = CGPoint(x: 0.8, y: 0.3)
        motion.setTarget(target, at: 0, logicalSize: image, animateFirstMove: true)
        XCTAssertTrue(motion.isTraveling)
        XCTAssertNotEqual(motion.sample(at: 0), target)
        var turns: [CGFloat] = []
        var deviations: [CGFloat] = []
        let start = try XCTUnwrap(motion.renderState(at: 0)).tipPosition
        let end = CGPoint(x: target.x * image.width, y: (1 - target.y) * image.height)
        for frame in 1...20 {
            let pose = try XCTUnwrap(motion.renderState(at: Double(frame) / 30))
            turns.append(abs(pose.rotation))
            let cross = (end.x - start.x) * (pose.tipPosition.y - start.y) - (end.y - start.y) * (pose.tipPosition.x - start.x)
            deviations.append(abs(cross) / hypot(end.x - start.x, end.y - start.y))
        }
        XCTAssertGreaterThan(turns.max() ?? 0, 0.05)
        XCTAssertGreaterThan(deviations.max() ?? 0, 5, "The captured 30 fps samples must include a visible arc")
        let finished = try XCTUnwrap(motion.sample(at: 10))
        XCTAssertEqual(finished.x, target.x, accuracy: 0.0001)
        XCTAssertEqual(finished.y, target.y, accuracy: 0.0001)
        XCTAssertFalse(motion.isMoving)
        motion.setTarget(nil, at: 10, logicalSize: image)
        XCTAssertNil(motion.renderState(at: 10))
    }

    func testRenderedPositionAndHeadingMatchOrdinaryCursorDynamics() throws {
        var motion = VirtualDisplayCursorMotion()
        let start = CGPoint(x: image.width * 0.2, y: image.height * 0.7)
        let end = CGPoint(x: image.width * 0.8, y: image.height * 0.3)
        motion.setTarget(CGPoint(x: 0.2, y: 0.3), at: 0, logicalSize: image)
        motion.setTarget(CGPoint(x: 0.8, y: 0.7), at: 0, logicalSize: image)
        let heading = visualCursorAppKitForwardHeading(renderRotation: 0)
        let candidate = try XCTUnwrap(HeadingDrivenCursorMotionModel.chooseBestCandidate(from:
            HeadingDrivenCursorMotionModel.makeCandidates(start: start, end: end,
                bounds: CGRect(origin: .zero, size: image),
                startForward: CGVector(dx: cos(heading), dy: sin(heading)),
                endForward: CGVector(dx: cos(heading), dy: sin(heading)))))
        let duration = OfficialCursorMotionModel.calibratedTravelDuration(distance: hypot(end.x - start.x, end.y - start.y), measurement: candidate.measurement)
        var dynamics = CursorVisualDynamicsAnimator.state(at: start, time: 0)
        var progress: CGFloat = 0, spring = CursorMotionSpringState()
        for frame in 1...6 {
            let time = CGFloat(frame) / 30
            (progress, spring) = CursorMotionProgressAnimator.advance(current: progress, state: spring,
                to: min(time / duration, 1) * OfficialCursorMotionModel.closeEnoughTime)
            let reference = CursorVisualDynamicsAnimator.advance(state: dynamics,
                targetTipPosition: candidate.path.sample(at: progress).point, targetTime: time,
                baseHeading: visualCursorRenderBaseHeading(), renderYAxisMultiplier: visualCursorRuntimeRenderYAxisMultiplier())
            dynamics = reference.state
            let actual = try XCTUnwrap(motion.renderState(at: Double(time)))
            XCTAssertEqual(actual.tipPosition.x, reference.renderState.tipPosition.x, accuracy: 0.0001)
            XCTAssertEqual(actual.tipPosition.y, reference.renderState.tipPosition.y, accuracy: 0.0001)
            XCTAssertEqual(actual.rotation, reference.renderState.rotation, accuracy: 0.0001)
        }
    }

    /// Reuses a caller-provided display; never hotplugs a screen during tests.
    @MainActor
    func testLiveCursorTravelCanBeCancelledAndClosedWithoutBlockingAppKit() async throws {
        guard let value = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_VIRTUAL_CURSOR_LIVE_DISPLAY_ID"],
              let displayID = UInt32(value) else {
            throw XCTSkip("Provide an existing virtual display ID for the AppKit cursor lifecycle check")
        }
        let overlay = try VirtualDisplayCursorOverlay(displayID: displayID)
        defer { overlay.close() }
        let cancelled = Task { await overlay.move(to: CGPoint(x: 0.8, y: 0.3)) }
        try await Task.sleep(nanoseconds: 50_000_000)
        overlay.setTarget(nil)
        let cancelResult = await cancelled.value
        XCTAssertFalse(cancelResult)
        let completed = await overlay.move(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(completed)
        let closed = Task { await overlay.move(to: CGPoint(x: 0.9, y: 0.1)) }
        try await Task.sleep(nanoseconds: 50_000_000)
        overlay.close()
        let closeResult = await closed.value
        XCTAssertFalse(closeResult)
    }
}
