import XCTest
@testable import OpenComputerUseKit

final class OpenComputerUseKitTests: XCTestCase {
    func testToolDefinitionCount() {
        XCTAssertEqual(ToolDefinitions.all.count, 9)
    }

    func testKeyPressParserSupportsCommandStyleChord() throws {
        let parsed = try KeyPressParser.parse("super+c")
        XCTAssertEqual(parsed.displayValue, "c")
        XCTAssertEqual(parsed.modifiers.count, 1)
    }

    func testInitializeResponseContainsToolsCapability() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.0"},"capabilities":{}}}"#)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains(#""name":"open-computer-use""#))
        XCTAssertTrue(response!.contains(#""tools":{"listChanged":false}"#))
    }

    func testWindowRelativeFrameUsesSharedGlobalCoordinates() {
        let window = CGRect(x: 1486, y: 556, width: 919, height: 644)
        let child = CGRect(x: 1486, y: 556, width: 919, height: 644)
        let textField = CGRect(x: 180, y: 176, width: 36, height: 18)
        let textFieldGlobal = CGRect(x: window.minX + textField.minX, y: window.minY + textField.minY, width: textField.width, height: textField.height)

        XCTAssertEqual(windowRelativeFrame(elementFrame: child, windowBounds: window), CGRect(x: 0, y: 0, width: 919, height: 644))
        XCTAssertEqual(windowRelativeFrame(elementFrame: textFieldGlobal, windowBounds: window), textField)
    }

    func testToolDescriptionsMatchOfficialComputerUseSurface() {
        let tools = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        XCTAssertEqual(
            tools["get_app_state"]?.description,
            "Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app."
        )
        XCTAssertTrue(tools["press_key"]?.description.contains("xdotool") == true)
        XCTAssertEqual(
            (tools["click"]?.inputSchema["properties"] as? [String: [String: Any]])?["mouse_button"]?["default"] as? String,
            "left"
        )
        XCTAssertEqual(
            (tools["click"]?.inputSchema["properties"] as? [String: [String: Any]])?["click_count"]?["default"] as? Int,
            1
        )
    }

    func testComputerUseErrorsFormatLikeToolText() {
        XCTAssertEqual(ComputerUseError.appNotFound("Sublime Text").errorDescription, #"appNotFound("Sublime Text")"#)
        XCTAssertFalse(ComputerUseError.appNotFound("Sublime Text").toolResultIsError)
        XCTAssertTrue(ComputerUseError.invalidArguments("bad").toolResultIsError)
    }
}
