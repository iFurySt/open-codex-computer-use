import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in live regression: a Chrome window that is already hidden (fully
/// covered) when the agent first sees it is parked on the agent display via
/// `window_placement=agent_display`; the next snapshot has the web content and
/// a screenshot, clicks and keys land, the user's Space, frontmost app and
/// pointer are untouched, and `restore` puts the window back and removes the
/// display.
@MainActor
final class AgentDisplayLiveTests: XCTestCase {
    func testHiddenChromeIsParkedOnTheAgentDisplayAndRestored() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST=1 to run the agent display live test")
        }
        setvbuf(stdout, nil, _IONBF, 0)
        guard AgentDisplay.shared.isSupported else {
            throw XCTSkip("CGVirtualDisplay is unavailable on this macOS")
        }
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: chromeURL.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp { _ = originalFrontApp.activate(options: [.activateAllWindows]) }
        }
        let testRoot = Self.packageRoot.appendingPathComponent(".build/ocu-agent-display-\(UUID().uuidString)", isDirectory: true)
        let profileURL = testRoot.appendingPathComponent("chrome-profile", isDirectory: true)
        let pageURL = testRoot.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Self.liveTestHTML.write(to: pageURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let chrome = Process()
        chrome.executableURL = chromeURL
        chrome.arguments = [
            "--user-data-dir=\(profileURL.path)", "--no-first-run", "--no-default-browser-check",
            "--disable-background-networking", "--disable-component-update",
            "--window-position=200,200", "--window-size=600,420", "--app=\(pageURL.absoluteString)",
        ]
        chrome.standardOutput = FileHandle.nullDevice
        chrome.standardError = FileHandle.nullDevice
        try chrome.run()
        defer { stop(chrome) }
        let window = try waitForWindow(pid: chrome.processIdentifier, nameContaining: "ocu-agent-", onScreenOnly: true)
        guard let runningChrome = NSRunningApplication(processIdentifier: window.pid) else { return XCTFail("Chrome not running") }
        let descriptor = RunningAppDescriptor(name: runningChrome.localizedName ?? "Google Chrome", bundleIdentifier: runningChrome.bundleIdentifier, pid: window.pid, runningApplication: runningChrome)

        // Cover Chrome before the agent ever looks at it: worst case, the page is hidden.
        let cover = try launch(executable: Self.packageRoot.appendingPathComponent(".build/debug/OpenComputerUseFixture"))
        defer { stop(cover) }
        _ = try waitForWindow(pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let hiddenTitle = try waitForWindow(pid: window.pid, nameContaining: "ocu-agent-", onScreenOnly: false).name
        XCTAssertTrue(hiddenTitle.hasSuffix("hidden"), "Chrome must have hidden the covered page, got \(hiddenTitle)")
        let hiddenSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)
        XCTAssertFalse(hiddenSnapshot.treeLines.contains { $0.contains("sky probe paragraph") }, "hidden page must not expose web content")
        XCTAssertTrue(hiddenSnapshot.treeLines.contains { $0.hasPrefix("Note: this window is covered") })

        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let mouseBefore = NSEvent.mouseLocation
        var displayCountBefore: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCountBefore)

        // Park on the agent display through the same call the tool uses.
        let windowElement = try XCTUnwrap(hiddenSnapshot.windowElement)
        let displayBounds = try AgentDisplay.shared.park(windowID: window.id, pid: window.pid, window: windowElement)
        defer { AgentDisplay.shared.restoreAll() }
        let parked = try waitForWindow(pid: window.pid, nameContaining: "ocu-agent-", onScreenOnly: false)
        print("agent display live test: display=\(displayBounds) parked=\(parked.bounds) title=\(parked.name)")
        XCTAssertTrue(displayBounds.contains(CGPoint(x: parked.bounds.minX + 1, y: parked.bounds.minY + 1)), "the window must sit on the agent display")
        let visibleTitle = try waitForWindow(pid: window.pid, nameContaining: "visible", onScreenOnly: false).name
        XCTAssertTrue(visibleTitle.hasSuffix("visible"), "Chrome must consider the parked page visible")

        let parkedSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)
        XCTAssertEqual(parkedSnapshot.targetWindowID, window.id)
        XCTAssertTrue(parkedSnapshot.treeLines.contains { $0.contains("sky probe paragraph") }, "parked snapshot must include web content")
        XCTAssertNotNil(parkedSnapshot.screenshotPNGData)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontBefore, "parking must not change the frontmost app")
        XCTAssertEqual(NSEvent.mouseLocation, mouseBefore, "parking must not move the pointer")

        let spi = SkyLightSPI.shared
        let windowPoint = CGPoint(x: parked.bounds.width / 2, y: parked.bounds.height - 60)
        try SkyClickDispatcher.click(
            target: SkyClickTarget(
                screenPoint: CGPoint(x: parked.bounds.minX + windowPoint.x, y: parked.bounds.minY + windowPoint.y),
                windowPoint: windowPoint, windowBounds: parked.bounds, windowID: window.id, pid: window.pid),
            clickCount: 1, spi: spi)
        try SkyKeyboardDispatcher.typeText(target: SkyKeyboardTarget(windowID: window.id, pid: window.pid), text: "ok", spi: spi)
        let acted = try waitForWindow(pid: window.pid, nameContaining: "ocu-agent-ok|clicks=1|", onScreenOnly: false)
        XCTAssertTrue(acted.name.hasPrefix("ocu-agent-ok|clicks=1|"), "click and keys must reach the parked window")

        // Restore: window back where it was, display gone.
        try AgentDisplay.shared.restore(windowID: window.id)
        let restored = try waitForWindow(pid: window.pid, nameContaining: "ocu-agent-", onScreenOnly: false)
        XCTAssertEqual(restored.bounds.origin, window.bounds.origin, "restore must put the window back")
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        var displayCountAfter: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCountAfter)
        XCTAssertEqual(displayCountAfter, displayCountBefore, "the agent display must be removed after restore")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontBefore)
    }

    private struct WindowRecord { let id: CGWindowID; let pid: pid_t; let bounds: CGRect; let name: String }

    private func waitForWindow(pid: pid_t, nameContaining marker: String, onScreenOnly: Bool) throws -> WindowRecord {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            for info in raw {
                guard let number = info[kCGWindowNumber as String] as? NSNumber,
                      let owner = info[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                      let name = info[kCGWindowName as String] as? String, name.contains(marker),
                      let bounds = CGRect(dictionaryRepresentation: (info[kCGWindowBounds as String] as? NSDictionary) ?? [:]), bounds.width > 0
                else { continue }
                return WindowRecord(id: number.uint32Value, pid: pid, bounds: bounds, name: name)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw ComputerUseError.message("Timed out waiting for window title containing \(marker)")
    }

    private func launch(executable: URL) throws -> Process {
        let process = Process(); process.executableURL = executable
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); return process
    }

    private func stop(_ process: Process) {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private static let liveTestHTML = #"""
    <!doctype html><meta charset="utf-8"><title>ocu-agent-ready</title>
    <style>html,body{margin:0;height:100%} input{width:90%;font:22px system-ui;margin:20px} button{position:absolute;left:0;right:0;bottom:0;height:120px;font:22px system-ui;background:#5b8def;color:#fff;border:0}</style>
    <p>sky probe paragraph</p><input id="t" autofocus placeholder="sky probe"><button id="b">click probe</button>
    <script>
      let clicks = 0; const input = document.querySelector('#t');
      const update = () => { document.title = `ocu-agent-${input.value}|clicks=${clicks}|${document.visibilityState}`; };
      document.querySelector('#b').addEventListener('click', () => { clicks += 1; update(); });
      input.addEventListener('input', update); document.addEventListener('visibilitychange', update); update();
    </script>
    """#

    private static let packageRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()
}
