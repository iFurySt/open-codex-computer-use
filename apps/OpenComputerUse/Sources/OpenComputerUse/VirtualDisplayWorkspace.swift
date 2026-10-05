import AppKit
import OpenComputerUseKit
import SwiftUI

struct WorkspaceCommandCell: Identifiable {
    let id = UUID()
    var title: String
    var source: String
    var output = ""
    var uiTree: String?
    var images: [Data] = []
    var isError = false
    var running = false
    var executedSource: String?
    var duration: TimeInterval?
    static func template(_ tool: String) -> Self {
        let arguments: [String: Any]
        switch tool {
        case "get_app_state": arguments = ["app": "$app"]
        case "click": arguments = ["app": "$app", "element_index": "REPLACE_FROM_SNAPSHOT", "click_method": "accessibility"]
        case "set_value": arguments = ["app": "$app", "element_index": "0", "value": "Hello"]
        case "press_key": arguments = ["app": "$app", "key": "Return"]
        case "type_text": arguments = ["app": "$app", "text": "Hello"]
        default: arguments = [:]
        }
        let bytes = try! JSONSerialization.data(withJSONObject: ["tool": tool, "args": arguments], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return .init(title: tool, source: String(decoding: bytes, as: UTF8.self))
    }
}

@MainActor
final class WorkspaceNotebook: ObservableObject {
    @Published var cells: [WorkspaceCommandCell] = VirtualDisplayExample.cells.map { .init(title: $0.title, source: $0.source) }
    @Published var running = false
    var stopRequested = false
    let kernel: VirtualDisplayNotebookKernel
    init(sessionID: String) { kernel = .init(sessionID: sessionID) }
}

@MainActor
final class VirtualDisplayWorkspaceModel: ObservableObject {
    @Published var applications: [VirtualDisplayAppChoice] = []
    @Published var sessions: [VirtualDisplayState] = []
    @Published var selectedSession: String?
    @Published var names: [String: String] = [:]
    @Published var notebooks: [String: WorkspaceNotebook] = [:]
    @Published var selectedApp: String?
    @Published var windows: [VirtualDisplayWindowInfo] = []
    @Published var selectedWindow: UInt32?
    @Published var search = ""
    @Published var launch = true
    @Published var scale = 1
    @Published var sessionName = ""
    @Published var originalSize = false
    @Published var busy = false
    @Published var message: String?
    @Published var permissionsGranted = false
    @Published var showingCreate = false
    @Published var showingAddApp = false
    var displayDidChange: (() -> Void)?
    private var polling: Task<Void, Never>?
    private let registry = VirtualDisplaySessionRegistry.shared
    var state: VirtualDisplayState? { sessions.first { $0.sessionID == selectedSession } }
    var chosen: VirtualDisplayAppChoice? { applications.first { $0.id == selectedApp } }
    var filtered: [VirtualDisplayAppChoice] {
        applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleIdentifier.localizedCaseInsensitiveContains(search) }
    }
    func name(_ state: VirtualDisplayState) -> String { names[state.sessionID] ?? "Session \(state.sessionID.prefix(6))" }
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
            return (apps, registry.states(), selected?.pid.map { registry.availableWindows(pid: $0) } ?? [], PermissionDiagnostics.current().allGranted)
        }.value
        let previousDisplays = Set(sessions.map(\.displayID))
        applications = values.0; sessions = values.1; permissionsGranted = values.3
        if selection == selectedApp { windows = values.2 }
        let live = Set(sessions.map(\.sessionID))
        notebooks = notebooks.filter { live.contains($0.key) }
        names = names.filter { live.contains($0.key) }
        for state in sessions where notebooks[state.sessionID] == nil { notebooks[state.sessionID] = WorkspaceNotebook(sessionID: state.sessionID) }
        if !live.contains(selectedSession ?? "") { selectedSession = sessions.first?.sessionID }
        if previousDisplays != Set(sessions.map(\.displayID)) { displayDidChange?() }
        if selectedWindow == nil || !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id }
    }
    func create() {
        guard !busy else { return }
        busy = true; message = nil
        let scale = scale; let title = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let created = try await Task.detached { [registry] in try registry.create(configuration: .init(scale: scale)) }.value
                names[created.sessionID] = title.isEmpty ? "Session \(sessions.count + 1)" : title
                selectedSession = created.sessionID; showingCreate = false
            } catch { message = error.localizedDescription }
            busy = false; await refresh()
        }
    }
    func addApplication() {
        guard let app = chosen, let state else { return }
        let mode = launch; let window = selectedWindow
        perform { [registry] in
            _ = try registry.attach(sessionID: state.sessionID, app: app.bundleIdentifier,
                                    pid: mode ? nil : app.pid, windowID: mode ? nil : window, launch: mode)
        } completed: { self.showingAddApp = false }
    }
    func pauseOrResume() {
        guard let state else { return }
        if state.phase != "paused" {
            notebooks[state.sessionID]?.stopRequested = true
            Task {
                do { _ = try await Task.detached { [registry] in try registry.pause(sessionID: state.sessionID) }.value }
                catch { message = error.localizedDescription }
                await refresh()
            }
        } else { perform { [registry] in _ = try registry.resume(sessionID: state.sessionID) } }
    }
    func stopNotebook(sessionID: String) {
        notebooks[sessionID]?.stopRequested = true
        Task {
            do { _ = try await Task.detached { [registry] in try registry.pause(sessionID: sessionID) }.value }
            catch { message = error.localizedDescription }
            await refresh()
        }
    }
    func end() {
        guard let state else { return }
        perform { [registry] in try registry.destroy(sessionID: state.sessionID) }
    }
    func selectManagedWindow(_ id: UInt32) {
        guard let state else { return }
        perform { [registry] in _ = try registry.selectWindow(sessionID: state.sessionID, windowID: id) }
    }
    func perform(_ operation: @escaping @Sendable () throws -> Void, completed: @escaping @MainActor () -> Void = {}) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            do { try await Task.detached { try operation() }.value; completed() }
            catch { message = error.localizedDescription }
            busy = false; await refresh()
        }
    }
    func runNotebook(sessionID: String, cellID: UUID? = nil) {
        guard !busy, let notebook = notebooks[sessionID], let target = sessions.first(where: { $0.sessionID == sessionID }) else { return }
        // Freeze run order/source/target. Edits made during a run apply to the next run.
        let commands = notebook.cells.filter { cellID == nil || $0.id == cellID }.map { ($0.id, $0.source) }
        guard !commands.isEmpty else { return }
        let app = target.app
        notebook.running = true; notebook.stopRequested = false; busy = true; message = nil
        Task {
            for (id, source) in commands {
                if notebook.stopRequested { break }
                guard let index = notebook.cells.firstIndex(where: { $0.id == id }) else { continue }
                notebook.cells[index].running = true
                let started = Date()
                let result: ToolCallResult
                do { result = try await Task.detached { try notebook.kernel.run(source: source, app: app) }.value }
                catch { result = .text(error.localizedDescription, isError: true) }
                if let index = notebook.cells.firstIndex(where: { $0.id == id }) {
                    let presentation = VirtualDisplayNotebookOutput(result)
                    notebook.cells[index].output = presentation.json
                    notebook.cells[index].uiTree = presentation.uiTree
                    notebook.cells[index].images = presentation.images
                    notebook.cells[index].isError = result.isError
                    notebook.cells[index].executedSource = source
                    notebook.cells[index].duration = Date().timeIntervalSince(started)
                    notebook.cells[index].running = false
                }
                await refresh()
                if result.isError || notebook.stopRequested { break }
            }
            notebook.running = false; busy = false
            await refresh()
        }
    }
}

