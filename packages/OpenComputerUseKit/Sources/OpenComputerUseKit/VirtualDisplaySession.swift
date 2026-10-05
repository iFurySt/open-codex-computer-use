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
    public let layoutVersion: Int
    public let foregroundBeforeCreation: Int32?
    public let foregroundAfterCreation: Int32?
    public let physicalLayoutPreserved: Bool
    public let captureIsRunning: Bool
    public let lastFrameDate: Date?
    public let captureError: String?
    public var dictionary: [String: Any] {
        var value: [String: Any] = ["session_id": sessionID, "display_id": displayID, "helper_pid": helperPID,
            "phase": phase, "layout_version": layoutVersion,
            "configuration": ["width": configuration.width, "height": configuration.height, "scale": configuration.scale],
            "frame": rectDictionary(frame), "windows": windows.map { ["window_id": $0.id, "pid": $0.pid, "title": $0.title, "frame": rectDictionary($0.frame)] as [String: Any] },
            "capabilities": ["global_input": false, "manual_preview_input": false, "system_drag_and_drop": false, "drag": false]]
        var captureState: [String: Any] = ["running": captureIsRunning]
        captureState["frame_age_seconds"] = lastFrameDate.map { max(0, Date().timeIntervalSince($0)) }
        captureState["error"] = captureError
        value["capture"] = captureState
        var observation: [String: Any] = ["physical_layout_preserved": physicalLayoutPreserved]
        observation["foreground_before_pid"] = foregroundBeforeCreation
        observation["foreground_after_pid"] = foregroundAfterCreation
        value["creation_observation"] = observation
        value["reason"] = reason; value["pid"] = pid; value["app"] = app; value["selected_window_id"] = selectedWindowID
        return value
    }
}

