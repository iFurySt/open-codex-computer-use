import Foundation

public struct EventStreamRecordingValidationOptions: Equatable, Sendable {
    public let inputPath: String
    public let strictOCU: Bool
    public let requiredEventTypes: [String]
    public let requireSkillDraft: Bool

    public init(
        inputPath: String,
        strictOCU: Bool = false,
        requiredEventTypes: [String] = [],
        requireSkillDraft: Bool = false
    ) {
        self.inputPath = inputPath
        self.strictOCU = strictOCU
        self.requiredEventTypes = requiredEventTypes
        self.requireSkillDraft = requireSkillDraft
    }
}

private let eventStreamValidationSkillDraftActionEventTypes: Set<String> = [
    "mouse.click",
    "mouse.context_menu",
    "mouse.drag",
    "keyboard.text_input",
    "keyboard.submit",
    "keyboard.shortcut",
    "terminal.value_changed",
    "selection.changed",
]

private let eventStreamValidationBlockingDiagnosticReasons: Set<String> = [
    "inputMonitorsUnavailable",
]

private let eventStreamValidationHandoffPathKeys = [
    "metadataPath",
    "sessionPath",
    "eventsPath",
    "suppressedEventsPath",
]

public func validateEventStreamRecording(
    options: EventStreamRecordingValidationOptions
) -> [String: Any] {
    do {
        return try validateEventStreamRecordingImpl(options: options)
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return [
            "ok": false,
            "errors": [message],
            "warnings": [],
        ]
    }
}