struct VirtualDisplayWorkspaceView: View {
    @ObservedObject var model: VirtualDisplayWorkspaceModel
    var requestPermissions: () -> Void
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(model.sessions, id: \.sessionID, selection: $model.selectedSession) { state in
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.name(state), systemImage: "display")
                    Text("\(state.phase.capitalized) · \(state.applications.count) apps").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4).tag(state.sessionID)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 9) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable().frame(width: 30, height: 30)
                    Text("OpenComputerUse").font(.system(size: 16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    if let state = model.state, let capture = try? VirtualDisplaySessionRegistry.shared.capture(sessionID: state.sessionID) {
                        VSplitView {
                            VStack(spacing: 0) {
                                VirtualDisplayPreview(capture: capture, originalSize: model.originalSize).id(state.sessionID)
                                    .overlay(alignment: .topLeading) {
                                        if state.phase == "paused" { Label("Paused", systemImage: "pause.fill").padding(8).background(.regularMaterial).padding() }
                                    }.frame(minHeight: 180)
                                Divider()
                                HStack {
                                    Text(state.phase.capitalized)
                                    if !state.windows.isEmpty {
                                        Picker("Target", selection: Binding(get: { state.selectedWindowID ?? 0 }, set: { model.selectManagedWindow($0) })) {
                                            ForEach(state.windows) { window in
                                                let owner = state.applications.first { $0.pid == window.pid }?.name ?? "Application"
                                                Text("\(owner) — \(window.title)").tag(window.id)
                                            }
                                        }.frame(maxWidth: 380).disabled(model.busy)
                                    }
                                    Spacer()
                                    Text(state.sessionID).font(.caption.monospaced()).textSelection(.enabled)
                                }.padding(10)
                            }.frame(minHeight: 240)
                            if let notebook = model.notebooks[state.sessionID] {
                                WorkspaceNotebookView(notebook: notebook, busy: model.busy, selectedApp: state.app, run: { model.runNotebook(sessionID: state.sessionID, cellID: $0) }, stop: { model.stopNotebook(sessionID: state.sessionID) })
                                    .frame(minHeight: 180, idealHeight: 300)
                            }
                        }
                    } else if !model.permissionsGranted {
                        ContentUnavailableView {
                            Label("Permissions needed", systemImage: "lock.shield")
                        } description: {
                            Text("Allow Accessibility and Screen Recording to create and operate virtual desktops.")
                        } actions: { Button("Set up permissions") { requestPermissions() } }
                    } else {
                        ContentUnavailableView {
                            Label("Virtual sessions", systemImage: "display.2")
                        } actions: {
                            createSessionButton
                        }
                    }
                    if let message = model.message ?? model.state?.reason {
                        Text(message).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                    }
                }.navigationTitle(model.state.map(model.name) ?? "Virtual sessions")
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            withAnimation {
                                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                            }
                        } label: { Image(systemName: "sidebar.left") }
                            .help(columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")
                            .accessibilityLabel(columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")
                        Button(action: showCreateSession) { Image(systemName: "square.and.pencil") }
                            .help("New Session").accessibilityLabel("New Session")
                            .keyboardShortcut("n", modifiers: .command).disabled(model.busy)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { model.showingAddApp = true } label: { Label("Add application", systemImage: "plus.app") }
                            .disabled(model.busy || model.state == nil || model.state?.phase == "paused")
                        Button { model.pauseOrResume() } label: { Label(model.state?.phase == "paused" ? "Resume" : "Pause", systemImage: model.state?.phase == "paused" ? "play" : "pause") }
                            .disabled(model.state == nil || (model.busy && model.state?.phase == "paused"))
                        Button { model.end() } label: { Label("End session", systemImage: "stop") }.disabled(model.busy || model.state == nil)
                        Toggle("Original size", isOn: $model.originalSize).help("Display capture pixels at their original size")
                    }
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .sheet(isPresented: $model.showingCreate) { createSheet }
        .sheet(isPresented: $model.showingAddApp) { addAppSheet }
        .frame(minWidth: 900, minHeight: 660)
    }
    private func showCreateSession() {
        model.sessionName = ""
        model.showingCreate = true
    }
    @ViewBuilder private var createSessionButton: some View {
        let button = Button(action: showCreateSession) {
            Label("Create Session", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
        }.controlSize(.large).buttonBorderShape(.capsule).disabled(model.busy)
        if #available(macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }
    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create virtual session").font(.title2)
            TextField("Session name", text: $model.sessionName)
            HStack {
                Text("Display scale")
                Spacer()
                DisplayScalePopUp(selection: $model.scale, enabled: !model.busy)
                    .frame(width: 230, height: 34)
            }
            Text("Each session has its own virtual display. Applications can be added after creation.").foregroundStyle(.secondary)
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for macOS to create and capture the display…").foregroundStyle(.secondary)
                }
            }
            HStack {
                if !model.permissionsGranted { Button("Set up permissions") { model.showingCreate = false; requestPermissions() } }
                Spacer()
                Button("Cancel") { model.showingCreate = false }.disabled(model.busy)
                Button("Create") { model.create() }.keyboardShortcut(.defaultAction).disabled(model.busy || !model.permissionsGranted)
            }
            if let message = model.message { Text(message).foregroundStyle(.red) }
        }.padding(24).frame(width: 440)
    }
    private var addAppSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add application to session").font(.title2)
            TextField("Find an application", text: $model.search)
            List(model.filtered, selection: $model.selectedApp) { app in
                HStack { Text(app.name); Spacer(); Text(app.pid.map { "PID \($0)" } ?? "Installed").foregroundStyle(.secondary) }.tag(app.id)
            }.frame(height: 260)
            Toggle("Launch a dedicated instance", isOn: $model.launch)
            if !model.launch {
                Picker("Existing window", selection: $model.selectedWindow) {
                    Text("Select window").tag(Optional<UInt32>.none)
                    ForEach(model.windows) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            Text("Dedicated instances quit with the session. Borrowed windows are restored.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.showingAddApp = false }.disabled(model.busy)
                Button("Add") { model.addApplication() }.keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.chosen == nil || (!model.launch && model.selectedWindow == nil)) }
            if let message = model.message { Text(message).foregroundStyle(.red) }
        }.padding(24).frame(width: 500)
        .onChange(of: model.selectedApp) { _, _ in model.selectedWindow = nil; Task { await model.refresh() } }
    }
}

