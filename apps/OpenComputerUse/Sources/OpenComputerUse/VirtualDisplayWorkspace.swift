import AppKit
import OpenComputerUseKit
import SwiftUI

@MainActor
final class VirtualDisplayWorkspaceModel: ObservableObject {
    @Published var applications: [VirtualDisplayAppChoice] = []
    @Published var selectedApp: String?
    @Published var windows: [VirtualDisplayWindowInfo] = []
    @Published var selectedWindow: UInt32?
    @Published var state: VirtualDisplayState?
    @Published var search = ""
    @Published var launch = false
    @Published var scale = 1
    @Published var originalSize = false
    @Published var busy = false
    @Published var message: String?
    @Published var permissionsGranted = false
    var displayDidChange: (() -> Void)?
    private var polling: Task<Void, Never>?
    private let registry = VirtualDisplaySessionRegistry.shared
    var chosen: VirtualDisplayAppChoice? { applications.first { $0.id == selectedApp } }
    var filtered: [VirtualDisplayAppChoice] {
        applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleIdentifier.localizedCaseInsensitiveContains(search) }
    }
    init() {
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func refresh() async {
        let selection = selectedApp
        let values = await Task.detached { [registry] in
            let apps = VirtualDisplaySessionRegistry.availableApplications()
            let selected = apps.first { $0.id == selection }
            return (apps, registry.currentState(), selected?.pid.map { registry.availableWindows(pid: $0) } ?? [], PermissionDiagnostics.current().allGranted)
        }.value
        let previousDisplay = state?.displayID
        applications = values.0; state = values.1; windows = values.2; permissionsGranted = values.3
        if previousDisplay != state?.displayID { displayDidChange?() }
        if selectedWindow == nil || !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id }
    }
    func start() {
        guard let app = chosen else { return }
        let mode = launch; let window = selectedWindow; let scale = scale
        perform { [registry] in
            let current = registry.currentState()
            let created = try current ?? registry.create(configuration: .init(scale: scale))
            _ = try registry.attach(sessionID: created.sessionID, app: app.bundleIdentifier,
                                    pid: mode ? nil : app.pid, windowID: mode ? nil : window, launch: mode)
        }
    }
    func pauseOrResume() {
        guard let state else { return }
        // Pause changes the input gate before waiting for any ongoing operation.
        if state.phase != "paused" {
            Task {
                do { _ = try await Task.detached { [registry] in try registry.pause(sessionID: state.sessionID) }.value }
                catch { message = error.localizedDescription }
                await refresh()
            }
        } else { perform { [registry] in _ = try registry.resume(sessionID: state.sessionID) } }
    }
    func end() {
        guard let state else { return }
        perform { [registry] in try registry.destroy(sessionID: state.sessionID) }
    }
    func selectManagedWindow(_ id: UInt32) {
        guard let state else { return }
        perform { [registry] in _ = try registry.selectWindow(sessionID: state.sessionID, windowID: id) }
    }
    func perform(_ operation: @escaping @Sendable () throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            do { try await Task.detached { try operation() }.value }
            catch { message = error.localizedDescription }
            busy = false
            await refresh()
        }
    }
}

