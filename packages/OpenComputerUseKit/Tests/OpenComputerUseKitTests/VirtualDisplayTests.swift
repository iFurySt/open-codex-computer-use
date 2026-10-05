import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class VirtualDisplayTests: XCTestCase {
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
