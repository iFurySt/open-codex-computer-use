import AppKit
import CoreGraphics
import Foundation

public enum EventStreamRecordingState: String, Codable, Equatable, Sendable {
    case idle
    case recording
    case stopped
    case cancelled
}

public enum EventStreamScreenshotPolicy: String, Equatable {
    case auto
    case always
    case never
}

public enum EventStreamStartApprovalPolicy: String, Equatable, Sendable {
    case automatic
    case interactive
    case mcpElicitation
    case approve
    case deny
    case cancel
}

public enum EventStreamStartApprovalDecision: Equatable, Sendable {
    case approved
    case denied
    case cancelled
}

public struct EventStreamStartApprovalError: LocalizedError, Equatable {
    public let decision: EventStreamStartApprovalDecision

    public var errorDescription: String? {
        switch decision {
        case .approved:
            return nil
        case .denied:
            return eventStreamStartApprovalDeniedMessage
        case .cancelled:
            return eventStreamStartApprovalCancelledMessage
        }
    }
}

public let eventStreamMaximumRecordingDuration: TimeInterval = 30 * 60
public let eventStreamMaximumDurationEndReason = "recording_time_limit_reached"
public let eventStreamStartApprovalCancelledMessage = "Record & Replay approval cancelled via MCP elicitation."
public let eventStreamStartApprovalDeniedMessage = "Record & Replay approval denied via MCP elicitation."
let eventStreamMouseDragDistanceThreshold: CGFloat = 3
let eventStreamMaximumRawEventsPerInputEvent = 32
public typealias EventStreamInputMonitorInstaller = @MainActor (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?

func eventStreamRecordingDurationLimitDescription(_ duration: TimeInterval) -> String {
    guard duration > 0 else {
        return "until stopped"
    }

    let totalSeconds = max(Int(duration.rounded()), 1)
    if totalSeconds % 60 == 0 {
        let minutes = totalSeconds / 60
        return "up to \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    return "up to \(totalSeconds) second\(totalSeconds == 1 ? "" : "s")"
}

private final class EventStreamInputMonitorToken {
    private let context: Any?
    private let removeHandler: () -> Void

    init(context: Any? = nil, removeHandler: @escaping () -> Void) {
        self.context = context
        self.removeHandler = removeHandler
    }

    func remove() {
        _ = context
        removeHandler()
    }
}

private final class EventStreamCGEventTapContext {
    weak var service: EventStreamService?

    init(service: EventStreamService) {
        self.service = service
    }
}

private let eventStreamCGEventTapCallback: CGEventTapCallBack = { _proxy, type, cgEvent, userInfo in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(cgEvent)
    }

    guard let userInfo,
          let event = NSEvent(cgEvent: cgEvent)
    else {
        return Unmanaged.passUnretained(cgEvent)
    }

    let context = Unmanaged<EventStreamCGEventTapContext>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    context.service?.recordInputEventFromCGEventTap(event, type: type)
    return Unmanaged.passUnretained(cgEvent)
}

public struct EventStreamRecordingStatus: Codable, Equatable, Sendable {
    public let sessionID: String?
    public let state: EventStreamRecordingState
    public let startedAt: String?
    public let endedAt: String?
    public let endReason: String?
    public let eventsPath: String?
    public let metadataPath: String?
    public let suppressedEventsPath: String?
    public let currentSegmentEventsPath: String?
    public let currentSegmentMetadataPath: String?
    public let eventCount: Int
    public let suppressedEventCount: Int

    public var isActive: Bool {
        state == .recording
    }

    public var asDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "state": state.rawValue,
            "active": isActive,
            "eventCount": eventCount,
            "suppressedEventCount": suppressedEventCount,
        ]

        if let sessionID {
            dictionary["sessionId"] = sessionID
            dictionary["sessionID"] = sessionID
        }
        if let startedAt {
            dictionary["startedAt"] = startedAt
        }
        if let endedAt {
            dictionary["endedAt"] = endedAt
        }
        if let endReason {
            dictionary["endReason"] = endReason
        }
        if let eventsPath {
            dictionary["eventsPath"] = eventsPath
        }
        if let metadataPath {
            dictionary["metadataPath"] = metadataPath
            dictionary["sessionPath"] = URL(fileURLWithPath: metadataPath)
                .deletingLastPathComponent()
                .appendingPathComponent("session.json")
                .path
        }
        if let suppressedEventsPath {
            dictionary["suppressedEventsPath"] = suppressedEventsPath
        }
        if let currentSegmentEventsPath {
            dictionary["currentSegmentEventsPath"] = currentSegmentEventsPath
        }
        if let currentSegmentMetadataPath {
            dictionary["currentSegmentMetadataPath"] = currentSegmentMetadataPath
        }

        return dictionary
    }

    public var sessionHandoffDictionary: [String: Any] {
        var dictionary: [String: Any] = [:]
        if let sessionID {
            dictionary["id"] = sessionID
        }
        if let startedAt {
            dictionary["startedAt"] = startedAt
        }
        if let endedAt {
            dictionary["endedAt"] = endedAt
        }
        if let endReason {
            dictionary["endReason"] = endReason
        }
        if let eventsPath {
            dictionary["eventsPath"] = eventsPath
        }
        return dictionary
    }

    public func jsonText(prettyPrinted: Bool = true) throws -> String {
        let options: JSONSerialization.WritingOptions = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let data = try JSONSerialization.data(withJSONObject: asDictionary, options: options)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode event stream status as JSON.")
        }
        return text
    }

    static var idle: EventStreamRecordingStatus {
        EventStreamRecordingStatus(
            sessionID: nil,
            state: .idle,
            startedAt: nil,
            endedAt: nil,
            endReason: nil,
            eventsPath: nil,
            metadataPath: nil,
            suppressedEventsPath: nil,
            currentSegmentEventsPath: nil,
            currentSegmentMetadataPath: nil,
            eventCount: 0,
            suppressedEventCount: 0
        )
    }
}

public struct EventStreamWaitResult: Equatable, Sendable {
    public let status: EventStreamRecordingStatus
    public let timedOut: Bool
    public let sessionMatched: Bool
}

public final class EventStreamService: @unchecked Sendable {
    public static let shared = EventStreamService()

    private let rootDirectory: URL
    private let installsInputMonitors: Bool
    private let showsRecordingControls: Bool
    private let screenshotPolicy: EventStreamScreenshotPolicy
    private let recordsRawEvents: Bool
    private let maximumDuration: TimeInterval
    private let startApprovalPolicy: EventStreamStartApprovalPolicy
    private let installsCGEventTap: Bool
    private let inputMonitorInstaller: EventStreamInputMonitorInstaller
    private let lock = NSLock()
    private var activeSession: EventStreamSession?
    private var inputMonitorTokens: [EventStreamInputMonitorToken] = []
    private var workspaceObserver: NSObjectProtocol?
    private var recordingControls: EventStreamRecordingControls?
    private var initialAXTreeLines: [String]?
    private var initialAXContextKey: String?
    private var lastAXTreeLines: [String]?
    private var lastAXContextKey: String?
    private var lastObservedWindowContextKey: String?
    private var lastSelectionSignature: String?
    private var lastTerminalValueSignature: String?
    private var pendingPointerEvent: EventStreamPendingPointerEvent?

    public init(
        rootDirectory: URL? = nil,
        installsInputMonitors: Bool = true,
        showsRecordingControls: Bool = eventStreamRecordingControlsEnabled(),
        screenshotPolicy: EventStreamScreenshotPolicy = eventStreamScreenshotPolicy(),
        recordsRawEvents: Bool = eventStreamRawEventsEnabled(),
        maximumDuration: TimeInterval = eventStreamRecordingMaximumDuration(),
        startApprovalPolicy: EventStreamStartApprovalPolicy = eventStreamStartApprovalPolicy(),
        installsCGEventTap: Bool = true,
        inputMonitorInstaller: @escaping EventStreamInputMonitorInstaller = { matching, handler in
            NSEvent.addGlobalMonitorForEvents(matching: matching, handler: handler)
        }
    ) {
        self.rootDirectory = rootDirectory ?? defaultEventStreamRootDirectory()
        self.installsInputMonitors = installsInputMonitors
        self.showsRecordingControls = showsRecordingControls
        self.screenshotPolicy = screenshotPolicy
        self.recordsRawEvents = recordsRawEvents
        self.maximumDuration = maximumDuration
        self.startApprovalPolicy = startApprovalPolicy
        self.installsCGEventTap = installsCGEventTap
        self.inputMonitorInstaller = inputMonitorInstaller
    }

    public var configuredStartApprovalPolicy: EventStreamStartApprovalPolicy {
        startApprovalPolicy
    }

    public var configuredMaximumDurationSeconds: Int {
        max(Int(maximumDuration.rounded()), 0)
    }

    public func start(approvalDecision: EventStreamStartApprovalDecision? = nil) throws -> EventStreamRecordingStatus {
        lock.lock()
        if let activeSession {
            let status = activeSession.status
            lock.unlock()
            return status
        }
        lock.unlock()

        try requestStartApprovalIfNeeded(approvalDecision: approvalDecision)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let now = Date()
        let sessionID = makeEventStreamSessionID(date: now)
        let sessionDirectory = rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let session = EventStreamSession(
            id: sessionID,
            directory: sessionDirectory,
            startedAtDate: now
        )
        try writeEmptyFileIfNeeded(session.suppressedEventsURL)

        lock.lock()
        if let activeSession {
            let status = activeSession.status
            lock.unlock()
            return status
        }
        activeSession = session
        lock.unlock()

        try appendEvent([
            "type": "session.started",
            "timestamp": eventStreamTimestamp(now),
            "sessionId": sessionID,
            "metadataPath": session.metadataURL.path,
            "eventsPath": session.eventsURL.path,
            "suppressedEventsPath": session.suppressedEventsURL.path,
        ])
        try writeStatus(session.status)
        scheduleMaximumDurationStopIfNeeded(sessionID: sessionID)
        installInputMonitorsIfNeeded()
        recordWindowChanged(reason: "initial")
        recordFocusedWindowChanged(reason: "initial")
        showRecordingControlsIfNeeded(startedAt: now)
        return session.status
    }

