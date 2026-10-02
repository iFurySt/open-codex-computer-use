import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in benchmark: N cycles of sky_click and sky_key against a fully covered
/// isolated Chrome window. Reports success counts and latency percentiles
/// (dispatch = time until the call returns; observed = time until the page
/// reflected the action). `OPEN_COMPUTER_USE_BENCH_CYCLES` sets N (default 20).
@MainActor
final class BackgroundInputBenchmarkLiveTests: XCTestCase {
    func testCoveredChromeClickAndKeyLatency() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH=1 to run the background input benchmark")
        }
        setvbuf(stdout, nil, _IONBF, 0)
        let cycles = Int(ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_BENCH_CYCLES"] ?? "") ?? 20
        let spi = SkyLightSPI.shared
        guard spi.capability.isAvailable else { throw XCTSkip("SkyLight SPI unavailable") }
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: chromeURL.path) else { throw XCTSkip("Chrome missing") }
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer { if let originalFrontApp { _ = originalFrontApp.activate(options: [.activateAllWindows]) } }

        let testRoot = Self.packageRoot.appendingPathComponent(".build/ocu-bench-\(UUID().uuidString)", isDirectory: true)
        let profileURL = testRoot.appendingPathComponent("chrome-profile", isDirectory: true)
        let pageURL = testRoot.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Self.html.write(to: pageURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let chrome = Process()
        chrome.executableURL = chromeURL
        chrome.arguments = ["--user-data-dir=\(profileURL.path)", "--no-first-run", "--no-default-browser-check", "--disable-background-networking", "--disable-component-update", "--window-position=200,200", "--window-size=600,420", "--app=\(pageURL.absoluteString)"]
        chrome.standardOutput = FileHandle.nullDevice; chrome.standardError = FileHandle.nullDevice
        try chrome.run()
        defer { stop(chrome) }
        let window = try waitForWindow(pid: chrome.processIdentifier, nameContaining: "ocu-bench-")
        // Pin visibility while visible (what get_app_state does), then cover it.
        let pinned = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_BENCH_UNPINNED"] != "1"
        if pinned { WindowOcclusionKeepAlive.shared.keepVisible(windowID: window.id, bounds: window.bounds, spi: spi) }
        defer { WindowOcclusionKeepAlive.shared.releaseAll() }
        let cover = try launch(executable: Self.packageRoot.appendingPathComponent(".build/debug/OpenComputerUseFixture"))
        defer { stop(cover) }
        _ = try waitForWindow(pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture")
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid)

        func title() -> String {
            let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
            for info in raw {
                if let n = info[kCGWindowNumber as String] as? NSNumber, n.uint32Value == window.id { return info[kCGWindowName as String] as? String ?? "" }
            }
            return ""
        }
        func observe(_ marker: String, timeout: TimeInterval = 3) -> TimeInterval? {
            let start = ProcessInfo.processInfo.systemUptime
            while ProcessInfo.processInfo.systemUptime - start < timeout {
                if title().contains(marker) { return ProcessInfo.processInfo.systemUptime - start }
                Thread.sleep(forTimeInterval: 0.003)
            }
            return nil
        }
        let windowPoint = CGPoint(x: window.bounds.width / 2, y: window.bounds.height - 60)
        let clickTarget = SkyClickTarget(screenPoint: CGPoint(x: window.bounds.minX + windowPoint.x, y: window.bounds.minY + windowPoint.y), windowPoint: windowPoint, windowBounds: window.bounds, windowID: window.id, pid: window.pid)
        let keyTarget = SkyKeyboardTarget(windowID: window.id, pid: window.pid)

        var clickDispatch: [Double] = [], clickObserved: [Double] = [], keyDispatch: [Double] = [], keyObserved: [Double] = []
        var clickOK = 0, keyOK = 0
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for cycle in 1...cycles {
            let c0 = ProcessInfo.processInfo.systemUptime
            try SkyClickDispatcher.click(target: clickTarget, clickCount: 1, spi: spi)
            let cDispatch = ProcessInfo.processInfo.systemUptime - c0
            if let seen = observe("clicks=\(cycle)|") { clickOK += 1; clickObserved.append((cDispatch + seen) * 1000) }
            clickDispatch.append(cDispatch * 1000)

            let k0 = ProcessInfo.processInfo.systemUptime
            try SkyKeyboardDispatcher.typeText(target: keyTarget, text: "k\(cycle).", spi: spi)
            let kDispatch = ProcessInfo.processInfo.systemUptime - k0
            if let seen = observe("k\(cycle).|") { keyOK += 1; keyObserved.append((kDispatch + seen) * 1000) }
            keyDispatch.append(kDispatch * 1000)
        }
        let frontAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
        func pct(_ values: [Double], _ p: Double) -> Double {
            guard !values.isEmpty else { return .nan }
            let sorted = values.sorted(); let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
            return sorted[index]
        }
        func row(_ name: String, _ values: [Double]) -> String {
            String(format: "BENCH %-22@ n=%2d p50=%7.1fms p95=%7.1fms max=%7.1fms", name, values.count, pct(values, 0.5), pct(values, 0.95), values.max() ?? .nan)
        }
        print("BENCH cycles=\(cycles) pinned=\(pinned) keySettle=\(Int(SkyKeyboardDispatcher.keyWindowFallbackSettle * 1000))ms release=\(Int(SkyKeyboardDispatcher.releaseSettle * 1000))ms target=covered isolated Chrome (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
        print("BENCH sky_click success \(clickOK)/\(cycles)   sky_key success \(keyOK)/\(cycles)   frontmost unchanged=\(frontBefore == frontAfter)")
        print(row("sky_click dispatch", clickDispatch)); print(row("sky_click observed", clickObserved))
        print(row("sky_key dispatch", keyDispatch)); print(row("sky_key observed", keyObserved))
        XCTAssertEqual(clickOK, cycles, "every background click must land")
        XCTAssertEqual(keyOK, cycles, "every background key must land")
        XCTAssertEqual(frontBefore, frontAfter)
    }

    private struct WindowRecord { let id: CGWindowID; let pid: pid_t; let bounds: CGRect; let name: String }
    private func waitForWindow(pid: pid_t, nameContaining marker: String) throws -> WindowRecord {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            for info in raw {
                guard let n = info[kCGWindowNumber as String] as? NSNumber, let owner = info[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                      let name = info[kCGWindowName as String] as? String, name.contains(marker),
                      let b = CGRect(dictionaryRepresentation: (info[kCGWindowBounds as String] as? NSDictionary) ?? [:]), b.width > 0 else { continue }
                return WindowRecord(id: n.uint32Value, pid: pid, bounds: b, name: name)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw ComputerUseError.message("timeout \(marker)")
    }
    private func launch(executable: URL) throws -> Process { let p = Process(); p.executableURL = executable; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try p.run(); return p }
    private func stop(_ process: Process) {
        if process.isRunning { process.terminate(); let d = Date().addingTimeInterval(5); while process.isRunning, Date() < d { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) } }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    private static let html = #"""
    <!doctype html><meta charset="utf-8"><title>ocu-bench-ready</title>
    <style>html,body{margin:0;height:100%} input{width:90%;font:22px system-ui;margin:20px} button{position:absolute;left:0;right:0;bottom:0;height:120px;font:22px system-ui;background:#5b8def;color:#fff;border:0}</style>
    <input id="t" autofocus><button id="b">probe</button>
    <script>
      let clicks = 0; const input = document.querySelector('#t');
      const update = () => { document.title = `ocu-bench-${input.value.slice(-12)}|clicks=${clicks}|`; };
      document.querySelector('#b').addEventListener('click', () => { clicks += 1; update(); });
      input.addEventListener('input', update); update();
    </script>
    """#
    private static let packageRoot: URL = { var url = URL(fileURLWithPath: #filePath); for _ in 0..<5 { url.deleteLastPathComponent() }; return url }()
}
