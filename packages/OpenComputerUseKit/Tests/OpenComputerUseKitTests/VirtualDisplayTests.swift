import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class VirtualDisplayTests: XCTestCase {
    func testBrowserCursorAssetLoadsFromPackageResources() throws {
        let image = try XCTUnwrap(BrowserUseCursorArtwork.image)
        XCTAssertEqual(image.width, 46)
        XCTAssertEqual(image.height, 48)
        XCTAssertTrue(image.alphaInfo == .last || image.alphaInfo == .premultipliedLast)
    }

    func testStableDisplaySlotsNeverReuseAnOccupiedIdentity() throws {
        let first = try VirtualDisplayIdentity.availableSerial(identity: "release|test", occupied: [])
        let second = try VirtualDisplayIdentity.availableSerial(identity: "release|test", occupied: [first])
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try VirtualDisplayIdentity.availableSerial(identity: "release|test", occupied: []), first)
        XCTAssertNotEqual(first, try VirtualDisplayIdentity.availableSerial(identity: "dev|test", occupied: []))
        let occupied = Set((UInt32(0)..<256).map { VirtualDisplayIdentity.serial(identity: "release|test", slot: $0) })
        XCTAssertFalse(occupied.contains(0))
        XCTAssertThrowsError(try VirtualDisplayIdentity.availableSerial(identity: "release|test", occupied: occupied))
    }
    func testVirtualSkyClickCannotSynthesizeActivationEvenWhenTargetIsInactive() {
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: 10, targetPID: 20, allowSyntheticFocus: false))
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: nil, targetPID: 20, allowSyntheticFocus: false))
        XCTAssertTrue(skyClickNeedsSyntheticFocus(frontmostPID: 10, targetPID: 20, allowSyntheticFocus: true))
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: 20, targetPID: 20, allowSyntheticFocus: true))
    }
    func testExampleCommandsBindToSessionAndRejectMalformedOperands() throws {
        for cell in VirtualDisplayExample.cells {
            let spec = try VirtualDisplayNotebookKernel.boundCommand(source: cell.source, sessionID: "example")
            XCTAssertEqual(spec.arguments["session_id"] as? String, "example")
        }
        XCTAssertEqual(try VirtualDisplayExample.validatedNumber("-42.25"), "-42.25")
        for invalid: Any in ["1e4", "nan", "12; command", "123456789", true, 42] {
            XCTAssertThrowsError(try VirtualDisplayExample.validatedNumber(invalid))
        }
    }
    func testNotebookOutputSeparatesTreeAndImagesFromFormattedJSON() throws {
        let result = ToolCallResult(content: [.text(#"{"result":"714"}"#), .text("App=Calculator\n0 standard window"), .pngImage(Data([1, 2, 3]))])
        let output = VirtualDisplayNotebookOutput(result)
        XCTAssertEqual(output.uiTree, "App=Calculator\n0 standard window")
        XCTAssertEqual(output.images, [Data([1, 2, 3])])
        let json = try JSONSerialization.jsonObject(with: Data(output.json.utf8)) as? [String: Any]
        XCTAssertEqual((json?["result"] as? [String: String])?["result"], "714")
        XCTAssertFalse(output.json.contains("AQID"))
        let failure = VirtualDisplayNotebookOutput(.text("Delivery unverified", isError: true))
        XCTAssertTrue(failure.json.contains("Delivery unverified"))
        XCTAssertTrue(failure.json.contains("true"))
    }
    func testNotebookBindsSessionAndSelectedAppWithoutAllowingEscape() throws {
        let spec = try VirtualDisplayNotebookKernel.boundCommand(source: #"{"tool":"get_app_state","args":{"app":"$app","session_id":"$session","window_id":42}}"#, sessionID: "s1", app: "com.apple.calculator")
        XCTAssertEqual(spec.tool, "get_app_state")
        XCTAssertEqual(spec.arguments["session_id"] as? String, "s1")
        XCTAssertEqual(spec.arguments["app"] as? String, "com.apple.calculator")
        XCTAssertEqual(spec.arguments["window_id"] as? Int, 42)
        for invalid in [#"{"tool":"click","args":{"session_id":"other"}}"#, #"{"tool":"create_virtual_display"}"#, #"{"tool":"shell","args":{"command":"echo hi"}}"#, #"{"tool":"get_app_state","args":[]}"#] {
            XCTAssertThrowsError(try VirtualDisplayNotebookKernel.boundCommand(source: invalid, sessionID: "s1"))
        }
    }
    func testNotebookPreservesExplicitAppAndEnforcesVirtualInputBoundary() throws {
        let spec = try VirtualDisplayNotebookKernel.boundCommand(source: #"{"tool":"get_app_state","args":{"app":"TextEdit"}}"#, sessionID: "s1", app: "Calculator")
        XCTAssertEqual(spec.arguments["app"] as? String, "TextEdit")
        let kernel = VirtualDisplayNotebookKernel(sessionID: "not-present")
        let result = try kernel.run(source: #"{"tool":"click","args":{"app":"TextEdit","click_method":"global","x":1,"y":1}}"#)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("Global input is forbidden") == true)
    }
    func testStateListingDoesNotRequireAParticularSession() throws {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "get_virtual_display_state", arguments: [:])
        XCTAssertFalse(result.isError)
        let text = try XCTUnwrap(result.primaryText)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        XCTAssertNotNil(object?["sessions"] as? [[String: Any]])
        let definition = try XCTUnwrap(ToolDefinitions.all.first { $0.name == "get_virtual_display_state" })
        XCTAssertFalse((definition.inputSchema["required"] as? [String] ?? []).contains("session_id"))
    }
    func testConfigurationUsesLogicalDimensionsAndBoundsPixelAllocation() throws {
        try VirtualDisplayConfiguration().validate()
        try VirtualDisplayConfiguration(width: 1920, height: 1080, scale: 2).validate()
        for invalid in [VirtualDisplayConfiguration(width: 0), VirtualDisplayConfiguration(scale: 3), VirtualDisplayConfiguration(width: 7680, scale: 2)] {
            XCTAssertThrowsError(try invalid.validate())
        }
    }
    func testCoordinateConversionHandlesRetinaNegativeOriginAndRejectsOutsidePoints() throws {
        let bounds = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let point = try VirtualDisplayCoordinates.globalPoint(pixel: CGPoint(x: 1920, y: 1080), pixelSize: CGSize(width: 3840, height: 2160), bounds: bounds)
        XCTAssertEqual(point, CGPoint(x: -960, y: 340))
        for outside in [CGPoint(x: -1, y: 20), CGPoint(x: 3840, y: 0), CGPoint(x: CGFloat.nan, y: 0)] {
            XCTAssertThrowsError(try VirtualDisplayCoordinates.globalPoint(pixel: outside, pixelSize: CGSize(width: 3840, height: 2160), bounds: bounds))
        }
    }
    func testVirtualInputRefusesGlobalBeforeSessionLookupEvenWhenEnabled() {
        let dispatcher = ComputerUseToolDispatcher()
        let result = dispatcher.callToolAsResult(name: "click", arguments: ["app": "TextEdit", "session_id": "absent", "click_method": "global", "x": 10, "y": 10])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("Global input is forbidden") == true)
    }
    func testUnverifiedDragIsRejectedBeforeSessionLookup() {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "drag", arguments: ["app": "TextEdit", "session_id": "absent", "from_x": 1, "from_y": 1, "to_x": 10, "to_y": 10])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("unsupported") == true)
        XCTAssertNil(normalizedElementIndexArgument(Double(Int.max)))
    }
    func testAdoptionDoesNotTruncateProcessAndWindowIdentifiers() {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "attach_app_to_virtual_display", arguments: ["app": "TextEdit", "session_id": "absent", "pid": Int64.max, "window_id": 1])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("range") == true)
    }
    func testSessionSchemaIsAdditiveAndWindowSelectionIsSnapshotOnly() throws {
        let tools = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })
        for name in ["click", "get_app_state", "scroll", "drag", "type_text", "press_key", "set_value", "perform_secondary_action"] {
            let schema = try XCTUnwrap(tools[name]?.inputSchema)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertNotNil(properties["session_id"])
            XCTAssertEqual(properties["window_id"] != nil, name == "get_app_state")
            XCTAssertTrue((schema["required"] as? [String])?.contains("app") == true)
        }
        let list = try XCTUnwrap(tools["list_apps"]?.inputSchema["properties"] as? [String: Any])
        XCTAssertNil(list["session_id"])
    }
    func testUnknownSessionAndUnscopedWindowNeverReachLegacyDiscovery() {
        let dispatcher = ComputerUseToolDispatcher()
        let unknown = dispatcher.callToolAsResult(name: "get_app_state", arguments: ["app": "TextEdit", "session_id": "unknown"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.primaryText?.contains("Unknown virtual display") == true)
        let unscoped = dispatcher.callToolAsResult(name: "get_app_state", arguments: ["app": "TextEdit", "window_id": 1])
        XCTAssertTrue(unscoped.isError)
        XCTAssertTrue(unscoped.primaryText?.contains("requires session_id") == true)
    }
}
