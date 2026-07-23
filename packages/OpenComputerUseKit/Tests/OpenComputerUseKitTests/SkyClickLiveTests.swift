import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

@MainActor
final class SkyClickLiveTests: XCTestCase {
    private struct WindowRecord {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let name: String
    }

    func testCoveredChromeReceivesExactlyOneSkyClickWithoutForegroundSideEffects() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 to run the isolated Chrome live test")
        }
        let spi = SkyLightSPI.shared
        guard spi.capability.isAvailable else {
            throw XCTSkip("SkyLight SPI unavailable: \(spi.capability.unavailableReason)")
        }

        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: chromeURL.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp {
                _ = originalFrontApp.activate(options: [.activateAllWindows])
            }
        }

        let coverExecutable = Self.packageRoot
            .appendingPathComponent(".build/debug/OpenComputerUseFixture")
        guard FileManager.default.isExecutableFile(atPath: coverExecutable.path) else {
            throw XCTSkip("Build OpenComputerUseFixture before running the live test")
        }
        let coverProbe = try launch(executable: coverExecutable)
        defer {
            stop(coverProbe)
        }
        let coverProbeWindow = try waitForWindow(
            pid: coverProbe.processIdentifier,
            nameContaining: "OpenComputerUseFixture"
        )

        let testRoot = Self.packageRoot.appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("ocu-sky-click-live-\(UUID().uuidString)", isDirectory: true)
        let profileURL = testRoot.appendingPathComponent("chrome-profile", isDirectory: true)
        let pageURL = testRoot.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        // XCTest's temporary directory can reject Foundation's atomic
        // replace/remove dance after a GUI child process gets access to the
        // parent. This page is disposable, so a direct write is sufficient.
        try Self.liveTestHTML.write(to: pageURL, atomically: false, encoding: .utf8)
        defer {
            do {
                try FileManager.default.removeItem(at: testRoot)
            } catch {
                print("sky_click live test cleanup warning: \(error)")
            }
        }

        let targetWidth = Int(min(640, coverProbeWindow.bounds.width - 80))
        let targetHeight = Int(min(480, coverProbeWindow.bounds.height - 80))
        let targetX = Int(coverProbeWindow.bounds.minX + 40)
        let targetY = Int(coverProbeWindow.bounds.minY + 40)

        let chrome = Process()
        chrome.executableURL = chromeURL
        chrome.arguments = [
            "--user-data-dir=\(profileURL.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-component-update",
            "--window-position=\(targetX),\(targetY)",
            "--window-size=\(targetWidth),\(targetHeight)",
            "--app=\(pageURL.absoluteString)",
        ]
        chrome.standardOutput = FileHandle.nullDevice
        chrome.standardError = FileHandle.nullDevice
        try chrome.run()
        defer {
            stop(chrome)
        }

        print("sky_click live test: Chrome launcher pid=\(chrome.processIdentifier)")
        let readyWindow = try waitForWindow(
            pid: chrome.processIdentifier,
            nameContaining: "ocu-sky-click-ready"
        )
        print("sky_click live test: target window=\(readyWindow.id) owner pid=\(readyWindow.pid)")
        stop(coverProbe)
        let cover = try launch(executable: coverExecutable)
        defer {
            stop(cover)
        }
        let coverWindow = try waitForWindow(
            pid: cover.processIdentifier,
            nameContaining: "OpenComputerUseFixture"
        )
        try waitUntil(timeout: 5, failure: "Isolated Chrome remained the frontmost app") {
            guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                return false
            }
            return frontPID != readyWindow.pid
        }
        try waitUntil(timeout: 5, failure: "The cover window did not move above isolated Chrome") {
            let ordered = windows()
            guard
                let currentCoverIndex = ordered.firstIndex(where: { $0.id == coverWindow.id }),
                let currentTargetIndex = ordered.firstIndex(where: { $0.id == readyWindow.id })
            else {
                return false
            }
            return currentCoverIndex < currentTargetIndex
        }

        let orderedBefore = windows()
        guard
            let coveredWindow = orderedBefore.first(where: { $0.id == readyWindow.id }),
            let freshCoverWindow = orderedBefore.first(where: { $0.id == coverWindow.id }),
            let coverIndex = orderedBefore.firstIndex(where: { $0.id == coverWindow.id }),
            let targetIndex = orderedBefore.firstIndex(where: { $0.id == readyWindow.id })
        else {
            return XCTFail("Could not re-read the controlled Chrome and cover windows")
        }
        XCTAssertTrue(
            freshCoverWindow.bounds.contains(coveredWindow.bounds),
            "The controlled Chrome window must be fully covered before sky_click"
        )
        XCTAssertLessThan(coverIndex, targetIndex, "The cover window must be above Chrome in z-order")
        try FixtureBridge.post(
            FixtureCommand(kind: "click", identifier: "fixture-input")
        )
        let foregroundStateBefore = try waitForFixtureState(
            pid: cover.processIdentifier,
            failure: "The foreground fixture did not keep its text field focused"
        ) { state in
            state.isActive == true
                && state.isKeyWindow == true
                && state.focusedIdentifier == "fixture-input"
        }
        print(
            "sky_click live test: cover=\(freshCoverWindow.bounds) target=\(coveredWindow.bounds) "
                + "z-order=\(coverIndex)<\(targetIndex) front-pid="
                + "\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)"
        )

        let frontPIDBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let cursorBefore = CGEvent(source: nil)?.location
        let screenPoint = CGPoint(x: coveredWindow.bounds.midX, y: coveredWindow.bounds.midY)
        let windowPoint = CGPoint(
            x: screenPoint.x - coveredWindow.bounds.minX,
            y: screenPoint.y - coveredWindow.bounds.minY
        )

        try SkyClickDispatcher.click(
            target: SkyClickTarget(
                screenPoint: screenPoint,
                windowPoint: windowPoint,
                windowBounds: coveredWindow.bounds,
                windowID: coveredWindow.id,
                pid: coveredWindow.pid
            ),
            clickCount: 1,
            spi: spi
        )
        print("sky_click live test: event recipe dispatched")

        let clickedWindow = try waitForWindow(pid: readyWindow.pid, nameContaining: "ocu-sky-click-clicked-")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let finalWindow = windows().first(where: { $0.id == clickedWindow.id })
        XCTAssertEqual(finalWindow?.name, "ocu-sky-click-clicked-1", "sky_click must trigger exactly one DOM click")
        XCTAssertEqual(
            NSWorkspace.shared.frontmostApplication?.processIdentifier,
            frontPIDBefore,
            "sky_click must not change the frontmost app"
        )
        let foregroundStateAfter = try waitForFixtureState(
            pid: cover.processIdentifier,
            failure: "The foreground fixture state was unavailable after sky_click"
        ) { _ in true }
        XCTAssertEqual(foregroundStateAfter.isActive, true, "sky_click must keep the foreground app active")
        XCTAssertEqual(foregroundStateAfter.isKeyWindow, true, "sky_click must keep the foreground window key")
        XCTAssertEqual(
            foregroundStateAfter.focusedIdentifier,
            foregroundStateBefore.focusedIdentifier,
            "sky_click must preserve the foreground first responder"
        )
        XCTAssertEqual(
            foregroundStateAfter.activationLossCount,
            foregroundStateBefore.activationLossCount,
            "sky_click must not transiently resign the foreground app"
        )
        XCTAssertEqual(
            foregroundStateAfter.keyWindowLossCount,
            foregroundStateBefore.keyWindowLossCount,
            "sky_click must not transiently resign the foreground key window"
        )

        if let cursorBefore, let cursorAfter = CGEvent(source: nil)?.location {
            XCTAssertLessThan(hypot(cursorAfter.x - cursorBefore.x, cursorAfter.y - cursorBefore.y), 0.5)
        }

        let orderedAfter = windows()
        guard
            let coverIndexAfter = orderedAfter.firstIndex(where: { $0.id == coverWindow.id }),
            let targetIndexAfter = orderedAfter.firstIndex(where: { $0.id == clickedWindow.id })
        else {
            return XCTFail("Could not verify final window z-order")
        }
        XCTAssertLessThan(coverIndexAfter, targetIndexAfter, "sky_click must not raise the Chrome window")
    }

    private func waitForWindow(
        pid: pid_t? = nil,
        nameContaining marker: String,
        timeout: TimeInterval = 10
    ) throws -> WindowRecord {
        var match: WindowRecord?
        do {
            try waitUntil(timeout: timeout, failure: "Timed out waiting for Chrome window title containing \(marker)") {
                match = windows().first(where: { window in
                    (pid == nil || window.pid == pid) && window.name.contains(marker)
                })
                return match != nil
            }
        } catch {
            let observed = windows()
                .filter { pid == nil || $0.pid == pid }
                .map { "\($0.id):\($0.name)" }
                .joined(separator: ", ")
            throw ComputerUseError.message(
                "Timed out waiting for Chrome window title containing \(marker); observed [\(observed)]"
            )
        }
        return try XCTUnwrap(match)
    }

    private func waitUntil(
        timeout: TimeInterval,
        failure: String,
        condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw ComputerUseError.message(failure)
    }

    private func waitForFixtureState(
        pid: pid_t,
        failure: String,
        condition: (FixtureAppState) -> Bool
    ) throws -> FixtureAppState {
        var match: FixtureAppState?
        try waitUntil(timeout: 5, failure: failure) {
            guard
                let state = try? FixtureBridge.readState(),
                state.processIdentifier == pid,
                condition(state)
            else {
                return false
            }
            match = state
            return true
        }
        return try XCTUnwrap(match)
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

    private func launch(executable: URL) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func windows() -> [WindowRecord] {
        let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return rawWindows.compactMap { info in
            guard
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width > 0,
                bounds.height > 0
            else {
                return nil
            }

            return WindowRecord(
                id: number.uint32Value,
                pid: ownerPID.int32Value,
                bounds: bounds,
                name: info[kCGWindowName as String] as? String ?? ""
            )
        }
    }

    private static let liveTestHTML = #"""
    <!doctype html>
    <meta charset="utf-8">
    <title>ocu-sky-click-ready</title>
    <style>
      html, body, button { width: 100%; height: 100%; margin: 0; }
      button { border: 0; font: 24px system-ui; background: #5b8def; color: white; }
    </style>
    <button id="target">sky_click probe</button>
    <script>
      let count = 0;
      document.querySelector('#target').addEventListener('click', () => {
        count += 1;
        document.title = `ocu-sky-click-clicked-${count}`;
      });
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
