#if canImport(JavaScriptCore)
import XCTest
@testable import OpenComputerUseKit

final class JavaScriptToolRuntimeTests: XCTestCase {
    private func runtime(_ caller: @escaping JavaScriptToolRuntime.ToolCaller = { _, _ in .text("ok") }) -> JavaScriptToolRuntime {
        JavaScriptToolRuntime(toolCaller: caller)
    }

    func testWriteProducesText() {
        let result = runtime().run(code: "write(\"hello\"); write(\" world\");", timeoutMs: 5000)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "hello world")
    }

    func testConsoleLog() {
        let result = runtime().run(code: "console.log(\"a\", 1);", timeoutMs: 5000)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "a 1\n")
    }

    func testCuaCallReachesTheToolCaller() {
        var seen: (String, [String: Any])?
        let rt = runtime { tool, args in
            seen = (tool, args)
            return .text("APP LIST")
        }
        let result = rt.run(code: "write(cua.listApps());", timeoutMs: 5000)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "APP LIST")
        XCTAssertEqual(seen?.0, "list_apps")
    }

    func testCuaForwardsArguments() {
        var seen: [String: Any]?
        let rt = runtime { tool, args in
            if tool == "click" { seen = args }
            return .text("clicked")
        }
        _ = rt.run(code: "cua.click(\"Notes\", { element_index: \"7\" });", timeoutMs: 5000)
        XCTAssertEqual(seen?["app"] as? String, "Notes")
        XCTAssertEqual(seen?["element_index"] as? String, "7")
    }

    func testToolErrorBecomesAThrownError() {
        let rt = runtime { _, _ in .text("no such window", isError: true) }
        let result = rt.run(code: "cua.click(\"Ghost\");", timeoutMs: 5000)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("no such window") ?? false)
    }

    func testCatchableToolError() {
        let rt = runtime { _, _ in .text("boom", isError: true) }
        let result = rt.run(
            code: "try { cua.click(\"X\"); } catch (e) { write(\"caught: \" + e.message); }",
            timeoutMs: 5000
        )
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "caught: boom")
    }

    func testRecursionGuardRejectsJs() {
        let result = runtime().run(code: "cua.call(\"js\", { code: \"1\" });", timeoutMs: 5000)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("cannot be called from inside js") ?? false)
    }

    func testGlobalThisPersistsAcrossCalls() {
        let rt = runtime()
        _ = rt.run(code: "globalThis.counter = 41;", timeoutMs: 5000)
        let result = rt.run(code: "write(String(globalThis.counter + 1));", timeoutMs: 5000)
        XCTAssertEqual(result.primaryText, "42")
    }

    func testResetClearsBindings() {
        let rt = runtime()
        _ = rt.run(code: "globalThis.keep = 1;", timeoutMs: 5000)
        rt.reset()
        let result = rt.run(code: "write(String(globalThis.keep));", timeoutMs: 5000)
        XCTAssertEqual(result.primaryText, "undefined")
    }

    func testLetDoesNotCollideAcrossCalls() {
        let rt = runtime()
        _ = rt.run(code: "let x = 1; write(String(x));", timeoutMs: 5000)
        let result = rt.run(code: "let x = 2; write(String(x));", timeoutMs: 5000)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "2")
    }

    func testTimeoutTerminatesRunawayScript() {
        let result = runtime().run(code: "while (true) {}", timeoutMs: 300)
        XCTAssertTrue(result.isError)
    }

    func testScreenshotRoundTripsImage() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
        let rt = runtime { _, _ in
            ToolCallResult(content: [.text("tree text"), .pngImage(bytes)])
        }
        let result = rt.run(code: "write(cua.screenshot(\"X\"));", timeoutMs: 5000)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.primaryText, "tree text")
        let imageItems = result.content.filter { $0.dictionary["type"] as? String == "image" }
        XCTAssertEqual(imageItems.count, 1)
        XCTAssertEqual(imageItems.first?.dictionary["data"] as? String, bytes.base64EncodedString())
    }
}
#endif
