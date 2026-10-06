import XCTest
@testable import OpenComputerUseKit
final class LockedUseReleaseBarrierTests: XCTestCase {
    func testNeedsContinuousLockedCoverageAndFreshSamples() {
        var b = LockedUseReleaseBarrier()
        for n in 0..<10 { XCTAssertFalse(b.observe(locked: true, presentation: "all", now: Double(n)/10)) }
        XCTAssertTrue(b.observe(locked: true, presentation: "all", now: 1))
        XCTAssertFalse(b.observe(locked: false, presentation: "all", now: 1.1))
        XCTAssertFalse(b.observe(locked: true, presentation: "all", now: 1.2))
        XCTAssertFalse(b.observe(locked: true, presentation: nil, now: 1.3))
        XCTAssertFalse(b.observe(locked: true, presentation: "all", now: 1.4))
        XCTAssertFalse(b.observe(locked: true, presentation: "all", now: 5))
        XCTAssertFalse(b.observe(locked: true, presentation: "all", now: 5.1))
    }
    func testTopologyOrClockChangeResetsStability() {
        var b = LockedUseReleaseBarrier()
        _ = b.observe(locked: true, presentation: "a", now: 1)
        _ = b.observe(locked: true, presentation: "a", now: 1.5)
        XCTAssertFalse(b.observe(locked: true, presentation: "b", now: 2))
        XCTAssertFalse(b.observe(locked: true, presentation: "b", now: .nan))
        XCTAssertFalse(b.observe(locked: true, presentation: "b", now: 3))
        XCTAssertFalse(b.observe(locked: true, presentation: "b", now: 2))
    }
}