    private func requestStartApprovalIfNeeded(approvalDecision: EventStreamStartApprovalDecision? = nil) throws {
        if let approvalDecision {
            switch approvalDecision {
            case .approved:
                return
            case .denied, .cancelled:
                throw EventStreamStartApprovalError(decision: approvalDecision)
            }
        }

        let policy: EventStreamStartApprovalPolicy
        switch startApprovalPolicy {
        case .automatic:
            policy = showsRecordingControls && installsInputMonitors ? .interactive : .approve
        default:
            policy = startApprovalPolicy
        }

        switch policy {
        case .automatic, .approve:
            return
        case .mcpElicitation:
            throw EventStreamStartApprovalError(decision: .cancelled)
        case .deny:
            throw EventStreamStartApprovalError(decision: .denied)
        case .cancel:
            throw EventStreamStartApprovalError(decision: .cancelled)
        case .interactive:
            let decision = requestInteractiveStartApproval(allowHeadlessAutoApprove: startApprovalPolicy == .automatic)
            switch decision {
            case .approved:
                return
            case .denied, .cancelled:
                throw EventStreamStartApprovalError(decision: decision)
            }
        }
    }

    private func requestInteractiveStartApproval(allowHeadlessAutoApprove: Bool) -> EventStreamStartApprovalDecision {
        performEventStreamOnMainSync {
            guard NSApp.isRunning else {
                return allowHeadlessAutoApprove ? .approved : .cancelled
            }

            let alert = NSAlert()
            alert.messageText = "Record & Replay wants to record your actions"
            alert.informativeText = "Open Computer Use will capture mouse, keyboard, window, and accessibility context until you click Done or Discard. Recording can last \(eventStreamRecordingDurationLimitDescription(self.maximumDuration))."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Start Recording")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            return response == .alertFirstButtonReturn ? .approved : .cancelled
        }
    }

    public func status() -> EventStreamRecordingStatus {
        lock.lock()
        if let activeSession {
            let status = activeSession.status
            lock.unlock()
            return status
        }
        lock.unlock()

        return (try? readLatestStatus()) ?? .idle
    }

    public func stop(endReason: String = "recording_controls_stopped") throws -> EventStreamRecordingStatus {
        try finish(state: .stopped, endReason: endReason)
    }

    public func cancel() throws -> EventStreamRecordingStatus {
        try finish(state: .cancelled, endReason: "recording_controls_cancelled")
    }

    public func wait(sessionID: String? = nil, timeout: TimeInterval? = nil) -> EventStreamRecordingStatus {
        waitResult(sessionID: sessionID, timeout: timeout).status
    }

