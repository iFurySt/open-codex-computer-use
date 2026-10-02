import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in live regression: a Chrome window parked on another Space (a
/// temporary WindowServer Space when the machine only has one) can still be
/// snapshotted, clicked and typed into from the active Space without changing
/// the active Space or the frontmost app.
@MainActor
final class CrossSpaceLiveTests: XCTestCase {
    private typealias MainCID = @convention(c) () -> UInt32
    private typealias CopySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (UInt32) -> UInt64
    private typealias CopySpacesForWindows = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SetCurrentSpace = @convention(c) (UInt32, CFString, UInt64) -> Void

    func testWindowOnAnotherSpaceIsReadableClickableAndTypable() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 to run the cross-Space live test")
        }
        setvbuf(stdout, nil, _IONBF, 0)
        let spi = SkyLightSPI.shared
        guard spi.capability.isAvailable, spi.occlusionCapability.isAvailable else {
            throw XCTSkip("SkyLight SPI unavailable")
        }
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let cidPtr = dlsym(sky, "SLSMainConnectionID"), let copyPtr = dlsym(sky, "SLSCopyManagedDisplaySpaces"),
              let activePtr = dlsym(sky, "SLSGetActiveSpace"), let setCurrentPtr = dlsym(sky, "SLSManagedDisplaySetCurrentSpace"),
              let spacesForPtr = dlsym(sky, "SLSCopySpacesForWindows")
        else {
            throw XCTSkip("Space SPIs unavailable")
        }
        let cid = unsafeBitCast(cidPtr, to: MainCID.self)()
        let copySpaces = unsafeBitCast(copyPtr, to: CopySpaces.self)
        let activeSpace = unsafeBitCast(activePtr, to: ActiveSpace.self)
        let setCurrentSpace = unsafeBitCast(setCurrentPtr, to: SetCurrentSpace.self)
        let copySpacesForWindows = unsafeBitCast(spacesForPtr, to: CopySpacesForWindows.self)
        var displayIdentifier = ""
        if let list = copySpaces(cid)?.takeRetainedValue() as? [[String: Any]], let first = list.first {
            displayIdentifier = first["Display Identifier"] as? String ?? ""
        }
        func spacesOfWindow(_ id: CGWindowID) -> [UInt64] {
            ((copySpacesForWindows(cid, 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]) ?? []).map(\.uint64Value)
        }
        func userSpaces() -> [UInt64] {
            var ids: [UInt64] = []
            if let displays = copySpaces(cid)?.takeRetainedValue() as? [[String: Any]] {
                for display in displays {
                    for space in (display["Spaces"] as? [[String: Any]]) ?? [] where (space["type"] as? NSNumber)?.intValue == 0 {
                        if let id = (space["id64"] as? NSNumber)?.uint64Value { ids.append(id) }
                    }
                }
            }
            return ids
        }

        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: chromeURL.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        // Third-party processes cannot move other apps' windows between Spaces on
        // macOS 26+ (SLSMoveWindowsToManagedSpace is gated on the window-management
        // bridge), so launch the target while the other Desktop is active instead.
        let homeSpace = activeSpace(cid)
        guard let otherSpace = userSpaces().first(where: { $0 != homeSpace }) else {
            throw XCTSkip("Create a second Desktop in Mission Control to run the cross-Space live test")
        }
        setCurrentSpace(cid, displayIdentifier as CFString, otherSpace)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(activeSpace(cid), otherSpace, "test setup must switch to the second Desktop")
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp { _ = originalFrontApp.activate(options: [.activateAllWindows]) }
        }
        let testRoot = Self.packageRoot.appendingPathComponent(".build/ocu-cross-space-\(UUID().uuidString)", isDirectory: true)
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
        let window = try waitForWindow(pid: chrome.processIdentifier, nameContaining: "ocu-space-", onScreenOnly: true)
        guard let runningChrome = NSRunningApplication(processIdentifier: window.pid) else { return XCTFail("Chrome not running") }
        let descriptor = RunningAppDescriptor(name: runningChrome.localizedName ?? "Google Chrome", bundleIdentifier: runningChrome.bundleIdentifier, pid: window.pid, runningApplication: runningChrome)
        _ = runningChrome.activate(options: [.activateAllWindows])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(spacesOfWindow(window.id), [otherSpace], "Chrome must have opened on the second Desktop")

        // Phase 1: visible snapshot (on the second Desktop) pins the window.
        let visibleSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)
        XCTAssertTrue(visibleSnapshot.treeLines.contains { $0.contains("sky probe") }, "visible snapshot must include web content")
        XCTAssertTrue(WindowOcclusionKeepAlive.shared.isPinned(windowID: window.id))

        // Back to the user's Desktop; bring the fixture to the front there.
        setCurrentSpace(cid, displayIdentifier as CFString, homeSpace)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(activeSpace(cid), homeSpace)
        let fixture = try launch(executable: Self.packageRoot.appendingPathComponent(".build/debug/OpenComputerUseFixture"))
        defer { stop(fixture) }
        _ = try waitForWindow(pid: fixture.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let parked = try waitForWindow(pid: window.pid, nameContaining: "ocu-space-", onScreenOnly: false)
        print("cross-space live test: parked window spaces=\(spacesOfWindow(window.id)) onScreen=\(parked.onScreen) title=\(parked.name) activeSpace=\(activeSpace(cid)) home=\(homeSpace) other=\(otherSpace)")
        XCTAssertEqual(spacesOfWindow(window.id), [otherSpace], "the window must live on the other Space")
        XCTAssertEqual(activeSpace(cid), homeSpace, "parking the window must not switch Spaces")
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        XCTAssertNotEqual(frontBefore, window.pid)

        // Phase 2: production paths against the parked window.
        let parkedSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)
        XCTAssertEqual(parkedSnapshot.targetWindowID, window.id, "snapshot must resolve the off-screen window")
        XCTAssertTrue(parkedSnapshot.treeLines.contains { $0.contains("sky probe") }, "parked snapshot must include web content")
        XCTAssertNotNil(parkedSnapshot.screenshotPNGData, "parked window must still be captured")
        XCTAssertEqual(activeSpace(cid), homeSpace, "snapshot must not switch Spaces")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "snapshot must not activate Chrome")

        let windowPoint = CGPoint(x: parked.bounds.width / 2, y: parked.bounds.height - 60)
        try SkyClickDispatcher.click(
            target: SkyClickTarget(
                screenPoint: CGPoint(x: parked.bounds.minX + windowPoint.x, y: parked.bounds.minY + windowPoint.y),
                windowPoint: windowPoint, windowBounds: parked.bounds, windowID: window.id, pid: window.pid),
            clickCount: 1, spi: spi)
        let clicked = try waitForWindow(pid: window.pid, nameContaining: "clicks=1", onScreenOnly: false)
        XCTAssertTrue(clicked.name.contains("clicks=1"), "sky_click must reach the parked window")

        try SkyKeyboardDispatcher.typeText(target: SkyKeyboardTarget(windowID: window.id, pid: window.pid), text: "s2", spi: spi)
        try SkyKeyboardDispatcher.pressKey(target: SkyKeyboardTarget(windowID: window.id, pid: window.pid), key: "cmd+a", spi: spi)
        try SkyKeyboardDispatcher.typeText(target: SkyKeyboardTarget(windowID: window.id, pid: window.pid), text: "Ok", spi: spi)
        let typed = try waitForWindow(pid: window.pid, nameContaining: "ocu-space-Ok|", onScreenOnly: false)
        print("cross-space live test: after typing title=\(typed.name)")
        XCTAssertTrue(typed.name.hasPrefix("ocu-space-Ok|clicks=1|"), "sky_key must type and select-all on the parked window")

        XCTAssertEqual(activeSpace(cid), homeSpace, "actions must not switch Spaces")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "actions must not activate Chrome")
        XCTAssertEqual(spacesOfWindow(window.id), [otherSpace], "the window must stay on the other Space")
        WindowOcclusionKeepAlive.shared.releaseAll()
    }

    private struct WindowRecord { let id: CGWindowID; let pid: pid_t; let bounds: CGRect; let name: String; let onScreen: Bool }

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
                return WindowRecord(id: number.uint32Value, pid: pid, bounds: bounds, name: name, onScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
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
    <!doctype html><meta charset="utf-8"><title>ocu-space-ready</title>
    <style>html,body{margin:0;height:100%} input{width:90%;font:22px system-ui;margin:20px} button{position:absolute;left:0;right:0;bottom:0;height:120px;font:22px system-ui;background:#5b8def;color:#fff;border:0}</style>
    <p>sky probe paragraph</p><input id="t" autofocus placeholder="sky probe"><button id="b">click probe</button>
    <script>
      let clicks = 0; const input = document.querySelector('#t');
      const update = () => { document.title = `ocu-space-${input.value}|clicks=${clicks}|${document.visibilityState}`; };
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