struct VirtualDisplayWorkspaceView: View {
    @ObservedObject var model: VirtualDisplayWorkspaceModel
    var requestPermissions: () -> Void
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(model.filtered, selection: $model.selectedApp) { app in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                        Text(app.pid == nil ? "Installed" : "Running · PID \(app.pid!)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.tag(app.id)
                }
                .listStyle(.sidebar)
                .searchable(text: $model.search, prompt: "Find an application")
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch a dedicated instance", isOn: $model.launch)
                    if !model.launch {
                        Picker("Window", selection: $model.selectedWindow) {
                            Text("Select window").tag(Optional<UInt32>.none)
                            ForEach(model.windows) { window in Text(window.title).tag(Optional(window.id)) }
                        }
                    }
                    Picker("Display scale", selection: $model.scale) {
                        Text("1× · 1920 × 1080").tag(1)
                        Text("2× · 3840 × 2160").tag(2)
                    }.disabled(model.state != nil)
                }.padding()
            }.navigationTitle("Applications")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 350)
        } detail: {
            VStack(spacing: 0) {
                if !model.permissionsGranted {
                    ContentUnavailableView {
                        Label("Permissions needed", systemImage: "lock.shield")
                    } description: {
                        Text("Allow Accessibility and Screen Recording to place, inspect and capture application windows.")
                    } actions: { Button("Set up permissions") { requestPermissions() } }
                } else if let state = model.state {
                    VirtualDisplayPreview(capture: VirtualDisplaySessionRegistry.shared.capture, originalSize: model.originalSize)
                        .overlay(alignment: .topLeading) {
                            if state.phase == "paused" { Label("Paused", systemImage: "pause.fill").padding(8).background(.regularMaterial).padding() }
                        }
                    Divider()
                    HStack {
                        Text(state.phase.capitalized)
                        Spacer()
                        Text(state.sessionID).font(.caption.monospaced()).textSelection(.enabled)
                    }.padding(10)
                    if !state.windows.isEmpty {
                        Picker("Target window", selection: Binding(get: { state.selectedWindowID ?? 0 }, set: { id in model.selectManagedWindow(id) })) {
                            ForEach(state.windows) { Text($0.title).tag($0.id) }
                        }.padding(.horizontal).padding(.bottom, 8)
                    }
                } else {
                    ContentUnavailableView("Virtual display", systemImage: "display.2", description: Text("Choose an application to open a dedicated workspace."))
                }
                if let message = model.message ?? model.state?.reason {
                    Text(message).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }.navigationTitle("Open Computer Use")
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.start() } label: { Label("Start", systemImage: "play.fill") }
                    .disabled(model.busy || !model.permissionsGranted || model.chosen == nil || model.state?.pid != nil || (!model.launch && model.selectedWindow == nil))
                Button { model.pauseOrResume() } label: { Label(model.state?.phase == "paused" ? "Resume" : "Pause", systemImage: model.state?.phase == "paused" ? "play" : "pause") }
                    .disabled(model.state == nil || (model.busy && model.state?.phase == "paused"))
                Button { model.end() } label: { Label("End", systemImage: "stop") }.disabled(model.busy || model.state == nil)
                Toggle("Original size", isOn: $model.originalSize)
                    .help("Display capture pixels at their original size")
            }
        }
        .frame(minWidth: 820, minHeight: 540)
    }
}

@MainActor
final class VirtualDisplayWorkspaceController: NSObject, NSWindowDelegate {
    static let shared = VirtualDisplayWorkspaceController()
    private var window: NSWindow?
    let model = VirtualDisplayWorkspaceModel()
    func show() {
        model.displayDidChange = { [weak self] in self?.keepOnPhysicalScreen() }
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            NSWindow.allowsAutomaticWindowTabbing = false
            let view = VirtualDisplayWorkspaceView(model: model) { PermissionOnboardingApp.present() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Open Computer Use"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: view)
            window.center(); self.window = window
            installMenu()
        }
        keepOnPhysicalScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func keepOnPhysicalScreen() {
        guard let window else { return }
        let virtualID = VirtualDisplaySessionRegistry.shared.activeDisplayID
        let physical = NSScreen.screens.filter { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value != virtualID }
        guard let screen = physical.first else { return }
        if !physical.contains(where: { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) }) {
            var frame = window.frame
            frame.size.width = min(frame.width, screen.visibleFrame.width); frame.size.height = min(frame.height, screen.visibleFrame.height)
            frame.origin = CGPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.midY - frame.height / 2)
            window.setFrame(frame, display: true)
        }
    }
    func windowDidMove(_ notification: Notification) { keepOnPhysicalScreen() }
    func windowDidChangeScreen(_ notification: Notification) { keepOnPhysicalScreen() }
    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Show Open Computer Use", action: #selector(showWorkspace), keyEquivalent: "0").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Open Computer Use", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key) }
        menu.addItem(editItem); NSApp.mainMenu = menu
    }
    @objc private func showWorkspace() { show() }
}