    public func waitResult(sessionID: String? = nil, timeout: TimeInterval? = nil) -> EventStreamWaitResult {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            if let sessionID,
               let requestedStatus = try? readStoredStatus(sessionID: sessionID),
               !requestedStatus.isActive {
                return EventStreamWaitResult(status: requestedStatus, timedOut: false, sessionMatched: true)
            }

            let current = status()
            let matchesSession = sessionID == nil || current.sessionID == sessionID
            if matchesSession, !current.isActive {
                return EventStreamWaitResult(status: current, timedOut: false, sessionMatched: true)
            }
            if sessionID != nil, !matchesSession {
                return EventStreamWaitResult(status: current, timedOut: true, sessionMatched: false)
            }
            if let deadline, Date() >= deadline {
                return EventStreamWaitResult(status: current, timedOut: true, sessionMatched: matchesSession)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func appendSyntheticEventForTesting(_ event: [String: Any]) throws {
        try appendEvent(event)
    }

    public func appendSuppressedEventForTesting(_ event: [String: Any]) throws {
        try appendSuppressedEvent(event)
    }

    public func appendDebugErrorForTesting(
        subsystem: String,
        reason: String,
        error: Error? = nil,
        context: [String: Any] = [:]
    ) throws {
        try recordDebugError(subsystem: subsystem, reason: reason, error: error, context: context)
    }

    func appendFocusedWindowChangedForTesting(
        reason: String,
        appName: String,
        bundleIdentifier: String?,
        snapshot: AppSnapshot
    ) throws {
        var payload: [String: Any] = [
            "type": "AX.focusedWindowChanged",
            "timestamp": eventStreamTimestamp(Date()),
            "reason": reason,
            "screenshotNeededForContext": false,
            "app": eventStreamApplicationContext(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                pid: snapshot.app.pid
            ),
        ]
        if let window = eventStreamWindowContext(snapshot: snapshot) {
            payload["window"] = window
        }
        if let accessibilityPayload = recordAccessibilityPayload(
            snapshot: snapshot,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        ) {
            payload["accessibilityInspectorPayload"] = accessibilityPayload
            payload["diffFromPrevious"] = accessibilityPayload["diffFromPrevious"] as? Bool ?? false
            payload["screenshotNeededForContext"] = accessibilityPayload["screenshotNeededForContext"] as? Bool ?? false
        }
        try appendEvent(payload)
    }

    private func finish(state: EventStreamRecordingState, endReason: String) throws -> EventStreamRecordingStatus {
        try finish(state: state, endReason: endReason, onlySessionID: nil)
    }

    private func finish(
        state: EventStreamRecordingState,
        endReason: String,
        onlySessionID: String?
    ) throws -> EventStreamRecordingStatus {
        lock.lock()
        guard let session = activeSession else {
            lock.unlock()
            return (try? readLatestStatus()) ?? .idle
        }
        if let onlySessionID, session.id != onlySessionID {
            let status = session.status
            lock.unlock()
            return status
        }
        if session.isFinishing {
            let status = session.status
            lock.unlock()
            return status
        }

        let endedAt = Date()
        session.endedAt = eventStreamTimestamp(endedAt)
        session.endReason = endReason
        session.isFinishing = true
        lock.unlock()

        removeInputMonitors()
        dismissRecordingControls()
        try appendEvent([
            "type": "session.ended",
            "timestamp": eventStreamTimestamp(endedAt),
            "sessionId": session.id,
            "endReason": endReason,
        ], sessionOverride: session)
        lock.lock()
        session.state = state
        session.isFinishing = false
        let finalStatus = session.status
        lock.unlock()
        try writeStatus(finalStatus)
        lock.lock()
        if activeSession === session {
            activeSession = nil
        }
        lock.unlock()
        return finalStatus
    }

    private func scheduleMaximumDurationStopIfNeeded(sessionID: String) {
        guard maximumDuration > 0 else {
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + maximumDuration) { [weak self] in
            _ = try? self?.finish(
                state: .stopped,
                endReason: eventStreamMaximumDurationEndReason,
                onlySessionID: sessionID
            )
        }
    }

    private func appendEvent(_ event: [String: Any], sessionOverride: EventStreamSession? = nil) throws {
        lock.lock()
        guard let session = sessionOverride ?? activeSession else {
            lock.unlock()
            return
        }
        session.eventCount += 1
        let eventURL = session.eventsURL
        let status = session.status
        lock.unlock()

        var payload = eventStreamCanonicalEventPayload(event)
        if payload["timestamp"] == nil {
            payload["timestamp"] = eventStreamTimestamp(Date())
        }
        if payload["sessionId"] == nil {
            payload["sessionId"] = session.id
        }

        try appendJSONObjectLine(payload, to: eventURL)
        try writeStatus(status)
    }

    private func appendSuppressedEvent(_ event: [String: Any]) throws {
        lock.lock()
        guard let session = activeSession else {
            lock.unlock()
            return
        }
        session.suppressedEventCount += 1
        let suppressedURL = session.suppressedEventsURL
        let status = session.status
        lock.unlock()

        var payload = eventStreamCanonicalEventPayload(event)
        if payload["timestamp"] == nil {
            payload["timestamp"] = eventStreamTimestamp(Date())
        }
        if payload["sessionId"] == nil {
            payload["sessionId"] = session.id
        }

        try appendJSONObjectLine(payload, to: suppressedURL)
        try writeStatus(status)
    }

    private func recordDebugError(
        subsystem: String,
        reason: String,
        error: Error? = nil,
        context: [String: Any] = [:]
    ) throws {
        let payload = eventStreamDebugErrorPayload(
            subsystem: subsystem,
            reason: reason,
            error: error,
            context: context
        )
        try appendEvent(payload)
    }

    private func writeStatus(_ status: EventStreamRecordingStatus) throws {
        let metadataURL: URL?
        if let metadataPath = status.metadataPath {
            metadataURL = URL(fileURLWithPath: metadataPath)
        } else {
            metadataURL = nil
        }

        let data = try JSONSerialization.data(
            withJSONObject: status.asDictionary,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let sessionHandoffData = try JSONSerialization.data(
            withJSONObject: status.sessionHandoffDictionary,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        if let metadataURL {
            try data.write(to: metadataURL, options: [.atomic])
            try sessionHandoffData.write(
                to: metadataURL.deletingLastPathComponent().appendingPathComponent("session.json"),
                options: [.atomic]
            )
        }

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try data.write(to: rootDirectory.appendingPathComponent("latest-session.json"), options: [.atomic])
        if status.isActive {
            try data.write(to: rootDirectory.appendingPathComponent("active-session.json"), options: [.atomic])
        } else {
            try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent("active-session.json"))
        }
    }

    private func readLatestStatus() throws -> EventStreamRecordingStatus {
        let data = try Data(contentsOf: rootDirectory.appendingPathComponent("latest-session.json"))
        let decoded = try JSONDecoder().decode(EventStreamRecordingStatus.self, from: data)
        if decoded.isActive {
            let unavailableStatus = EventStreamRecordingStatus(
                sessionID: decoded.sessionID,
                state: .stopped,
                startedAt: decoded.startedAt,
                endedAt: eventStreamTimestamp(Date()),
                endReason: "recording_process_unavailable",
                eventsPath: decoded.eventsPath,
                metadataPath: decoded.metadataPath,
                suppressedEventsPath: decoded.suppressedEventsPath,
                currentSegmentEventsPath: nil,
                currentSegmentMetadataPath: nil,
                eventCount: decoded.eventCount,
                suppressedEventCount: decoded.suppressedEventCount
            )
            try? writeStatus(unavailableStatus)
            return unavailableStatus
        }
        return decoded
    }

    private func readStoredStatus(sessionID: String) throws -> EventStreamRecordingStatus {
        guard eventStreamSessionIdentifierIsSafe(sessionID) else {
            throw ComputerUseError.message("Invalid event stream session id.")
        }
        let sessionDirectory = rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let metadataURL = sessionDirectory.appendingPathComponent("metadata.json")
        let sessionURL = sessionDirectory.appendingPathComponent("session.json")
        let statusURL = FileManager.default.fileExists(atPath: metadataURL.path) ? metadataURL : sessionURL
        let data = try Data(contentsOf: statusURL)
        return try JSONDecoder().decode(EventStreamRecordingStatus.self, from: data)
    }

    private func installInputMonitorsIfNeeded() {
        guard installsInputMonitors else {
            return
        }

        performEventStreamOnMainSync { [self] in
            guard self.inputMonitorTokens.isEmpty, self.workspaceObserver == nil else {
                return
            }

            if self.installsCGEventTap, let token = self.installCGEventTapInputMonitor() {
                self.inputMonitorTokens.append(token)
            } else {
                self.installNSEventInputMonitors()
            }

            self.workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recordFocusedWindowChanged(reason: "applicationActivated")
            }

            if self.inputMonitorTokens.isEmpty {
                try? self.recordDebugError(
                    subsystem: "inputMonitoring",
                    reason: "inputMonitorsUnavailable",
                    context: [
                        "monitorsInstalled": 0,
                        "recordsRawEvents": self.recordsRawEvents,
                    ]
                )
            }
        }
    }

    private func removeInputMonitors() {
        guard installsInputMonitors else {
            return
        }

        performEventStreamOnMainSync { [self] in
            for token in self.inputMonitorTokens {
                token.remove()
            }
            self.inputMonitorTokens.removeAll()
            self.lock.lock()
            self.pendingPointerEvent = nil
            self.lock.unlock()

            if let workspaceObserver = self.workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
                self.workspaceObserver = nil
            }
        }
    }

    @MainActor
    private func installNSEventInputMonitors() {
        if let token = inputMonitorInstaller(
            [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            { [weak self] event in
                self?.recordMouseDown(event)
            }
        ) {
            inputMonitorTokens.append(EventStreamInputMonitorToken {
                NSEvent.removeMonitor(token)
            })
        }

        if let token = inputMonitorInstaller(
            [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            { [weak self] event in
                self?.recordMouseDragged(event)
            }
        ) {
            inputMonitorTokens.append(EventStreamInputMonitorToken {
                NSEvent.removeMonitor(token)
            })
        }

        if let token = inputMonitorInstaller(
            [.leftMouseUp, .rightMouseUp, .otherMouseUp],
            { [weak self] event in
                self?.recordMouseUp(event)
            }
        ) {
            inputMonitorTokens.append(EventStreamInputMonitorToken {
                NSEvent.removeMonitor(token)
            })
        }

        if let token = inputMonitorInstaller(
            [.keyDown],
            { [weak self] event in
                self?.recordKeyDown(event)
            }
        ) {
            inputMonitorTokens.append(EventStreamInputMonitorToken {
                NSEvent.removeMonitor(token)
            })
        }

        if recordsRawEvents,
           let token = inputMonitorInstaller(
               [.scrollWheel],
               { [weak self] event in
                   self?.recordScrollWheel(event)
               }
           )
        {
            inputMonitorTokens.append(EventStreamInputMonitorToken {
                NSEvent.removeMonitor(token)
            })
        }
    }

    @MainActor
    private func installCGEventTapInputMonitor() -> EventStreamInputMonitorToken? {
        var mask: CGEventMask = 0
        for type in [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
            .keyDown,
        ] {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }
        if recordsRawEvents {
            mask |= CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        }

        let context = EventStreamCGEventTapContext(service: self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventStreamCGEventTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return EventStreamInputMonitorToken(context: context) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
    }

    fileprivate func recordInputEventFromCGEventTap(_ event: NSEvent, type: CGEventType) {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            recordMouseDown(event)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            recordMouseDragged(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            recordMouseUp(event)
        case .keyDown:
            recordKeyDown(event)
        case .scrollWheel:
            recordScrollWheel(event)
        default:
            break
        }
    }

    private func showRecordingControlsIfNeeded(startedAt: Date) {
        guard showsRecordingControls, installsInputMonitors else {
            return
        }

        performEventStreamOnMainSync { [self] in
            guard NSApp.isRunning else {
                return
            }

            self.recordingControls?.close()
            let controls = EventStreamRecordingControls(
                startedAt: startedAt,
                onStop: { [weak self] in
                    _ = try? self?.stop()
                },
                onCancel: { [weak self] in
                    _ = try? self?.cancel()
                }
            )
            self.recordingControls = controls
            controls.show()
        }
    }

    private func dismissRecordingControls() {
        guard showsRecordingControls, installsInputMonitors else {
            return
        }

        performEventStreamOnMainSync { [self] in
            self.recordingControls?.close()
            self.recordingControls = nil
        }
    }

    private func recordMouseDown(_ event: NSEvent) {
        guard let button = eventStreamMouseButton(forEventType: event.type) else {
            return
        }

        let appKitPoint = event.locationInWindow
        let screenPoint = eventStreamScreenStatePoint(fromAppKitGlobalPoint: appKitPoint)
        let pendingEvent = EventStreamPendingPointerEvent(
            button: button,
            clickCount: max(event.clickCount, 1),
            startedAt: Date(),
            appKitStartLocation: appKitPoint,
            screenStartLocation: screenPoint,
            rawEvents: recordsRawEvents ? [
                eventStreamRawEventSummary(event, screenPoint: screenPoint, button: button)
            ] : []
        )

        lock.lock()
        pendingPointerEvent = pendingEvent
        lock.unlock()
    }

    private func recordMouseDragged(_ event: NSEvent) {
        guard let button = eventStreamMouseButton(forEventType: event.type) else {
            return
        }

        let appKitPoint = event.locationInWindow
        let screenPoint = eventStreamScreenStatePoint(fromAppKitGlobalPoint: appKitPoint)

        lock.lock()
        if var pendingPointerEvent, pendingPointerEvent.button == button {
            pendingPointerEvent.appKitLastLocation = appKitPoint
            pendingPointerEvent.screenLastLocation = screenPoint
            if recordsRawEvents {
                pendingPointerEvent.appendRawEvent(
                    eventStreamRawEventSummary(event, screenPoint: screenPoint, button: button)
                )
            }
            pendingPointerEvent.didDrag = eventStreamPointerDidDrag(
                start: pendingPointerEvent.screenStartLocation,
                end: screenPoint,
                observedDrag: pendingPointerEvent.didDrag
            )
            self.pendingPointerEvent = pendingPointerEvent
        }
        lock.unlock()
    }

    private func recordMouseUp(_ event: NSEvent) {
        guard let button = eventStreamMouseButton(forEventType: event.type) else {
            return
        }

        let appKitPoint = event.locationInWindow
        let screenPoint = eventStreamScreenStatePoint(fromAppKitGlobalPoint: appKitPoint)
        let fallbackPendingEvent = EventStreamPendingPointerEvent(
            button: button,
            clickCount: max(event.clickCount, 1),
            startedAt: Date(),
            appKitStartLocation: appKitPoint,
            screenStartLocation: screenPoint,
            rawEvents: recordsRawEvents ? [
                eventStreamRawEventSummary(event, screenPoint: screenPoint, button: button)
            ] : []
        )

        lock.lock()
        let pendingEvent = pendingPointerEvent?.button == button ? pendingPointerEvent : fallbackPendingEvent
        pendingPointerEvent = nil
        lock.unlock()

        guard var pointerEvent = pendingEvent else {
            return
        }
        pointerEvent.appKitLastLocation = appKitPoint
        pointerEvent.screenLastLocation = screenPoint
        if recordsRawEvents {
            pointerEvent.appendRawEvent(eventStreamRawEventSummary(event, screenPoint: screenPoint, button: button))
        }

        if eventStreamPointerDidDrag(
            start: pointerEvent.screenStartLocation,
            end: pointerEvent.screenLastLocation,
            observedDrag: pointerEvent.didDrag
        ) {
            recordFocusedWindowChangedIfNeeded(reason: "inputContextChanged")
            recordMouseDrag(pointerEvent)
            recordSelectionChangedIfNeeded(reason: "mouse.drag")
        } else {
            recordFocusedWindowChangedIfNeeded(reason: "inputContextChanged")
            recordMouseClick(pointerEvent)
            recordSelectionChangedIfNeeded(reason: eventStreamMouseEventType(forButton: pointerEvent.button))
        }
    }

    private func recordMouseClick(_ pointerEvent: EventStreamPendingPointerEvent) {
        var payload: [String: Any] = [
            "type": eventStreamMouseEventType(forButton: pointerEvent.button),
            "timestamp": eventStreamTimestamp(Date()),
            "button": pointerEvent.button,
            "clickCount": pointerEvent.clickCount,
            "location": [
                "x": pointerEvent.screenLastLocation.x,
                "y": pointerEvent.screenLastLocation.y,
            ],
            "appKitLocation": [
                "x": pointerEvent.appKitLastLocation.x,
                "y": pointerEvent.appKitLastLocation.y,
            ],
        ]
        payload.merge(currentEventStreamAppContext()) { current, _ in current }
        if let target = currentEventStreamPointerTarget(atScreenPoint: pointerEvent.screenLastLocation) {
            payload["targetAccessibilityElement"] = target
        }
        if recordsRawEvents, !pointerEvent.rawEvents.isEmpty {
            payload["experimentalRawEvents"] = pointerEvent.rawEvents
        }
        try? appendEvent(payload)
    }

    private func recordMouseDrag(_ pointerEvent: EventStreamPendingPointerEvent) {
        let distance = eventStreamPointerDistance(pointerEvent.screenStartLocation, pointerEvent.screenLastLocation)
        var payload: [String: Any] = [
            "type": "mouse.drag",
            "timestamp": eventStreamTimestamp(Date()),
            "button": pointerEvent.button,
            "startLocation": [
                "x": pointerEvent.screenStartLocation.x,
                "y": pointerEvent.screenStartLocation.y,
            ],
            "endLocation": [
                "x": pointerEvent.screenLastLocation.x,
                "y": pointerEvent.screenLastLocation.y,
            ],
            "startAppKitLocation": [
                "x": pointerEvent.appKitStartLocation.x,
                "y": pointerEvent.appKitStartLocation.y,
            ],
            "endAppKitLocation": [
                "x": pointerEvent.appKitLastLocation.x,
                "y": pointerEvent.appKitLastLocation.y,
            ],
            "distance": distance,
            "durationMilliseconds": max(0, Int(Date().timeIntervalSince(pointerEvent.startedAt) * 1000)),
        ]
        payload.merge(currentEventStreamAppContext()) { current, _ in current }
        if let target = currentEventStreamPointerTarget(atScreenPoint: pointerEvent.screenLastLocation) {
            payload["targetAccessibilityElement"] = target
        }
        if recordsRawEvents, !pointerEvent.rawEvents.isEmpty {
            payload["experimentalRawEvents"] = pointerEvent.rawEvents
        }
        try? appendEvent(payload)
    }

    private func recordKeyDown(_ event: NSEvent) {
        guard let payloadKind = eventStreamKeyboardPayloadKind(
            characters: event.characters,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            return
        }

        recordFocusedWindowChangedIfNeeded(reason: "inputContextChanged")
        let appContext = currentEventStreamAppContext()
        let focusedElement = currentEventStreamFocusedElement()
        let secureInput = focusedElement.map(eventStreamFocusedElementIsSecure) ?? false
        let terminalInput = focusedElement.map { eventStreamFocusedElementIsTerminal($0, appContext: appContext) } ?? false
        var payload: [String: Any] = [
            "type": payloadKind.type,
            "timestamp": eventStreamTimestamp(Date()),
            "keyCode": Int(event.keyCode),
        ]
        if let text = payloadKind.text {
            if secureInput {
                payload["secureInput"] = true
                payload["textLength"] = text.count
            } else {
                payload["text"] = text
            }
        }
        if let key = payloadKind.key {
            payload["key"] = key
        }
        let modifiers = eventStreamModifierNames(event.modifierFlags)
        if !modifiers.isEmpty {
            payload["modifiers"] = modifiers
        }
        payload.merge(appContext) { current, _ in current }
        if let focusedElement {
            payload["focusedAccessibilityElement"] = terminalInput
                ? eventStreamTerminalRedactedFocusedElement(focusedElement)
                : focusedElement
        }
        if recordsRawEvents {
            payload["experimentalRawEvents"] = [
                eventStreamRawEventSummary(event, redactCharacters: secureInput || terminalInput)
            ]
        }
        try? appendEvent(payload)
        if let focusedElement {
            recordTerminalValueChangedIfNeeded(reason: payloadKind.type, focusedElement: focusedElement, appContext: appContext)
        }
        recordSelectionChangedIfNeeded(reason: payloadKind.type)
    }

    private func recordScrollWheel(_ event: NSEvent) {
        guard recordsRawEvents else {
            return
        }

        let appKitPoint = event.locationInWindow
        let screenPoint = eventStreamScreenStatePoint(fromAppKitGlobalPoint: appKitPoint)
        recordFocusedWindowChangedIfNeeded(reason: "inputContextChanged")
        var payload: [String: Any] = [
            "type": "experimentalRawEvents",
            "timestamp": eventStreamTimestamp(Date()),
            "reason": "scrollWheel",
            "experimentalRawEvents": [
                eventStreamRawEventSummary(event, screenPoint: screenPoint)
            ],
        ]
        payload.merge(currentEventStreamAppContext()) { current, _ in current }
        if let target = currentEventStreamPointerTarget(atScreenPoint: screenPoint) {
            payload["targetAccessibilityElement"] = target
        }
        try? appendEvent(payload)
        recordSelectionChangedIfNeeded(reason: "scrollWheel")
    }

    private func recordFocusedWindowChangedIfNeeded(reason: String) {
        guard let currentContextKey = currentEventStreamWindowContextKey() else {
            return
        }

        lock.lock()
        let shouldRecord = lastObservedWindowContextKey != currentContextKey
        if shouldRecord {
            lastObservedWindowContextKey = currentContextKey
        }
        lock.unlock()

        if shouldRecord {
            recordWindowChanged(reason: reason, observedContextKey: currentContextKey)
            recordFocusedWindowChanged(reason: reason, observedContextKey: currentContextKey)
        }
    }

    private func recordSelectionChangedIfNeeded(reason: String) {
        guard let focusedElement = currentEventStreamFocusedElement() else {
            return
        }

        let selectedText = focusedElement["selectedText"] as? String ?? ""
        let signature = selectedText.isEmpty
            ? eventStreamSelectionClearedSignature(focusedElement: focusedElement)
            : eventStreamSelectionSignature(focusedElement: focusedElement)
        let selectionCleared = selectedText.isEmpty

        guard let signature else {
            return
        }

        lock.lock()
        let shouldRecord: Bool
        if selectionCleared {
            shouldRecord = lastSelectionSignature != nil
            if shouldRecord {
                lastSelectionSignature = nil
            }
        } else {
            shouldRecord = lastSelectionSignature != signature
            if shouldRecord {
                lastSelectionSignature = signature
            }
        }
        lock.unlock()

        guard shouldRecord else {
            return
        }

        var payload = eventStreamSelectionChangedPayload(
            reason: reason,
            selectedText: selectedText,
            selectionSignature: signature,
            focusedElement: focusedElement,
            selectionCleared: selectionCleared
        )
        payload.merge(currentEventStreamAppContext()) { current, _ in current }
        try? appendEvent(payload)
    }

    private func recordTerminalValueChangedIfNeeded(
        reason: String,
        focusedElement: [String: Any],
        appContext: [String: Any]
    ) {
        guard eventStreamFocusedElementIsTerminal(focusedElement, appContext: appContext),
              let value = eventStreamTerminalValue(focusedElement),
              !eventStreamFocusedElementIsSecure(focusedElement)
        else {
            return
        }

        let valueHash = eventStreamStableTextHash(value)
        let signature = eventStreamTerminalValueSignature(focusedElement: focusedElement, valueHash: valueHash)

        lock.lock()
        let shouldRecord = lastTerminalValueSignature != signature
        if shouldRecord {
            lastTerminalValueSignature = signature
        }
        lock.unlock()

        guard shouldRecord else {
            return
        }

        var payload: [String: Any] = [
            "type": "terminal.value_changed",
            "timestamp": eventStreamTimestamp(Date()),
            "reason": reason,
            "valueHash": valueHash,
            "valueLength": value.count,
            "terminalValueSignature": signature,
            "focusedAccessibilityElement": eventStreamTerminalRedactedFocusedElement(focusedElement),
        ]
        payload.merge(appContext) { current, _ in current }
        try? appendEvent(payload)
    }

    private func recordFocusedWindowChanged(reason: String) {
        recordFocusedWindowChanged(reason: reason, observedContextKey: nil)
    }

    private func recordWindowChanged(reason: String, observedContextKey: String? = nil) {
        guard let contextKey = observedContextKey ?? currentEventStreamWindowContextKey() else {
            return
        }

        var payload = eventStreamWindowChangedPayload(
            reason: reason,
            contextKey: contextKey,
            context: currentEventStreamAppContext()
        )
        if payload["window"] == nil {
            payload["windowUnavailable"] = true
        }
        try? appendEvent(payload)
    }

    private func recordFocusedWindowChanged(reason: String, observedContextKey: String?) {
        if let contextKey = observedContextKey ?? currentEventStreamWindowContextKey() {
            lock.lock()
            lastObservedWindowContextKey = contextKey
            lock.unlock()
        }

        var payload: [String: Any] = [
            "type": "AX.focusedWindowChanged",
            "timestamp": eventStreamTimestamp(Date()),
            "reason": reason,
            "screenshotNeededForContext": false,
        ]
        payload.merge(currentEventStreamAppContext()) { current, _ in current }
        if let accessibilityPayload = recordAccessibilityPayload() {
            payload["accessibilityInspectorPayload"] = accessibilityPayload
            payload["diffFromPrevious"] = accessibilityPayload["diffFromPrevious"] as? Bool ?? false
            payload["screenshotNeededForContext"] = accessibilityPayload["screenshotNeededForContext"] as? Bool ?? false
        }
        try? appendEvent(payload)
    }

    private func recordAccessibilityPayload() -> [String: Any]? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            try? appendSuppressedEvent([
                "type": "AX.snapshot.suppressed",
                "reason": "frontmostApplicationUnavailable",
            ])
            try? recordDebugError(
                subsystem: "accessibility",
                reason: "frontmostApplicationUnavailable"
            )
            return nil
        }

        let descriptor = RunningAppDescriptor(
            name: AppDiscovery.appName(app),
            bundleIdentifier: app.bundleIdentifier,
            pid: app.processIdentifier,
            runningApplication: app
        )

        do {
            let snapshot = try SnapshotBuilder.build(
                for: descriptor,
                includeScreenshot: screenshotPolicy != .never
            )
            return recordAccessibilityPayload(
                snapshot: snapshot,
                appName: descriptor.name,
                bundleIdentifier: descriptor.bundleIdentifier
            )
        } catch {
            try? appendSuppressedEvent([
                "type": "AX.snapshot.suppressed",
                "reason": "snapshotUnavailable",
                "message": (error as? LocalizedError)?.errorDescription ?? String(describing: error),
                "app": [
                    "name": descriptor.name,
                    "pid": Int(descriptor.pid),
                    "bundleIdentifier": descriptor.bundleIdentifier ?? "",
                ],
            ])
            try? recordDebugError(
                subsystem: "accessibility",
                reason: "snapshotUnavailable",
                error: error,
                context: [
                    "app": [
                        "name": descriptor.name,
                        "pid": Int(descriptor.pid),
                        "bundleIdentifier": descriptor.bundleIdentifier ?? "",
                    ],
                ]
            )
            return nil
        }
    }

    private func recordAccessibilityPayload(
        snapshot: AppSnapshot,
        appName: String,
        bundleIdentifier: String?
    ) -> [String: Any]? {
        let contextKey = eventStreamAXContextKey(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: snapshot.windowTitle
        )
        let currentTreeLines = snapshot.treeLines

        lock.lock()
        let previousTreeLines = lastAXContextKey == contextKey ? lastAXTreeLines : nil
        let baselineTreeLines = initialAXContextKey == contextKey ? initialAXTreeLines : nil
        if initialAXContextKey != contextKey {
            initialAXContextKey = contextKey
            initialAXTreeLines = currentTreeLines
        }
        lastAXContextKey = contextKey
        lastAXTreeLines = currentTreeLines
        lock.unlock()

        if let previousTreeLines,
           let difference = eventStreamCompactAXDiff(
               previous: previousTreeLines,
               current: currentTreeLines
           )
        {
            let cumulativeDifference = baselineTreeLines.flatMap { baselineTreeLines in
                eventStreamCompactAXDiff(
                    previous: baselineTreeLines,
                    current: currentTreeLines
                )
            }
            if baselineTreeLines != nil, cumulativeDifference == nil {
                try? appendSuppressedEvent([
                    "type": "AX.diff.suppressed",
                    "reason": "cumulativeDiffExceededBudget",
                    "contextKey": contextKey,
                ])
                try? recordDebugError(
                    subsystem: "accessibility",
                    reason: "cumulativeDiffExceededBudget",
                    context: [
                        "contextKeyHash": eventStreamStableTextHash(contextKey),
                    ]
                )
            }
            let screenshotContext = persistScreenshotIfNeeded(
                snapshot: snapshot,
                payloadKind: "diff",
                treeLines: difference.lines
            )
            return eventStreamAccessibilityPayload(
                kind: "diff",
                snapshot: snapshot,
                renderedText: difference.renderedText,
                treeLines: difference.lines,
                diffFromPrevious: true,
                cumulativeDifference: cumulativeDifference,
                screenshotContext: screenshotContext
            )
        }

        let screenshotContext = persistScreenshotIfNeeded(
            snapshot: snapshot,
            payloadKind: "full",
            treeLines: currentTreeLines
        )
        return eventStreamAccessibilityPayload(
            kind: "full",
            snapshot: snapshot,
            renderedText: snapshot.renderedText,
            treeLines: currentTreeLines,
            diffFromPrevious: false,
            cumulativeDifference: nil,
            screenshotContext: screenshotContext
        )
    }

    private func persistScreenshotIfNeeded(
        snapshot: AppSnapshot,
        payloadKind: String,
        treeLines: [String]
    ) -> EventStreamScreenshotContext {
        let isNeeded = eventStreamScreenshotNeededForContext(
            policy: screenshotPolicy,
            payloadKind: payloadKind,
            treeLineCount: treeLines.count,
            hasFocusedSummary: snapshot.focusedSummary != nil
        )
        guard isNeeded else {
            return EventStreamScreenshotContext(needed: false, path: nil)
        }

        guard let screenshotPNGData = snapshot.screenshotPNGData else {
            return EventStreamScreenshotContext(needed: true, path: nil)
        }

        lock.lock()
        let screenshotsDirectory = activeSession?.screenshotsDirectory
        lock.unlock()

        guard let screenshotsDirectory else {
            return EventStreamScreenshotContext(needed: true, path: nil)
        }

        do {
            try FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
            let filename = "\(eventStreamCompactTimestamp(Date()))-\(payloadKind)-context.png"
            let url = screenshotsDirectory.appendingPathComponent(filename)
            try screenshotPNGData.write(to: url, options: [.atomic])
            return EventStreamScreenshotContext(needed: true, path: url.path)
        } catch {
            try? appendSuppressedEvent([
                "type": "screenshot.suppressed",
                "reason": "writeFailed",
                "message": (error as? LocalizedError)?.errorDescription ?? String(describing: error),
            ])
            try? recordDebugError(
                subsystem: "screenshot",
                reason: "writeFailed",
                error: error
            )
            return EventStreamScreenshotContext(needed: true, path: nil)
        }
    }
}

private final class EventStreamSession {
    let id: String
    let directory: URL
    let startedAt: String
    var endedAt: String?
    var endReason: String?
    var state: EventStreamRecordingState = .recording
    var isFinishing = false
    var eventCount = 0
    var suppressedEventCount = 0

    init(id: String, directory: URL, startedAtDate: Date) {
        self.id = id
        self.directory = directory
        self.startedAt = eventStreamTimestamp(startedAtDate)
    }

    var eventsURL: URL {
        directory.appendingPathComponent("events.jsonl")
    }

    var metadataURL: URL {
        directory.appendingPathComponent("metadata.json")
    }

    var sessionURL: URL {
        directory.appendingPathComponent("session.json")
    }

    var suppressedEventsURL: URL {
        directory.appendingPathComponent("suppressed.jsonl")
    }

    var screenshotsDirectory: URL {
        directory.appendingPathComponent("screenshots", isDirectory: true)
    }

    var status: EventStreamRecordingStatus {
        EventStreamRecordingStatus(
            sessionID: id,
            state: state,
            startedAt: startedAt,
            endedAt: endedAt,
            endReason: endReason,
            eventsPath: eventsURL.path,
            metadataPath: metadataURL.path,
            suppressedEventsPath: suppressedEventsURL.path,
            currentSegmentEventsPath: state == .recording ? eventsURL.path : nil,
            currentSegmentMetadataPath: state == .recording ? metadataURL.path : nil,
            eventCount: eventCount,
            suppressedEventCount: suppressedEventCount
        )
    }
}

private struct EventStreamPendingPointerEvent {
    let button: String
    let clickCount: Int
    let startedAt: Date
    let appKitStartLocation: CGPoint
    let screenStartLocation: CGPoint
    var appKitLastLocation: CGPoint
    var screenLastLocation: CGPoint
    var didDrag = false
    var rawEvents: [[String: Any]]

    init(
        button: String,
        clickCount: Int,
        startedAt: Date,
        appKitStartLocation: CGPoint,
        screenStartLocation: CGPoint,
        rawEvents: [[String: Any]]
    ) {
        self.button = button
        self.clickCount = clickCount
        self.startedAt = startedAt
        self.appKitStartLocation = appKitStartLocation
        self.screenStartLocation = screenStartLocation
        self.appKitLastLocation = appKitStartLocation
        self.screenLastLocation = screenStartLocation
        self.rawEvents = rawEvents
    }

    mutating func appendRawEvent(_ rawEvent: [String: Any]) {
        if rawEvents.count < eventStreamMaximumRawEventsPerInputEvent {
            rawEvents.append(rawEvent)
        } else if !rawEvents.isEmpty {
            rawEvents[rawEvents.count - 1] = rawEvent
        }
    }
}

private func eventStreamApplicationContext(
    appName: String,
    bundleIdentifier: String?,
    pid: pid_t
) -> [String: Any] {
    var application: [String: Any] = [
        "name": appName,
        "pid": Int(pid),
    ]
    if let bundleIdentifier {
        application["bundleIdentifier"] = bundleIdentifier
    }
    return application
}

private func eventStreamWindowContext(snapshot: AppSnapshot) -> [String: Any]? {
    var window: [String: Any] = [:]
    if let windowTitle = snapshot.windowTitle, !windowTitle.isEmpty {
        window["title"] = windowTitle
    }
    if let targetWindowID = snapshot.targetWindowID {
        window["id"] = targetWindowID
    }
    if let targetWindowLayer = snapshot.targetWindowLayer {
        window["layer"] = targetWindowLayer
    }
    if let windowBounds = snapshot.windowBounds {
        window["bounds"] = [
            "x": windowBounds.origin.x,
            "y": windowBounds.origin.y,
            "width": windowBounds.size.width,
            "height": windowBounds.size.height,
        ]
    }
    return window.isEmpty ? nil : window
}

private func currentEventStreamAppContext() -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return [:]
    }

