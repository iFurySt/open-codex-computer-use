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

enum WorkspaceSidebarSelection: Hashable {
    case session(String)
    case display(UInt32)
}

enum WorkspaceCreationKind {
    case session, display
    var title: String { self == .session ? "New session" : "New display" }
}

@MainActor
final class VirtualDisplayWorkspaceModel: ObservableObject {
    @Published var applications: [VirtualDisplayAppChoice] = []
    @Published var sessions: [VirtualDisplayState] = []
    @Published var selectedSession: String?
    @Published var selectedDisplay: UInt32?
    @Published var displays: [VirtualDisplayResourceState] = []
    @Published var preferredDisplay: UInt32?
    @Published var displayNames: [UInt32: String] = [:]
    @Published var displayName = ""
    @Published var showingCreateDisplay = false
    @Published var names: [String: String] = [:]
    @Published var notebooks: [String: WorkspaceNotebook] = [:]
    @Published var selectedApp: String?
    @Published var windows: [VirtualDisplayWindowInfo] = []
    @Published var selectedWindow: UInt32?
    @Published var selectedProcessPID: Int32?
    @Published var candidateProcesses: [VirtualDisplayApplicationCandidate] = []
    @Published var search = ""
    @Published var launch = true
    @Published var scale = 1
    @Published var sessionName = ""
    @Published var originalSize = false
    @Published var busy = false
    @Published private(set) var creating: WorkspaceCreationKind?
    @Published private(set) var creationToast: String?
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
    func name(_ display: VirtualDisplayResourceState) -> String { displayNames[display.displayID] ?? "Display \(display.displayID)" }
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
        let selectedPID = selectedProcessPID
        let values = await Task.detached { [registry] in
            let apps = VirtualDisplaySessionRegistry.availableApplications()
            let selected = apps.first { $0.id == selection }
            let candidates = selected.map { (try? registry.applicationCandidates(app: $0.bundleIdentifier)) ?? [] } ?? []
            return (apps, registry.states(), candidates.first { $0.pid == selectedPID }?.windows ?? [], PermissionDiagnostics.current().allGranted, registry.displayStates(), selected == nil ? [] : candidates)
        }.value
        let previousDisplays = Set(displays.map(\.displayID))
        applications = values.0; sessions = values.1; permissionsGranted = values.3; displays = values.4
        if selection == selectedApp && selectedPID == selectedProcessPID {
            candidateProcesses = values.5
            windows = values.2
            if let selectedProcessPID, !candidateProcesses.contains(where: { $0.pid == selectedProcessPID }) {
                self.selectedProcessPID = nil
            }
        }
        let live = Set(sessions.map(\.sessionID))
        notebooks = notebooks.filter { live.contains($0.key) }
        names = names.filter { live.contains($0.key) }
        displayNames = displayNames.filter { key, _ in displays.contains { $0.displayID == key } }
        for state in sessions where notebooks[state.sessionID] == nil { notebooks[state.sessionID] = WorkspaceNotebook(sessionID: state.sessionID) }
        if let id = selectedDisplay, let display = displays.first(where: { $0.displayID == id }) {
            selectedSession = display.sessionIDs.first
        } else {
            selectedDisplay = nil
            if !live.contains(selectedSession ?? "") { selectedSession = sessions.first?.sessionID }
        }
        if previousDisplays != Set(displays.map(\.displayID)) { displayDidChange?() }
        if selectedWindow == nil || !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = nil }
    }
    func create() {
        guard !busy else { return }
        beginCreation(.session)
        let scale = scale; let title = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayID = preferredDisplay
        let configuration = displays.first(where: { $0.displayID == displayID })?.configuration ?? .init(scale: scale)
        Task {
            do {
                let created = try await Task.detached { [registry] in try registry.create(configuration: configuration, displayID: displayID) }.value
                names[created.sessionID] = title.isEmpty ? "Session \(sessions.count + 1)" : title
                selectedDisplay = nil; selectedSession = created.sessionID
                await refresh()
                creating = nil; busy = false
            } catch { await creationFailed(error, kind: .session) }
        }
    }
    func createDisplay() {
        guard !busy else { return }
        beginCreation(.display)
        let configuration = VirtualDisplayConfiguration(scale: scale)
        let title = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let id = try await Task.detached { [registry] in
                    try registry.prewarm(configuration: configuration, reuseDisplay: false)
                }.value
                if !title.isEmpty { displayNames[id] = title }
                selectedDisplay = id; selectedSession = nil
                await refresh()
                creating = nil; busy = false
            } catch { await creationFailed(error, kind: .display) }
        }
    }
    private func beginCreation(_ kind: WorkspaceCreationKind) {
        creating = kind; busy = true; message = nil; creationToast = nil
        showingCreate = false; showingCreateDisplay = false
    }
    private func creationFailed(_ error: Error, kind: WorkspaceCreationKind) async {
        creationToast = error.localizedDescription
        // Keep the skeleton and error together briefly, then restore the unmodified draft.
        // This also lets AppKit finish dismissing a sheet when creation fails immediately.
        try? await Task.sleep(for: .seconds(2.5))
        await refresh()
        creationToast = nil; creating = nil; busy = false
        if kind == .session { showingCreate = true } else { showingCreateDisplay = true }
    }
    func addApplication() {
        guard !busy, let app = chosen, let state else { return }
        let mode = launch; let window = selectedWindow; let processPID = selectedProcessPID
        let previousPIDs = Set(state.applications.map(\.pid))
        busy = true; message = nil
        Task {
            do {
                let result = try await Task.detached { [registry] in
                    try registry.attach(sessionID: state.sessionID, app: app.bundleIdentifier,
                        pid: mode ? nil : processPID, windowID: mode ? nil : window, launch: mode)
                }.value
                if mode {
                    // A new process is owned, but no window has been selected for movement.
                    launch = false
                    selectedProcessPID = result.applications.first { !previousPIDs.contains($0.pid) }?.pid
                    selectedWindow = nil
                } else { showingAddApp = false }
            } catch { message = error.localizedDescription }
            busy = false; await refresh()
        }
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
    var sidebarSelection: WorkspaceSidebarSelection? {
        get { selectedDisplay.map(WorkspaceSidebarSelection.display) ?? selectedSession.map(WorkspaceSidebarSelection.session) }
        set {
            switch newValue {
            case .session(let id): selectedDisplay = nil; selectedSession = id
            case .display(let id): selectedDisplay = id; selectedSession = displays.first { $0.displayID == id }?.sessionIDs.first
            case nil: break // Collapsing a group must not clear the current desktop.
            }
        }
    }
    func deleteSession(_ id: String, deleteDisplay: Bool = false) {
        notebooks[id]?.stopRequested = true
        perform { [registry] in try registry.destroy(sessionID: id, retainDisplay: !deleteDisplay) }
    }
    func deleteDisplay(_ display: VirtualDisplayResourceState) {
        for id in display.sessionIDs { notebooks[id]?.stopRequested = true }
        perform { [registry] in try registry.destroyDisplay(displayID: display.displayID) }
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

private enum WorkspaceSidebarLayout {
    // One explicit gutter: avoid sidebar List's state-dependent automatic insets.
    static let outerInset: CGFloat = 10
    static let childIndent: CGFloat = 12
    static let rowInset: CGFloat = 8

    static let resourceInsets = EdgeInsets(
        top: 0, leading: rowInset + childIndent, bottom: 0, trailing: rowInset
    )
}

struct VirtualDisplayWorkspaceView: View {
    @ObservedObject var model: VirtualDisplayWorkspaceModel
    var requestPermissions: () -> Void
    @State private var sessionsExpanded = true
    @State private var displaysExpanded = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    WorkspaceSidebarGroupHeader(title: "Sessions", expanded: $sessionsExpanded, busy: model.busy, create: showCreateSession)

                    if sessionsExpanded {
                        ForEach(model.sessions, id: \.sessionID) { state in
                            WorkspaceSidebarResourceRow(title: model.name(state), subtitle: "\(state.phase.capitalized) · \(state.applications.count) apps", icon: "rectangle.stack", busy: model.busy,
                                selected: model.sidebarSelection == .session(state.sessionID),
                                select: { model.sidebarSelection = .session(state.sessionID) },
                                delete: { model.deleteSession(state.sessionID) })
                                .contextMenu {
                                    Button("Delete Session", role: .destructive) { model.deleteSession(state.sessionID) }.disabled(model.busy)
                                    Button("Delete Session and Display", role: .destructive) { model.deleteSession(state.sessionID, deleteDisplay: true) }.disabled(model.busy)
                                }
                        }
                    }
                    WorkspaceSidebarGroupHeader(title: "Displays", expanded: $displaysExpanded, busy: model.busy, create: showCreateDisplay)
                        .padding(.top, 8)
                    if displaysExpanded {
                        ForEach(model.displays) { display in
                            WorkspaceSidebarResourceRow(title: model.name(display), subtitle: displaySubtitle(display), icon: "display", busy: model.busy,
                                selected: model.sidebarSelection == .display(display.displayID),
                                select: { model.sidebarSelection = .display(display.displayID) },
                                delete: { model.deleteDisplay(display) })
                                .contextMenu {
                                    Button("Delete Display and Sessions", role: .destructive) { model.deleteDisplay(display) }.disabled(model.busy)
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WorkspaceSidebarLayout.outerInset)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 9) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable().frame(width: 30, height: 30)
                    Text("OpenComputerUse").font(.system(size: 16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WorkspaceSidebarLayout.outerInset).padding(.top, 12).padding(.bottom, 20)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: showCreateSession) { Image(systemName: "square.and.pencil") }
                        .help("New Session").accessibilityLabel("New Session")
                        .keyboardShortcut("n", modifiers: .command).disabled(model.busy)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    if let creating = model.creating {
                        WorkspaceCreationSkeleton(kind: creating)
                    } else if let state = model.state, let capture = try? VirtualDisplaySessionRegistry.shared.capture(sessionID: state.sessionID) {
                        VSplitView {
                            VStack(spacing: 0) {
                                VirtualDisplayPreview(capture: capture, originalSize: model.originalSize).id(state.sessionID)
                                    .overlay(alignment: .topLeading) {
                                        if state.phase == "paused" { Label("Paused", systemImage: "pause.fill").padding(8).background(.regularMaterial).padding() }
                                    }.frame(minHeight: 180)
                            }.frame(minHeight: 240)
                            if let notebook = model.notebooks[state.sessionID] {
                                WorkspaceNotebookView(notebook: notebook, busy: model.busy, selectedApp: state.app, run: { model.runNotebook(sessionID: state.sessionID, cellID: $0) }, stop: { model.stopNotebook(sessionID: state.sessionID) })
                                    .frame(minHeight: 180, idealHeight: 300)
                            }
                        }
                    } else if let id = model.selectedDisplay, let display = model.displays.first(where: { $0.displayID == id }) {
                        ContentUnavailableView {
                            Label(model.name(display), systemImage: "display")
                        } description: {
                            Text(displaySubtitle(display))
                        } actions: {
                            sessionCreationButton { showCreateSession(on: display) }
                                .disabled(!display.online || !model.permissionsGranted)
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
                    if model.creating == nil, let message = model.message ?? model.state?.reason {
                        Text(message).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                    }
                }
                .overlay(alignment: .top) {
                    if let error = model.creationToast {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.callout).lineLimit(3).help(error)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                            .padding(20).accessibilityLabel("Creation failed: \(error)")
                    }
                }
                .navigationTitle(model.creating?.title ?? (model.state == nil ? model.selectedDisplay.map { "Display \($0)" } ?? "Virtual sessions" : ""))
                .toolbar {
                    sessionTitleToolbarItem
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.selectedDisplay == nil, model.creating == nil, model.state != nil {
                            if let state = model.state, !state.windows.isEmpty {
                                Picker("Target", selection: Binding(get: { state.selectedWindowID ?? 0 }, set: { model.selectManagedWindow($0) })) {
                                    ForEach(state.windows) { window in
                                        let owner = state.applications.first { $0.pid == window.pid }?.name ?? "Application"
                                        Text("\(owner) — \(window.title)").tag(window.id)
                                    }
                                }.frame(maxWidth: 220).disabled(model.busy)
                            }
                            Button { model.showingAddApp = true } label: { Label("Add application", systemImage: "plus.app") }
                                .disabled(model.busy || model.state == nil || model.state?.phase == "paused")
                            Button { model.pauseOrResume() } label: { Label(model.state?.phase == "paused" ? "Resume" : "Pause", systemImage: model.state?.phase == "paused" ? "play" : "pause") }
                                .disabled(model.creating != nil || model.state == nil || (model.busy && model.state?.phase == "paused"))
                            Button { model.end() } label: { Label("End session", systemImage: "stop") }.disabled(model.busy || model.state == nil)
                            Toggle("Original size", isOn: $model.originalSize).help("Display capture pixels at their original size")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $model.showingCreate) { createSheet }
        .sheet(isPresented: $model.showingCreateDisplay) { createDisplaySheet }
        .sheet(isPresented: $model.showingAddApp) { addAppSheet }
        .frame(minWidth: 900, minHeight: 660)
    }
    @ToolbarContentBuilder private var sessionTitleToolbarItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { sessionHeader }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { sessionHeader }
        }
    }
    @ViewBuilder private var sessionHeader: some View {
        if model.creating == nil, let state = model.state {
            WorkspaceSessionHeader(name: model.name(state), sessionID: state.sessionID, phase: state.phase)
        }
    }
    private func showCreateDisplay() {
        model.displayName = ""; model.message = nil; model.showingCreateDisplay = true
    }
    private func showCreateSession() {
        model.message = nil
        model.sessionName = ""
        model.preferredDisplay = nil
        model.showingCreate = true
    }
    private func showCreateSession(on display: VirtualDisplayResourceState) {
        showCreateSession()
        model.preferredDisplay = display.displayID
        model.scale = display.configuration.scale
    }
    private func displaySubtitle(_ display: VirtualDisplayResourceState) -> String {
        let status = !display.online ? "Disconnected" : display.sessionIDs.isEmpty ? "Ready for reuse" : "In use"
        return "\(display.configuration.width) × \(display.configuration.height) · \(display.configuration.scale)× · \(status)"
    }
    private var createSessionButton: some View { sessionCreationButton(action: showCreateSession) }
    @ViewBuilder private func sessionCreationButton(action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
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
    private var displayChoices: [WorkspaceChoicePopUp.Choice] {
        var choices: [WorkspaceChoicePopUp.Choice] = [.init(value: 0, title: "Automatic — reuse or create")]
        choices += model.displays.map { display in
            let available = display.online && display.sessionIDs.isEmpty
            let suffix = !display.online ? " · Disconnected" : display.sessionIDs.isEmpty ? "" : " · In use"
            return .init(value: Int(display.displayID), title: model.name(display) + suffix, enabled: available)
        }
        if let id = model.preferredDisplay, !model.displays.contains(where: { $0.displayID == id }) {
            choices.append(.init(value: Int(id), title: "Display \(id) · Unavailable", enabled: false))
        }
        return choices
    }
    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create virtual session").font(.title2)
            TextField("Session name (optional)", text: $model.sessionName)
            HStack {
                Text("Display")
                Spacer()
                WorkspaceChoicePopUp(
                    selection: Binding(
                        get: { model.preferredDisplay.map(Int.init) ?? 0 },
                        set: { model.preferredDisplay = $0 == 0 ? nil : UInt32($0) }
                    ),
                    choices: displayChoices,
                    accessibilityLabel: "Display", enabled: !model.busy
                ).frame(width: 230, height: 34)
            }
            .onChange(of: model.preferredDisplay) { _, id in
                if let display = model.displays.first(where: { $0.displayID == id }) {
                    model.scale = display.configuration.scale
                }
            }
            HStack {
                Text("Display scale")
                Spacer()
                DisplayScalePopUp(selection: $model.scale, enabled: !model.busy && model.preferredDisplay == nil)
                    .frame(width: 230, height: 34)
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
    private var createDisplaySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create virtual display").font(.title2)
            TextField("Display name (optional)", text: $model.displayName)
            HStack {
                Text("Display scale")
                Spacer()
                DisplayScalePopUp(selection: $model.scale, enabled: !model.busy)
                    .frame(width: 230, height: 34)
            }
            HStack {
                if !model.permissionsGranted {
                    Button("Set up permissions") { model.showingCreateDisplay = false; requestPermissions() }
                }
                Spacer()
                Button("Cancel") { model.showingCreateDisplay = false }.disabled(model.busy)
                Button("Create") { model.createDisplay() }.keyboardShortcut(.defaultAction)
                    .disabled(model.busy || !model.permissionsGranted)
            }
            if let message = model.message { Text(message).foregroundStyle(.red) }
        }.padding(24).frame(width: 440)
    }
    private var applicationScopeDescription: String {
        if model.launch {
            return "Request a new dedicated instance, then select its windows. It will quit safely with the session."
        }
        if model.state?.applications.contains(where: { $0.pid == model.selectedProcessPID && $0.owned }) == true {
            return "Select this dedicated instance’s windows one at a time. It stays hidden until every window is contained, and quits safely with the session."
        }
        return "Only the selected window will temporarily move to the virtual display. Other windows stay in place; the borrowed process will not quit."
    }

    private var addAppSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add application to session").font(.title2)
            TextField("Find an application", text: $model.search)
            List(model.filtered, selection: $model.selectedApp) { app in
                HStack { Text(app.name); Spacer(); Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.tag(app.id)
            }.frame(height: 260)
            Toggle("Launch a dedicated instance", isOn: $model.launch)
            if !model.launch {
                Picker("Existing process", selection: $model.selectedProcessPID) {
                    Text("Select process").tag(Optional<Int32>.none)
                    ForEach(model.candidateProcesses) { candidate in
                        Text("\(candidate.name) · PID \(candidate.pid)").tag(Optional(candidate.pid))
                    }
                }
                Picker("Existing window", selection: $model.selectedWindow) {
                    Text("Select window").tag(Optional<UInt32>.none)
                    ForEach(model.windows) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            Text(applicationScopeDescription).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.showingAddApp = false }.disabled(model.busy)
                Button(model.launch ? "Launch" : "Move selected window") { model.addApplication() }.keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.chosen == nil || (!model.launch && (model.selectedProcessPID == nil || model.selectedWindow == nil))) }
            if let message = model.message { Text(message).foregroundStyle(.red) }
        }.padding(24).frame(width: 500)
        .onChange(of: model.selectedApp) { _, _ in model.selectedWindow = nil; model.selectedProcessPID = nil; Task { await model.refresh() } }
        .onChange(of: model.selectedProcessPID) { _, _ in model.selectedWindow = nil; Task { await model.refresh() } }
    }
}

