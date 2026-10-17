import AppKit
import XCTest
@testable import OpenComputerUseKit

final class TextSelectionOperationTests: XCTestCase {
    private func target(_ mode: TextSelectionMode = .text) throws -> TextSelectionTarget {
        try TextSelectionResolver.resolve(value: "a👍中文", text: "中文", prefix: nil, suffix: nil, selection: mode)
    }

    func testAllModesAreVerified() throws {
        for mode in TextSelectionMode.allCases {
            let target = try target(mode)
            var applied: CFRange?
            try applyVerifiedTextSelection(target: target, originalValue: "a👍中文", validate: {},
                readValue: { "a👍中文" }, writeRange: { applied = $0 }, readRange: { applied })
            XCTAssertEqual(applied?.location, target.location)
            XCTAssertEqual(applied?.length, target.length)
        }
    }

    func testMissingOrRefusedRangeIsAnError() throws {
        for range in [nil, CFRange(location: 0, length: 0)] {
            XCTAssertThrowsError(try applyVerifiedTextSelection(target: target(), originalValue: "a👍中文", validate: {},
                readValue: { "a👍中文" }, writeRange: { _ in }, readRange: { range })) {
                XCTAssertTrue(String(describing: $0).contains("could not verify"))
            }
        }
    }

    func testRevokedSessionCannotWrite() throws {
        var wrote = false
        XCTAssertThrowsError(try applyVerifiedTextSelection(target: target(), originalValue: "a👍中文",
            validate: { throw ComputerUseError.message("revoked") }, readValue: { "a👍中文" },
            writeRange: { _ in wrote = true }, readRange: { nil }))
        XCTAssertFalse(wrote)
    }

    func testRevocationAfterWritingCannotReportSuccess() throws {
        var range: CFRange?
        XCTAssertThrowsError(try applyVerifiedTextSelection(target: target(), originalValue: "a👍中文",
            validate: { if range != nil { throw ComputerUseError.message("revoked") } }, readValue: { "a👍中文" },
            writeRange: { range = $0 }, readRange: { range }))
    }

    func testCanonicallyEqualButDifferentValueCannotUseTheOldRange() throws {
        var wrote = false
        XCTAssertThrowsError(try applyVerifiedTextSelection(target: target(), originalValue: "é",
            validate: {}, readValue: { "e\u{301}" }, writeRange: { _ in wrote = true }, readRange: { nil }))
        XCTAssertFalse(wrote)
    }

    func testChangedTextAfterWritingCannotReportSuccess() throws {
        var value = "a👍中文"
        let target = try target()
        XCTAssertThrowsError(try applyVerifiedTextSelection(target: target, originalValue: value,
            validate: {}, readValue: { value }, writeRange: { _ in value = "changed" },
            readRange: { CFRange(location: target.location, length: target.length) }))
    }

    func testQueryIndexesValidateSessionBeforeLookingUpTheApp() {
        let service = ComputerUseService()
        XCTAssertThrowsError(try LockedUseActionScope.withValidator({ throw ComputerUseError.message("revoked") }) {
            try service.selectText(app: "nonexistent-selection-test-app", elementIndex: "1000001", text: "x",
                                   prefix: nil, suffix: nil, selection: .text)
        }) { XCTAssertTrue(String(describing: $0).contains("revoked")) }
    }

    func testNativeDispatcherRejectsMalformedOptions() {
        let dispatcher = ComputerUseToolDispatcher()
        for (key, value) in [("prefix", 2 as Any), ("suffix", false as Any), ("selection", 3 as Any), ("selection", "" as Any)] {
            let result = dispatcher.callToolAsResult(name: "select_text", arguments: [
                "app": "nonexistent-selection-test-app", "element_index": "1", "text": "x", key: value,
            ])
            XCTAssertTrue(result.isError)
            XCTAssertTrue(result.primaryText?.contains(key) == true)
        }
    }

    @MainActor
    func testRealAXTextViewSupportsUTF16SelectionAndBothCaretModes() throws {
        guard AXIsProcessTrusted(), NSScreen.main != nil else { throw XCTSkip("Real AX selection requires Accessibility and a display") }
        NSApplication.shared.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 350, height: 150),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "OCU selection fixture \(UUID().uuidString)"
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 150))
        textView.string = "a👍中文"
        window.contentView = textView
        window.orderFront(nil)
        defer { window.close() }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func textArea(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
            if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole { return element }
            guard depth < 8 else { return nil }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = textArea(child, depth: depth + 1) { return found }
            }
            return nil
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let application = AXUIElementCreateApplication(getpid())
        let windows = try XCTUnwrap(attribute(application, kAXWindowsAttribute) as? [AXUIElement])
        let axWindow = try XCTUnwrap(windows.first { attribute($0, kAXTitleAttribute) as? String == window.title })
        let element = try XCTUnwrap(textArea(axWindow))
        for mode in TextSelectionMode.allCases {
            let target = try target(mode)
            try AccessibilityTextSelection.writeRange(CFRange(location: target.location, length: target.length), to: element)
            let range = try XCTUnwrap(AccessibilityTextSelection.readRange(of: element))
            XCTAssertEqual(range.location, target.location)
            XCTAssertEqual(range.length, target.length)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: target.location, length: target.length))
        }
    }
}
