import XCTest
@testable import OpenComputerUseKit

final class TextSelectionResolverTests: XCTestCase {
    private func resolve(
        value: String,
        text: String,
        prefix: String? = nil,
        suffix: String? = nil,
        selection: TextSelectionMode = .text
    ) throws -> TextSelectionTarget {
        try TextSelectionResolver.resolve(value: value, text: text, prefix: prefix, suffix: suffix, selection: selection)
    }

    func testResolvesUniqueMatch() throws {
        let target = try resolve(value: "hello world", text: "world")

        XCTAssertEqual(target.location, 6)
        XCTAssertEqual(target.length, 5)
        XCTAssertEqual(target.matchedLocation, 6)
        XCTAssertEqual(target.matchedLength, 5)
        XCTAssertEqual(target.selectionMode, .text)
    }

    func testCursorModesCollapseToZeroLengthRanges() throws {
        let before = try resolve(value: "hello world", text: "world", selection: .cursorBefore)
        let after = try resolve(value: "hello world", text: "world", selection: .cursorAfter)

        XCTAssertEqual(before.location, 6)
        XCTAssertEqual(before.length, 0)
        XCTAssertEqual(after.location, 11)
        XCTAssertEqual(after.length, 0)
    }

    func testMissingTextFailsClosed() {
        XCTAssertThrowsError(try resolve(value: "hello world", text: "missing")) { error in
            XCTAssertEqual(error as? TextSelectionResolverError, .notFound)
        }
    }

    func testEmptyTextFailsClosed() {
        XCTAssertThrowsError(try resolve(value: "hello", text: "")) { error in
            XCTAssertEqual(error as? TextSelectionResolverError, .emptyText)
        }
    }

    func testAmbiguousTextRequiresDisambiguation() {
        XCTAssertThrowsError(try resolve(value: "ab ab", text: "ab")) { error in
            XCTAssertEqual(error as? TextSelectionResolverError, .ambiguous(occurrenceCount: 2))
        }
    }

    func testOverlappingPlacementsAlsoCountAsAmbiguous() {
        XCTAssertThrowsError(try resolve(value: "aaa", text: "aa")) { error in
            XCTAssertEqual(error as? TextSelectionResolverError, .ambiguous(occurrenceCount: 2))
        }
    }

    func testPrefixDisambiguatesToTheLaterMatch() throws {
        let target = try resolve(value: "ab ab", text: "ab", prefix: "ab ")

        XCTAssertEqual(target.location, 3)
        XCTAssertEqual(target.length, 2)
    }

    func testSuffixDisambiguatesToTheEarlierMatch() throws {
        let target = try resolve(value: "ab cd ab ef", text: "ab", suffix: " cd")

        XCTAssertEqual(target.location, 0)
        XCTAssertEqual(target.length, 2)
    }

    func testEmptyPrefixAndSuffixBehaveLikeNil() throws {
        let target = try resolve(value: "hello world", text: "world", prefix: "", suffix: "")

        XCTAssertEqual(target.location, 6)
    }

    func testOffsetsFollowUTF16UnitsForEmojiAndCJK() throws {
        let target = try resolve(value: "a\u{1F44D}中文b\u{1F44D}", text: "中文")

        XCTAssertEqual(target.location, 3)
        XCTAssertEqual(target.length, 2)
    }

    func testSelectionModeRawValuesMatchTheToolSchema() {
        XCTAssertEqual(TextSelectionMode.allCases.map(\.rawValue), ["text", "cursor_before", "cursor_after"])
    }
}
