import AppKit
import CoreGraphics
import Foundation
import OpenComputerUseKit

func multiSessionChecks() throws {
    let registry = VirtualDisplaySessionRegistry.shared
    let originalDisplays = Set(VirtualDisplaySessionRegistry.onlineDisplayIDs())
    let first = try registry.create()
    defer { try? registry.destroyAll() }
    let firstCapture = try registry.capture(sessionID: first.sessionID)
    let second = try registry.create(configuration: .init(scale: 2))
    let secondCapture = try registry.capture(sessionID: second.sessionID)
    try ensure(first.displayID != second.displayID && firstCapture !== secondCapture, "Sessions shared display or capture identity")
    try ensure(registry.states().count == 2, "Both sessions must be discoverable")
    report("independent_sessions_created")
    let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayTestApp")
    var processes: [Process] = []
    defer { for process in processes where process.isRunning { process.terminate(); process.waitUntilExit() } }
    var targets: [(session: String, app: String, pid: Int32, window: UInt32)] = []
    for display in [first, first, second] {
        let process = Process(); process.executableURL = binary
        process.arguments = ["--display-id", String(display.displayID)]
        process.standardOutput = FileHandle.standardError
        try process.run(); processes.append(process)
        let deadline = Date(timeIntervalSinceNow: 10)
        var windows: [VirtualDisplayWindowInfo] = []
        repeat {
            windows = registry.availableWindows(pid: process.processIdentifier)
            if !windows.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        guard let window = windows.first else { throw NSError(domain: "VirtualDisplayRunner", code: 20) }
        let running = NSRunningApplication(processIdentifier: process.processIdentifier)
        let app = running?.bundleIdentifier ?? running?.localizedName ?? "VirtualDisplayTestApp"
        if try registry.state(sessionID: display.sessionID).phase == "paused" { _ = try registry.resume(sessionID: display.sessionID) }
        _ = try registry.attach(sessionID: display.sessionID, app: app, pid: process.processIdentifier, windowID: window.id)
        targets.append((display.sessionID, app, process.processIdentifier, window.id))
    }
    let state = try registry.state(sessionID: first.sessionID)
    try ensure(state.applications.count == 2 && state.windows.count == 2, "One display did not retain both applications")
    try ensure(state.windows.allSatisfy { first.frame.contains($0.frame) }, "A managed app escaped its display")
    do {
        _ = try registry.attach(sessionID: second.sessionID, app: targets[0].app, pid: targets[0].pid, windowID: targets[0].window)
        throw NSError(domain: "VirtualDisplayRunner", code: 21, userInfo: [NSLocalizedDescriptionKey: "Cross-session ownership was accepted"])
    } catch let error as ComputerUseError {
        try ensure(error.localizedDescription.contains("another virtual session"), "Unexpected ownership error")
    }
    report("multiple_apps_and_ownership_verified")
    let firstKernel = VirtualDisplayNotebookKernel(sessionID: first.sessionID)
    let secondKernel = VirtualDisplayNotebookKernel(sessionID: second.sessionID)
    for target in targets {
        if try registry.state(sessionID: target.session).phase == "paused" { _ = try registry.resume(sessionID: target.session) }
        let kernel = target.session == first.sessionID ? firstKernel : secondKernel
        let source = "{\"tool\":\"get_app_state\",\"args\":{\"window_id\":\(target.window)}}"
        let before = try kernel.run(source: source, app: target.app)
        try ensure(!before.isError && before.primaryText?.contains("Counter 0") == true, "Cell snapshot was not bound to the requested app/window")
        let button = try index(before.primaryText ?? "", matching: "Increment")
        let after = try kernel.run(source: "{\"tool\":\"click\",\"args\":{\"element_index\":\"\(button)\",\"click_method\":\"accessibility\"}}", app: target.app)
        try ensure(!after.isError && after.primaryText?.contains("Counter 1") == true, "Notebook cell did not change the selected real UI")
        report("notebook_real_ui_verified", ["session_id": target.session, "pid": target.pid])
    }
    _ = try registry.pause(sessionID: first.sessionID)
    let denied = try firstKernel.run(source: "{\"tool\":\"press_key\",\"args\":{\"key\":\"Return\"}}", app: targets[0].app)
    try ensure(denied.isError && denied.primaryText?.contains("paused") == true, "Paused notebook still accepted input")
    let other = try secondKernel.run(source: "{\"tool\":\"get_app_state\",\"args\":{}}", app: targets[2].app)
    try ensure(!other.isError && other.primaryText?.contains("Counter 1") == true, "Pausing another session contaminated this client")
    let otherButton = try index(other.primaryText ?? "", matching: "Increment")
    let otherChanged = try secondKernel.run(source: "{\"tool\":\"click\",\"args\":{\"element_index\":\"\(otherButton)\",\"click_method\":\"accessibility\"}}", app: targets[2].app)
    try ensure(!otherChanged.isError && otherChanged.primaryText?.contains("Counter 2") == true, "Another session's pause blocked this session")
    let frameDeadline = Date(timeIntervalSinceNow: 10)
    while (firstCapture.latestFrame() == nil || secondCapture.latestFrame() == nil), Date() < frameDeadline { Thread.sleep(forTimeInterval: 0.1) }
    try ensure(firstCapture.latestFrame() != nil && secondCapture.latestFrame() != nil, "Independent captures did not produce frames")
    report("pause_and_capture_isolation_verified")
    try registry.destroy(sessionID: second.sessionID)
    try ensure(registry.states().count == 1 && firstCapture.isRunning && secondCapture.latestFrame() == nil, "Destroy contaminated another capture/session")
    try ensure(!VirtualDisplaySessionRegistry.onlineDisplayIDs().contains(second.displayID), "Second display remained after destroy")
    _ = try registry.resume(sessionID: first.sessionID)
    let remaining = try firstKernel.run(source: "{\"tool\":\"get_app_state\",\"args\":{\"window_id\":\(targets[0].window)}}", app: targets[0].app)
    try ensure(!remaining.isError && remaining.primaryText?.contains("Counter 1") == true, "Remaining session was unusable after independent teardown")
    try registry.destroyAll()
    try ensure(registry.states().isEmpty && firstCapture.latestFrame() == nil, "All-session teardown retained state/frame")
    try ensure(processes.allSatisfy(\.isRunning), "Borrowed applications were terminated")
    try ensure(Set(VirtualDisplaySessionRegistry.onlineDisplayIDs()) == originalDisplays, "Display topology did not return to its original IDs")
    report("multi_session_complete")
}
