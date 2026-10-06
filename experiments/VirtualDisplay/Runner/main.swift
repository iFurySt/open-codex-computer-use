import AppKit
import ApplicationServices
import CoreGraphics
import CoreVideo
import ImageIO
import Foundation
import OpenComputerUseKit

final class RunnerDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Thread.detachNewThread {
            do {
                _ = try LabTarget.shared.end()
                DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) }
            } catch { report("cleanup_failure", ["error": error.localizedDescription]); DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: false) } }
        }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--lab") { MainActor.assumeIsolated { showVirtualDisplayLab() }; return }
        Thread.detachNewThread {
            var exitCode: Int32 = 0
            do { try runChecks() } catch { report("failure", ["error": error.localizedDescription]); exitCode = 1 }
            exit(exitCode)
        }
    }
}
func report(_ name: String, _ fields: [String: Any] = [:]) {
    var fields = fields; fields["check"] = name
    print(String(decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)); fflush(stdout)
}
func ensure(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "VirtualDisplayRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func index(_ text: String, matching name: String) throws -> String {
    for line in text.split(separator: "\n") where line.contains(name) {
        if let first = line.split(whereSeparator: { $0.isWhitespace }).first, Int(first) != nil { return String(first) }
    }
    throw NSError(domain: "VirtualDisplayRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing AX element: \(name)\n\(text)"])
}
final class InputObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var globalFromRunner = 0
    private var otherMouseEvents = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    func start() {
        DispatchQueue.main.sync {
            let events: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown, .keyUp, .scrollWheel]
            let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    let observer = Unmanaged<InputObservation>.fromOpaque(context).takeUnretainedValue()
                    observer.record(event, type: type)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap { source = CFMachPortCreateRunLoopSource(nil, tap, 0); CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        }
    }
    private func record(_ event: CGEvent, type: CGEventType) {
        lock.lock(); defer { lock.unlock() }
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier) { globalFromRunner += 1 }
        else if type == .mouseMoved || type == .leftMouseDragged { otherMouseEvents += 1 }
    }
    func observation() -> (available: Bool, global: Int, otherMouse: Int) {
        lock.lock(); defer { lock.unlock() }; return (tap != nil, globalFromRunner, otherMouseEvents)
    }
    func stop() { DispatchQueue.main.sync { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; if let tap { CFMachPortInvalidate(tap) }; source = nil; tap = nil } }
}