    var context: [String: Any] = [
        "app": eventStreamApplicationContext(
            appName: AppDiscovery.appName(app),
            bundleIdentifier: app.bundleIdentifier,
            pid: app.processIdentifier
        ),
    ]
    if let window = frontmostWindowContext(pid: app.processIdentifier) {
        context["window"] = window
    }
    return context
}

private func currentEventStreamWindowContextKey() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return nil
    }

    let windowTitle = frontmostWindowContext(pid: app.processIdentifier)?["title"] as? String
    return eventStreamAXContextKey(
        appName: AppDiscovery.appName(app),
        bundleIdentifier: app.bundleIdentifier,
        windowTitle: windowTitle
    )
}

func eventStreamAXContextKey(
    appName: String,
    bundleIdentifier: String?,
    windowTitle: String?
) -> String {
    [
        bundleIdentifier ?? appName,
        windowTitle ?? "",
    ].joined(separator: "\u{1f}")
}

func eventStreamWindowChangedPayload(
    reason: String,
    contextKey: String,
    context: [String: Any],
    timestamp: String = eventStreamTimestamp(Date())
) -> [String: Any] {
    var payload: [String: Any] = [
        "type": "window.changed",
        "timestamp": timestamp,
        "reason": reason,
        "windowContextKey": contextKey,
    ]
    payload.merge(context) { current, _ in current }
    return payload
}

