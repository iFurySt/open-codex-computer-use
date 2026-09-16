import AppKit
import XCTest
@testable import OpenComputerUseKit

/// A target window can sit outside every active display (a window plan that remembered a monitor
/// which has since been rearranged). macOS then serves a chrome-only tree and the software cursor
/// is drawn on an unrelated screen, so both surfaces must report that state instead of staying silent.
final class OffDisplayWindowTests: XCTestCase {
    private let builtIn = VisualCursorScreenMapping(
        screenStateFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )
    private let externalLeft = VisualCursorScreenMapping(
        screenStateFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
        appKitFrame: CGRect(x: 0, y: 982, width: 1512, height: 982)
    )

    func testPointOnActiveDisplay() {
        let mappings = [builtIn]
        XCTAssertTrue(isPointOnActiveDisplay(CGPoint(x: 100, y: 100), screenMappings: mappings))
        XCTAssertFalse(isPointOnActiveDisplay(CGPoint(x: -1512 + 10, y: 100), screenMappings: mappings))
    }

    func testNoteIsSilentWhenTheWindowIsOnADisplay() {
        XCTAssertNil(offDisplayWindowNote(windowBounds: CGRect(x: 120, y: 120, width: 1230, height: 820), screenMappings: [builtIn]))
        XCTAssertNil(offDisplayWindowNote(windowBounds: nil, screenMappings: [builtIn]))
        XCTAssertNil(offDisplayWindowNote(windowBounds: CGRect(x: -1512, y: 132, width: 1492, height: 928), screenMappings: []))
    }

    func testNoteNamesAnOffDisplayWindow() {
        let note = offDisplayWindowNote(
            windowBounds: CGRect(x: -1512, y: 132, width: 1492, height: 928),
            screenMappings: [builtIn]
        )
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("off all active displays") == true)
    }

    func testNoteIsSilentWhenTheWindowIsOnEitherDisplay() {
        XCTAssertNil(offDisplayWindowNote(windowBounds: CGRect(x: -1512, y: 132, width: 1492, height: 928), screenMappings: [builtIn, externalLeft]))
    }

    func testCursorTargetIsSkippedOffDisplay() {
        XCTAssertNil(makeVisualCursorTarget(at: CGPoint(x: -1000, y: 400), targetWindowID: nil, targetWindowLayer: nil, screenMappings: [builtIn]))
        XCTAssertNotNil(makeVisualCursorTarget(at: CGPoint(x: 400, y: 400), targetWindowID: nil, targetWindowLayer: nil, screenMappings: [builtIn]))
    }
}