private func rectDictionary(_ frame: CGRect) -> [String: Double] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
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
    init(configuration: VirtualDisplayConfiguration) throws {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VirtualDisplayHost")
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("VirtualDisplayHost")
        process.executableURL = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : sibling
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        do {
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as! [String: Any]
            // Unique simultaneous identity, stable only for this lease. Layout is explicitly applied.
            value["serial"] = UInt32.random(in: 1...UInt32.max)
            var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
            let reply = try readReply(timeout: 10)
            if let error = reply["error"] as? String { throw ComputerUseError.message(error) }
            guard let id = reply["display_id"] as? NSNumber, id.uint32Value != 0 else { throw ComputerUseError.message("Invalid display-holder response") }
            displayID = id.uint32Value
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

private final class VirtualDisplaySession {
    let id = UUID().uuidString
    let holder: VirtualDisplayHolder
    let configuration: VirtualDisplayConfiguration
    var bounds: CGRect
    var version = 1
    var physicalLayout: [UInt32: CGRect] = [:]
    var foregroundBefore: Int32?
    var foregroundAfter: Int32?
    var layoutPreserved = true
    var application: NSRunningApplication?
    var processBirthDate: Date?
    var owned = false
    var temporaryProfile: URL?
    var originals: [UInt32: WindowRecovery] = [:]
    var frames: [UInt32: CGRect] = [:]
    var selected: UInt32?
    let pauseLock = NSLock()
    private var pauseReason: String?
    private var targetPID: Int32?
    func setPID(_ pid: Int32) { pauseLock.lock(); targetPID = pid; pauseLock.unlock() }
    func pauseIfActivated(_ pid: Int32) { pauseLock.lock(); if targetPID == pid { pauseReason = "Target application became frontmost" }; pauseLock.unlock() }
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
    private var session: VirtualDisplaySession?
    private var controlledSession: VirtualDisplaySession?
    private var inputEpoch = 0
    private var observers: [NSObjectProtocol] = []
    private let monitorQueue = DispatchQueue(label: "com.ifuryst.ocu.virtual-display.monitor")
    private var monitor: DispatchSourceTimer?
    private let recoveryURL: URL
    public let capture = VirtualDisplayCapture()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        recoveryURL = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ifuryst.opencomputeruse.cli").appendingPathComponent("virtual-display-recovery.json")
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.pauseForDesktopChange() })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.controlLock.lock(); let current = self.controlledSession; self.controlLock.unlock()
            current?.pauseIfActivated(app.processIdentifier)
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in self?.pauseForDesktopChange() })
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.monitorSession() }
        timer.resume(); monitor = timer
    }
    public func pauseForDesktopChange() {
        controlLock.lock(); let current = controlledSession; controlLock.unlock()
        current?.pause("Desktop changed or locked; inspect and resume explicitly")
    }
    private func requireSession(_ id: String) throws -> VirtualDisplaySession {
        guard let session, session.id == id else { throw ComputerUseError.message("Unknown virtual display session") }
        return session
    }
    public func currentState() -> VirtualDisplayState? {
        lock.lock(); defer { lock.unlock() }
        return session.map(state)
    }
    public func state(sessionID: String) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        if s.reason == nil { try? validate(s, requireApp: false) }
        return state(s)
    }
    private func state(_ s: VirtualDisplaySession) -> VirtualDisplayState {
        let windows = s.application.map { VirtualDisplayWindowAccess.windows(pid: $0.processIdentifier).filter { s.frames[$0.info.id] != nil }.map(\.info) } ?? []
        return .init(sessionID: s.id, displayID: s.holder.displayID, helperPID: s.holder.process.processIdentifier, frame: s.bounds, configuration: s.configuration,
                     phase: s.reason != nil ? "paused" : s.application == nil ? "ready" : "attached", reason: s.reason,
                     pid: s.application?.processIdentifier, app: s.application?.bundleIdentifier ?? s.application?.localizedName,
                     selectedWindowID: s.selected, windows: windows, layoutVersion: s.version,
                     foregroundBeforeCreation: s.foregroundBefore, foregroundAfterCreation: s.foregroundAfter,
                     physicalLayoutPreserved: s.layoutPreserved, captureIsRunning: capture.isRunning, lastFrameDate: capture.latestFrameDate, captureError: capture.error)
    }
    public func create(configuration: VirtualDisplayConfiguration = .init()) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        guard !Thread.isMainThread else { throw ComputerUseError.message("Create virtual displays on a worker thread") }
        try configuration.validate()
        guard session == nil else { throw ComputerUseError.message("A virtual session already exists; end it before creating another") }
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw ComputerUseError.permissionDenied("Accessibility and Screen Recording permissions are required") }
        try recoverWindows()
        let originalPhysical = Self.physicalLayout(excluding: 0)
        let originalForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let holder = try VirtualDisplayHolder(configuration: configuration)
        let s = VirtualDisplaySession(holder: holder, configuration: configuration)
        do {
            let deadline = Date(timeIntervalSinceNow: 10)
            var ready = false
            while Date() < deadline {
                let id = holder.displayID
                let screenReady = DispatchQueue.main.sync { NSScreen.screens.contains { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id } }
                if CGDisplayIsActive(id) != 0, screenReady, try capture.start(displayID: id, configuration: configuration) {
                    ready = true; break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard ready else { throw ComputerUseError.message("Virtual display did not become capturable") }
            s.bounds = CGDisplayBounds(holder.displayID)
            s.physicalLayout = Self.physicalLayout(excluding: holder.displayID)
            s.foregroundBefore = originalForeground; s.foregroundAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
            s.layoutPreserved = s.physicalLayout == originalPhysical
            if !s.layoutPreserved { s.pause("Physical display layout changed during setup; inspect before resuming") }
            session = s
            controlLock.lock(); controlledSession = s; controlLock.unlock()
            return state(s)
        } catch { capture.stop(); holder.stop(); throw error }
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
    public var activeDisplayID: UInt32? {
        controlLock.lock(); defer { controlLock.unlock() }; return controlledSession?.holder.displayID
    }
    public var activeSessionID: String? {
        controlLock.lock(); defer { controlLock.unlock() }
        return controlledSession?.id
    }
    public func availableWindows(pid: Int32) -> [VirtualDisplayWindowInfo] {
        VirtualDisplayWindowAccess.windows(pid: pid).map(\.info)
    }
    public func attach(sessionID: String, app query: String, pid: Int32? = nil, windowID: UInt32? = nil, launch: Bool = false) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        guard s.application == nil else { throw ComputerUseError.message("Session already has a target application") }
        guard s.reason == nil else { throw ComputerUseError.message("Session is paused") }
        if AppSafetyPolicy.isBlocked(bundleIdentifier: query.lowercased()) { throw AppSafetyPolicy.permissionDenied(bundleIdentifier: query) }
        let application: NSRunningApplication
        if launch {
            guard pid == nil, windowID == nil else { throw ComputerUseError.invalidArguments("Launch does not accept pid/window_id") }
            let before = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) else { throw ComputerUseError.message("Launch requires an installed bundle identifier") }
            if query.caseInsensitiveCompare("com.google.Chrome") == .orderedSame {
                let profile = FileManager.default.temporaryDirectory.appendingPathComponent("ocu-chrome-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                s.temporaryProfile = profile
            }
            let launchBox = LaunchResult()
            let semaphore = DispatchSemaphore(value: 0)
            let launchProfile = s.temporaryProfile
            DispatchQueue.main.async {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false; config.createsNewApplicationInstance = true; config.addsToRecentItems = false
                if let profile = launchProfile { config.arguments = ["--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check"] }
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    launchBox.app = app; launchBox.error = error; semaphore.signal()
                }
            }
            guard semaphore.wait(timeout: .now() + 15) == .success else { throw ComputerUseError.message("Application launch timed out; inspect running applications before retrying") }
            if let error = launchBox.error { throw error }
            guard let app = launchBox.app, !before.contains(app.processIdentifier) else { throw ComputerUseError.message("Launch reused an existing application; explicit adoption is required") }
            application = app; s.owned = true
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
        s.application = application
        s.setPID(application.processIdentifier)
        s.processBirthDate = processStartDate(application.processIdentifier)
        do {
            guard s.processBirthDate != nil else { throw ComputerUseError.message("Cannot verify application startup identity") }
            if s.owned { try persistOwnedApplication(s) }
            let deadline = Date(timeIntervalSinceNow: 8)
            var candidates: [VirtualDisplayWindow] = []
            repeat {
                candidates = VirtualDisplayWindowAccess.windows(pid: application.processIdentifier)
                if !candidates.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
            guard let chosen = windowID.flatMap({ id in candidates.first { $0.info.id == id } }) ?? (launch ? candidates.first : nil) else {
                throw ComputerUseError.message("No exact movable on-screen window found")
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier else {
                throw ComputerUseError.message("Target application is frontmost; switch to another app before attaching")
            }
            try manage(chosen, session: s)
            s.selected = chosen.info.id
            if launch {
                for candidate in candidates where candidate.info.id != chosen.info.id { try manage(candidate, session: s) }
            }
            return state(s)
        } catch { s.pause("Attach failed: \(error.localizedDescription). End the session to restore any moved windows."); throw error }
    }
    private func manage(_ window: VirtualDisplayWindow, session s: VirtualDisplaySession) throws {
        let originalDisplay = Self.onlineDisplayIDs().filter { $0 != s.holder.displayID }.max {
            let left = CGDisplayBounds($0).intersection(window.info.frame)
            let right = CGDisplayBounds($1).intersection(window.info.frame)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        }
        guard let launchDate = processStartDate(window.info.pid) else {
            throw ComputerUseError.message("Cannot verify the target application's launch identity before moving its window")
        }
        s.originals[window.info.id] = WindowRecovery(pid: window.info.pid, launchDate: launchDate,
            bundleIdentifier: s.application?.bundleIdentifier, windowID: window.info.id, frame: window.info.frame,
            displayID: originalDisplay, displayFrame: originalDisplay.map { CGDisplayBounds($0) })
        try persistRecovery(s)
        let inset = s.bounds.insetBy(dx: 40, dy: 60)
        let target = CGRect(x: inset.minX, y: inset.minY, width: min(window.info.frame.width, inset.width), height: min(window.info.frame.height, inset.height))
        try VirtualDisplayWindowAccess.place(window, frame: target)
        s.frames[window.info.id] = target
    }
    public func selectWindow(sessionID: String, windowID: UInt32) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        guard let app = s.application, !app.isTerminated, processStartDate(app.processIdentifier) == s.processBirthDate,
              let expected = s.frames[windowID],
              let window = VirtualDisplayWindowAccess.windows(pid: app.processIdentifier).first(where: { $0.info.id == windowID }),
              s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else {
            throw ComputerUseError.message("Select an existing window managed by this session in its verified virtual frame")
        }
        if s.selected != windowID { s.selected = windowID; s.version += 1 }
        try? validate(s, requireApp: true)
        return state(s)
    }
    public func pause(sessionID: String) throws -> VirtualDisplayState {
        controlLock.lock(); let s = controlledSession; controlLock.unlock()
        guard let s, s.id == sessionID else { throw ComputerUseError.message("Unknown virtual display session") }
        s.pause("Paused by caller")
        return try state(sessionID: sessionID)
    }
    public func resume(sessionID: String) throws -> VirtualDisplayState {
        lock.lock(); defer { lock.unlock() }
        let s = try requireSession(sessionID)
        // Layout/identity checks run even while paused. Never automatically reclaim moved windows.
        try validate(s, requireApp: false, recoveringCapture: true)
        if !capture.isRunning || capture.error != nil {
            capture.stop()
            guard try capture.start(displayID: s.holder.displayID, configuration: s.configuration) else {
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
        guard let running = s.application, running.bundleIdentifier?.caseInsensitiveCompare(app) == .orderedSame || running.localizedName?.caseInsensitiveCompare(app) == .orderedSame else {
            throw ComputerUseError.invalidArguments("app does not match the virtual session target")
        }
        if let windowID {
            guard !isAction, s.frames[windowID] != nil else { throw ComputerUseError.invalidArguments("window_id must select a managed window through get_app_state") }
            if s.selected != windowID { s.selected = windowID; s.version += 1 }
        }
        if isAction { try validate(s, requireApp: true) } else { try? validate(s, requireApp: true) }
        guard let id = s.selected, let window = VirtualDisplayWindowAccess.windows(pid: running.processIdentifier).first(where: { $0.info.id == id }) else {
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
        guard let s = session, s.id == sessionID else { return }
        capture.setCursor(CGPoint(x: (global.x - s.bounds.minX) / s.bounds.width, y: (global.y - s.bounds.minY) / s.bounds.height))
    }
    public func clearCursor() {
        controlLock.lock(); inputEpoch += 1; controlLock.unlock()
        capture.setCursor(nil)
    }
    func checkInput(sessionID: String) throws {
        let s = try requireSession(sessionID) // called inside withOperation's recursive lock
        if let reason = s.reason { throw ComputerUseError.message("Session paused: \(reason)") }
        try validate(s, requireApp: true)
    }
    private static func physicalLayout(excluding id: UInt32) -> [UInt32: CGRect] {
        Dictionary(uniqueKeysWithValues: onlineDisplayIDs().filter { $0 != id }.map { ($0, CGDisplayBounds($0)) })
    }
    private func validate(_ s: VirtualDisplaySession, requireApp: Bool, recoveringCapture: Bool = false) throws {
        func fail(_ reason: String) throws -> Never { s.pause(reason); throw ComputerUseError.message(reason) }
        guard s.holder.process.isRunning, CGDisplayIsActive(s.holder.displayID) != 0 else { try fail("Virtual display disconnected") }
        let current = CGDisplayBounds(s.holder.displayID)
        if !VirtualDisplayWindowAccess.close(current, s.bounds) {
            s.bounds = current; s.version += 1; capture.stop()
            try fail("Display layout changed; inspect and resume")
        }
        let physical = Self.physicalLayout(excluding: s.holder.displayID)
        if physical != s.physicalLayout {
            s.physicalLayout = physical; s.version += 1; capture.stop()
            try fail("Physical display layout changed; inspect and resume")
        }
        if let desktop = CGSessionCopyCurrentDictionary() as? [String: Any],
           (desktop["CGSSessionScreenIsLocked"] as? Bool == true || desktop[kCGSessionOnConsoleKey as String] as? Bool == false) {
            try fail("Desktop is locked or inactive")
        }
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { try fail("System permissions were revoked") }
        if !recoveringCapture {
            if let captureError = capture.error { try fail(captureError) }
            guard capture.isRunning else { try fail("Capture is not running; inspect and resume") }
        }
        guard let app = s.application else {
            if requireApp { try fail("Session has no target application") }
            return
        }
        guard !app.isTerminated, let birth = s.processBirthDate, processStartDate(app.processIdentifier) == birth else { try fail("Target application exited or its process identity changed") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier else { try fail("Target application became frontmost") }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if ["com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent", "com.apple.loginwindow"].contains(frontmost) { try fail("System dialog or login screen requires user attention") }
        let windows = VirtualDisplayWindowAccess.windows(pid: app.processIdentifier)
        for window in windows {
            if let expected = s.frames[window.info.id] {
                guard s.bounds.contains(window.info.frame), VirtualDisplayWindowAccess.close(expected, window.info.frame) else { try fail("Managed window moved or resized; end and reattach") }
            } else if s.owned {
                try manage(window, session: s)
            } else {
                // Borrowed applications may have unrelated windows. Do not move or drive them.
                if (VirtualDisplayWindowAccess.attribute(window.element, "AXModal") as? Bool) == true {
                    try fail("Unmanaged modal window requires explicit handling")
                }
            }
        }
        if let selected = s.selected, !windows.contains(where: { $0.info.id == selected }) { try fail("Selected window is no longer on-screen") }
    }
    private func monitorSession() {
        guard lock.try() else { return }; defer { lock.unlock() }
        guard let s = session, s.reason == nil else { return }
        try? validate(s, requireApp: false)
    }
    public func destroy(sessionID: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let s = session else { return }
        guard s.id == sessionID else { throw ComputerUseError.message("Unknown virtual display session") }
        s.pause("Ending session")
        do {
            func restoreWindows() throws { for record in s.originals.values { try restore(record) } }
            if !s.owned { try restoreWindows() }
            if s.owned, let app = s.application, !app.isTerminated {
                // Quit dedicated apps on the virtual screen. Only bring their
                // windows back when the user needs to resolve a refusal/prompt.
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
            capture.stop(); s.holder.stop()
            let deadline = Date(timeIntervalSinceNow: 5)
            while Self.onlineDisplayIDs().contains(s.holder.displayID), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            guard !Self.onlineDisplayIDs().contains(s.holder.displayID) else { throw ComputerUseError.message("Display removal was not confirmed") }
            if let profile = s.temporaryProfile, FileManager.default.fileExists(atPath: profile.path) { try FileManager.default.removeItem(at: profile) }
            let ownedRecord = ownedRecoveryFile(s.id)
            if FileManager.default.fileExists(atPath: ownedRecord.path) { try FileManager.default.removeItem(at: ownedRecord) }
            try? FileManager.default.removeItem(at: recoveryURL)
            session = nil
            controlLock.lock(); controlledSession = nil; controlLock.unlock()
        } catch { s.pause("Cleanup incomplete: \(error.localizedDescription)"); throw error }
    }
    private var ownedRecoveryDirectory: URL { recoveryURL.deletingLastPathComponent().appendingPathComponent("virtual-display-owned") }
    private func ownedRecoveryFile(_ id: String) -> URL { ownedRecoveryDirectory.appendingPathComponent(id + ".json") }
    private func persistOwnedApplication(_ s: VirtualDisplaySession) throws {
        guard let app = s.application, let birth = s.processBirthDate else { return }
        try FileManager.default.createDirectory(at: ownedRecoveryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let record = OwnedApplicationRecovery(pid: app.processIdentifier, startDate: birth, bundleIdentifier: app.bundleIdentifier, profile: s.temporaryProfile)
        let url = ownedRecoveryFile(s.id)
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
            if let profile = record.profile {
                let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                let name = profile.lastPathComponent
                guard profile.isFileURL, name.hasPrefix("ocu-chrome-"), UUID(uuidString: String(name.dropFirst("ocu-chrome-".count))) != nil,
                      profile.resolvingSymlinksInPath().deletingLastPathComponent() == temporary else {
                    throw ComputerUseError.message("Recovery profile path cannot be verified; record retained")
                }
                if FileManager.default.fileExists(atPath: profile.path) { try FileManager.default.removeItem(at: profile) }
            }
            try FileManager.default.removeItem(at: file)
        }
    }
    private func persistRecovery(_ s: VirtualDisplaySession) throws {
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(Array(s.originals.values)).write(to: recoveryURL, options: .atomic)
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
        let physical = ids.prefix(Int(count)).filter { $0 != session?.holder.displayID }.map { CGDisplayBounds($0) }
        let preferred = record.displayID.flatMap { id in ids.prefix(Int(count)).contains(id) && id != session?.holder.displayID ? CGDisplayBounds(id) : nil }
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
}
