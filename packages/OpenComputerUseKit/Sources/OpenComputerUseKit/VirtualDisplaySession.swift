import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct VirtualDisplayConfiguration: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var scale: Int
    public init(width: Int = 1920, height: Int = 1080, scale: Int = 1) {
        self.width = width; self.height = height; self.scale = scale
    }
    public func validate() throws {
        guard (640...7680).contains(width), (480...4320).contains(height), [1, 2].contains(scale),
              width * scale <= 7680, height * scale <= 4320 else {
            throw ComputerUseError.invalidArguments("Display size must fit 7680×4320 pixels; scale must be 1 or 2")
        }
    }
}

public struct VirtualDisplayAppChoice: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let pid: Int32?
}

public struct VirtualDisplayWindowInfo: Identifiable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var title: String
    public var frame: CGRect
}

/// A read-only candidate is not an authorization to move or operate its windows.
public struct VirtualDisplayApplicationCandidate: Identifiable, Sendable {
    public let pid: Int32
    public let app: String
    public let name: String
    public let windows: [VirtualDisplayWindowInfo]
    public let windowsAvailable: Bool
    public var id: Int32 { pid }
    public var dictionary: [String: Any] {
        ["pid": pid, "app": app, "name": name, "windows_available": windowsAvailable,
         "windows": windows.map { ["window_id": $0.id, "pid": $0.pid, "title": $0.title,
                                    "frame": rectDictionary($0.frame)] as [String: Any] }]
    }
}

public struct VirtualDisplayLaunchReusedError: LocalizedError {
    public let candidates: [VirtualDisplayApplicationCandidate]
    public var errorDescription: String? { "Launch reused an existing application; explicitly select a candidate PID and window_id to adopt" }
    public var dictionary: [String: Any] {
        ["error": "launch_reused_existing_instance", "message": errorDescription!,
         "candidates": candidates.map(\.dictionary)]
    }
}

/// Validate caller intent before touching a session or requesting an application launch.
enum VirtualDisplayAttachmentIntent {
    static func validate(app: String?, pid: Int32?, windowID: UInt32?, launch: Bool, newDocument: Bool) throws {
        if launch {
            guard let app, !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  pid == nil, windowID == nil else {
                throw ComputerUseError.invalidArguments("Launch requires app and does not accept pid/window_id")
            }
        } else {
            guard let pid, pid > 0, let windowID, windowID > 0, !newDocument else {
                throw ComputerUseError.invalidArguments("Adoption requires an explicit live pid and window_id; new_document is launch-only")
            }
        }
        if newDocument, app?.caseInsensitiveCompare("com.apple.TextEdit") != .orderedSame {
            throw ComputerUseError.invalidArguments("new_document requires a dedicated TextEdit launch")
        }
    }

    static func shouldPauseForUnmanagedWindow(owned: Bool, hidden: Bool, modal: Bool) -> Bool {
        modal || (owned && !hidden)
    }

    static func verifiedDedicatedInstance(pid: Int32, previousPIDs: Set<Int32>, requestedApp: String,
                                          actualApp: String?, birth: Date?) -> Bool {
        !previousPIDs.contains(pid) && birth != nil && actualApp?.caseInsensitiveCompare(requestedApp) == .orderedSame
    }
}

public struct VirtualDisplayApplicationInfo: Identifiable, Sendable {
    public let pid: Int32
    public let app: String
    public let name: String
    public let owned: Bool
    public let documentURL: URL?
    public let selectedWindowID: UInt32?
    public let candidateWindows: [VirtualDisplayWindowInfo]
    public var id: Int32 { pid }
}

/// A display resource can be leased to a session or held idle for reuse.
public struct VirtualDisplayResourceState: Identifiable, Sendable {
    public let displayID: UInt32
    public let helperPID: Int32
    public let configuration: VirtualDisplayConfiguration
    public let frame: CGRect
    public let sessionIDs: [String]
    public let online: Bool
    public var id: UInt32 { displayID }
    public var dictionary: [String: Any] {
        ["display_id": displayID, "helper_pid": helperPID,
         "configuration": ["width": configuration.width, "height": configuration.height, "scale": configuration.scale],
         "frame": rectDictionary(frame), "session_ids": sessionIDs, "online": online]
    }
}

public struct VirtualDisplayState: Sendable {
    public let sessionID: String
    public let displayID: UInt32
    public let helperPID: Int32
    public let frame: CGRect
    public let configuration: VirtualDisplayConfiguration
    public let phase: String
    public let reason: String?
    public let pid: Int32?
    public let app: String?
    public let selectedWindowID: UInt32?
    public let windows: [VirtualDisplayWindowInfo]
    public let applications: [VirtualDisplayApplicationInfo]
    public let layoutVersion: Int
    public let foregroundBeforeCreation: Int32?
    public let foregroundAfterCreation: Int32?
    public let physicalLayoutPreserved: Bool
    public let displaySerial: UInt32
    public let additionalConfigurationApplied: Bool
    public let desktopBeforeCreation: VirtualDisplayDesktopObservation?
    public let desktopAfterCreation: VirtualDisplayDesktopObservation?
    public var displayReused: Bool = false
    public let captureIsRunning: Bool
    public let lastFrameDate: Date?
    public let captureError: String?
    public var dictionary: [String: Any] {
        var value: [String: Any] = ["session_id": sessionID, "display_id": displayID, "helper_pid": helperPID,
            "phase": phase, "layout_version": layoutVersion, "display_reused": displayReused,
            "configuration": ["width": configuration.width, "height": configuration.height, "scale": configuration.scale],
            "frame": rectDictionary(frame), "windows": windows.map { ["window_id": $0.id, "pid": $0.pid, "title": $0.title, "frame": rectDictionary($0.frame)] as [String: Any] },
            "capabilities": ["global_input": false, "manual_preview_input": false, "system_drag_and_drop": false, "drag": false]]
        var captureState: [String: Any] = ["running": captureIsRunning]
        captureState["frame_age_seconds"] = lastFrameDate.map { max(0, Date().timeIntervalSince($0)) }
        captureState["error"] = captureError
        value["applications"] = applications.map { application in
            var entry: [String: Any] = ["pid": application.pid, "app": application.app, "name": application.name, "owned": application.owned]
            entry["document_path"] = application.documentURL?.path
            entry["selected_window_id"] = application.selectedWindowID
            entry["candidate_windows"] = application.candidateWindows.map { ["window_id": $0.id, "pid": $0.pid, "title": $0.title, "frame": rectDictionary($0.frame)] as [String: Any] }
            return entry
        }
        value["capture"] = captureState
        var observation: [String: Any] = ["physical_layout_preserved": physicalLayoutPreserved]
        observation["foreground_before_pid"] = foregroundBeforeCreation
        observation["foreground_after_pid"] = foregroundAfterCreation
        observation["display_serial"] = displaySerial
        observation["additional_configuration_applied"] = additionalConfigurationApplied
        observation["desktop_before"] = desktopBeforeCreation?.dictionary
        observation["desktop_after"] = desktopAfterCreation?.dictionary
        if let before = desktopBeforeCreation, let after = desktopAfterCreation {
            observation["main_display_preserved"] = before.mainDisplayID == after.mainDisplayID
            if let dock = before.dockDisplayID { observation["dock_display_preserved"] = dock == after.dockDisplayID }
        }
        value["creation_observation"] = observation
        value["reason"] = reason; value["pid"] = pid; value["app"] = app; value["selected_window_id"] = selectedWindowID
        return value
    }
}

private func rectDictionary(_ frame: CGRect) -> [String: Double] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
}

enum VirtualDisplaySessionStartupPolicy {
    static func creationPauseReason(physicalLayoutPreserved: Bool) -> String? {
        physicalLayoutPreserved ? nil : "Physical display layout changed during setup; inspect before resuming"
    }

    static func shouldPauseForDesktopChange(onlyManagedApplications: Bool, hasManagedApplications: Bool) -> Bool {
        !onlyManagedApplications || hasManagedApplications
    }
}