private func validateEventStreamRecordingImpl(
    options: EventStreamRecordingValidationOptions
) throws -> [String: Any] {
    let resolved = try resolveEventStreamValidationInput(path: options.inputPath)
    var warnings: [String] = []
    var errors: [String] = []

    let metadata = try resolved.metadataURL.map(readEventStreamValidationJSONObject) ?? [:]
    let metadataJSONURL = resolved.sessionDirectory.appendingPathComponent("metadata.json")
    let sessionAliasURL = resolved.sessionDirectory.appendingPathComponent("session.json")
    if resolved.metadataURL == nil {
        if options.strictOCU {
            errors.append("strict OCU validation requires metadata.json or session.json")
        } else {
            warnings.append("metadata/session files not available; validating events.jsonl only")
        }
    } else if FileManager.default.fileExists(atPath: metadataJSONURL.path),
       FileManager.default.fileExists(atPath: sessionAliasURL.path)
    {
        do {
            let metadataJSON = try readEventStreamValidationJSONObject(metadataJSONURL)
            let sessionJSON = try readEventStreamValidationJSONObject(sessionAliasURL)
            if !eventStreamValidationSessionAliasCompatible(metadata: metadataJSON, sessionAlias: sessionJSON) {
                errors.append("metadata.json and session.json differ")
            }
        } catch {
            errors.append((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    } else if options.strictOCU {
        errors.append("strict OCU validation requires both metadata.json and session.json")
    } else {
        warnings.append("metadata/session alias pair is incomplete")
    }

    let declaredPaths = eventStreamValidationHandoffPathEvidence(
        metadata: metadata,
        baseDirectory: resolved.sessionDirectory
    )
    errors.append(
        contentsOf: eventStreamValidationHandoffPathErrors(
            evidence: declaredPaths,
            requireAllPaths: options.strictOCU
        )
    )

    let state = metadata["state"] as? String
    let currentSegmentEventsURL = eventStreamValidationOptionalPath(
        metadata["currentSegmentEventsPath"],
        baseDirectory: resolved.sessionDirectory
    )
    let currentSegmentMetadataURL = eventStreamValidationOptionalPath(
        metadata["currentSegmentMetadataPath"],
        baseDirectory: resolved.sessionDirectory
    )
    if let currentSegmentEventsURL,
       !FileManager.default.fileExists(atPath: currentSegmentEventsURL.path)
    {
        errors.append("currentSegmentEventsPath does not exist: \(metadata["currentSegmentEventsPath"] ?? currentSegmentEventsURL.path)")
    }
    if let currentSegmentMetadataURL,
       !FileManager.default.fileExists(atPath: currentSegmentMetadataURL.path)
    {
        errors.append("currentSegmentMetadataPath does not exist: \(metadata["currentSegmentMetadataPath"] ?? currentSegmentMetadataURL.path)")
    }
    if options.strictOCU {
        if state == "recording" {
            if currentSegmentEventsURL == nil {
                errors.append("recording state requires currentSegmentEventsPath")
            }
            if currentSegmentMetadataURL == nil {
                errors.append("recording state requires currentSegmentMetadataPath")
            }
        } else if state == "stopped" || state == "cancelled" {
            if currentSegmentEventsURL != nil {
                errors.append("final state must not include currentSegmentEventsPath")
            }
            if currentSegmentMetadataURL != nil {
                errors.append("final state must not include currentSegmentMetadataPath")
            }
        }
    }

    let eventsURL = resolved.eventsURL ?? eventStreamValidationPath(
        metadata["eventsPath"],
        baseDirectory: resolved.sessionDirectory,
        fallback: resolved.sessionDirectory.appendingPathComponent("events.jsonl")
    )
    let suppressedURL = eventStreamValidationPath(
        metadata["suppressedEventsPath"],
        baseDirectory: resolved.sessionDirectory,
        fallback: resolved.sessionDirectory.appendingPathComponent("suppressed.jsonl")
    )

    let events: [[String: Any]]
    do {
        events = try readEventStreamValidationJSONL(eventsURL)
    } catch {
        errors.append((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        events = []
    }

    let suppressedEvents: [[String: Any]]
    if FileManager.default.fileExists(atPath: suppressedURL.path) {
        do {
            suppressedEvents = try readEventStreamValidationJSONL(suppressedURL)
        } catch {
            errors.append((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            suppressedEvents = []
        }
    } else if options.strictOCU || metadata["suppressedEventsPath"] != nil {
        errors.append("suppressedEventsPath does not exist: \(suppressedURL.path)")
        suppressedEvents = []
    } else {
        warnings.append("suppressed events file not found: \(suppressedURL.path)")
        suppressedEvents = []
    }

    if let eventCount = metadata["eventCount"] as? Int {
        if eventCount != events.count {
            errors.append("eventCount=\(eventCount) does not match events.jsonl lines=\(events.count)")
        }
    } else {
        warnings.append("metadata has no eventCount")
    }

    if let suppressedEventCount = metadata["suppressedEventCount"] as? Int {
        if suppressedEventCount != suppressedEvents.count {
            errors.append("suppressedEventCount=\(suppressedEventCount) does not match suppressed.jsonl lines=\(suppressedEvents.count)")
        }
    } else {
        warnings.append("metadata has no suppressedEventCount")
    }

    let eventTypeCounts = eventStreamValidationEventTypeCounts(events)
    for requiredEventType in options.requiredEventTypes where eventTypeCounts[requiredEventType, default: 0] == 0 {
        errors.append("missing required event type: \(requiredEventType)")
    }

    let active = metadata["active"] as? Bool
    let endReason = metadata["endReason"] as? String
    let startedEvents = events.filter { eventStreamValidationEventKind($0) == "session.started" }
    let sessionStartedCountInvalid = startedEvents.count != 1
    let firstEventType = events.first.flatMap(eventStreamValidationEventKind)
    let sessionStartedIsFirst = firstEventType == "session.started"
    let sessionStartedNotFirst = !startedEvents.isEmpty && !sessionStartedIsFirst
    let endedEvents = events.filter { eventStreamValidationEventKind($0) == "session.ended" }
    let endedReasons = Set(endedEvents.compactMap { $0["endReason"] as? String })
    let sessionEndedCountInvalid = endedEvents.count > 1
    let finalEventType = events.last.flatMap(eventStreamValidationEventKind)
    let sessionEndedIsFinal = finalEventType == "session.ended"
    let sessionEndedNotFinal = !endedEvents.isEmpty && !sessionEndedIsFinal
    let inferredEndReason = endReason ?? (endedReasons.count == 1 ? endedReasons.first : nil)
    let recordingWasCancelled = state == "cancelled" || inferredEndReason == "recording_controls_cancelled"
    let recordingIncomplete = eventStreamValidationRecordingIncomplete(
        state: state,
        active: active,
        endedEvents: endedEvents
    )
    let blockingDiagnostics = eventStreamValidationBlockingDiagnostics(events)
    let hasSkillDraftAction = eventStreamValidationSkillDraftActionEventTypes.contains {
        eventTypeCounts[$0, default: 0] > 0
    }
    let skillDraftReasons = eventStreamValidationSkillDraftBlockingReasons(
        hasAction: hasSkillDraftAction,
        recordingWasCancelled: recordingWasCancelled,
        recordingIncomplete: recordingIncomplete,
        blockingDiagnostics: blockingDiagnostics,
        sessionStartedNotFirst: sessionStartedNotFirst,
        sessionStartedCountInvalid: sessionStartedCountInvalid,
        sessionEndedNotFinal: sessionEndedNotFinal,
        sessionEndedCountInvalid: sessionEndedCountInvalid
    )
    if options.requireSkillDraft {
        errors.append(contentsOf: skillDraftReasons)
    }

    if sessionStartedCountInvalid {
        let message = startedEvents.isEmpty
            ? "recording has no session.started event"
            : "recording has multiple session.started events"
        if options.strictOCU {
            errors.append(message)
        } else if !options.requireSkillDraft {
            warnings.append(message)
        }
    }

    if sessionStartedNotFirst {
        let message = "session.started is not the first event"
        if options.strictOCU {
            errors.append(message)
        } else if !options.requireSkillDraft {
            warnings.append(message)
        }
    }

    if sessionEndedCountInvalid {
        let message = "recording has multiple session.ended events"
        if options.strictOCU {
            errors.append(message)
        } else if !options.requireSkillDraft {
            warnings.append(message)
        }
    }

    if sessionEndedNotFinal {
        let message = "session.ended is not the final event"
        if options.strictOCU {
            errors.append(message)
        } else if !options.requireSkillDraft {
            warnings.append(message)
        }
    }

    if state == "stopped" || state == "cancelled" {
        if endedEvents.isEmpty {
            let message = "final state \(state ?? "") has no session.ended event"
            if options.strictOCU {
                errors.append(message)
            } else {
                warnings.append(message)
            }
        }
        if let endReason {
            if !endedReasons.isEmpty, !endedReasons.contains(endReason) {
                errors.append("metadata endReason=\(endReason) not present in session.ended events: \(Array(endedReasons).sorted())")
            }
        }
    }

    let sessionID = (metadata["sessionId"] as? String) ?? (metadata["sessionID"] as? String)
    if let sessionID {
        let mismatchedLines = events.enumerated().compactMap { index, event -> Int? in
            guard let eventSessionID = event["sessionId"] as? String else {
                return nil
            }
            return eventSessionID == sessionID ? nil : index + 1
        }
        if !mismatchedLines.isEmpty {
            errors.append("event sessionId mismatch at JSONL lines: \(Array(mismatchedLines.prefix(10)))")
        }
    }

    for (index, event) in events.enumerated() {
        for screenshotPath in collectEventStreamValidationScreenshotPaths(event) {
            let screenshotURL = eventStreamValidationURL(path: screenshotPath, baseDirectory: resolved.sessionDirectory)
            if !eventStreamValidationURL(screenshotURL, isInside: resolved.sessionDirectory) {
                errors.append("screenshotPath from event line \(index + 1) must stay inside session directory: \(screenshotPath)")
                continue
            }
            if !FileManager.default.fileExists(atPath: screenshotURL.path) {
                errors.append("screenshotPath from event line \(index + 1) does not exist: \(screenshotPath)")
            }
        }
    }

    if options.strictOCU {
        if metadata["active"] as? Bool != (state == "recording") {
            errors.append("metadata active flag does not match state")
        }
        if state != "recording" {
            let activeSessionURL = resolved.sessionDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("active-session.json")
            if FileManager.default.fileExists(atPath: activeSessionURL.path) {
                errors.append("active-session.json exists after final session state")
            }
        }
    }

    var result: [String: Any] = [
        "ok": errors.isEmpty,
        "sessionDir": resolved.sessionDirectory.path,
        "sessionPath": sessionAliasURL.path,
        "eventsPath": eventsURL.path,
        "suppressedEventsPath": suppressedURL.path,
        "eventCount": events.count,
        "suppressedEventCount": suppressedEvents.count,
        "eventTypes": eventTypeCounts.sortedDictionary(),
        "sessionStartedCount": startedEvents.count,
        "sessionStartedCountInvalid": sessionStartedCountInvalid,
        "sessionEndedCount": endedEvents.count,
        "sessionEndedCountInvalid": sessionEndedCountInvalid,
        "declaredPaths": declaredPaths,
        "warnings": warnings,
        "errors": errors,
    ]
    if let metadataURL = resolved.metadataURL {
        result["metadataPath"] = metadataURL.path
    }
    if let currentSegmentEventsURL {
        result["currentSegmentEventsPath"] = currentSegmentEventsURL.path
    }
    if let currentSegmentMetadataURL {
        result["currentSegmentMetadataPath"] = currentSegmentMetadataURL.path
    }
    if let state {
        result["state"] = state
    }
    if let active {
        result["active"] = active
    }
    if let inferredEndReason {
        result["endReason"] = inferredEndReason
    }
    if let firstEventType {
        result["firstEventType"] = firstEventType
        result["sessionStartedIsFirst"] = sessionStartedIsFirst
    }
    if let finalEventType {
        result["finalEventType"] = finalEventType
        result["sessionEndedIsFinal"] = sessionEndedIsFinal
    }
    if let sessionID {
        result["sessionId"] = sessionID
    }
    if let metadataEventCount = metadata["eventCount"] as? Int {
        result["metadataEventCount"] = metadataEventCount
    }
    if let metadataSuppressedEventCount = metadata["suppressedEventCount"] as? Int {
        result["metadataSuppressedEventCount"] = metadataSuppressedEventCount
    }
    result["skillDraftReady"] = skillDraftReasons.isEmpty
    result["skillDraftReasons"] = skillDraftReasons
    result["recordingIncomplete"] = recordingIncomplete
    result["blockingDiagnostics"] = blockingDiagnostics
    result["requireSkillDraft"] = options.requireSkillDraft
    return result
}

private func eventStreamValidationSkillDraftBlockingReasons(
    hasAction: Bool,
    recordingWasCancelled: Bool,
    recordingIncomplete: Bool,
    blockingDiagnostics: [[String: Any]],
    sessionStartedNotFirst: Bool,
    sessionStartedCountInvalid: Bool,
    sessionEndedNotFinal: Bool,
    sessionEndedCountInvalid: Bool
) -> [String] {
    var reasons: [String] = []
    if !hasAction {
        reasons.append("recording has no high-level user action events")
    }
    if recordingWasCancelled {
        reasons.append("recording was cancelled; do not create or update a skill from this event stream")
    }
    if recordingIncomplete {
        reasons.append("recording is not complete; stop the recording before creating a skill")
    }
    if !blockingDiagnostics.isEmpty {
        reasons.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    }
    if sessionStartedCountInvalid {
        reasons.append("recording must contain exactly one session.started event before creating a skill")
    }
    if sessionStartedNotFirst {
        reasons.append("recording has events before session.started; start must be the first event before creating a skill")
    }
    if sessionEndedNotFinal {
        reasons.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    }
    if sessionEndedCountInvalid {
        reasons.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    }
    return reasons
}

private func eventStreamValidationRecordingIncomplete(
    state: String?,
    active: Bool?,
    endedEvents: [[String: Any]]
) -> Bool {
    if state == "recording" || active == true {
        return true
    }
    return endedEvents.isEmpty
}

private func eventStreamValidationBlockingDiagnostics(_ events: [[String: Any]]) -> [[String: Any]] {
    var diagnostics: [[String: Any]] = []
    for (index, event) in events.enumerated() where eventStreamValidationEventKind(event) == "debug.error" {
        let reason = event["reason"] as? String
        guard reason.map(eventStreamValidationBlockingDiagnosticReasons.contains) == true else {
            continue
        }
        var diagnostic: [String: Any] = ["line": index + 1]
        for key in ["subsystem", "reason", "errorType"] {
            if let value = event[key] {
                diagnostic[key] = value
            }
        }
        diagnostics.append(diagnostic)
    }
    return diagnostics
}

private struct EventStreamValidationInput {
    let sessionDirectory: URL
    let metadataURL: URL?
    let eventsURL: URL?
}

private func resolveEventStreamValidationInput(path: String) throws -> EventStreamValidationInput {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw ComputerUseError.message("Path does not exist: \(path)")
    }

    if isDirectory.boolValue {
        let metadataURL = url.appendingPathComponent("metadata.json")
        let sessionURL = url.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            return EventStreamValidationInput(sessionDirectory: url, metadataURL: metadataURL, eventsURL: nil)
        }
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            return EventStreamValidationInput(sessionDirectory: url, metadataURL: sessionURL, eventsURL: nil)
        }
        throw ComputerUseError.message("Session directory has no metadata.json or session.json: \(path)")
    }

    switch url.lastPathComponent {
    case "metadata.json":
        return EventStreamValidationInput(
            sessionDirectory: url.deletingLastPathComponent(),
            metadataURL: url,
            eventsURL: nil
        )
    case "session.json":
        let metadataURL = url.deletingLastPathComponent().appendingPathComponent("metadata.json")
        let statusURL = FileManager.default.fileExists(atPath: metadataURL.path) ? metadataURL : url
        return EventStreamValidationInput(
            sessionDirectory: url.deletingLastPathComponent(),
            metadataURL: statusURL,
            eventsURL: nil
        )
    case "events.jsonl":
        return EventStreamValidationInput(
            sessionDirectory: url.deletingLastPathComponent(),
            metadataURL: nil,
            eventsURL: url
        )
    default:
        throw ComputerUseError.message("Input must be a session directory, metadata.json, session.json, or events.jsonl.")
    }
}

private func readEventStreamValidationJSONObject(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ComputerUseError.message("Expected JSON object in \(url.path).")
    }
    return object
}

private func readEventStreamValidationJSONL(_ url: URL) throws -> [[String: Any]] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var events: [[String: Any]] = []
    for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
        let data = Data(line.utf8)
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComputerUseError.message("Expected JSON object in \(url.path):\(index + 1).")
        }
        events.append(event)
    }
    return events
}