func eventStreamDebugErrorPayload(
    subsystem: String,
    reason: String,
    error: Error? = nil,
    context: [String: Any] = [:],
    timestamp: String = eventStreamTimestamp(Date())
) -> [String: Any] {
    var payload: [String: Any] = [
        "type": "debug.error",
        "timestamp": timestamp,
        "subsystem": subsystem,
        "reason": reason,
    ]
    if let error {
        payload["errorType"] = String(describing: Swift.type(of: error))
    }
    payload.merge(eventStreamDebugSafeContext(context)) { current, _ in current }
    return payload
}

private func eventStreamDebugSafeContext(_ context: [String: Any]) -> [String: Any] {
    var safeContext: [String: Any] = [:]
    for (key, value) in context {
        if let nested = value as? [String: Any] {
            let sanitizedNested = eventStreamDebugSafeContext(nested)
            if !sanitizedNested.isEmpty {
                safeContext[key] = sanitizedNested
            }
        } else if let string = value as? String {
            if key.lowercased().contains("path") {
                continue
            }
            safeContext[key] = eventStreamTruncatedText(string, limit: 160)
        } else if let number = value as? NSNumber {
            safeContext[key] = number
        } else if let boolean = value as? Bool {
            safeContext[key] = boolean
        } else if let integer = value as? Int {
            safeContext[key] = integer
        } else if let double = value as? Double {
            safeContext[key] = double
        }
    }
    return safeContext
}