public enum VirtualDisplayCoordinates {
    public static func globalPoint(pixel: CGPoint, pixelSize: CGSize, bounds: CGRect) throws -> CGPoint {
        guard pixelSize.width.isFinite, pixelSize.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              pixelSize.width > 0, pixelSize.height > 0, bounds.width > 0, bounds.height > 0,
              pixel.x.isFinite, pixel.y.isFinite, pixel.x >= 0, pixel.y >= 0,
              pixel.x < pixelSize.width, pixel.y < pixelSize.height else {
            throw ComputerUseError.invalidArguments("Point is outside the current captured image")
        }
        return CGPoint(x: bounds.minX + pixel.x * bounds.width / pixelSize.width,
                       y: bounds.minY + pixel.y * bounds.height / pixelSize.height)
    }
}

struct VirtualDisplayWindow {
    let info: VirtualDisplayWindowInfo
    let element: AXUIElement
}

// AXWindowNumber is not consistently exposed. Resolve the window server identity,
// never choose an AX window by title alone (duplicate titles are common).
enum VirtualDisplayWindowAccess {
    typealias WindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    static let windowFunction: WindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowFunction.self)
    }()
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func contains(_ element: AXUIElement, in root: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<64 {
            if CFEqual(current, root) { return true }
            guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            current = parent as! AXUIElement
        }
        return false
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    static func windows(pid: pid_t, includeOffscreen: Bool = false) -> [VirtualDisplayWindow] {
        let application = AXUIElementCreateApplication(pid)
        guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        let info = CGWindowListCopyWindowInfo(includeOffscreen ? .optionAll : .optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return elements.compactMap { element in
            var id: CGWindowID = 0
            guard windowFunction?(element, &id) == .success, id != 0,
                  let record = info.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }),
                  let frame = frame(element), frame.width > 0, frame.height > 0,
                  (record[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return VirtualDisplayWindow(info: .init(id: id, pid: pid, title: attribute(element, kAXTitleAttribute) as? String ?? "Untitled", frame: frame), element: element)
        }
    }
    static func place(_ window: VirtualDisplayWindow, frame: CGRect) throws {
        guard (attribute(window.element, kAXMinimizedAttribute) as? Bool) != true,
              (attribute(window.element, "AXFullScreen") as? Bool) != true else {
            throw ComputerUseError.message("Minimized and full-screen windows cannot be managed")
        }
        var position = frame.origin; var size = frame.size
        guard let pointValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw ComputerUseError.message("Cannot create window geometry")
        }
        if abs(window.info.frame.width - size.width) > 2 || abs(window.info.frame.height - size.height) > 2 {
            guard AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue) == .success else {
                throw ComputerUseError.message("Window is not resizable")
            }
        }
        guard AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, pointValue) == .success else {
            throw ComputerUseError.message("Window is not movable")
        }
        Thread.sleep(forTimeInterval: 0.12)
        guard let actual = self.frame(window.element), close(actual, frame) else {
            throw ComputerUseError.message("Application rejected requested window geometry")
        }
    }
    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}

private final class VirtualDisplayHolder {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    var displayID: UInt32 = 0
    let serial: UInt32
    var additionalConfigurationApplied = false
    init(configuration: VirtualDisplayConfiguration, serial: UInt32) throws {
        self.serial = serial
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VirtualDisplayHost")
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayHost")
        process.executableURL = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : sibling
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        do {
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as! [String: Any]
            // Reuse an unoccupied stable identity so WindowServer can remember its arrangement.
            value["serial"] = serial
            var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
            let reply = try readReply(timeout: 10)
            if let error = reply["error"] as? String { throw ComputerUseError.message(error) }
            guard let id = reply["display_id"] as? NSNumber, id.uint32Value != 0 else { throw ComputerUseError.message("Invalid display-holder response") }
            displayID = id.uint32Value
            additionalConfigurationApplied = reply["configuration_applied"] as? Bool ?? true
        } catch { stop(); throw error }
    }
    private func readReply(timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var bytes = Data()
        while Date() < deadline, bytes.count < 65536 {
            var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            if poll(&fd, 1, 100) > 0 {
                var byte: UInt8 = 0
                guard read(fd.fd, &byte, 1) == 1 else { break }
                if byte == 10 { return try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:] }
                bytes.append(byte)
            }
        }
        throw ComputerUseError.message("Display-holder startup timed out or exited")
    }
    func stop() {
        // EOF is reliable even when the private object's last reference is retained internally.
        try? input.fileHandleForWriting.close()
        let deadline = Date(timeIntervalSinceNow: 3)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate() }
        let terminationDeadline = Date(timeIntervalSinceNow: 2)
        while process.isRunning, Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
    deinit { if process.isRunning { stop() } }
}

struct VirtualDisplayOperationContext {
    let sessionID: String
    let app: RunningAppDescriptor
    let window: VirtualDisplayWindow
    let layoutVersion: Int
    var cacheKey: String { "\(sessionID):\(app.pid):\(window.info.id):\(layoutVersion)" }
}