private func eventStreamValidationPath(_ value: Any?, baseDirectory: URL, fallback: URL) -> URL {
    guard let path = value as? String, !path.isEmpty else {
        return fallback
    }
    return eventStreamValidationURL(path: path, baseDirectory: baseDirectory)
}

private func eventStreamValidationOptionalPath(_ value: Any?, baseDirectory: URL) -> URL? {
    guard let path = value as? String, !path.isEmpty else {
        return nil
    }
    return eventStreamValidationURL(path: path, baseDirectory: baseDirectory)
}

private func eventStreamValidationURL(path: String, baseDirectory: URL) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    return baseDirectory.appendingPathComponent(path)
}

private func eventStreamValidationHandoffPathEvidence(
    metadata: [String: Any],
    baseDirectory: URL
) -> [String: [String: Any]] {
    var evidence: [String: [String: Any]] = [:]
    for key in eventStreamValidationHandoffPathKeys {
        let value = metadata[key]
        var entry: [String: Any] = [
            "value": value ?? NSNull(),
            "resolvedPath": NSNull(),
            "exists": NSNull(),
        ]
        if let path = value as? String, !path.isEmpty {
            let resolvedURL = eventStreamValidationURL(path: path, baseDirectory: baseDirectory)
            entry["resolvedPath"] = resolvedURL.path
            entry["exists"] = FileManager.default.fileExists(atPath: resolvedURL.path)
        }
        evidence[key] = entry
    }
    return evidence
}