func eventStreamSelectionSignature(focusedElement: [String: Any]) -> String? {
    guard let selectedText = focusedElement["selectedText"] as? String,
          !selectedText.isEmpty
    else {
        return nil
    }

    return [
        eventStreamSelectionSignaturePart(focusedElement["role"]),
        eventStreamSelectionSignaturePart(focusedElement["subrole"]),
        eventStreamSelectionSignaturePart(focusedElement["title"]),
        eventStreamSelectionSignaturePart(focusedElement["label"]),
        eventStreamSelectionSignaturePart(focusedElement["value"]),
        selectedText,
        eventStreamSelectionFrameSignature(focusedElement["frame"] as? [String: Any]),
    ].joined(separator: "\u{1f}")
}

func eventStreamSelectionClearedSignature(focusedElement: [String: Any]) -> String? {
    let parts = [
        eventStreamSelectionSignaturePart(focusedElement["role"]),
        eventStreamSelectionSignaturePart(focusedElement["subrole"]),
        eventStreamSelectionSignaturePart(focusedElement["title"]),
        eventStreamSelectionSignaturePart(focusedElement["label"]),
        eventStreamSelectionSignaturePart(focusedElement["value"]),
        eventStreamSelectionFrameSignature(focusedElement["frame"] as? [String: Any]),
    ]
    guard parts.contains(where: { !$0.isEmpty }) else {
        return nil
    }

    return (parts + ["<selection-cleared>"]).joined(separator: "\u{1f}")
}

func eventStreamSelectionChangedPayload(
    reason: String,
    selectedText: String,
    selectionSignature: String,
    focusedElement: [String: Any],
    selectionCleared: Bool,
    timestamp: String = eventStreamTimestamp(Date())
) -> [String: Any] {
    var payload: [String: Any] = [
        "type": "selection.changed",
        "timestamp": timestamp,
        "reason": reason,
        "selectedText": selectedText,
        "selectionSignature": selectionSignature,
        "focusedAccessibilityElement": focusedElement,
    ]
    if selectionCleared {
        payload["selectionCleared"] = true
    }
    return payload
}

func eventStreamFocusedElementIsSecure(_ focusedElement: [String: Any]) -> Bool {
    if focusedElement["secureInput"] as? Bool == true || focusedElement["protectedContent"] as? Bool == true {
        return true
    }

    let role = (focusedElement["role"] as? String ?? "").lowercased()
    let subrole = (focusedElement["subrole"] as? String ?? "").lowercased()
    let roleDescription = (focusedElement["roleDescription"] as? String ?? "").lowercased()

    if subrole.contains("secure") || subrole.contains("password") {
        return true
    }
    if roleDescription.contains("secure") || roleDescription.contains("password") {
        return true
    }
    return role.contains("secure") || role.contains("password")
}

func eventStreamFocusedElementIsTerminal(_ focusedElement: [String: Any], appContext: [String: Any]) -> Bool {
    if eventStreamFocusedElementIsSecure(focusedElement) {
        return false
    }

    let bundleIdentifier = ((appContext["app"] as? [String: Any])?["bundleIdentifier"] as? String ?? "").lowercased()
    let appName = ((appContext["app"] as? [String: Any])?["name"] as? String ?? "").lowercased()
    let terminalAppIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.warp.warp-stable",
        "dev.warp.warp",
    ]
    let terminalApp = terminalAppIdentifiers.contains(bundleIdentifier)
        || appName == "terminal"
        || appName == "iterm"
        || appName == "iterm2"
        || appName == "warp"

    let role = (focusedElement["role"] as? String ?? "").lowercased()
    let subrole = (focusedElement["subrole"] as? String ?? "").lowercased()
    let roleDescription = (focusedElement["roleDescription"] as? String ?? "").lowercased()
    let title = (focusedElement["title"] as? String ?? "").lowercased()
    let label = (focusedElement["label"] as? String ?? "").lowercased()
    let textRole = role.contains("text") || role.contains("webarea") || role.contains("statictext")
    let terminalHint = [role, subrole, roleDescription, title, label].contains { value in
        value.contains("terminal") || value.contains("shell") || value.contains("console")
    }

    return terminalApp && (textRole || terminalHint)
}

func eventStreamTerminalValue(_ focusedElement: [String: Any]) -> String? {
    guard let value = focusedElement["value"] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return nil
    }
    return value
}

func eventStreamTerminalValueSignature(focusedElement: [String: Any], valueHash: String) -> String {
    [
        eventStreamSelectionSignaturePart(focusedElement["role"]),
        eventStreamSelectionSignaturePart(focusedElement["subrole"]),
        eventStreamSelectionSignaturePart(focusedElement["title"]),
        eventStreamSelectionSignaturePart(focusedElement["label"]),
        eventStreamSelectionFrameSignature(focusedElement["frame"] as? [String: Any]),
        valueHash,
    ].joined(separator: "\u{1f}")
}

func eventStreamTerminalRedactedFocusedElement(_ focusedElement: [String: Any]) -> [String: Any] {
    var redacted = focusedElement
    if let value = focusedElement["value"] as? String {
        redacted["valueHash"] = eventStreamStableTextHash(value)
        redacted["valueLength"] = value.count
        redacted.removeValue(forKey: "value")
    }
    if let selectedText = focusedElement["selectedText"] as? String {
        redacted["selectedTextLength"] = selectedText.count
        redacted.removeValue(forKey: "selectedText")
    }
    redacted["terminalValueRedacted"] = true
    return redacted
}

func eventStreamStableTextHash(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

private func eventStreamSelectionSignaturePart(_ value: Any?) -> String {
    value as? String ?? ""
}

private func eventStreamSelectionFrameSignature(_ frame: [String: Any]?) -> String {
    guard let frame else {
        return ""
    }

    return ["x", "y", "width", "height"]
        .map { key in eventStreamSelectionNumberSignature(frame[key]) }
        .joined(separator: ",")
}

private func eventStreamSelectionNumberSignature(_ value: Any?) -> String {
    if let number = value as? NSNumber {
        return String(format: "%.3f", number.doubleValue)
    }
    if let value = value as? CGFloat {
        return String(format: "%.3f", Double(value))
    }
    if let value = value as? Double {
        return String(format: "%.3f", value)
    }
    if let value = value as? Int {
        return String(format: "%.3f", Double(value))
    }
    return ""
}

func eventStreamScreenStatePoint(
    fromAppKitGlobalPoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    guard let mapping = screenMappings.first(where: { $0.appKitFrame.contains(point) }) else {
        return point
    }

    let localX = point.x - mapping.appKitFrame.minX
    let localY = mapping.appKitFrame.maxY - point.y

    return CGPoint(
        x: mapping.screenStateFrame.minX + localX,
        y: mapping.screenStateFrame.minY + localY
    )
}

private func currentEventStreamPointerTarget(atScreenPoint point: CGPoint) -> [String: Any]? {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return nil
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var hitElement: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &hitElement)
    guard result == .success, let hitElement else {
        return nil
    }

    return eventStreamAccessibilityElementSummary(
        hitElement,
        windowBounds: currentEventStreamWindowBounds(forPID: app.processIdentifier)
    )
}

private func currentEventStreamFocusedElement() -> [String: Any]? {
    let systemWide = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
    guard result == .success, let value else {
        return nil
    }

    let element = (value as! AXUIElement)
    return eventStreamAccessibilityElementSummary(element, windowBounds: nil)
}

private func eventStreamAccessibilityElementSummary(_ element: AXUIElement, windowBounds: CGRect?) -> [String: Any] {
    var summary: [String: Any] = [:]

    if let role = eventStreamStringValue(of: element, attribute: kAXRoleAttribute) {
        summary["role"] = role
    }
    if let subrole = eventStreamStringValue(of: element, attribute: kAXSubroleAttribute) {
        summary["subrole"] = subrole
    }
    if let roleDescription = eventStreamStringValue(of: element, attribute: kAXRoleDescriptionAttribute) {
        summary["roleDescription"] = eventStreamTruncatedText(roleDescription)
    }
    if let title = eventStreamStringValue(of: element, attribute: kAXTitleAttribute) {
        summary["title"] = eventStreamTruncatedText(title)
    }
    if let label = eventStreamStringValue(of: element, attribute: kAXDescriptionAttribute) {
        summary["label"] = eventStreamTruncatedText(label)
    }
    if let value = eventStreamStringValue(of: element, attribute: kAXValueAttribute) {
        summary["value"] = eventStreamTruncatedText(value)
    }
    if let selectedText = eventStreamStringValue(of: element, attribute: kAXSelectedTextAttribute) {
        summary["selectedText"] = eventStreamTruncatedText(selectedText)
    }
    if eventStreamBooleanValue(of: element, attribute: "AXProtectedContent") == true {
        summary["protectedContent"] = true
    }
    if let frame = eventStreamFrame(of: element) {
        summary["frame"] = eventStreamRectDictionary(frame)
        if let windowBounds {
            summary["windowFrame"] = eventStreamRectDictionary(windowRelativeFrame(elementFrame: frame, windowBounds: windowBounds))
        }
    }
    if let actions = eventStreamActions(of: element), !actions.isEmpty {
        summary["actions"] = actions
    }
    if eventStreamFocusedElementIsSecure(summary) {
        summary["secureInput"] = true
        summary.removeValue(forKey: "value")
        summary.removeValue(forKey: "selectedText")
    }

    return summary
}

private func eventStreamStringValue(of element: AXUIElement, attribute: String) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    return nil
}

private func eventStreamBooleanValue(of element: AXUIElement, attribute: String) -> Bool? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else {
        return nil
    }

    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean))
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}

private func eventStreamActions(of element: AXUIElement) -> [String]? {
    var actions: CFArray?
    let result = AXUIElementCopyActionNames(element, &actions)
    guard result == .success else {
        return nil
    }

    return actions as? [String]
}

private func eventStreamFrame(of element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
    let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    guard
        positionResult == .success,
        sizeResult == .success,
        let positionValue,
        let sizeValue
    else {
        return nil
    }

    let positionAXValue = positionValue as! AXValue
    let sizeAXValue = sizeValue as! AXValue
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionAXValue, .cgPoint, &position),
          AXValueGetValue(sizeAXValue, .cgSize, &size)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func eventStreamRectDictionary(_ rect: CGRect) -> [String: Any] {
    [
        "x": rect.origin.x,
        "y": rect.origin.y,
        "width": rect.size.width,
        "height": rect.size.height,
    ]
}