private func processStartDate(_ pid: Int32) -> Date? {
    var info = proc_bsdinfo()
    let bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    if bytes == MemoryLayout<proc_bsdinfo>.size, info.pbi_start_tvsec != 0 {
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
    return NSRunningApplication(processIdentifier: pid)?.launchDate
}

private struct OwnedApplicationRecovery: Codable {
    let pid: Int32
    let startDate: Date
    let bundleIdentifier: String?
    let profile: URL?
    let documentDirectory: URL?
}

private struct WindowRecovery: Codable {
    let pid: Int32
    let launchDate: Date?
    let bundleIdentifier: String?
    let windowID: UInt32
    let frame: CGRect
    let displayID: UInt32?
    let displayFrame: CGRect?
}

/// Registered as soon as LaunchServices returns a verified new instance.
/// Notification is post-creation: containment improves latency, never guarantees zero flash.
private final class DedicatedLaunchWindowObserver: @unchecked Sendable {
    private let application: NSRunningApplication
    private let birth: Date
    private var observer: AXObserver?
    private var containing = true // Accessed only on AppKit's main run loop.

    init?(application: NSRunningApplication, birth: Date) {
        precondition(Thread.isMainThread)
        self.application = application; self.birth = birth
        var value: AXObserver?
        guard AXObserverCreate(application.processIdentifier, { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<DedicatedLaunchWindowObserver>.fromOpaque(context).takeUnretainedValue()
            owner.containCreatedWindow()
        }, &value) == .success, let value else { return nil }
        guard AXObserverAddNotification(value, AXUIElementCreateApplication(application.processIdentifier),
            kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success else { return nil }
        observer = value
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(value), .commonModes)
    }

    private func containCreatedWindow() {
        guard containing, !application.isTerminated,
              processStartDate(application.processIdentifier) == birth,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier else { return }
        _ = application.hide()
    }

    func finishContainment() {
        if Thread.isMainThread { containing = false }
        else { DispatchQueue.main.sync { containing = false } }
    }

    deinit {
        guard let observer else { return }
        let remove = {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        if Thread.isMainThread { remove() } else { DispatchQueue.main.sync(execute: remove) }
    }
}

private final class VirtualDisplayApplication {
    let application: NSRunningApplication
    let processBirthDate: Date
    let owned: Bool
    let temporaryProfile: URL?
    let documentURL: URL?
    var selected: UInt32?
    var launchObserver: DedicatedLaunchWindowObserver?
    init(application: NSRunningApplication, processBirthDate: Date, owned: Bool, temporaryProfile: URL?, documentURL: URL?) {
        self.application = application; self.processBirthDate = processBirthDate
        self.owned = owned; self.temporaryProfile = temporaryProfile; self.documentURL = documentURL
    }
}

private final class VirtualDisplaySession {
    let id = UUID().uuidString
    let holder: VirtualDisplayHolder
    let configuration: VirtualDisplayConfiguration
    let capture = VirtualDisplayCapture()
    var displayReused = false
    var bounds: CGRect
    var version = 1
    var physicalLayout: [UInt32: CGRect] = [:]
    var desktopBefore: VirtualDisplayDesktopObservation?
    var desktopAfter: VirtualDisplayDesktopObservation?
    var foregroundBefore: Int32?
    var foregroundAfter: Int32?
    var layoutPreserved = true
    var applications: [Int32: VirtualDisplayApplication] = [:]
    var selectedPID: Int32?
    var selected: UInt32? { selectedPID.flatMap { applications[$0]?.selected } }
    var originals: [UInt32: WindowRecovery] = [:]
    var frames: [UInt32: CGRect] = [:]
    let pauseLock = NSLock()
    private var pauseReason: String?
    private var targetPIDs: Set<Int32> = []
    func setPIDs(_ pids: Set<Int32>) { pauseLock.lock(); targetPIDs = pids; pauseLock.unlock() }
    func pauseIfActivated(_ pid: Int32) { pauseLock.lock(); if targetPIDs.contains(pid) { pauseReason = "Managed application became frontmost" }; pauseLock.unlock() }
    func pauseForDesktopChange(onlyManagedApplications: Bool) {
        pauseLock.lock(); defer { pauseLock.unlock() }
        if VirtualDisplaySessionStartupPolicy.shouldPauseForDesktopChange(
            onlyManagedApplications: onlyManagedApplications, hasManagedApplications: !targetPIDs.isEmpty) {
            pauseReason = "Desktop changed or locked; inspect and resume explicitly"
        }
    }
    init(holder: VirtualDisplayHolder, configuration: VirtualDisplayConfiguration) {
        self.holder = holder; self.configuration = configuration; bounds = CGDisplayBounds(holder.displayID)
    }
    var reason: String? { pauseLock.lock(); defer { pauseLock.unlock() }; return pauseReason }
    func pause(_ reason: String?) { pauseLock.lock(); pauseReason = reason; pauseLock.unlock() }
}

/// Registry is process-wide. All operations serialize independently of AppKit's main
/// thread. GUI callers must submit blocking operations off the main thread.
public final class VirtualDisplaySessionRegistry: @unchecked Sendable {
    public static let shared = VirtualDisplaySessionRegistry()
    private let lock = NSRecursiveLock()
    private let controlLock = NSLock()
    private var sessions: [String: VirtualDisplaySession] = [:]
    private var sessionOrder: [String] = []
    private var idleDisplays: [(configuration: VirtualDisplayConfiguration, holder: VirtualDisplayHolder)] = []
    private var idleDisplayIDs: Set<UInt32> = []
    private var controlledSessions: [String: VirtualDisplaySession] = [:]
    private var controlledOrder: [String] = []
    private var inputEpoch = 0
    private var observers: [NSObjectProtocol] = []
    private let monitorQueue = DispatchQueue(label: "com.ifuryst.ocu.virtual-display.monitor")
    private var monitor: DispatchSourceTimer?
    private let recoveryURL: URL
    private let emptyCapture = VirtualDisplayCapture()
    /// Legacy single-session access. Multi-session callers use capture(sessionID:).
    public var capture: VirtualDisplayCapture {
        controlLock.lock(); defer { controlLock.unlock() }
        return controlledOrder.last.flatMap { controlledSessions[$0]?.capture } ?? emptyCapture
    }
    public func capture(sessionID: String) throws -> VirtualDisplayCapture {
        controlLock.lock(); defer { controlLock.unlock() }
        guard let session = controlledSessions[sessionID] else { throw ComputerUseError.message("Unknown virtual display session") }
        return session.capture
    }
    public func states() -> [VirtualDisplayState] {
        lock.lock(); defer { lock.unlock() }; return sessionOrder.compactMap { sessions[$0].map(state) }
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var directory = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ifuryst.opencomputeruse.cli")
        let namespace = ProcessInfo.processInfo.environment[openComputerUseAppAgentSocketNamespaceEnvironmentKey]
        if let namespace, !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            directory.appendPathComponent(openComputerUseAppAgentSocketFileName(namespace: namespace))
        }
        recoveryURL = directory.appendingPathComponent("virtual-display-recovery.json")
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.pauseForDesktopChange(onlyManagedApplications: name == NSWorkspace.activeSpaceDidChangeNotification) })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.controlLock.lock(); let current = Array(self.controlledSessions.values); self.controlLock.unlock()
            current.forEach { $0.pauseIfActivated(app.processIdentifier) }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in self?.pauseForDesktopChange() })
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.monitorSession() }
        timer.resume(); monitor = timer
    }
    public func pauseForDesktopChange(onlyManagedApplications: Bool = false) {
        controlLock.lock(); let current = Array(controlledSessions.values); controlLock.unlock()
        current.forEach { $0.pauseForDesktopChange(onlyManagedApplications: onlyManagedApplications) }
    }
    private func requireSession(_ id: String) throws -> VirtualDisplaySession {
        guard let session = sessions[id] else { throw ComputerUseError.message("Unknown virtual display session") }
        return session
    }
    public func currentState() -> VirtualDisplayState? {
        lock.lock(); defer { lock.unlock() }
        return sessionOrder.last.flatMap { sessions[$0].map(state) }
    }
    public func state(sessionID: String) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        if s.reason == nil { try? validate(s, requireApp: false) }
        return state(s)
    }
    private func state(_ s: VirtualDisplaySession) -> VirtualDisplayState {
        let apps = s.applications.values.sorted { $0.application.processIdentifier < $1.application.processIdentifier }
        let selectedApp = s.selectedPID.flatMap { s.applications[$0]?.application }
        let windows = apps.flatMap { VirtualDisplayWindowAccess.windows(pid: $0.application.processIdentifier).filter { s.frames[$0.info.id] != nil }.map(\.info) }
        return .init(sessionID: s.id, displayID: s.holder.displayID, helperPID: s.holder.process.processIdentifier, frame: s.bounds, configuration: s.configuration,
                     phase: s.reason != nil ? "paused" : apps.isEmpty ? "ready" : apps.contains(where: { $0.selected == nil || $0.application.isHidden }) ? "awaiting_window_selection" : "attached", reason: s.reason,
                     pid: selectedApp?.processIdentifier, app: selectedApp?.bundleIdentifier ?? selectedApp?.localizedName,
                     selectedWindowID: s.selected, windows: windows,
                     applications: apps.map { .init(pid: $0.application.processIdentifier, app: $0.application.bundleIdentifier ?? $0.application.localizedName ?? "Unknown", name: $0.application.localizedName ?? "Application", owned: $0.owned, documentURL: $0.documentURL, selectedWindowID: $0.selected, candidateWindows: VirtualDisplayWindowAccess.windows(pid: $0.application.processIdentifier, includeOffscreen: true).map(\.info)) },
                     layoutVersion: s.version, foregroundBeforeCreation: s.foregroundBefore, foregroundAfterCreation: s.foregroundAfter,
                     physicalLayoutPreserved: s.layoutPreserved, displaySerial: s.holder.serial, additionalConfigurationApplied: !s.displayReused && s.holder.additionalConfigurationApplied, desktopBeforeCreation: s.desktopBefore, desktopAfterCreation: s.desktopAfter, displayReused: s.displayReused, captureIsRunning: s.capture.isRunning, lastFrameDate: s.capture.latestFrameDate, captureError: s.capture.error)
    }
    public func create(configuration: VirtualDisplayConfiguration = .init(), reuseDisplay: Bool = true, displayID: UInt32? = nil) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        guard !Thread.isMainThread else { throw ComputerUseError.message("Create virtual displays on a worker thread") }
        try configuration.validate()
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw ComputerUseError.permissionDenied("Accessibility and Screen Recording permissions are required") }
        if let displayID {
            guard reuseDisplay, idleDisplays.contains(where: { $0.holder.displayID == displayID && $0.configuration == configuration }) else {
                throw ComputerUseError.invalidArguments("display_id must identify a matching idle display and reuse_display must be true")
            }
        }
        if sessions.isEmpty { try recoverWindows() }
        let originalPhysical = physicalLayout()
        let desktopBefore = VirtualDisplayDesktopObservation.current(excluding: ownedDisplayIDs)
        let originalForeground = desktopBefore.foregroundPID
        // Prune disconnected holders before leasing; never reuse an active session.
        for entry in idleDisplays where !entry.holder.process.isRunning || CGDisplayIsActive(entry.holder.displayID) == 0 {
            try releaseIdleDisplays(displayID: entry.holder.displayID)
        }
        let holder: VirtualDisplayHolder
        let reused: Bool
        if reuseDisplay, let index = idleDisplays.firstIndex(where: { $0.configuration == configuration && (displayID == nil || $0.holder.displayID == displayID) }) {
            holder = idleDisplays.remove(at: index).holder
            updateIdleDisplayIDs()
            reused = true
        } else {
            guard displayID == nil else { throw ComputerUseError.message("Selected idle display disconnected; refresh displays before creating a session") }
            holder = try VirtualDisplayIdentity.withCreationLock {
                let occupied = Set(Self.onlineDisplayIDs().map(CGDisplaySerialNumber)).union(sessions.values.map { $0.holder.serial }).union(idleDisplays.map { $0.holder.serial })
                let serial = try VirtualDisplayIdentity.availableSerial(occupied: occupied)
                let created = try VirtualDisplayHolder(configuration: configuration, serial: serial)
                let deadline = Date(timeIntervalSinceNow: 3)
                while !Self.onlineDisplayIDs().contains(created.displayID), Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                guard Self.onlineDisplayIDs().contains(created.displayID) else {
                    created.stop()
                    throw ComputerUseError.message("Display identity did not become visible before allocation completed")
                }
                return created
            }
            reused = false
        }
        let s = VirtualDisplaySession(holder: holder, configuration: configuration)
        s.displayReused = reused
        do {
            let deadline = Date(timeIntervalSinceNow: 10)
            var ready = false
            while Date() < deadline {
                let id = holder.displayID
                let screenReady = DispatchQueue.main.sync { NSScreen.screens.contains { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id } }
                if CGDisplayIsActive(id) != 0, screenReady, try s.capture.start(displayID: id, configuration: configuration) {
                    ready = true; break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard ready else { throw ComputerUseError.message("Virtual display did not become capturable") }
            s.bounds = CGDisplayBounds(holder.displayID)
            s.physicalLayout = physicalLayout(excluding: holder.displayID)
            s.foregroundBefore = originalForeground; s.foregroundAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
            s.desktopBefore = desktopBefore
            s.desktopAfter = VirtualDisplayDesktopObservation.current(excluding: ownedDisplayIDs.union([holder.displayID]))
            s.layoutPreserved = s.physicalLayout == originalPhysical
            // No app/window is authorized yet. Record setup focus/Dock observations,
            // but do not require a manual resume for an otherwise healthy empty session.
            if let reason = VirtualDisplaySessionStartupPolicy.creationPauseReason(physicalLayoutPreserved: s.layoutPreserved) {
                s.pause(reason)
            }
            sessions[s.id] = s; sessionOrder.append(s.id)
            controlLock.lock(); controlledSessions[s.id] = s; controlledOrder.append(s.id); controlLock.unlock()
            return state(s)
        } catch {
            s.capture.stop()
            if reused {
                idleDisplays.append((configuration, holder)); updateIdleDisplayIDs()
            } else { holder.stop() }
            throw error
        }
    }
    /// Reserve an empty display. Repeated prewarm with a matching live configuration is idempotent.
    public func prewarm(configuration: VirtualDisplayConfiguration = .init()) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        guard !Thread.isMainThread else { throw ComputerUseError.message("Prewarm virtual displays on a worker thread") }
        try configuration.validate()
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw ComputerUseError.permissionDenied("Accessibility and Screen Recording permissions are required") }
        if let entry = idleDisplays.first(where: { $0.configuration == configuration && $0.holder.process.isRunning && CGDisplayIsActive($0.holder.displayID) != 0 }) {
            return entry.holder.displayID
        }
        let session = try create(configuration: configuration)
        try destroy(sessionID: session.sessionID, retainDisplay: true)
        return session.displayID
    }
    /// Snapshot resources and their association under the same registry lock.
    public func displayStates() -> [VirtualDisplayResourceState] {
        lock.lock(); defer { lock.unlock() }
        var result = sessionOrder.compactMap { sessions[$0] }.map { session in
            VirtualDisplayResourceState(displayID: session.holder.displayID, helperPID: session.holder.process.processIdentifier,
                configuration: session.configuration, frame: CGDisplayBounds(session.holder.displayID), sessionIDs: [session.id],
                online: session.holder.process.isRunning && CGDisplayIsActive(session.holder.displayID) != 0)
        }
        result += idleDisplays.map { entry in
            VirtualDisplayResourceState(displayID: entry.holder.displayID, helperPID: entry.holder.process.processIdentifier,
                configuration: entry.configuration, frame: CGDisplayBounds(entry.holder.displayID), sessionIDs: [],
                online: entry.holder.process.isRunning && CGDisplayIsActive(entry.holder.displayID) != 0)
        }
        return result.sorted { $0.displayID < $1.displayID }
    }
    /// Serialized cascade: safe session cleanup must succeed before retiring the display.
    /// Quitting apps/restoring windows cannot be rolled back; failure preserves unfinished state.
    public func destroyDisplay(displayID: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        guard !Thread.isMainThread else { throw ComputerUseError.message("Delete virtual displays on a worker thread") }
        guard displayStates().contains(where: { $0.displayID == displayID }) else {
            throw ComputerUseError.message("Unknown or foreign virtual display")
        }
        for session in states().filter({ $0.displayID == displayID }) {
            try destroy(sessionID: session.sessionID, retainDisplay: true)
        }
        try releaseIdleDisplays(displayID: displayID)
    }
    public func idleDisplayStates() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return idleDisplays.map { entry in
            ["display_id": entry.holder.displayID, "helper_pid": entry.holder.process.processIdentifier,
             "configuration": ["width": entry.configuration.width, "height": entry.configuration.height, "scale": entry.configuration.scale],
             "online": entry.holder.process.isRunning && CGDisplayIsActive(entry.holder.displayID) != 0,
             "frame": rectDictionary(CGDisplayBounds(entry.holder.displayID))]
        }
    }
    /// Release only idle displays owned by this runtime. Active sessions cannot be released here.
    public func releaseIdleDisplays(displayID: UInt32? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard !Thread.isMainThread else { throw ComputerUseError.message("Release virtual displays on a worker thread") }
        if let displayID, !idleDisplays.contains(where: { $0.holder.displayID == displayID }) {
            throw ComputerUseError.message("Unknown idle display; active or foreign displays cannot be released")
        }
        for entry in idleDisplays.filter({ displayID == nil || $0.holder.displayID == displayID }) {
            try removeDisplay(entry.holder)
            idleDisplays.removeAll { $0.holder === entry.holder }
            updateIdleDisplayIDs()
        }
    }
    private func updateIdleDisplayIDs() {
        controlLock.lock(); idleDisplayIDs = Set(idleDisplays.map { $0.holder.displayID }); controlLock.unlock()
    }
    private func removeDisplay(_ holder: VirtualDisplayHolder) throws {
        holder.stop()
        let deadline = Date(timeIntervalSinceNow: 5)
        while Self.onlineDisplayIDs().contains(holder.displayID), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        guard !Self.onlineDisplayIDs().contains(holder.displayID) else { throw ComputerUseError.message("Display removal was not confirmed") }
    }
    public static func onlineDisplayIDs() -> [UInt32] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 64); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
    public static func availableApplications() -> [VirtualDisplayAppChoice] {
        // A picker must include unused installed apps and must not wait for a
        // synchronous Spotlight query on every UI refresh.
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var choices: [String: VirtualDisplayAppChoice] = [:]
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension != "app" {
                    if url.pathComponents.count - root.pathComponents.count >= 2 { enumerator.skipDescendants() }
                    continue
                }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier,
                      bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true,
                      bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool != true else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                choices[id.lowercased()] = .init(id: id, name: name, bundleIdentifier: id,
                    pid: running.first { $0.bundleIdentifier?.lowercased() == id.lowercased() }?.processIdentifier)
            }
        }
        for app in running {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            choices[id.lowercased()] = .init(id: id, name: app.localizedName ?? id, bundleIdentifier: id, pid: app.processIdentifier)
        }
        return choices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var activeDisplayIDs: Set<UInt32> {
        controlLock.lock(); defer { controlLock.unlock() }
        return Set(controlledSessions.values.map { $0.holder.displayID })
    }
    /// All displays held by this runtime, including idle reservations.
    public var ownedDisplayIDs: Set<UInt32> {
        controlLock.lock(); defer { controlLock.unlock() }
        return Set(controlledSessions.values.map { $0.holder.displayID }).union(idleDisplayIDs)
    }
    public var activeDisplayID: UInt32? {
        controlLock.lock(); defer { controlLock.unlock() }
        return controlledOrder.last.flatMap { controlledSessions[$0]?.holder.displayID }
    }
    public var activeSessionID: String? {
        controlLock.lock(); defer { controlLock.unlock() }
        return controlledOrder.last
    }
    public func applicationCandidates(app query: String? = nil, pid: Int32? = nil) throws -> [VirtualDisplayApplicationCandidate] {
        guard pid.map({ $0 > 0 }) ?? true else { throw ComputerUseError.invalidArguments("pid must be positive") }
        if let query, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ComputerUseError.invalidArguments("app must not be empty")
        }
        let accessible = AXIsProcessTrusted()
        return NSWorkspace.shared.runningApplications.filter { application in
            !application.isTerminated && (query != nil || pid != nil || application.activationPolicy == .regular)
                && (pid == nil || application.processIdentifier == pid)
                && (query == nil || application.bundleIdentifier?.caseInsensitiveCompare(query!) == .orderedSame
                    || application.localizedName?.caseInsensitiveCompare(query!) == .orderedSame)
        }.sorted { $0.processIdentifier < $1.processIdentifier }.map { application in
            let blocked = application.bundleIdentifier.map { AppSafetyPolicy.isBlocked(bundleIdentifier: $0.lowercased()) } ?? false
            return .init(pid: application.processIdentifier, app: application.bundleIdentifier ?? application.localizedName ?? "Unknown",
                         name: application.localizedName ?? "Application",
                         windows: accessible && !blocked ? VirtualDisplayWindowAccess.windows(pid: application.processIdentifier, includeOffscreen: true).map(\.info) : [],
                         windowsAvailable: accessible && !blocked)
        }
    }

    public func availableWindows(pid: Int32) -> [VirtualDisplayWindowInfo] {
        VirtualDisplayWindowAccess.windows(pid: pid).map(\.info)
    }
    public func attach(sessionID: String, app requestedApp: String? = nil, pid: Int32? = nil, windowID: UInt32? = nil, launch: Bool = false, newDocument: Bool = false, manageAllWindows: Bool = false) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        guard !manageAllWindows || launch else { throw ComputerUseError.invalidArguments("manage_all_windows is only valid for a verified dedicated launch") }
        try VirtualDisplayAttachmentIntent.validate(app: requestedApp, pid: pid, windowID: windowID, launch: launch, newDocument: newDocument)
        let query = requestedApp ?? pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            ?? ""
        guard !query.isEmpty else { throw ComputerUseError.invalidArguments("Cannot resolve the selected process app identity") }
        let s = try requireSession(sessionID)
        guard s.reason == nil || !launch else { throw ComputerUseError.message("Session is paused; dedicated launch is unavailable") }
        try validate(s, requireApp: false, allowingWindow: pid.flatMap { owner in windowID.map { (owner, $0) } })
        if AppSafetyPolicy.isBlocked(bundleIdentifier: query.lowercased()) { throw AppSafetyPolicy.permissionDenied(bundleIdentifier: query) }
        let application: NSRunningApplication
        var owned = false
        var temporaryProfile: URL?
        var documentURL: URL?
        var launchObserver: DedicatedLaunchWindowObserver?
        if newDocument {
            guard launch, pid == nil, windowID == nil, query.caseInsensitiveCompare("com.apple.TextEdit") == .orderedSame else {
                throw ComputerUseError.invalidArguments("new_document requires a dedicated TextEdit launch")
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-document-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            documentURL = directory.appendingPathComponent("Result.txt")
            try Data().write(to: documentURL!, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: documentURL!.path)
        }
        if launch {
            guard pid == nil, windowID == nil else { throw ComputerUseError.invalidArguments("Launch does not accept pid/window_id") }
            let before = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) else { throw ComputerUseError.message("Launch requires an installed bundle identifier") }
            if query.caseInsensitiveCompare("com.google.Chrome") == .orderedSame {
                let profile = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-chrome-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                temporaryProfile = profile
            }
            let launchBox = LaunchResult()
            let semaphore = DispatchSemaphore(value: 0)
            let launchProfile = temporaryProfile
            let launchDocument = documentURL
            let initialPosition = "\(Int(s.bounds.minX)),\(Int(s.bounds.minY))"
            DispatchQueue.main.async {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false; config.hides = true; config.createsNewApplicationInstance = true; config.addsToRecentItems = false
                if let profile = launchProfile { config.arguments = ["--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check", "--window-position=\(initialPosition)"] }
                let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { app, error in
                    DispatchQueue.main.async {
                        // Opening documents can override LaunchServices' hides flag.
                        // Only hide the verified new, background instance we requested.
                        if let app, VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(
                            pid: app.processIdentifier, previousPIDs: before, requestedApp: query,
                            actualApp: app.bundleIdentifier, birth: processStartDate(app.processIdentifier)),
                           NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                            if let birth = processStartDate(app.processIdentifier) {
                                launchBox.windowObserver = DedicatedLaunchWindowObserver(application: app, birth: birth)
                            }
                            _ = app.hide()
                        }
                        launchBox.app = app; launchBox.error = error; semaphore.signal()
                    }
                }
                if let document = launchDocument {
                    // Supply the initial document event with the hidden app launch,
                    // rather than a later URL-open operation that can unhide it.
                    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                    let documents = NSAppleEventDescriptor.list()
                    documents.insert(NSAppleEventDescriptor(fileURL: document), at: 1)
                    event.setParam(documents, forKeyword: AEKeyword(keyDirectObject))
                    config.appleEvent = event
                }
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
            }
            guard semaphore.wait(timeout: .now() + 15) == .success else { throw ComputerUseError.message("Application launch timed out; inspect running applications before retrying") }
            if let error = launchBox.error { throw error }
            guard let app = launchBox.app else { throw ComputerUseError.message("Launch returned no application") }
            guard !before.contains(app.processIdentifier) else {
                throw VirtualDisplayLaunchReusedError(candidates: try applicationCandidates(app: query))
            }
            guard VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(pid: app.processIdentifier, previousPIDs: before,
                requestedApp: query, actualApp: app.bundleIdentifier, birth: processStartDate(app.processIdentifier)) else {
                throw ComputerUseError.message("Cannot verify a dedicated instance matching the requested app; no ownership acquired")
            }
            application = app; owned = true; launchObserver = launchBox.windowObserver
        } else {
            guard let pid, let windowID, windowID != 0,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                throw ComputerUseError.invalidArguments("Adoption requires a live pid and window_id")
            }
            application = app
        }
        guard application.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame || application.localizedName?.caseInsensitiveCompare(query) == .orderedSame else {
            throw ComputerUseError.invalidArguments("app does not match the selected process")
        }
        if let bundle = application.bundleIdentifier, AppSafetyPolicy.isBlocked(bundleIdentifier: bundle.lowercased()) { throw AppSafetyPolicy.permissionDenied(bundleIdentifier: bundle) }
        let pid = application.processIdentifier
        guard !sessions.values.contains(where: { $0.id != s.id && $0.applications[pid] != nil }) else {
            throw ComputerUseError.message("Application already belongs to another virtual session")
        }
        guard let birth = processStartDate(pid) else { throw ComputerUseError.message("Cannot verify application startup identity") }
        if let existing = s.applications[pid] {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                throw ComputerUseError.message("Target application is frontmost; switch to another app before attaching")
            }
            guard !launch, existing.processBirthDate == birth, let windowID,
                  let window = VirtualDisplayWindowAccess.windows(pid: pid, includeOffscreen: existing.owned).first(where: { $0.info.id == windowID }) else {
                throw ComputerUseError.message("Application is already attached; select or add an explicit window")
            }
            do {
                if s.frames[windowID] == nil { try manage(window, session: s) }
                existing.selected = windowID; s.selectedPID = pid; s.version += 1
                if existing.owned { try revealDedicatedApplicationIfContained(existing, session: s) }
                return state(s)
            } catch {
                s.pause("Window attachment failed: \(error.localizedDescription). Inspect or end the session to restore windows.")
                throw error
            }
        }
        let attached = VirtualDisplayApplication(application: application, processBirthDate: birth, owned: owned, temporaryProfile: temporaryProfile, documentURL: documentURL)
        attached.launchObserver = launchObserver
        s.applications[pid] = attached
        s.setPIDs(Set(s.applications.keys))
        do {
            if owned { try persistOwnedApplication(attached, sessionID: s.id) }
            let deadline = Date(timeIntervalSinceNow: 8)
            var candidates: [VirtualDisplayWindow] = []
            repeat {
                if launch {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                        throw ComputerUseError.message("Dedicated app activated while opening its window")
                    }
                    // NSDocumentController may unhide after the launch callback.
                    // Maintain the hidden state while waiting for the first AX window,
                    // using AX directly rather than cached NSRunningApplication state.
                    _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXHiddenAttribute as CFString, kCFBooleanTrue)
                }
                candidates = VirtualDisplayWindowAccess.windows(pid: application.processIdentifier, includeOffscreen: launch)
                if !candidates.isEmpty { break }
                Thread.sleep(forTimeInterval: launch ? 0.01 : 0.1)
            } while Date() < deadline
            if launch && !manageAllWindows {
                guard processStartDate(pid) == birth, NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                    throw ComputerUseError.message("Dedicated instance identity or foreground changed before window selection")
                }
                if !application.isHidden { _ = DispatchQueue.main.sync { application.hide() } }
                let hideDeadline = Date(timeIntervalSinceNow: 3)
                while !application.isHidden, Date() < hideDeadline { Thread.sleep(forTimeInterval: 0.02) }
                guard application.isHidden else { throw ComputerUseError.message("Dedicated instance declined to remain hidden before window selection") }
                s.version += 1
                return state(s) // No window movement is authorized by app/PID alone.
            }
            guard let chosen = windowID.flatMap({ id in candidates.first { $0.info.id == id } }) ?? (launch ? candidates.first : nil) else {
                throw ComputerUseError.message("No exact movable on-screen window found")
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier else {
                throw ComputerUseError.message("Target application is frontmost; switch to another app before attaching")
            }
            if launch {
                // A document may finish opening after the launch callback and unhide
                // its app again. Contain it before changing any window geometry.
                if !application.isHidden { _ = DispatchQueue.main.sync { application.hide() } }
                let hideDeadline = Date(timeIntervalSinceNow: 3)
                while !application.isHidden, Date() < hideDeadline { Thread.sleep(forTimeInterval: 0.02) }
                guard application.isHidden else { throw ComputerUseError.message("Dedicated app declined to hide; cannot contain its windows") }
            }
            try manage(chosen, session: s)
            attached.selected = chosen.info.id; s.selectedPID = pid; s.version += 1
            if launch {
                for candidate in candidates where candidate.info.id != chosen.info.id { try manage(candidate, session: s) }
                // Read back every hidden window before revealing. Do not rely on the first window alone.
                for window in VirtualDisplayWindowAccess.windows(pid: pid, includeOffscreen: true) {
                    guard let expected = s.frames[window.info.id], s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else {
                        throw ComputerUseError.message("A launch window escaped the verified virtual frame; app remains hidden")
                    }
                }
                if let reason = s.reason { throw ComputerUseError.message("Paused before revealing the dedicated app: \(reason)") }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                    throw ComputerUseError.message("Dedicated app activated before reveal")
                }
                attached.launchObserver?.finishContainment()
                if application.isHidden { _ = DispatchQueue.main.sync { application.unhide() } }
                let revealDeadline = Date(timeIntervalSinceNow: 3)
                while application.isHidden, Date() < revealDeadline { Thread.sleep(forTimeInterval: 0.02) }
                guard !application.isHidden else { throw ComputerUseError.message("Dedicated app declined to unhide") }
                try validate(s, requireApp: true)
            }
            return state(s)
        } catch { s.pause("Attach failed: \(error.localizedDescription). End the session to restore any moved windows."); throw error }
    }
    private func revealDedicatedApplicationIfContained(_ attached: VirtualDisplayApplication, session s: VirtualDisplaySession) throws {
        let app = attached.application
        guard attached.owned, !app.isTerminated, processStartDate(app.processIdentifier) == attached.processBirthDate else {
            throw ComputerUseError.message("Cannot verify dedicated instance ownership for reveal")
        }
        let windows = VirtualDisplayWindowAccess.windows(pid: app.processIdentifier, includeOffscreen: true)
        guard !windows.isEmpty, windows.allSatisfy({ window in
            guard let expected = s.frames[window.info.id] else { return false }
            return s.bounds.contains(window.info.frame) && VirtualDisplayWindowAccess.close(expected, window.info.frame)
        }) else { return } // Leave the entire instance hidden until every visible window is explicitly contained.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier else {
            s.pause("Dedicated instance became frontmost before reveal")
            throw ComputerUseError.message("Dedicated instance became frontmost before reveal")
        }
        attached.launchObserver?.finishContainment()
        if app.isHidden { _ = DispatchQueue.main.sync { app.unhide() } }
        let deadline = Date(timeIntervalSinceNow: 3)
        while app.isHidden, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard !app.isHidden else { throw ComputerUseError.message("Dedicated instance declined to reveal its authorized windows") }
        try validate(s, requireApp: true)
    }

    private func manage(_ window: VirtualDisplayWindow, session s: VirtualDisplaySession) throws {
        let originalDisplay = Self.onlineDisplayIDs().filter { !ownedDisplayIDs.contains($0) }.max {
            let left = CGDisplayBounds($0).intersection(window.info.frame)
            let right = CGDisplayBounds($1).intersection(window.info.frame)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        }
        guard let launchDate = processStartDate(window.info.pid) else {
            throw ComputerUseError.message("Cannot verify the target application's launch identity before moving its window")
        }
        if let saved = s.originals[window.info.id] {
            guard saved.pid == window.info.pid, saved.launchDate == launchDate else {
                throw ComputerUseError.message("Saved window identity no longer matches the selected process")
            }
        } else {
            s.originals[window.info.id] = WindowRecovery(pid: window.info.pid, launchDate: launchDate,
                bundleIdentifier: s.applications[window.info.pid]?.application.bundleIdentifier, windowID: window.info.id, frame: window.info.frame,
                displayID: originalDisplay, displayFrame: originalDisplay.map { CGDisplayBounds($0) })
            try persistRecovery()
        }
        let inset = s.bounds.insetBy(dx: 40, dy: 60)
        let width = min(window.info.frame.width, inset.width), height = min(window.info.frame.height, inset.height)
        let offset = CGFloat(s.frames.count % 8) * 36
        let target = CGRect(x: inset.minX + min(offset, max(0, inset.width - width)), y: inset.minY + min(offset, max(0, inset.height - height)), width: width, height: height)
        try VirtualDisplayWindowAccess.place(window, frame: target)
        s.frames[window.info.id] = target
    }
    public func selectWindow(sessionID: String, windowID: UInt32) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        guard let owner = s.originals[windowID]?.pid, let attached = s.applications[owner],
              !attached.application.isTerminated, processStartDate(owner) == attached.processBirthDate,
              let expected = s.frames[windowID],
              let window = VirtualDisplayWindowAccess.windows(pid: owner).first(where: { $0.info.id == windowID }),
              s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else {
            throw ComputerUseError.message("Select an existing window managed by this session in its verified virtual frame")
        }
        if attached.selected != windowID || s.selectedPID != owner { attached.selected = windowID; s.selectedPID = owner; s.version += 1 }
        try? validate(s, requireApp: true)
        return state(s)
    }
    public func pause(sessionID: String) throws -> VirtualDisplayState {
        controlLock.lock(); let s = controlledSessions[sessionID]; controlLock.unlock()
        guard let s else { throw ComputerUseError.message("Unknown virtual display session") }
        s.pause("Paused by caller")
        return try state(sessionID: sessionID)
    }
    public func resume(sessionID: String) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        // Layout/identity checks run even while paused. Never automatically reclaim moved windows.
        try validate(s, requireApp: false, recoveringCapture: true)
        if !s.capture.isRunning || s.capture.error != nil {
            s.capture.stop()
            guard try s.capture.start(displayID: s.holder.displayID, configuration: s.configuration) else {
                throw ComputerUseError.message("Display is not yet capturable; session remains paused")
            }
        }
        s.pause(nil); s.version += 1
        return state(s)
    }
    func withOperation<T>(sessionID: String, app: String, windowID: UInt32?, isAction: Bool, _ operation: (VirtualDisplayOperationContext) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        if isAction, let reason = s.reason { throw ComputerUseError.message("Session paused: \(reason)") }
        let matches = s.applications.values.filter {
            $0.application.bundleIdentifier?.caseInsensitiveCompare(app) == .orderedSame || $0.application.localizedName?.caseInsensitiveCompare(app) == .orderedSame
        }
        let candidates: [VirtualDisplayApplication]
        if let windowID { candidates = matches.filter { s.originals[windowID]?.pid == $0.application.processIdentifier } }
        else if isAction, matches.count > 1 { candidates = matches.filter { $0.application.processIdentifier == s.selectedPID } }
        else { candidates = matches }
        guard candidates.count == 1, let attached = candidates.first else {
            throw ComputerUseError.invalidArguments("app must identify exactly one managed application; use window_id through get_app_state to disambiguate instances")
        }
        let running = attached.application
        if isAction && running.isHidden { throw ComputerUseError.message("Dedicated instance is awaiting explicit window selection and reveal") }
        if let windowID {
            guard !isAction, s.frames[windowID] != nil else { throw ComputerUseError.invalidArguments("window_id must select a managed window through get_app_state") }
            if attached.selected != windowID { attached.selected = windowID; s.version += 1 }
        }
        s.selectedPID = running.processIdentifier
        if isAction { try validate(s, requireApp: true) } else { try? validate(s, requireApp: true) }
        guard let id = attached.selected, let window = VirtualDisplayWindowAccess.windows(pid: running.processIdentifier).first(where: { $0.info.id == id }) else {
            throw ComputerUseError.message("Selected window disappeared; choose another managed window")
        }
        guard let expected = s.frames[id], s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else {
            throw ComputerUseError.message("Selected managed window is outside its verified virtual frame")
        }
        controlLock.lock(); let epoch = inputEpoch; controlLock.unlock()
        let context = VirtualDisplayOperationContext(sessionID: s.id,
            app: RunningAppDescriptor(name: running.localizedName ?? app, bundleIdentifier: running.bundleIdentifier, pid: running.processIdentifier, runningApplication: running),
            window: window, layoutVersion: s.version + epoch)
        let result = try operation(context)
        if isAction { try validate(s, requireApp: true) } else { try? validate(s, requireApp: true) }
        return result
    }
    func setCursor(sessionID: String, global: CGPoint) {
        guard let s = sessions[sessionID] else { return }
        s.capture.setCursor(CGPoint(x: (global.x - s.bounds.minX) / s.bounds.width, y: (global.y - s.bounds.minY) / s.bounds.height))
    }
    public func clearCursor() {
        controlLock.lock(); inputEpoch += 1
        let captures = controlledSessions.values.map(\.capture)
        controlLock.unlock()
        captures.forEach { $0.setCursor(nil) }
    }
    func checkInput(sessionID: String) throws {
        let s = try requireSession(sessionID) // called inside withOperation's recursive lock
        if let reason = s.reason { throw ComputerUseError.message("Session paused: \(reason)") }
        try validate(s, requireApp: true)
    }
    private func physicalLayout(excluding id: UInt32 = 0) -> [UInt32: CGRect] {
        let virtual = Set(sessions.values.map { $0.holder.displayID }).union(idleDisplays.map { $0.holder.displayID }).union([id])
        return Dictionary(uniqueKeysWithValues: Self.onlineDisplayIDs().filter { !virtual.contains($0) }.map { ($0, CGDisplayBounds($0)) })
    }
    private func validate(_ s: VirtualDisplaySession, requireApp: Bool, recoveringCapture: Bool = false, allowingWindow: (Int32, UInt32)? = nil) throws {
        func fail(_ reason: String) throws -> Never { s.pause(reason); throw ComputerUseError.message(reason) }
        guard s.holder.process.isRunning, CGDisplayIsActive(s.holder.displayID) != 0 else { try fail("Virtual display disconnected") }
        let current = CGDisplayBounds(s.holder.displayID)
        if !VirtualDisplayWindowAccess.close(current, s.bounds) {
            s.bounds = current; s.version += 1; s.capture.stop()
            try fail("Display layout changed; inspect and resume")
        }
        let physical = physicalLayout(excluding: s.holder.displayID)
        if physical != s.physicalLayout {
            s.physicalLayout = physical; s.version += 1; s.capture.stop()
            try fail("Physical display layout changed; inspect and resume")
        }
        if let desktop = CGSessionCopyCurrentDictionary() as? [String: Any],
           (desktop["CGSSessionScreenIsLocked"] as? Bool == true || desktop[kCGSessionOnConsoleKey as String] as? Bool == false) {
            try fail("Desktop is locked or inactive")
        }
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { try fail("System permissions were revoked") }
        if !recoveringCapture {
            if let captureError = s.capture.error { try fail(captureError) }
            guard s.capture.isRunning else { try fail("Capture is not running; inspect and resume") }
        }
        if s.applications.isEmpty {
            if requireApp { try fail("Session has no managed application") }
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if ["com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent", "com.apple.loginwindow"].contains(frontmost?.bundleIdentifier ?? "") { try fail("System dialog or login screen requires user attention") }
        for attached in s.applications.values {
            let app = attached.application
            guard !app.isTerminated, processStartDate(app.processIdentifier) == attached.processBirthDate else { try fail("Managed application exited or its process identity changed") }
            guard frontmost?.processIdentifier != app.processIdentifier else { try fail("Managed application became frontmost") }
            let windows = VirtualDisplayWindowAccess.windows(pid: app.processIdentifier, includeOffscreen: attached.owned && app.isHidden)
            for window in windows {
                if let expected = s.frames[window.info.id] {
                    guard s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else { try fail("Managed window moved or resized; end and reattach") }
                    if let sheets = VirtualDisplayWindowAccess.attribute(window.element, "AXSheets") as? [AXUIElement] {
                        for sheet in sheets {
                            guard VirtualDisplayWindowAccess.contains(sheet, in: window.element),
                                  let frame = VirtualDisplayWindowAccess.frame(sheet), s.bounds.contains(frame) else {
                                try fail("Sheet ownership or virtual-screen geometry cannot be verified")
                            }
                        }
                    }
                } else {
                    let modal = (VirtualDisplayWindowAccess.attribute(window.element, "AXModal") as? Bool) == true
                        || (VirtualDisplayWindowAccess.attribute(window.element, kAXRoleAttribute) as? String) == "AXSheet"
                    if let (allowedPID, allowedID) = allowingWindow, window.info.pid == allowedPID {
                        if window.info.id != allowedID && VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: attached.owned, hidden: app.isHidden, modal: modal) {
                            s.pause("Other unmanaged windows require explicit authorization before resuming input")
                        }
                        continue // Moving the requested window grants no rights over its siblings.
                    }
                    if VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: attached.owned, hidden: app.isHidden, modal: modal) {
                        try fail("Unmanaged window or dialog requires explicit authorization; no window was automatically moved")
                    }
                }
            }
            if let selected = attached.selected, !windows.contains(where: { $0.info.id == selected }) { try fail("Managed window is no longer on-screen") }
        }
    }
    private func monitorSession() {
        guard lock.try() else { return }; defer { lock.unlock() }
        for s in sessions.values where s.reason == nil { try? validate(s, requireApp: false) }
    }
    public func destroyAll() throws {
        lock.lock(); defer { lock.unlock() }
        for state in states() { try destroy(sessionID: state.sessionID, retainDisplay: false) }
        try releaseIdleDisplays()
    }
    public func destroy(sessionID: String, retainDisplay: Bool = true) throws {
        lock.lock(); defer { lock.unlock() }
        guard let s = sessions[sessionID] else { throw ComputerUseError.message("Unknown virtual display session") }
        s.pause("Ending session")
        do {
            for attached in s.applications.values {
                let app = attached.application
                func restoreWindows() throws {
                    for record in s.originals.values where record.pid == app.processIdentifier { try restore(record) }
                }
                if !attached.owned { try restoreWindows() }
                if attached.owned, !app.isTerminated {
                    guard processStartDate(app.processIdentifier) == attached.processBirthDate else { throw ComputerUseError.message("Cannot verify owned process identity for cleanup") }
                    guard app.terminate() else {
                        try restoreWindows()
                        throw ComputerUseError.message("Application declined to quit; windows restored for attention, session retained")
                    }
                    let deadline = Date(timeIntervalSinceNow: 5)
                    while !app.isTerminated, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                    if !app.isTerminated {
                        try restoreWindows()
                        throw ComputerUseError.message("Application is waiting to quit; windows restored for attention, session retained")
                    }
                }
                if let profile = attached.temporaryProfile, FileManager.default.fileExists(atPath: profile.path) { try FileManager.default.removeItem(at: profile) }
                if let document = attached.documentURL {
                    try removeOwnedTemporaryDirectory(document.deletingLastPathComponent(), prefix: "ocu-document-")
                }
                let record = ownedRecoveryFile(s.id, pid: app.processIdentifier)
                if FileManager.default.fileExists(atPath: record.path) { try FileManager.default.removeItem(at: record) }
            }
            s.capture.stop()
            if !retainDisplay { try removeDisplay(s.holder) }
            // Journal writes happen before removal from memory, so failed writes retain cleanup state.
            try persistRecovery(excluding: s.id)
            if retainDisplay {
                idleDisplays.append((s.configuration, s.holder)); updateIdleDisplayIDs()
            }
            sessions.removeValue(forKey: s.id); sessionOrder.removeAll { $0 == s.id }
            controlLock.lock(); controlledSessions.removeValue(forKey: s.id); controlledOrder.removeAll { $0 == s.id }; controlLock.unlock()
        } catch { s.pause("Cleanup incomplete: \(error.localizedDescription)"); throw error }
    }
    private var ownedRecoveryDirectory: URL { recoveryURL.deletingLastPathComponent().appendingPathComponent("virtual-display-owned") }
    private func ownedRecoveryFile(_ id: String, pid: Int32) -> URL { ownedRecoveryDirectory.appendingPathComponent("\(id)-\(pid).json") }
    private func persistOwnedApplication(_ attached: VirtualDisplayApplication, sessionID: String) throws {
        let app = attached.application
        try FileManager.default.createDirectory(at: ownedRecoveryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let record = OwnedApplicationRecovery(pid: app.processIdentifier, startDate: attached.processBirthDate, bundleIdentifier: app.bundleIdentifier, profile: attached.temporaryProfile, documentDirectory: attached.documentURL?.deletingLastPathComponent())
        let url = ownedRecoveryFile(sessionID, pid: app.processIdentifier)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func recoverOwnedApplications() throws {
        guard FileManager.default.fileExists(atPath: ownedRecoveryDirectory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: ownedRecoveryDirectory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let record = try JSONDecoder().decode(OwnedApplicationRecovery.self, from: Data(contentsOf: file))
            if let current = processStartDate(record.pid) {
                if current == record.startDate { continue } // Keep live apps and their profiles; never force quit after a crash.
            } else if kill(record.pid, 0) == 0 || errno != ESRCH { continue }
            if let profile = record.profile { try removeOwnedTemporaryDirectory(profile, prefix: "ocu-chrome-") }
            if let directory = record.documentDirectory { try removeOwnedTemporaryDirectory(directory, prefix: "ocu-document-") }
            try FileManager.default.removeItem(at: file)
        }
    }
    private func removeOwnedTemporaryDirectory(_ directory: URL, prefix: String) throws {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let name = directory.lastPathComponent
        guard directory.isFileURL, name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
              directory.resolvingSymlinksInPath().deletingLastPathComponent() == temporary else {
            throw ComputerUseError.message("Recovery directory path cannot be verified; record retained")
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    public func ownedDocument(sessionID: String, app: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let session = try requireSession(sessionID)
        let matches = session.applications.values.filter { $0.owned && $0.application.bundleIdentifier?.caseInsensitiveCompare(app) == .orderedSame }
        guard matches.count == 1, let attached = matches.first, let document = attached.documentURL,
              !attached.application.isTerminated, processStartDate(attached.application.processIdentifier) == attached.processBirthDate else {
            throw ComputerUseError.message("No verified session-owned document for this app")
        }
        return document
    }
    private func persistRecovery(excluding id: String? = nil) throws {
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let records = sessions.values.filter { $0.id != id }.flatMap { Array($0.originals.values) }
        try JSONEncoder().encode(records).write(to: recoveryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
    }
    private func restore(_ record: WindowRecovery) throws {
        guard let app = NSRunningApplication(processIdentifier: record.pid), !app.isTerminated else { return }
        guard let originalLaunch = record.launchDate else {
            throw ComputerUseError.message("Recovery lacks a verifiable launch identity; record retained for inspection")
        }
        guard processStartDate(record.pid) == originalLaunch, app.bundleIdentifier == record.bundleIdentifier else { return }
        guard let window = VirtualDisplayWindowAccess.windows(pid: record.pid, includeOffscreen: true).first(where: { $0.info.id == record.windowID }) else { return }
        var target = record.frame
        var ids = [CGDirectDisplayID](repeating: 0, count: 64); var count: UInt32 = 0
        CGGetActiveDisplayList(64, &ids, &count)
        let physical = ids.prefix(Int(count)).filter { !ownedDisplayIDs.contains($0) }.map { CGDisplayBounds($0) }
        let preferred = record.displayID.flatMap { id in ids.prefix(Int(count)).contains(id) && !ownedDisplayIDs.contains(id) ? CGDisplayBounds(id) : nil }
        if let preferred, let oldDisplay = record.displayFrame, oldDisplay.intersects(record.frame) {
            target.origin.x += preferred.minX - oldDisplay.minX
            target.origin.y += preferred.minY - oldDisplay.minY
        }
        if !physical.contains(where: { $0.contains(target) }), let available = preferred ?? physical.first {
            target.size.width = min(target.width, available.width - 80); target.size.height = min(target.height, available.height - 120)
            target.origin = CGPoint(x: available.minX + 40, y: available.minY + 60)
        }
        try VirtualDisplayWindowAccess.place(window, frame: target)
    }
    private func recoverWindows() throws {
        try recoverOwnedApplications()
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        let records = try JSONDecoder().decode([WindowRecovery].self, from: Data(contentsOf: recoveryURL))
        for record in records { try restore(record) }
        try FileManager.default.removeItem(at: recoveryURL)
    }
}

private final class LaunchResult: @unchecked Sendable {
    var app: NSRunningApplication?
    var error: Error?
    var windowObserver: DedicatedLaunchWindowObserver?
}