private func eventStreamValidationHandoffPathErrors(
    evidence: [String: [String: Any]],
    requireAllPaths: Bool
) -> [String] {
    var errors: [String] = []
    for key in eventStreamValidationHandoffPathKeys {
        let entry = evidence[key] ?? [:]
        let value = entry["value"]
        if let path = value as? String, !path.isEmpty {
            if entry["exists"] as? Bool == false {
                errors.append("\(key) does not exist: \(path)")
            }
            continue
        }
        if value != nil, !(value is NSNull), !((value as? String)?.isEmpty == true) {
            errors.append("\(key) must be a non-empty string")
        } else if requireAllPaths {
            errors.append("strict OCU validation requires \(key)")
        }
    }
    return errors
}

private func eventStreamValidationSessionAliasCompatible(
    metadata: [String: Any],
    sessionAlias: [String: Any]
) -> Bool {
    if jsonObjectsEqual(metadata, sessionAlias) {
        return true
    }

    let metadataSessionID = eventStreamValidationFirstString(metadata, keys: ["sessionId", "sessionID", "id"])
    let sessionID = eventStreamValidationFirstString(sessionAlias, keys: ["id", "sessionId", "sessionID"])
    guard let metadataSessionID, let sessionID, metadataSessionID == sessionID else {
        return false
    }

    if let metadataStartedAt = metadata["startedAt"] as? String,
       metadataStartedAt != sessionAlias["startedAt"] as? String
    {
        return false
    }

    for key in ["endedAt", "endReason"] {
        if let sessionValue = sessionAlias[key] as? String,
           sessionValue != metadata[key] as? String
        {
            return false
        }
    }

    guard let sessionEventsPath = sessionAlias["eventsPath"] as? String,
          let metadataEventsPath = metadata["eventsPath"] as? String
    else {
        return false
    }
    if sessionEventsPath != metadataEventsPath,
       URL(fileURLWithPath: sessionEventsPath).lastPathComponent != URL(fileURLWithPath: metadataEventsPath).lastPathComponent
    {
        return false
    }

    return true
}