private func currentEventStreamWindowBounds(forPID pid: pid_t) -> CGRect? {
    guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    guard let window = rawWindows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }),
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? NSNumber,
          let y = bounds["Y"] as? NSNumber,
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber
    else {
        return nil
    }

    return CGRect(
        x: x.doubleValue,
        y: y.doubleValue,
        width: width.doubleValue,
        height: height.doubleValue
    )
}

private func eventStreamTruncatedText(_ text: String, limit: Int = 500) -> String {
    guard text.count > limit else {
        return text
    }

    return String(text.prefix(limit)) + "..."
}

struct EventStreamAXDifference: Equatable {
    let lines: [String]

    var renderedText: String {
        var output = ["The following is a diff from the previous accessibility tree"]
        output.append(contentsOf: lines)
        return output.joined(separator: "\n")
    }

    var cumulativeRenderedText: String {
        var output = ["The following is a cumulative diff from the initial accessibility tree"]
        output.append(contentsOf: lines)
        return output.joined(separator: "\n")
    }
}

struct EventStreamScreenshotContext: Equatable {
    let needed: Bool
    let path: String?
}

func eventStreamCompactAXDiff(
    previous: [String],
    current: [String],
    maxDiffLines: Int = 240
) -> EventStreamAXDifference? {
    guard previous != current else {
        return EventStreamAXDifference(lines: [])
    }

    guard let operations = eventStreamAXDiffOperations(previous: previous, current: current) else {
        return nil
    }

    var lines: [String] = []
    var pendingRemoved: [String] = []
    var pendingAdded: [String] = []

    func flushPending() -> Bool {
        guard !pendingRemoved.isEmpty || !pendingAdded.isEmpty else {
            return true
        }

        var consumedAddedIndexes = Set<Int>()
        for removedLine in pendingRemoved {
            if let removedIdentity = eventStreamAXLineIdentity(removedLine),
               let addedIndex = pendingAdded.indices.first(where: { addedIndex in
                   !consumedAddedIndexes.contains(addedIndex)
                       && eventStreamAXLineIdentity(pendingAdded[addedIndex]) == removedIdentity
               })
            {
                lines.append("~ \(removedLine) -> \(pendingAdded[addedIndex])")
                consumedAddedIndexes.insert(addedIndex)
            } else {
                lines.append("- \(removedLine)")
            }

            if lines.count > maxDiffLines {
                return false
            }
        }

        for addedIndex in pendingAdded.indices where !consumedAddedIndexes.contains(addedIndex) {
            lines.append("+ \(pendingAdded[addedIndex])")
            if lines.count > maxDiffLines {
                return false
            }
        }

        pendingRemoved.removeAll()
        pendingAdded.removeAll()
        return true
    }

    for operation in operations {
        switch operation {
        case .same:
            guard flushPending() else {
                return nil
            }
        case .removed(let line):
            pendingRemoved.append(line)
        case .added(let line):
            pendingAdded.append(line)
        }
    }

    guard flushPending() else {
        return nil
    }

    return EventStreamAXDifference(lines: lines)
}

private enum EventStreamAXDiffOperation: Equatable {
    case same
    case removed(String)
    case added(String)
}

private func eventStreamAXDiffOperations(previous: [String], current: [String]) -> [EventStreamAXDiffOperation]? {
    let maxMatrixCells = 1_000_000
    let columns = current.count + 1
    guard (previous.count + 1) * columns <= maxMatrixCells else {
        return nil
    }

    let previousComparable = previous.map(eventStreamAXLineComparable)
    let currentComparable = current.map(eventStreamAXLineComparable)
    var table = Array(repeating: 0, count: (previous.count + 1) * columns)

    func offset(_ previousIndex: Int, _ currentIndex: Int) -> Int {
        previousIndex * columns + currentIndex
    }

    if !previous.isEmpty, !current.isEmpty {
        for previousIndex in stride(from: previous.count - 1, through: 0, by: -1) {
            for currentIndex in stride(from: current.count - 1, through: 0, by: -1) {
                if previousComparable[previousIndex] == currentComparable[currentIndex] {
                    table[offset(previousIndex, currentIndex)] = table[offset(previousIndex + 1, currentIndex + 1)] + 1
                } else {
                    table[offset(previousIndex, currentIndex)] = max(
                        table[offset(previousIndex + 1, currentIndex)],
                        table[offset(previousIndex, currentIndex + 1)]
                    )
                }
            }
        }
    }

    var operations: [EventStreamAXDiffOperation] = []
    var previousIndex = 0
    var currentIndex = 0
    while previousIndex < previous.count || currentIndex < current.count {
        if previousIndex < previous.count,
           currentIndex < current.count,
           previousComparable[previousIndex] == currentComparable[currentIndex]
        {
            operations.append(.same)
            previousIndex += 1
            currentIndex += 1
        } else if currentIndex < current.count,
                  (previousIndex == previous.count
                      || table[offset(previousIndex, currentIndex + 1)] >= table[offset(previousIndex + 1, currentIndex)])
        {
            operations.append(.added(current[currentIndex]))
            currentIndex += 1
        } else if previousIndex < previous.count {
            operations.append(.removed(previous[previousIndex]))
            previousIndex += 1
        }
    }

    return operations
}

private func eventStreamAXLineComparable(_ line: String) -> String {
    line.replacingOccurrences(
        of: #"^\s*\d+\s+"#,
        with: "",
        options: .regularExpression
    )
}

private func eventStreamAXLineIdentity(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
        return nil
    }
    let elementIndex = String(trimmed[..<firstSpace])
    guard elementIndex.allSatisfy(\.isNumber) else {
        return nil
    }

    let remainder = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
    if let quoteIndex = remainder.firstIndex(of: "\"") {
        let role = remainder[..<quoteIndex].trimmingCharacters(in: .whitespaces)
        return role.isEmpty ? nil : "\(elementIndex) \(role)"
    }
    if let closeParen = remainder.firstIndex(of: ")") {
        let end = remainder.index(after: closeParen)
        let role = remainder[..<end].trimmingCharacters(in: .whitespaces)
        return role.isEmpty ? nil : "\(elementIndex) \(role)"
    }

    let roleWords = remainder.split(separator: " ").prefix(3).joined(separator: " ")
    return roleWords.isEmpty ? nil : "\(elementIndex) \(roleWords)"
}

private func eventStreamAccessibilityPayload(
    kind: String,
    snapshot: AppSnapshot,
    renderedText: String,
    treeLines: [String],
    diffFromPrevious: Bool,
    cumulativeDifference: EventStreamAXDifference?,
    screenshotContext: EventStreamScreenshotContext
) -> [String: Any] {
    var payload: [String: Any] = [
        "kind": kind,
        "diffFromPrevious": diffFromPrevious,
        "renderedText": renderedText,
        "treeLines": treeLines,
        "screenshotNeededForContext": screenshotContext.needed,
        "screenshotAvailable": snapshot.screenshotPNGData != nil,
    ]
    if !diffFromPrevious {
        payload["fullTree"] = treeLines
    }
    if let cumulativeDifference {
        payload["cumulativeDiffFromInitial"] = true
        payload["cumulativeRenderedText"] = cumulativeDifference.cumulativeRenderedText
        payload["cumulativeTreeLines"] = cumulativeDifference.lines
    } else {
        payload["cumulativeDiffFromInitial"] = false
    }
    if let screenshotPath = screenshotContext.path {
        payload["screenshotPath"] = screenshotPath
    }

    if let windowTitle = snapshot.windowTitle {
        payload["windowTitle"] = windowTitle
    }
    if let focusedSummary = snapshot.focusedSummary {
        payload["focusedSummary"] = focusedSummary
    }
    if let selectedText = snapshot.selectedText {
        payload["selectedText"] = selectedText
    }
    if let windowBounds = snapshot.windowBounds {
        payload["windowBounds"] = [
            "x": windowBounds.origin.x,
            "y": windowBounds.origin.y,
            "width": windowBounds.size.width,
            "height": windowBounds.size.height,
        ]
    }

    return payload
}

private func frontmostWindowContext(pid: pid_t) -> [String: Any]? {
    guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    guard let window = rawWindows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }) else {
        return nil
    }

    var context: [String: Any] = [:]
    if let windowID = window[kCGWindowNumber as String] as? NSNumber {
        context["id"] = windowID.intValue
    }
    if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
        context["title"] = title
    }
    if let layer = window[kCGWindowLayer as String] as? NSNumber {
        context["layer"] = layer.intValue
    }
    if let bounds = window[kCGWindowBounds as String] as? [String: Any] {
        context["bounds"] = bounds
    }

    return context.isEmpty ? nil : context
}

private func defaultEventStreamRootDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_EVENT_STREAM_DIR"],
       !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return applicationSupport
        .appendingPathComponent("OpenComputerUse", isDirectory: true)
        .appendingPathComponent("recordings", isDirectory: true)
}

public func eventStreamRecordingControlsEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return true
    }

    return !["0", "false", "no", "off"].contains(rawValue)
}

public func eventStreamScreenshotPolicy(environment: [String: String] = ProcessInfo.processInfo.environment) -> EventStreamScreenshotPolicy {
    guard let rawValue = environment["OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return .auto
    }

    return EventStreamScreenshotPolicy(rawValue: rawValue) ?? .auto
}

public func eventStreamRecordingMaximumDuration(environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
    guard let rawValue = environment["OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let value = TimeInterval(rawValue),
        value >= 0
    else {
        return eventStreamMaximumRecordingDuration
    }

    return value
}

public func eventStreamRawEventsEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return true
    }

    return !["0", "false", "no", "off"].contains(rawValue)
}

public func eventStreamStartApprovalPolicy(environment: [String: String] = ProcessInfo.processInfo.environment) -> EventStreamStartApprovalPolicy {
    guard let rawValue = environment["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return .automatic
    }

    switch rawValue {
    case "auto", "automatic":
        return .automatic
    case "1", "true", "yes", "on", "interactive", "prompt", "ui":
        return .interactive
    case "mcp", "elicitation", "mcp-elicitation", "mcp_elicitation":
        return .mcpElicitation
    case "0", "false", "no", "off", "approve", "approved", "auto-approve", "autoapprove":
        return .approve
    case "deny", "denied":
        return .deny
    case "cancel", "cancelled", "canceled":
        return .cancel
    default:
        return .automatic
    }
}

