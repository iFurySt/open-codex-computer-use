import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// Element frames are window-relative, so a cursor point derived from a
/// snapshot stops being valid the moment the window moves. These numbers are
/// the ones the bug was reproduced with: the same window on the built-in
/// display (`x = -1400`) and on the main display (`x = 600`).
final class CursorWindowAnchorTests: XCTestCase {
    private let builtInDisplayFrame = CGRect(x: -1400, y: 200, width: 500, height: 400)
    private let mainDisplayFrame = CGRect(x: 600, y: 200, width: 500, height: 400)

    private func anchor() -> CursorRestingAnchor {
        CursorRestingAnchor(
            windowID: 4242,
            layer: 0,
            windowLocalPoint: CGPoint(x: 250, y: 200),
            windowBounds: builtInDisplayFrame
        )
    }

    func testAnchorStaysPutWhileTheWindowDoesNotMove() {
        let point = anchor().screenStatePoint(liveFrame: builtInDisplayFrame)
        XCTAssertEqual(point, CGPoint(x: -1150, y: 400))
    }

    /// The reported bug: the window is dragged to the main display while the
    /// cursor is travelling, and the cursor finishes on the display the window
    /// just left.
    func testAnchorFollowsTheWindowOntoTheOtherDisplay() {
        let point = anchor().screenStatePoint(liveFrame: mainDisplayFrame)
        XCTAssertEqual(point, CGPoint(x: 850, y: 400))
    }

    /// Only the frame origin moves; the window-local offset must survive, so a
    /// click still lands on the same control inside the window.
    func testAnchorPreservesTheWindowLocalOffset() {
        let moved = CGRect(x: -1400, y: -600, width: 500, height: 400)
        let point = anchor().screenStatePoint(liveFrame: moved)
        XCTAssertEqual(point, CGPoint(x: -1150, y: -400))
    }

    /// A window that shrank must not put the cursor outside itself.
    func testAnchorClampsIntoASmallerLiveFrame() {
        let shrunk = CGRect(x: 600, y: 200, width: 120, height: 80)
        let point = anchor().screenStatePoint(liveFrame: shrunk)
        XCTAssertEqual(point, CGPoint(x: 720, y: 280))
    }

    /// No usable size means no re-derivation: the caller keeps the point it has
    /// rather than guessing.
    func testAnchorRejectsALiveFrameWithoutSize() {
        XCTAssertNil(anchor().screenStatePoint(liveFrame: .zero))
        XCTAssertNil(anchor().screenStatePoint(liveFrame: CGRect(x: 10, y: 10, width: 0, height: 40)))
    }

    func testTrackerPrefersTheRegisteredLiveFrame() {
        CursorWindowFrameTracker.installFrameOverrideForTesting { windowID in
            windowID == 4242 ? self.mainDisplayFrame : nil
        }
        defer { CursorWindowFrameTracker.installFrameOverrideForTesting(nil) }

        XCTAssertEqual(CursorWindowFrameTracker.liveFrame(for: 4242), mainDisplayFrame)
        XCTAssertNil(CursorWindowFrameTracker.liveFrame(for: 1))
    }

    /// Registering nothing must not produce a frame out of thin air; the
    /// window list is the only remaining source and an unknown id has no entry.
    func testTrackerReportsNothingForAnUnknownWindow() {
        CursorWindowFrameTracker.forgetAll()

        XCTAssertNil(CursorWindowFrameTracker.liveFrame(for: CGWindowID(0)))
    }
}
