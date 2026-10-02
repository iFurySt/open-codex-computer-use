import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in live regression: a snapshot taken while an isolated Chrome window is
/// visible pins its visible state, so after another window fully covers it the
/// next snapshot still contains the web content and the page stays visible.
@MainActor
final class OcclusionKeepAliveLiveTests: XCTestCase {
    func testCoveredChromeKeepsWebContentAfterVisibleSnapshot() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 to run the isolated Chrome live test")
        }
        let spi = SkyLightSPI.shared
        guard spi.occlusionCapability.isAvailable else {
            throw XCTSkip("SkyLight occlusion SPI unavailable: \(spi.occlusionCapability.unavailableReason)")
        }
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: chromeURL.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        let coverExecutable = Self.packageRoot.appendingPathComponent(".build/debug/OpenComputerUseFixture")
        guard FileManager.default.isExecutableFile(atPath: coverExecutable.path) else {
            throw XCTSkip("Build OpenComputerUseFixture before running the live test")
        }
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp {
                _ = originalFrontApp.activate(options: [.activateAllWindows])
            }
        }

        let testRoot = Self.packageRoot.appendingPathComponent(".build/ocu-occlusion-live-\(UUID().uuidString)", isDirectory: true)
        let profileURL = testRoot.appendingPathComponent("chrome-profile", isDirectory: true)
        let pageURL = testRoot.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Self.liveTestHTML.write(to: pageURL, atomically: false, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: testRoot)
        }

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
        defer {
            stop(chrome)
        }
        let window = try waitForWindow(pid: chrome.processIdentifier, nameContaining: "ocu-occlusion-", onScreenOnly: true)
        guard let runningChrome = NSRunningApplication(processIdentifier: window.pid) else {
            return XCTFail("Chrome is not a running application")
        }
        let descriptor = RunningAppDescriptor(
            name: runningChrome.localizedName ?? "Google Chrome",
            bundleIdentifier: runningChrome.bundleIdentifier,
            pid: window.pid,
            runningApplication: runningChrome
        )

        // Chrome is visible: this snapshot must see web content and pin the window.
        _ = runningChrome.activate(options: [.activateAllWindows])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let visibleSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)

        XCTAssertTrue(visibleSnapshot.treeLines.contains { $0.contains("sky probe") }, "visible snapshot must include the web content")
        XCTAssertTrue(WindowOcclusionKeepAlive.shared.isPinned(windowID: window.id), "the visible window must be pinned")
        XCTAssertEqual(visibleSnapshot.targetWindowID, window.id)

        let cover = try launch(executable: coverExecutable)
        defer {
            stop(cover)
        }
        _ = try waitForWindow(pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let coverBounds = try XCTUnwrap(waitForWindow(pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true).bounds)
        XCTAssertTrue(coverBounds.contains(window.bounds), "the fixture must fully cover Chrome")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid)

        let pageTitle = try waitForWindow(pid: window.pid, nameContaining: "ocu-occlusion-", onScreenOnly: false).name
        XCTAssertTrue(pageTitle.hasSuffix("vis=visible"), "Chrome must still consider the covered page visible, got \(pageTitle)")

        let coveredSnapshot = try SnapshotBuilder.build(for: descriptor, recoveryPolicy: .readOnly)

        XCTAssertTrue(coveredSnapshot.treeLines.contains { $0.contains("sky probe") }, "covered snapshot must still include the web content")
        XCTAssertFalse(coveredSnapshot.treeLines.contains { $0.hasPrefix("Note: this window is covered") })
        XCTAssertNotNil(coveredSnapshot.screenshotPNGData)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "snapshots must not activate Chrome")

        WindowOcclusionKeepAlive.shared.releaseAll()
        XCTAssertFalse(WindowOcclusionKeepAlive.shared.isPinned(windowID: window.id))
    }

    private struct WindowRecord {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let name: String
    }

    private func waitForWindow(pid: pid_t, nameContaining marker: String, onScreenOnly: Bool) throws -> WindowRecord {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            for info in raw {
                guard
                    let number = info[kCGWindowNumber as String] as? NSNumber,
                    let owner = info[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                    let name = info[kCGWindowName as String] as? String, name.contains(marker),
                    let bounds = CGRect(dictionaryRepresentation: (info[kCGWindowBounds as String] as? NSDictionary) ?? [:]),
                    bounds.width > 0
                else {
                    continue
                }
                return WindowRecord(id: number.uint32Value, pid: pid, bounds: bounds, name: name)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw ComputerUseError.message("Timed out waiting for window title containing \(marker)")
    }

    private func launch(executable: URL) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func stop(_ process: Process) {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private static let liveTestHTML = #"""
    <!doctype html>
    <meta charset="utf-8">
    <title>ocu-occlusion-ready</title>
    <p>sky probe paragraph</p>
    <input id="target" autofocus placeholder="sky probe">
    <script>
      const update = () => { document.title = `ocu-occlusion-${document.visibilityState === 'visible' ? 'vis=visible' : 'vis=hidden'}`; };
      document.addEventListener('visibilitychange', update);
      update();
    </script>
    """#

    private static let packageRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }()
}
