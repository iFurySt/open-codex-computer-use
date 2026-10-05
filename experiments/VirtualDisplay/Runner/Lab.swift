import AppKit
import OpenComputerUseKit
import SwiftUI

@MainActor
final class VirtualDisplayLabModel: ObservableObject {
    @Published var state: VirtualDisplayState?
    @Published var output = "Create a test workspace, then exercise real AX actions."
    @Published var busy = false
    private let target = LabTarget.shared
    private let registry = VirtualDisplaySessionRegistry.shared
    func perform(_ operation: @escaping @Sendable () throws -> String) {
        guard !busy else { return }; busy = true
        Task {
            do { output = try await Task.detached { try operation() }.value }
            catch { output = error.localizedDescription }
            state = await Task.detached { [registry] in registry.currentState() }.value
            busy = false
        }
    }
    func create() { perform { [target] in try target.create() } }
    func inspect() { perform { [target] in try target.inspect() } }
    func increment() { perform { [target] in try target.increment() } }
    func writeText() { perform { [target] in try target.writeText() } }
    func end() { perform { [target] in try target.end() } }
}

final class LabTarget: @unchecked Sendable {
    static let shared = LabTarget()
    private var process: Process?
    private var app = "VirtualDisplayTestApp"
    private let dispatcher = ComputerUseToolDispatcher()
    private let registry = VirtualDisplaySessionRegistry.shared
    func create() throws -> String {
        let state = try registry.create()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayTestApp")
        process.arguments = ["--display-id", String(state.displayID)]
        try process.run(); self.process = process
        let deadline = Date(timeIntervalSinceNow: 8)
        while Date() < deadline {
            if let window = registry.availableWindows(pid: process.processIdentifier).first {
                let running = NSRunningApplication(processIdentifier: process.processIdentifier)
                app = running?.bundleIdentifier ?? running?.localizedName ?? app
                _ = try registry.attach(sessionID: state.sessionID, app: app, pid: process.processIdentifier, windowID: window.id)
                return try inspect()
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw NSError(domain: "VirtualDisplayLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test window did not appear; use End to clean up"])
    }
    func call(_ name: String, arguments: [String: Any] = [:]) throws -> ToolCallResult {
        guard let state = registry.currentState() else { throw NSError(domain: "VirtualDisplayLab", code: 2) }
        var args = arguments; args["session_id"] = state.sessionID; args["app"] = app
        return try dispatcher.callTool(name: name, arguments: args)
    }
    func inspect() throws -> String { try call("get_app_state", arguments: ["text_limit": "max"]).primaryText ?? "" }
    func increment() throws -> String {
        let state = try inspect(); let element = try index(state, matching: "Increment")
        _ = try call("click", arguments: ["element_index": element, "click_method": "accessibility"])
        return try inspect()
    }
    func writeText() throws -> String {
        let state = try inspect(); let element = try index(state, matching: "live-input")
        _ = try call("set_value", arguments: ["element_index": element, "value": "Hello virtual display 你好"])
        return try inspect()
    }
    func end() throws -> String {
        if let state = registry.currentState() { try registry.destroy(sessionID: state.sessionID) }
        if let process, process.isRunning { process.terminate(); process.waitUntilExit() }
        process = nil
        return "Display removed and test application stopped."
    }
}

struct VirtualDisplayLabView: View {
    @StateObject private var model = VirtualDisplayLabModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Create") { model.create() }.disabled(model.state != nil)
                Button("Inspect") { model.inspect() }.disabled(model.state?.pid == nil)
                Button("Increment") { model.increment() }.disabled(model.state?.pid == nil)
                Button("Write text") { model.writeText() }.disabled(model.state?.pid == nil)
                Button("End") { model.end() }.disabled(model.state == nil)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }.padding().disabled(model.busy)
            VirtualDisplayPreview(capture: VirtualDisplaySessionRegistry.shared.capture).frame(minHeight: 360)
            ScrollView { Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }.frame(height: 200)
        }.frame(minWidth: 850, minHeight: 620)
    }
}

@MainActor
func showVirtualDisplayLab() {
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1050, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Virtual Display Lab"; window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: VirtualDisplayLabView())
    window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
}