struct WorkspaceNotebookView: View {
    @ObservedObject var notebook: WorkspaceNotebook
    var busy: Bool
    var selectedApp: String?
    var run: (UUID?) -> Void
    var stop: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Actions").font(.headline)
                Text(selectedApp ?? "Calculator → TextEdit").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { run(nil) } label: { Label("Run all", systemImage: "play.fill") }.disabled(busy || notebook.cells.isEmpty)
                Button { stop() } label: { Label("Stop and pause", systemImage: "pause.fill") }.disabled(!notebook.running)
                Menu {
                    ForEach(["get_virtual_display_state", "get_app_state", "click", "set_value", "type_text", "press_key"], id: \.self) { tool in
                        Button(tool) { notebook.cells.append(.template(tool)) }
                    }
                } label: { Label("Add cell", systemImage: "plus") }.disabled(notebook.running)
            }.padding(10).background(.bar)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($notebook.cells) { $cell in
                            WorkspaceCommandCellView(cell: $cell, busy: busy, run: { run(cell.id) }, remove: { notebook.cells.removeAll { $0.id == cell.id } }).id(cell.id)
                        }
                    }.padding(12)
                }.onChange(of: notebook.cells.count) { previous, count in
                    if count > previous, let last = notebook.cells.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

struct WorkspaceCommandCellView: View {
    @Binding var cell: WorkspaceCommandCell
    var busy: Bool
    var run: () -> Void
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: run) { Image(systemName: "play.fill") }.help("Run cell").accessibilityLabel("Run \(cell.title)").disabled(busy)
                TextField("Cell title", text: $cell.title).textFieldStyle(.plain).font(.headline)
                if cell.running { ProgressView().controlSize(.small) }
                else if let duration = cell.duration {
                    Label(cell.isError ? "Error" : "Completed", systemImage: cell.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(cell.isError ? .red : .secondary).font(.caption)
                    Text(String(format: "%.2fs", duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(action: remove) { Image(systemName: "trash") }.help("Remove cell").disabled(busy)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $cell.source).font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(4).background(.quaternary.opacity(0.3))
                        .frame(height: 164).accessibilityLabel("Command \(cell.title)").disabled(cell.running)
                    if cell.executedSource != nil && cell.executedSource != cell.source {
                        Text("Edited since last run").font(.caption).foregroundStyle(.orange)
                    }
                }.frame(minWidth: 200, maxWidth: 320)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Result · JSON").font(.caption).foregroundStyle(.secondary)
                    if cell.executedSource != nil {
                        ScrollView([.horizontal, .vertical]) {
                            Text(cell.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: cell.uiTree == nil ? 164 : 100)
                        if cell.uiTree != nil || !cell.images.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                if let tree = cell.uiTree {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("UI Tree").font(.caption).foregroundStyle(.secondary)
                                        ScrollView([.horizontal, .vertical]) {
                                            Text(tree).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }.frame(maxWidth: .infinity)
                                }
                                if !cell.images.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Screenshot").font(.caption).foregroundStyle(.secondary)
                                        ForEach(Array(cell.images.enumerated()), id: \.offset) { _, data in
                                            if let image = NSImage(data: data) {
                                                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                            }
                                        }
                                    }.frame(width: 160)
                                }
                            }.frame(height: 240)
                        }
                    } else {
                        Text("Run this cell to inspect its result.").font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
                    }
                }.frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cell.isError ? Color.red.opacity(0.4) : Color.secondary.opacity(0.15)))
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 880), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Open Computer Use"; window.isReleasedWhenClosed = false; window.delegate = self
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
            window.contentView = NSHostingView(rootView: view)
            DispatchQueue.main.async { window.toolbar?.showsBaselineSeparator = false }
            window.center(); self.window = window
            installMenu()
        }
        keepOnPhysicalScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func keepOnPhysicalScreen() {
        guard let window else { return }
        let virtualIDs = VirtualDisplaySessionRegistry.shared.activeDisplayIDs
        let physical = NSScreen.screens.filter { !virtualIDs.contains(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
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

// AppKit popup menus overlay their selected row without resizing the sheet.
// Follows HeyYo's NativeAudioInputDevicePopUp pattern; no audio dependencies.
private struct DisplayScalePopUp: NSViewRepresentable {
    @Binding var selection: Int
    var enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("Display scale")
        for (scale, title) in [(1, "1× · 1920 × 1080"), (2, "2× · 3840 × 2160")] {
            button.addItem(withTitle: title)
            button.lastItem?.tag = scale
        }
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        button.selectItem(withTag: selection)
        button.isEnabled = enabled
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem else { return }
            selection.wrappedValue = item.tag
        }
    }
}