private struct WorkspaceCreationSkeleton: View {
    let kind: WorkspaceCreationKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                bar(width: 90, height: 12)
                Spacer()
                bar(width: 180, height: 12)
            }
            if kind == .session {
                Divider()
                HStack {
                    bar(width: 110, height: 14)
                    Spacer()
                    bar(width: 72, height: 24)
                }
                ForEach(0..<2) { _ in
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.14))
                        RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.14))
                    }.frame(height: 82)
                }
            }
        }
        .padding(20)
        .opacity(dimmed && !reduceMotion ? 0.25 : 1)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { dimmed = true }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .session ? "Creating virtual session" : "Creating virtual display")
    }
    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.22)).frame(width: width, height: height)
    }
}

private struct WorkspaceSidebarGroupHeader: View {
    let title: String
    @Binding var expanded: Bool
    let busy: Bool
    let create: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).opacity(hovering ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 22)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(title)")
            Button(action: create) { Image(systemName: "plus").frame(width: 28, height: 38).contentShape(Rectangle()) }
                .buttonStyle(WorkspaceIconButtonStyle()).opacity(hovering ? 1 : 0).disabled(busy)
                .help(title == "Displays" ? "New Display" : "New Session")
                .accessibilityLabel(title == "Displays" ? "New Display" : "New Session")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct WorkspaceSidebarResourceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let busy: Bool
    let selected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Image(systemName: icon).frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, WorkspaceSidebarLayout.resourceInsets.leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button(action: delete) { Image(systemName: "trash").frame(width: 22, height: 24) }
                .buttonStyle(WorkspaceIconButtonStyle()).opacity(hovering ? 1 : 0).disabled(busy)
                .padding(.trailing, WorkspaceSidebarLayout.resourceInsets.trailing)
                .help("Delete \(title)").accessibilityLabel("Delete \(title)")
        }
        .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : hovering ? Color.primary.opacity(0.04) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle()).onHover { hovering = $0 }
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
                Button(action: run) { Image(systemName: "play.fill").frame(width: 28, height: 24) }.buttonStyle(WorkspaceIconButtonStyle()).help("Run cell").accessibilityLabel("Run \(cell.title)").disabled(busy)
                TextField("Cell title", text: $cell.title).textFieldStyle(.plain).font(.headline)
                if cell.running { ProgressView().controlSize(.small) }
                else if let duration = cell.duration {
                    Label(cell.isError ? "Error" : "Completed", systemImage: cell.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(cell.isError ? .red : .secondary).font(.caption)
                    Text(String(format: "%.2fs", duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(action: remove) { Image(systemName: "trash").frame(width: 28, height: 24) }.buttonStyle(WorkspaceIconButtonStyle()).help("Remove cell").disabled(busy)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    WorkspaceCodeBlock(text: $cell.source, title: "Command", editable: !cell.running)
                        .frame(height: 194).accessibilityLabel("Command \(cell.title)")
                    if cell.executedSource != nil && cell.executedSource != cell.source {
                        Text("Edited since last run").font(.caption).foregroundStyle(.orange)
                    }
                }.frame(minWidth: 200, maxWidth: 320)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    WorkspaceCodeBlock(text: .constant(cell.executedSource == nil ? "" : cell.output), title: "Result", editable: false)
                        .frame(height: cell.uiTree == nil ? 194 : 130)
                    if cell.executedSource != nil {
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
        let virtualIDs = VirtualDisplaySessionRegistry.shared.ownedDisplayIDs
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

// Shared native selection control, following HeyYo's Microphone popup pattern.
// A selected-row popup overlays the trigger; fixed width keeps both form rows aligned.
private struct DisplayScalePopUp: View {
    @Binding var selection: Int
    var enabled: Bool
    var body: some View {
        WorkspaceChoicePopUp(selection: $selection, choices: [
            .init(value: 1, title: "1× · 1920 × 1080"),
            .init(value: 2, title: "2× · 3840 × 2160")
        ], accessibilityLabel: "Display scale", enabled: enabled)
    }
}

private struct WorkspaceChoicePopUp: NSViewRepresentable {
    struct Choice: Equatable {
        let value: Int
        let title: String
        var enabled = true
    }
    @Binding var selection: Int
    let choices: [Choice]
    let accessibilityLabel: String
    var enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        // Polling refreshes the workspace; leave the menu intact when its options are unchanged.
        if context.coordinator.choices != choices {
            button.removeAllItems()
            for choice in choices {
                button.addItem(withTitle: choice.title)
                button.lastItem?.tag = choice.value
                button.lastItem?.isEnabled = choice.enabled
            }
            button.menu?.autoenablesItems = false
            context.coordinator.choices = choices
        }
        // Native menus reserve a leading checkmark gutter while anchoring the title.
        // Include that gutter so the menu also covers the trigger’s trailing arrows.
        button.menu?.minimumWidth = 246
        if button.selectedItem?.tag != selection { button.selectItem(withTag: selection) }
        button.isEnabled = enabled
        button.setAccessibilityLabel(accessibilityLabel)
        button.cell?.lineBreakMode = .byTruncatingMiddle
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Int>
        var choices: [Choice] = []
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem else { return }
            selection.wrappedValue = item.tag
        }
    }
}