private func eventStreamValidationFirstString(_ dictionary: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dictionary[key] as? String, !value.isEmpty {
            return value
        }
    }
    return nil
}

private func eventStreamValidationEventTypeCounts(_ events: [[String: Any]]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for event in events {
        if let type = eventStreamValidationEventKind(event) {
            counts[type, default: 0] += 1
        }
    }
    return counts
}

private func eventStreamValidationEventKind(_ event: [String: Any]) -> String? {
    (event["kind"] as? String) ?? (event["type"] as? String)
}

private func collectEventStreamValidationScreenshotPaths(_ value: Any) -> [String] {
    if let dictionary = value as? [String: Any] {
        var paths: [String] = []
        for (key, child) in dictionary {
            if key == "screenshotPath", let path = child as? String, !path.isEmpty {
                paths.append(path)
            } else {
                paths.append(contentsOf: collectEventStreamValidationScreenshotPaths(child))
            }
        }
        return paths
    }
    if let array = value as? [Any] {
        return array.flatMap { collectEventStreamValidationScreenshotPaths($0) }
    }
    return []
}

private func eventStreamValidationURL(_ url: URL, isInside directory: URL) -> Bool {
    let candidatePath = url.standardizedFileURL.path
    let directoryPath = directory.standardizedFileURL.path
    return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
}

private func jsonObjectsEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    guard JSONSerialization.isValidJSONObject(lhs), JSONSerialization.isValidJSONObject(rhs) else {
        return false
    }
    let lhsData = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys])
    let rhsData = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys])
    return lhsData == rhsData
}

private extension Dictionary where Key == String, Value == Int {
    func sortedDictionary() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: sorted { $0.key < $1.key })
    }
}
