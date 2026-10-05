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
}
