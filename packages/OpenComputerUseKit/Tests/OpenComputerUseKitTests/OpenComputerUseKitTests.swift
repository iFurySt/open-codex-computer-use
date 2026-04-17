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

    func testToolDescriptionsExposeIntrusionHints() {
        let tools = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0.description) })

        XCTAssertTrue(tools["get_app_state"]?.contains("without activating") == true)
        XCTAssertTrue(tools["press_key"]?.contains("super+n") == true)
        XCTAssertTrue(tools["type_text"]?.contains("target app PID") == true)
        XCTAssertTrue(tools["drag"]?.contains("moves the real pointer") == true)
    }
}