func runChecks() throws {
    let args = CommandLine.arguments
    func argument(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
    let cycles = Int(argument("--cycles") ?? "20") ?? 20
    guard (1...100).contains(cycles) else { throw NSError(domain: "VirtualDisplayRunner", code: 3) }
    if args.contains("--holder-only") { try holderCycles(cycles); return }
    if args.contains("--desktop-lifecycle") { try desktopLifecycleChecks(cycles: cycles); return }
    if args.contains("--example") { try exampleChecks(); return }
    if args.contains("--multi-session") { try multiSessionChecks(); return }
    if let bundle = argument("--third-party") { try thirdPartyCheck(bundle); return }
    report("permissions", ["accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess()])
    let registry = VirtualDisplaySessionRegistry.shared
    let dispatcher = ComputerUseToolDispatcher()
    let previousFrontApp = NSWorkspace.shared.frontmostApplication
    let probeURL = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-focus-probe-\(UUID().uuidString).json")
    var probe: Process?
    var probeBefore: [String: Any]?
    if args.contains("--foreground-guard") {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayTestApp")
        process.arguments = ["--foreground-probe", probeURL.path]
        try process.run(); probe = process
        let deadline = Date(timeIntervalSinceNow: 5)
        repeat {
            probeBefore = (try? Data(contentsOf: probeURL)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if probeBefore?["active"] as? Bool == true, probeBefore?["key"] as? Bool == true, probeBefore?["first_responder_is_input"] as? Bool == true { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
    }
    defer {
        if let probe, probe.isRunning { probe.terminate(); probe.waitUntilExit() }
        try? FileManager.default.removeItem(at: probeURL)
        if probe != nil, let previousFrontApp { DispatchQueue.main.sync { _ = previousFrontApp.activate() } }
    }
    if probe != nil { try ensure(probeBefore?["first_responder_is_input"] as? Bool == true, "Foreground probe was not ready") }
    let initialFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let initialPointer = CGEvent(source: nil)?.location
    let inputObservation = InputObservation(); inputObservation.start(); defer { inputObservation.stop() }
    func desktop(_ stage: String) {
        let point = CGEvent(source: nil)?.location ?? .zero
        report("desktop_observation", ["stage": stage, "frontmost_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, "pointer_x": point.x, "pointer_y": point.y])
    }
    desktop("before_create")
    let display = try registry.create(configuration: .init(scale: Int(argument("--scale") ?? "1") ?? 1))
    defer { try? registry.destroy(sessionID: display.sessionID, retainDisplay: false) }
    report("display_ready", display.dictionary)
    desktop("after_create")
    let process = Process()
    let testBinary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayTestApp")
    process.executableURL = testBinary
    process.arguments = ["--display-id", String(display.displayID)]
    process.standardOutput = FileHandle.standardError
    try process.run()
    defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    var windows: [VirtualDisplayWindowInfo] = []
    let deadline = Date(timeIntervalSinceNow: 10)
    repeat { windows = registry.availableWindows(pid: process.processIdentifier); if !windows.isEmpty { break }; Thread.sleep(forTimeInterval: 0.1) } while Date() < deadline
    let testApp = NSRunningApplication(processIdentifier: process.processIdentifier)
    let app = testApp?.bundleIdentifier ?? testApp?.localizedName ?? "VirtualDisplayTestApp"
    guard let window = windows.first else { throw NSError(domain: "VirtualDisplayRunner", code: 4, userInfo: [NSLocalizedDescriptionKey: "Test app has no AX/window-server match"]) }
    let attached = try registry.attach(sessionID: display.sessionID, app: app, pid: process.processIdentifier, windowID: window.id)
    report("window_placed", attached.dictionary)
    let selected = try registry.selectWindow(sessionID: display.sessionID, windowID: window.id)
    try ensure(selected.selectedWindowID == window.id, "Typed window selection did not preserve exact identity")
    desktop("after_attach")
    func call(_ name: String, _ extra: [String: Any] = [:]) throws -> ToolCallResult {
        var arguments: [String: Any] = ["session_id": display.sessionID, "app": app, "snapshot_mode": "full"]
        arguments.merge(extra) { _, new in new }
        return try dispatcher.callTool(name: name, arguments: arguments)
    }
    let before = try call("get_app_state", ["text_limit": "max"])
    let beforeText = before.primaryText ?? ""
    try ensure(beforeText.contains("Counter 0"), "Real AX counter state unavailable")
    try ensure((before.asDictionary["content"] as? [[String: Any]])?.contains(where: { $0["type"] as? String == "image" }) == true, "Real ScreenCaptureKit window screenshot unavailable")
    let beforeID = String(beforeText.split(separator: " ")[2])
    let steady = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "auto", "base_snapshot_id": beforeID])
    try ensure(steady.primaryText?.contains("mode=diff") == true && steady.primaryText?.contains("AX unchanged") == true,
               "Real AX unchanged snapshot did not use compact output")
    report("ax_unchanged_diff_verified", ["full_bytes": beforeText.utf8.count, "unchanged_bytes": steady.primaryText?.utf8.count ?? 0])
    let button = try index(beforeText, matching: "Increment")
    let click = try call("click", ["element_index": button, "click_method": "accessibility"])
    try ensure(click.primaryText?.contains("Counter 1") == true, "AXPress did not change the real UI")
    let delta = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "auto", "base_snapshot_id": beforeID])
    try ensure(delta.primaryText?.contains("Counter 1") == true && delta.primaryText?.contains("mode=diff") == true,
               "Real AX click diff lost the action outcome")
    if let path = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_AX_REAL_REPLAY_OUTPUT"] {
        let fullAfter = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "full"])
        let data = try JSONSerialization.data(withJSONObject: ["source": "real AppKit test app AX/SCK in a virtual session", "scenarios": [["name": "real-appkit-counter", "observations": [
            ["full": beforeText, "auto": beforeText],
            ["full": beforeText, "auto": steady.primaryText ?? ""],
            ["full": fullAfter.primaryText ?? "", "auto": delta.primaryText ?? ""]
        ]]]], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
    report("ax_diff_verified", ["full_bytes": beforeText.utf8.count, "unchanged_bytes": steady.primaryText?.utf8.count ?? 0, "changed_bytes": delta.primaryText?.utf8.count ?? 0])
    report("ax_click_verified")
    if args.contains("--ax-diff-only") {
        let baseline = try call("get_app_state", ["text_limit": "max"])
        let baselineText = baseline.primaryText ?? ""
        let baselineID = String(baselineText.split(separator: " ")[2])
        try ensure(try index(baselineText, matching: "Increment") == button,
                   "Real AX button reference changed after clicking")
        let input = try index(baselineText, matching: "live-input")
        let hidden = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "none"])
        try ensure(hidden.primaryText?.contains("AX snapshot") != true,
                   "Hidden observation published an AX snapshot")
        let value = "AX diff verification 你好"
        _ = try call("set_value", ["element_index": input, "value": value, "snapshot_mode": "none"])
        let changed = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "auto", "base_snapshot_id": baselineID])
        let changedText = changed.primaryText ?? ""
        try ensure(changedText.contains("mode=diff") && changedText.contains(value) && changedText.contains("base_snapshot_id=\(baselineID)"),
                   "Hidden reads/actions lost the explicit published baseline or text update")
        let current = try call("get_app_state", ["text_limit": "max"])
        try ensure(try index(current.primaryText ?? "", matching: "live-input") == input,
                   "Real AX text field reference changed after value update")
        try ensure(try index(current.primaryText ?? "", matching: "Increment") == button,
                   "Unchanged button reference changed after text update")
        report("ax_hidden_baseline_and_value_verified", ["full_bytes": (current.primaryText ?? "").utf8.count, "changed_bytes": changedText.utf8.count])
        let recovered = try call("get_app_state", ["text_limit": "max", "snapshot_mode": "auto", "base_snapshot_id": "missing-verification-baseline"])
        try ensure(recovered.primaryText?.contains("mode=full") == true && recovered.primaryText?.contains(value) == true,
                   "Missing baseline did not recover the current full AX tree")
        report("ax_stable_references_and_full_recovery_verified")
        return
    }
    desktop("after_click")
    let after = try call("get_app_state", ["text_limit": "max"])
    let textInput = try index(after.primaryText ?? "", matching: "live-input")
    let value = "Virtual display 你好 🖥️"
    let typed = try call("set_value", ["element_index": textInput, "value": value])
    try ensure(typed.primaryText?.contains(value) == true, "AX text value not observed")
    report("text_verified")
    desktop("after_text")
    let scrollBefore = try call("get_app_state", ["text_limit": "max"])
    let scrollIndex = try index(scrollBefore.primaryText ?? "", matching: "scroll area")
    _ = try call("scroll", ["element_index": scrollIndex, "direction": "up", "pages": 1])
    let scrollAfter = try call("get_app_state", ["text_limit": "max"])
    func imageData(_ result: ToolCallResult) -> String? {
        (result.asDictionary["content"] as? [[String: Any]])?.first { $0["type"] as? String == "image" }?["data"] as? String
    }
    try ensure(imageData(scrollBefore) != imageData(scrollAfter), "Scroll did not change the captured UI")
    report("scroll_verified")
    let popupIndex = try index(scrollAfter.primaryText ?? "", matching: "Open sheet")
    _ = try call("click", ["element_index": popupIndex, "click_method": "accessibility"])
    let sheetState = try call("get_app_state", ["text_limit": "max"])
    try ensure(sheetState.primaryText?.contains("Test sheet") == true, "Attached sheet is not inspectable")
    let dismissIndex = try index(sheetState.primaryText ?? "", matching: "button Dismiss")
    _ = try call("click", ["element_index": dismissIndex, "click_method": "accessibility"])
    report("sheet_verified")
    let dragResult = dispatcher.callToolAsResult(name: "drag", arguments: ["session_id": display.sessionID, "app": app, "from_x": 500, "from_y": 300, "to_x": 640, "to_y": 310])
    try ensure(dragResult.isError && dragResult.primaryText?.contains("unsupported") == true, "Unverified virtual drag was accepted")
    report("unsupported_drag_rejected")
    _ = try call("get_app_state", ["text_limit": "max"])
    registry.clearCursor()
    let afterTurn = dispatcher.callToolAsResult(name: "click", arguments: ["session_id": display.sessionID, "app": app, "element_index": button])
    try ensure(afterTurn.isError, "Turn-ended reused an action snapshot")
    report("turn_cache_invalidation_verified")
    let otherClient = ComputerUseToolDispatcher()
    let uncached = otherClient.callToolAsResult(name: "click", arguments: ["session_id": display.sessionID, "app": app, "element_index": button])
    try ensure(uncached.isError, "Another client reused this client's snapshot")
    _ = try otherClient.callTool(name: "get_app_state", arguments: ["session_id": display.sessionID, "app": app])
    report("client_cache_isolation_verified")
    let paused = try registry.pause(sessionID: display.sessionID)
    try ensure(paused.phase == "paused", "Pause state not applied")
    let pausedSnapshot = try call("get_app_state", ["text_limit": "max"])
    try ensure(pausedSnapshot.primaryText?.contains("Counter 1") == true, "Paused session cannot be inspected")
    let denied = dispatcher.callToolAsResult(name: "click", arguments: ["session_id": display.sessionID, "app": app, "element_index": button])
    try ensure(denied.isError, "Paused session accepted input")
    _ = try registry.resume(sessionID: display.sessionID)
    let stale = dispatcher.callToolAsResult(name: "click", arguments: ["session_id": display.sessionID, "app": app, "element_index": button])
    try ensure(stale.isError, "Resume reused a stale snapshot")
    report("pause_and_snapshot_invalidation_verified")
    if args.contains("--strict-desktop") { try ensure(NSWorkspace.shared.frontmostApplication?.processIdentifier == initialFrontmost, "Frontmost application changed during background checks: \(initialFrontmost ?? 0) → \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
    try ensure(CGEvent(source: nil)?.location == initialPointer, "System pointer moved during checks: \(String(describing: initialPointer)) → \(String(describing: CGEvent(source: nil)?.location)) (keep pointer still)")
    }
    let observed = inputObservation.observation()
    try ensure(observed.global == 0, "Agent posted input into the global session event stream")
    if observed.available && observed.otherMouse == 0 {
        try ensure(CGEvent(source: nil)?.location == initialPointer, "Pointer moved without observed external mouse input")
    }
    report("input_delivery_observed", ["event_tap_available": observed.available, "global_events_from_runner": observed.global, "external_mouse_events": observed.otherMouse])
    let frameDeadline = Date(timeIntervalSinceNow: 5)
    while registry.capture.latestFrame() == nil, Date() < frameDeadline { Thread.sleep(forTimeInterval: 0.1) }
    try ensure(registry.capture.latestFrame() != nil, "Display stream produced no complete frame")
    if let frame = registry.capture.latestFrame(), let managed = registry.currentState()?.windows.first {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let scale = display.configuration.scale
        let x = Int(managed.frame.minX - display.frame.minX + 25) * scale
        let y = Int(managed.frame.minY - display.frame.minY + 100) * scale
        guard let base = CVPixelBufferGetBaseAddress(frame), x < CVPixelBufferGetWidth(frame), y < CVPixelBufferGetHeight(frame) else { throw NSError(domain: "VirtualDisplayRunner", code: 6) }
        let pixel = base.advanced(by: y * CVPixelBufferGetBytesPerRow(frame) + x * 4).assumingMemoryBound(to: UInt8.self)
        try ensure(Int(pixel[2]) > Int(pixel[1]) + 40 && Int(pixel[2]) > Int(pixel[0]) + 40, "Stream is not showing the test window's red source marker")
    }
    report("capture_source_marker_verified")
    if probe != nil {
        Thread.sleep(forTimeInterval: 0.2)
        let observed = try JSONSerialization.jsonObject(with: Data(contentsOf: probeURL)) as? [String: Any] ?? [:]
        try ensure(observed["active"] as? Bool == true && observed["key"] as? Bool == true && observed["first_responder_is_input"] as? Bool == true, "Foreground AppKit focus was lost")
        try ensure(observed["activation_losses"] as? Int == probeBefore?["activation_losses"] as? Int && observed["key_losses"] as? Int == probeBefore?["key_losses"] as? Int, "Foreground AppKit transiently resigned")
        report("foreground_appkit_verified", observed)
    }
    report("capture_and_foreground_verified")
    if args.contains("--input-matrix") {
        func counterValue(_ text: String) -> Int? {
            let regex = try! NSRegularExpression(pattern: "Counter ([0-9]+)")
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), let digits = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[digits])
        }
        for method in ["app_post", "sky_click"] {
            let before = try call("get_app_state", ["text_limit": "max"])
            let count = counterValue(before.primaryText ?? "")
            let element = try index(before.primaryText ?? "", matching: "Increment")
            let result = dispatcher.callToolAsResult(name: "click", arguments: ["session_id": display.sessionID, "app": app, "element_index": element, "click_method": method])
            let after = try call("get_app_state", ["text_limit": "max"])
            let next = counterValue(after.primaryText ?? "")
            report("input_method_result", ["method": method, "verified_exactly_one_click": count != nil && next == count! + 1, "error": result.isError, "details": result.isError ? result.primaryText ?? "" : "Read back real counter"])
        }
        _ = try call("get_app_state", ["text_limit": "max"])
        let keyboard = dispatcher.callToolAsResult(name: "press_key", arguments: ["session_id": display.sessionID, "app": app, "key": "Tab"])
        report("input_method_result", ["method": "press_key", "error": keyboard.isError, "details": keyboard.isError ? keyboard.primaryText ?? "" : "Read-back completed; target focus effect needs inspection"])
        let observed = inputObservation.observation()
        try ensure(observed.global == 0, "Explicit input method posted into global event stream")
        report("input_matrix_global_stream_verified", ["global_events_from_runner": observed.global])
    }
    try registry.destroy(sessionID: display.sessionID, retainDisplay: false)
    let restored = registry.availableWindows(pid: process.processIdentifier).first { $0.id == window.id }
    try ensure(restored != nil, "Borrowed test application was closed")
    report("borrowed_app_preserved")
    // The runner owns this test process; remove its restored physical window
    // before starting display-only stress cycles.
    if process.isRunning { process.terminate(); process.waitUntilExit() }
    for cycle in 1...cycles {
        let state = try registry.create()
        try ensure(registry.capture.isRunning, "Capture did not restart")
        try registry.destroy(sessionID: state.sessionID, retainDisplay: false)
        try ensure(registry.capture.latestFrame() == nil, "Old capture frame survived teardown")
        report("lifecycle", ["cycle": cycle])
    }
    let fault = try registry.create()
    try ensure(kill(fault.helperPID, SIGKILL) == 0, "Could not inject owned-helper failure")
    Thread.sleep(forTimeInterval: 0.2)
    let faultState = try registry.state(sessionID: fault.sessionID)
    try ensure(faultState.phase == "paused", "Helper death did not pause the session")
    try registry.destroy(sessionID: fault.sessionID, retainDisplay: false)
    report("helper_failure_cleanup_verified")
    report("complete", ["cycles": cycles])
}
func thirdPartyCheck(_ bundle: String) throws {
    let registry = VirtualDisplaySessionRegistry.shared
    let originalFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let state = try registry.create()
    do {
        let attached = try registry.attach(sessionID: state.sessionID, app: bundle, launch: true, manageAllWindows: true)
        report("third_party_attached", attached.dictionary)
        let dispatcher = ComputerUseToolDispatcher()
        let args: [String: Any] = ["session_id": state.sessionID, "app": bundle, "text_limit": "max"]
        let snapshot = try dispatcher.callTool(name: "get_app_state", arguments: args)
        try ensure(snapshot.primaryText?.contains("Window:") == true, "Third party AX state missing")
        report("third_party_snapshot", ["app": bundle, "text": snapshot.primaryText ?? ""])
        let key = bundle == "com.google.Chrome" ? "super+l" : "super+f"
        let result = try dispatcher.callTool(name: "press_key", arguments: ["session_id": state.sessionID, "app": bundle, "key": key])
        report("third_party_key_readback", ["app": bundle, "text": result.primaryText ?? ""])
        try ensure(originalFrontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier, "Third-party application activated")
        report("third_party_background_verified", ["app": bundle])
    } catch {
        report("third_party_compatibility_failure", ["app": bundle, "reason": error.localizedDescription, "state": registry.currentState()?.dictionary ?? [:]])
        try registry.destroy(sessionID: state.sessionID, retainDisplay: false)
        throw error
    }
    try registry.destroy(sessionID: state.sessionID, retainDisplay: false)
    report("third_party_cleanup_verified", ["app": bundle])
}
func holderCycles(_ cycles: Int) throws {
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayHost")
    for cycle in 1...cycles {
        let process = Process(); let input = Pipe(); let output = Pipe()
        process.executableURL = helper; process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        try input.fileHandleForWriting.write(contentsOf: Data("{\"width\":1920,\"height\":1080,\"scale\":1,\"serial\":\(UInt32.random(in: 1...UInt32.max))}\n".utf8))
        var line = Data(); let deadline = Date(timeIntervalSinceNow: 12)
        while Date() < deadline {
            var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            if poll(&fd, 1, 100) > 0 {
                var byte: UInt8 = 0
                guard read(fd.fd, &byte, 1) == 1 else { break }
                if byte == 10 { break }; line.append(byte)
            }
        }
        let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any] ?? [:]
        guard let id = reply["display_id"] as? UInt32 else { throw NSError(domain: "VirtualDisplayRunner", code: 5, userInfo: [NSLocalizedDescriptionKey: String(describing: reply)]) }
        let onlineDeadline = Date(timeIntervalSinceNow: 5)
        while !VirtualDisplaySessionRegistry.onlineDisplayIDs().contains(id), Date() < onlineDeadline { Thread.sleep(forTimeInterval: 0.05) }
        try ensure(VirtualDisplaySessionRegistry.onlineDisplayIDs().contains(id), "Holder display did not come online")
        try input.fileHandleForWriting.close()
        let exitDeadline = Date(timeIntervalSinceNow: 5)
        while process.isRunning, Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.05) }
        try ensure(!process.isRunning, "Holder did not exit on EOF")
        let removalDeadline = Date(timeIntervalSinceNow: 5)
        while VirtualDisplaySessionRegistry.onlineDisplayIDs().contains(id), Date() < removalDeadline { Thread.sleep(forTimeInterval: 0.05) }
        report("removal_observation", ["display_id": id, "online": VirtualDisplaySessionRegistry.onlineDisplayIDs()])
        try ensure(!VirtualDisplaySessionRegistry.onlineDisplayIDs().contains(id), "Display survived its holder")
        report("holder_lifecycle", ["cycle": cycle])
    }
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = RunnerDelegate(); application.delegate = delegate
application.run()