func eventStreamMouseEventType(forButton button: String) -> String {
    button == "right" ? "mouse.context_menu" : "mouse.click"
}

func eventStreamMouseButton(forEventType eventType: NSEvent.EventType) -> String? {
    switch eventType {
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
        return "left"
    case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
        return "right"
    case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
        return "middle"
    default:
        return nil
    }
}

func eventStreamPointerDistance(_ start: CGPoint, _ end: CGPoint) -> CGFloat {
    hypot(end.x - start.x, end.y - start.y)
}

func eventStreamPointerDidDrag(
    start: CGPoint,
    end: CGPoint,
    observedDrag: Bool,
    threshold: CGFloat = eventStreamMouseDragDistanceThreshold
) -> Bool {
    observedDrag || eventStreamPointerDistance(start, end) >= threshold
}

func eventStreamRawEventSummary(
    eventType: NSEvent.EventType,
    appKitLocation: CGPoint? = nil,
    screenLocation: CGPoint? = nil,
    button: String? = nil,
    clickCount: Int? = nil,
    keyCode: UInt16? = nil,
    characters: String? = nil,
    modifierFlags: NSEvent.ModifierFlags = [],
    scrollingDeltaX: CGFloat? = nil,
    scrollingDeltaY: CGFloat? = nil,
    hasPreciseScrollingDeltas: Bool? = nil,
    phase: NSEvent.Phase = [],
    momentumPhase: NSEvent.Phase = [],
    redactCharacters: Bool = false
) -> [String: Any] {
    var summary: [String: Any] = [
        "eventType": eventStreamRawEventTypeName(eventType),
    ]
    if let appKitLocation {
        summary["appKitLocation"] = [
            "x": appKitLocation.x,
            "y": appKitLocation.y,
        ]
    }
    if let screenLocation {
        summary["location"] = [
            "x": screenLocation.x,
            "y": screenLocation.y,
        ]
    }
    if let button {
        summary["button"] = button
    }
    if let clickCount {
        summary["clickCount"] = clickCount
    }
    if let keyCode {
        summary["keyCode"] = Int(keyCode)
    }
    if let characters, !characters.isEmpty {
        if redactCharacters {
            summary["charactersRedacted"] = true
            summary["characterCount"] = characters.count
        } else {
            summary["characters"] = characters
        }
    }
    let modifiers = eventStreamModifierNames(modifierFlags)
    if !modifiers.isEmpty {
        summary["modifiers"] = modifiers
    }
    if let scrollingDeltaX {
        summary["scrollingDeltaX"] = scrollingDeltaX
    }
    if let scrollingDeltaY {
        summary["scrollingDeltaY"] = scrollingDeltaY
    }
    if let hasPreciseScrollingDeltas {
        summary["hasPreciseScrollingDeltas"] = hasPreciseScrollingDeltas
    }
    if let phaseName = eventStreamRawPhaseName(phase) {
        summary["phase"] = phaseName
    }
    if let momentumPhaseName = eventStreamRawPhaseName(momentumPhase) {
        summary["momentumPhase"] = momentumPhaseName
    }
    return summary
}

private func eventStreamRawEventSummary(
    _ event: NSEvent,
    screenPoint: CGPoint? = nil,
    button: String? = nil,
    redactCharacters: Bool = false
) -> [String: Any] {
    let isPointerEvent = eventStreamMouseButton(forEventType: event.type) != nil
    let appKitLocation = event.type == .keyDown ? nil : event.locationInWindow
    let scrollPhase = event.type == .scrollWheel ? event.phase : []
    let scrollMomentumPhase = event.type == .scrollWheel ? event.momentumPhase : []
    return eventStreamRawEventSummary(
        eventType: event.type,
        appKitLocation: appKitLocation,
        screenLocation: screenPoint,
        button: button,
        clickCount: isPointerEvent && event.clickCount > 0 ? event.clickCount : nil,
        keyCode: event.type == .keyDown ? event.keyCode : nil,
        characters: event.type == .keyDown ? event.characters : nil,
        modifierFlags: event.modifierFlags,
        scrollingDeltaX: event.type == .scrollWheel ? event.scrollingDeltaX : nil,
        scrollingDeltaY: event.type == .scrollWheel ? event.scrollingDeltaY : nil,
        hasPreciseScrollingDeltas: event.type == .scrollWheel ? event.hasPreciseScrollingDeltas : nil,
        phase: scrollPhase,
        momentumPhase: scrollMomentumPhase,
        redactCharacters: redactCharacters
    )
}

func eventStreamRawEventTypeName(_ eventType: NSEvent.EventType) -> String {
    switch eventType {
    case .leftMouseDown:
        return "leftMouseDown"
    case .leftMouseUp:
        return "leftMouseUp"
    case .rightMouseDown:
        return "rightMouseDown"
    case .rightMouseUp:
        return "rightMouseUp"
    case .otherMouseDown:
        return "otherMouseDown"
    case .otherMouseUp:
        return "otherMouseUp"
    case .leftMouseDragged:
        return "leftMouseDragged"
    case .rightMouseDragged:
        return "rightMouseDragged"
    case .otherMouseDragged:
        return "otherMouseDragged"
    case .keyDown:
        return "keyDown"
    case .scrollWheel:
        return "scrollWheel"
    default:
        return "eventType\(eventType.rawValue)"
    }
}

func eventStreamRawPhaseName(_ phase: NSEvent.Phase) -> String? {
    if phase.isEmpty {
        return nil
    }

    var names: [String] = []
    if phase.contains(.mayBegin) {
        names.append("mayBegin")
    }
    if phase.contains(.began) {
        names.append("began")
    }
    if phase.contains(.stationary) {
        names.append("stationary")
    }
    if phase.contains(.changed) {
        names.append("changed")
    }
    if phase.contains(.ended) {
        names.append("ended")
    }
    if phase.contains(.cancelled) {
        names.append("cancelled")
    }
    return names.isEmpty ? nil : names.joined(separator: ",")
}

struct EventStreamKeyboardPayloadKind: Equatable {
    let type: String
    let text: String?
    let key: String?
}

func eventStreamKeyboardPayloadKind(
    characters: String?,
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
) -> EventStreamKeyboardPayloadKind? {
    let key = eventStreamKeyName(keyCode: keyCode, characters: characters)
    let normalizedModifiers = eventStreamModifierNames(modifierFlags)
    if key == "Return" || key == "Enter" {
        return EventStreamKeyboardPayloadKind(type: "keyboard.submit", text: nil, key: key)
    }
    if !normalizedModifiers.isEmpty {
        return EventStreamKeyboardPayloadKind(type: "keyboard.shortcut", text: nil, key: key)
    }
    guard let characters, !characters.isEmpty else {
        return nil
    }
    return EventStreamKeyboardPayloadKind(type: "keyboard.text_input", text: characters, key: nil)
}

func eventStreamModifierNames(_ modifierFlags: NSEvent.ModifierFlags) -> [String] {
    var names: [String] = []
    if modifierFlags.contains(.command) {
        names.append("command")
    }
    if modifierFlags.contains(.option) {
        names.append("option")
    }
    if modifierFlags.contains(.control) {
        names.append("control")
    }
    if modifierFlags.contains(.shift) {
        names.append("shift")
    }
    return names
}

func eventStreamKeyName(keyCode: UInt16, characters: String?) -> String {
    switch keyCode {
    case 36:
        return "Return"
    case 76:
        return "Enter"
    case 48:
        return "Tab"
    case 51:
        return "Backspace"
    case 53:
        return "Escape"
    case 123:
        return "Left"
    case 124:
        return "Right"
    case 125:
        return "Down"
    case 126:
        return "Up"
    default:
        if let characters, !characters.isEmpty {
            return characters.uppercased()
        }
        return "KeyCode\(keyCode)"
    }
}

func eventStreamScreenshotNeededForContext(
    policy: EventStreamScreenshotPolicy,
    payloadKind _: String,
    treeLineCount: Int,
    hasFocusedSummary: Bool
) -> Bool {
    switch policy {
    case .never:
        return false
    case .always:
        return true
    case .auto:
        return treeLineCount <= 8 || !hasFocusedSummary
    }
}

private func makeEventStreamSessionID(date: Date) -> String {
    "session-\(eventStreamCompactTimestamp(date))-\(UUID().uuidString.lowercased())"
}

private func eventStreamSessionIdentifierIsSafe(_ sessionID: String) -> Bool {
    guard sessionID.hasPrefix("session-"), !sessionID.isEmpty else {
        return false
    }
    return sessionID.allSatisfy { character in
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return false
        }
        return (scalar.value >= 97 && scalar.value <= 122)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 48 && scalar.value <= 57)
            || scalar.value == 45
    }
}

private func eventStreamTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func eventStreamCompactTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
    return formatter.string(from: date)
}

private func appendJSONObjectLine(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    guard let line = String(data: data, encoding: .utf8) else {
        throw ComputerUseError.message("Failed to encode event stream event.")
    }
    try appendTextLine(line, to: url)
}

private func eventStreamCanonicalEventPayload(_ event: [String: Any]) -> [String: Any] {
    var payload = event
    if payload["kind"] == nil, let type = payload["type"] as? String {
        payload["kind"] = type
    }
    if payload["type"] == nil, let kind = payload["kind"] as? String {
        payload["type"] = kind
    }
    return payload
}

private func appendTextLine(_ line: String, to url: URL) throws {
    let data = Data((line + "\n").utf8)
    if !FileManager.default.fileExists(atPath: url.path) {
        try data.write(to: url, options: [.atomic])
        return
    }

    let handle = try FileHandle(forWritingTo: url)
    defer {
        try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

private func writeEmptyFileIfNeeded(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
        try Data().write(to: url, options: [.atomic])
    }
}

@discardableResult
private func performEventStreamOnMainSync<Result: Sendable>(_ body: @MainActor @escaping () -> Result) -> Result {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            body()
        }
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            body()
        }
    }
}
