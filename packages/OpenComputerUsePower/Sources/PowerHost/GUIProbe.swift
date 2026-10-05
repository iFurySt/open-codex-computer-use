import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import IOKit
import PowerCore

// Explicit attended probe. It never unlocks the session or requests TCC permissions.
enum PowerGUIProbe {
    static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    static func find(_ root: AXUIElement, id: String, depth: Int = 0) -> AXUIElement? {
        if attribute(root, "AXIdentifier" as CFString) as? String == id { return root }
        guard depth < 8, let children = attribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] else { return nil }
        for child in children.prefix(64) { if let match = find(child, id: id, depth: depth + 1) { return match } }
        return nil
    }
    static func lidClosed() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerFailure.backend("Cannot read lid state") }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { throw PowerFailure.backend("This device does not expose lid state") }
        return value.boolValue
    }
    static func capture(pid: Int32) throws -> Data {
        let done = DispatchSemaphore(value: 0)
        final class ResultBox: @unchecked Sendable { var result: Result<Data, Error>? }
        let box = ResultBox()
        Task.detached {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.title == "OCU Power GUI Probe \(pid)" }) else { throw PowerFailure.backend("Probe window is not capturable") }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration(); config.width = 360; config.height = 220; config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let representation = NSBitmapImageRep(cgImage: image)
                guard let png = representation.representation(using: .png, properties: [:]) else { throw PowerFailure.backend("Cannot encode probe screenshot") }
                box.result = .success(png)
            } catch { box.result = .failure(error) }
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success, let result = box.result else { throw PowerFailure.backend("Probe capture timed out") }
        return try result.get()
    }
    static func run(waitForClosedLid: Bool, seconds: Double, displayID: UInt32?, connection: PowerClient) throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw PowerFailure.backend("GUI probe requires Accessibility and Screen Recording for the signed Power app") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("OCUPowerGUIFixture")
        guard FileManager.default.isExecutableFile(atPath: fixture.path) else { throw PowerFailure.backend("Build the Power app bundle or all package products before running GUI probe") }
        if let displayID {
            var count: UInt32 = 0; var displays = [CGDirectDisplayID](repeating: 0, count: 64)
            guard CGGetOnlineDisplayList(64, &displays, &count) == .success, displays.prefix(Int(count)).contains(displayID) else { throw PowerFailure.invalid("Requested display is not online") }
        }
        var options = HoldOptions(); options.lifetime = .connection; options.preventLidSleep = waitForClosedLid
        let hold = try connection.acquire(options)
        defer { try? connection.release(hold.id) }
        let ownerPipe = Pipe()
        let target = Process(); target.executableURL = fixture
        target.standardInput = ownerPipe; target.arguments = ["--probe-owner"] + (displayID.map { ["--display-id", String($0)] } ?? [])
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try target.run()
        defer { try? ownerPipe.fileHandleForWriting.close(); if target.isRunning { target.terminate(); target.waitUntilExit() } }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        var button: AXUIElement?, counter: AXUIElement?
        let readyDeadline = PowerClock.now + 5
        repeat {
            button = find(app, id: "power-increment"); counter = find(app, id: "power-counter")
            if button != nil && counter != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while PowerClock.now < readyDeadline
        guard let button, let counter else { throw PowerFailure.backend("Real fixture AX controls unavailable") }
        if !waitForClosedLid, NSWorkspace.shared.frontmostApplication?.processIdentifier != frontmost { throw PowerFailure.backend("Fixture launch changed physical foreground application") }
        if waitForClosedLid {
            fputs("Ready: close the lid within 60 seconds; probe never unlocks the session.\n", stderr)
            let deadline = PowerClock.now + 60
            while try !lidClosed(), PowerClock.now < deadline { Thread.sleep(forTimeInterval: 0.25) }
            guard try lidClosed() else { throw PowerFailure.backend("Lid was not closed; closed-lid acceptance remains unverified") }
        }
        var checks = 0
        let deadline = PowerClock.now + seconds
        repeat {
            if waitForClosedLid { guard try lidClosed() else { throw PowerFailure.backend("Lid opened before the test interval finished") } }
            guard try connection.status(hold.id).holds.first?.phase == "active" else { throw PowerFailure.backend("Power hold is no longer active") }
            let before = try capture(pid: target.processIdentifier)
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { throw PowerFailure.backend("AXPress did not succeed") }
            checks += 1
            let expected = "Count: \(checks)"
            let until = PowerClock.now + 2
            while attribute(counter, kAXValueAttribute as CFString) as? String != expected, PowerClock.now < until { Thread.sleep(forTimeInterval: 0.05) }
            guard attribute(counter, kAXValueAttribute as CFString) as? String == expected else { throw PowerFailure.backend("AX counter did not change") }
            let after = try capture(pid: target.processIdentifier)
            guard before != after else { throw PowerFailure.backend("Captured window did not change after real AX action") }
            Thread.sleep(forTimeInterval: 1)
        } while PowerClock.now < deadline
        struct Report: Encodable { let verified: Bool; let closed_lid: Bool; let checks: Int; let seconds: Double }
        try output(Report(verified: true, closed_lid: waitForClosedLid, checks: checks, seconds: seconds))
    }
}
