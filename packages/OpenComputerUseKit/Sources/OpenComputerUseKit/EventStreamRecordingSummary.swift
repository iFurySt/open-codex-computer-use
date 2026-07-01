import Foundation

public struct EventStreamRecordingSummaryOptions: Equatable, Sendable {
    public let inputPath: String
    public let includeText: Bool
    public let requireAction: Bool

    public init(inputPath: String, includeText: Bool = false, requireAction: Bool = false) {
        self.inputPath = inputPath
        self.includeText = includeText
        self.requireAction = requireAction
    }
}

private let eventStreamSummaryActionEventTypes: Set<String> = [
    "mouse.click",
    "mouse.context_menu",
    "mouse.drag",
    "keyboard.text_input",
    "keyboard.submit",
    "keyboard.shortcut",
    "terminal.value_changed",
    "selection.changed",
]

private let eventStreamSummaryContextEventTypes: Set<String> = [
    "session.started",
    "session.ended",
    "window.changed",
    "AX.focusedWindowChanged",
    "debug.error",
    "experimentalRawEvents",
]

private let eventStreamSummarySafetyKeywords: [(String, String)] = [
    ("send", "sendAction"),
    ("delete", "deleteAction"),
    ("remove", "deleteAction"),
    ("trash", "deleteAction"),
    ("archive", "archiveAction"),
    ("purchase", "purchaseAction"),
    ("buy", "purchaseAction"),
    ("pay", "paymentAction"),
    ("approve", "approvalAction"),
    ("upload", "uploadAction"),
    ("publish", "publishAction"),
    ("share", "shareAction"),
    ("invite", "inviteAction"),
    ("submit", "submitAction"),
    ("save", "saveAction"),
]

private let eventStreamSummaryBlockingDiagnosticReasons: Set<String> = [
    "inputMonitorsUnavailable",
]

private let eventStreamSummaryActionSequenceLimit = 50
private let eventStreamSummaryRuntimeInputsLimit = 50
private let eventStreamSummarySafetySignalsLimit = 50
private let eventStreamSummaryElementListLimit = 25
private let eventStreamSummaryDiagnosticsLimit = 25
private let eventStreamSummaryScreenshotPathsLimit = 25

public func summarizeEventStreamRecording(
    options: EventStreamRecordingSummaryOptions
) throws -> [String: Any] {
    let resolved = try resolveEventStreamSummaryInput(path: options.inputPath)
    let events = try readEventStreamSummaryJSONL(resolved.eventsURL)

    var eventTypeCounts: [String: Int] = [:]
    var actionEvents: [[String: Any]] = []
    var contextEventCount = 0
    var windows: [[String: Any]] = []
    var seenWindowKeys: Set<String> = []
    var actionSequence: [[String: Any]] = []
    var targetElements: [[String: Any]] = []
    var focusedElements: [[String: Any]] = []
    var selectionEvents: [[String: Any]] = []
    var debugErrors: [[String: Any]] = []
    var blockingDiagnostics: [[String: Any]] = []
    var redactionEvents: [[String: Any]] = []
    var screenshotPaths: [String] = []
    var runtimeInputs: [[String: Any]] = []
    var safetySignals: [[String: Any]] = []
    var sessionEndReasons: Set<String> = []
    var targetElementCount = 0
    var focusedElementCount = 0
    var selectionEventCount = 0
    var debugErrorCount = 0
    var redactionEventCount = 0
    var screenshotPathCount = 0
    var runtimeInputCount = 0
    var safetySignalCount = 0

    for (offset, event) in events.enumerated() {
        let line = offset + 1
        let eventType = eventStreamSummaryEventKind(event)
        if let eventType {
            eventTypeCounts[eventType, default: 0] += 1
            if eventStreamSummaryContextEventTypes.contains(eventType) {
                contextEventCount += 1
            }
        }

        if let window = eventStreamSummaryWindow(from: event) {
            let key = [
                window["bundleIdentifier"] as? String ?? "",
                window["appName"] as? String ?? "",
                window["windowTitle"] as? String ?? "",
            ].joined(separator: "|")
            if !seenWindowKeys.contains(key) {
                seenWindowKeys.insert(key)
                windows.append(window)
            }
        }

        if let actionType = eventStreamSummaryActionType(for: event) {
            actionEvents.append(event)
            var action: [String: Any] = [
                "line": line,
                "type": actionType,
            ]
            if let timestamp = event["timestamp"] as? String {
                action["timestamp"] = timestamp
            }
            if let window = eventStreamSummaryWindow(from: event) {
                action["window"] = window
            }
            for key in ["location", "startLocation", "endLocation", "key", "modifiers", "selectionCleared", "reason"] {
                if let value = event[key] {
                    action[key] = value
                }
            }
            if let rawEvents = event["experimentalRawEvents"] as? [[String: Any]] {
                let rawEventTypes = rawEvents.compactMap { $0["eventType"] as? String }
                if !rawEventTypes.isEmpty {
                    action["rawEventTypes"] = Array(rawEventTypes.prefix(8))
                }
                if let scroll = rawEvents.first(where: { $0["eventType"] as? String == "scrollWheel" }) {
                    for key in ["scrollingDeltaX", "scrollingDeltaY", "hasPreciseScrollingDeltas"] {
                        if let value = scroll[key] {
                            action[key] = value
                        }
                    }
                }
            }
            if let text = event["text"] as? String {
                action["textLength"] = text.count
            } else if let textLength = event["textLength"] {
                action["textLength"] = textLength
            }
            if let element = eventStreamSummaryElement(from: event, includeText: options.includeText) {
                action["element"] = element
            }
            if let runtimeInput = eventStreamSummaryRuntimeInput(
                line: line,
                event: event,
                action: action
            ) {
                runtimeInputCount += 1
                if runtimeInputs.count < eventStreamSummaryRuntimeInputsLimit {
                    runtimeInputs.append(runtimeInput)
                }
            }
            if let safetySignal = eventStreamSummarySafetySignal(
                line: line,
                event: event,
                action: action
            ) {
                safetySignalCount += 1
                if safetySignals.count < eventStreamSummarySafetySignalsLimit {
                    safetySignals.append(safetySignal)
                }
            }
            if actionSequence.count < eventStreamSummaryActionSequenceLimit {
                actionSequence.append(action)
            }
        }

        if let target = event["targetAccessibilityElement"] as? [String: Any] {
            targetElementCount += 1
            let wrapper = ["targetAccessibilityElement": target]
            if targetElements.count < eventStreamSummaryElementListLimit {
                targetElements.append(eventStreamSummaryElement(from: wrapper, includeText: options.includeText) ?? [:])
            }
        }
        if let focused = event["focusedAccessibilityElement"] as? [String: Any] {
            focusedElementCount += 1
            let wrapper = ["focusedAccessibilityElement": focused]
            if focusedElements.count < eventStreamSummaryElementListLimit {
                focusedElements.append(eventStreamSummaryElement(from: wrapper, includeText: options.includeText) ?? [:])
            }
        }

        if eventType == "selection.changed" {
            selectionEventCount += 1
            let selectedText = event["selectedText"] as? String
            if selectionEvents.count < eventStreamSummaryElementListLimit {
                selectionEvents.append([
                    "line": line,
                    "selectedTextLength": selectedText?.count ?? 0,
                    "selectionCleared": event["selectionCleared"] as? Bool == true,
                ])
            }
        }

        if eventType == "session.ended", let endReason = event["endReason"] as? String, !endReason.isEmpty {
            sessionEndReasons.insert(endReason)
        }

        if eventType == "debug.error" {
            if eventStreamSummaryIsBlockingDiagnostic(event) {
                blockingDiagnostics.append(eventStreamSummaryFilteredEvent(
                    line: line,
                    event: event,
                    keys: ["subsystem", "reason", "errorType"]
                ))
            }
            debugErrorCount += 1
            if debugErrors.count < eventStreamSummaryDiagnosticsLimit {
                debugErrors.append(eventStreamSummaryFilteredEvent(
                    line: line,
                    event: event,
                    keys: ["subsystem", "reason", "errorType"]
                ))
            }
        }

        if event["secureInput"] as? Bool == true || event["redacted"] as? Bool == true {
            redactionEventCount += 1
            if redactionEvents.count < eventStreamSummaryDiagnosticsLimit {
                var redaction: [String: Any] = [
                    "line": line,
                    "secureInput": event["secureInput"] as? Bool == true,
                    "redacted": event["redacted"] as? Bool == true,
                ]
                if let eventType {
                    redaction["type"] = eventType
                }
                redactionEvents.append(redaction)
            }
        }

        if let payload = event["accessibilityInspectorPayload"] as? [String: Any],
           let screenshotPath = payload["screenshotPath"] as? String,
           !screenshotPath.isEmpty
        {
            screenshotPathCount += 1
            if screenshotPaths.count < eventStreamSummaryScreenshotPathsLimit {
                screenshotPaths.append(screenshotPath)
            }
        }
    }

    let summaryLimits = eventStreamSummaryLimits(
        actionEventCount: actionEvents.count,
        actionSequenceStored: actionSequence.count,
        runtimeInputCount: runtimeInputCount,
        runtimeInputsStored: runtimeInputs.count,
        safetySignalCount: safetySignalCount,
        safetySignalsStored: safetySignals.count,
        targetElementCount: targetElementCount,
        targetElementsStored: targetElements.count,
        focusedElementCount: focusedElementCount,
        focusedElementsStored: focusedElements.count,
        selectionEventCount: selectionEventCount,
        selectionEventsStored: selectionEvents.count,
        debugErrorCount: debugErrorCount,
        debugErrorsStored: debugErrors.count,
        redactionEventCount: redactionEventCount,
        redactionEventsStored: redactionEvents.count,
        screenshotPathCount: screenshotPathCount,
        screenshotPathsStored: screenshotPaths.count
    )
    let hasTruncatedSummary = summaryLimits["hasTruncatedSummary"] as? Bool == true

    let inferredEndReason = (resolved.metadata["endReason"] as? String)
        ?? (sessionEndReasons.count == 1 ? sessionEndReasons.first : nil)
    let recordingWasCancelled = (resolved.metadata["state"] as? String) == "cancelled"
        || inferredEndReason == "recording_controls_cancelled"
    let recordingIncomplete = eventStreamSummaryRecordingIncomplete(
        metadata: resolved.metadata,
        eventTypeCounts: eventTypeCounts
    )
    let firstEventType = events.first.flatMap(eventStreamSummaryEventKind)
    let sessionStartedIsFirst = firstEventType == "session.started"
    let sessionStartedNotFirst = eventTypeCounts["session.started", default: 0] > 0 && !sessionStartedIsFirst
    let sessionStartedCountInvalid = eventTypeCounts["session.started", default: 0] != 1
    let finalEventType = events.last.flatMap(eventStreamSummaryEventKind)
    let sessionEndedIsFinal = finalEventType == "session.ended"
    let sessionEndedNotFinal = eventTypeCounts["session.ended", default: 0] > 0 && !sessionEndedIsFinal
    let sessionEndedCountInvalid = eventTypeCounts["session.ended", default: 0] > 1

    var warnings: [String] = []
    if actionEvents.isEmpty {
        warnings.append("recording has no high-level user action events")
    }
    if recordingWasCancelled {
        warnings.append("recording was cancelled; do not create or update a skill from this event stream")
    }
    if recordingIncomplete {
        warnings.append("recording is not complete; stop the recording before creating a skill")
    }
    if sessionStartedCountInvalid {
        warnings.append("recording must contain exactly one session.started event before creating a skill")
    }
    if sessionStartedNotFirst {
        warnings.append("recording has events before session.started; start must be the first event before creating a skill")
    }
    if sessionEndedNotFinal {
        warnings.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    }
    if sessionEndedCountInvalid {
        warnings.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    }
    if eventTypeCounts["AX.focusedWindowChanged", default: 0] == 0 {
        warnings.append("recording has no AX focused window context")
    }
    if !debugErrors.isEmpty {
        warnings.append("recording includes debug.error events; inspect diagnostics before creating a skill")
    }
    if !blockingDiagnostics.isEmpty {
        warnings.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    }
    if !redactionEvents.isEmpty {
        warnings.append("recording includes redaction or secureInput signals; avoid copying sensitive values")
    }
    if !safetySignals.isEmpty {
        warnings.append("recording includes actions that may require explicit user confirmation")
    }
    if hasTruncatedSummary {
        warnings.append("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill")
    }

    var errors: [String] = []
    if options.requireAction, actionEvents.isEmpty {
        errors.append("required at least one high-level user action event")
    }
    if options.requireAction, recordingWasCancelled {
        errors.append("recording was cancelled; do not create or update a skill from this event stream")
    }
    if options.requireAction, recordingIncomplete {
        errors.append("recording is not complete; stop the recording before creating a skill")
    }
    if options.requireAction, sessionStartedCountInvalid {
        errors.append("recording must contain exactly one session.started event before creating a skill")
    }
    if options.requireAction, sessionStartedNotFirst {
        errors.append("recording has events before session.started; start must be the first event before creating a skill")
    }
    if options.requireAction, sessionEndedNotFinal {
        errors.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    }
    if options.requireAction, sessionEndedCountInvalid {
        errors.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    }
    if options.requireAction, !blockingDiagnostics.isEmpty {
        errors.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    }

    let skillEvidence = eventStreamSummarySkillEvidence(
        eventTypeCounts: eventTypeCounts,
        hasActionEvents: !actionEvents.isEmpty,
        hasTargetElements: !targetElements.isEmpty,
        hasFocusedElements: !focusedElements.isEmpty,
        hasSelectionSignals: !selectionEvents.isEmpty,
        hasScreenshots: !screenshotPaths.isEmpty,
        hasDebugErrors: !debugErrors.isEmpty,
        hasBlockingDiagnostics: !blockingDiagnostics.isEmpty,
        recordingIncomplete: recordingIncomplete,
        sessionStartedNotFirst: sessionStartedNotFirst,
        sessionStartedCountInvalid: sessionStartedCountInvalid,
        sessionEndedNotFinal: sessionEndedNotFinal,
        sessionEndedCountInvalid: sessionEndedCountInvalid,
        hasRedactionSignals: !redactionEvents.isEmpty,
        hasSafetySignals: !safetySignals.isEmpty,
        hasTruncatedSummary: hasTruncatedSummary
    )

    var result: [String: Any] = [
        "ok": errors.isEmpty,
        "sessionDir": resolved.sessionDirectory.path,
        "eventsPath": resolved.eventsURL.path,
        "eventCount": events.count,
        "eventTypes": eventTypeCounts.sortedDictionary(),
        "actionEventCount": actionEvents.count,
        "contextEventCount": contextEventCount,
        "windows": windows,
        "skillEvidence": skillEvidence,
        "skillReadiness": eventStreamSummarySkillReadiness(
            evidence: skillEvidence,
            hasWindowContext: !windows.isEmpty,
            recordingWasCancelled: recordingWasCancelled,
            recordingIncomplete: recordingIncomplete,
            sessionStartedNotFirst: sessionStartedNotFirst,
            sessionStartedCountInvalid: sessionStartedCountInvalid,
            sessionEndedNotFinal: sessionEndedNotFinal,
            sessionEndedCountInvalid: sessionEndedCountInvalid
        ),
        "summaryLimits": summaryLimits,
        "runtimeInputs": runtimeInputs,
        "safetySignals": safetySignals,
        "actionSequence": actionSequence,
        "targetElements": targetElements,
        "focusedElements": focusedElements,
        "selectionEvents": selectionEvents,
        "debugErrors": debugErrors,
        "blockingDiagnostics": blockingDiagnostics,
        "redactionEvents": redactionEvents,
        "screenshotPaths": screenshotPaths,
        "includesRawText": options.includeText,
        "warnings": warnings,
        "errors": errors,
        "sessionStartedCount": eventTypeCounts["session.started", default: 0],
        "sessionEndedCount": eventTypeCounts["session.ended", default: 0],
    ]
    if let firstEventType {
        result["firstEventType"] = firstEventType
        result["sessionStartedIsFirst"] = sessionStartedIsFirst
    }
    if let finalEventType {
        result["finalEventType"] = finalEventType
        result["sessionEndedIsFinal"] = sessionEndedIsFinal
    }

    if let metadataURL = resolved.metadataURL {
        result["metadataPath"] = metadataURL.path
    }
    if let sessionID = resolved.metadata["sessionId"] ?? resolved.metadata["sessionID"] {
        result["sessionId"] = sessionID
    }
    if let state = resolved.metadata["state"] {
        result["state"] = state
    }
    if let endReason = inferredEndReason {
        result["endReason"] = endReason
    }

    return result
}

private struct EventStreamSummaryInput {
    let sessionDirectory: URL
    let metadataURL: URL?
    let metadata: [String: Any]
    let eventsURL: URL
}

private func resolveEventStreamSummaryInput(path: String) throws -> EventStreamSummaryInput {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw ComputerUseError.message("Path does not exist: \(path)")
    }

    if isDirectory.boolValue {
        let metadataURL = url.appendingPathComponent("metadata.json")
        let sessionURL = url.appendingPathComponent("session.json")
        let resolvedMetadataURL: URL?
        let metadata: [String: Any]
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            resolvedMetadataURL = metadataURL
            metadata = try readEventStreamSummaryJSONObject(metadataURL)
        } else if FileManager.default.fileExists(atPath: sessionURL.path) {
            resolvedMetadataURL = sessionURL
            metadata = try readEventStreamSummaryJSONObject(sessionURL)
        } else {
            resolvedMetadataURL = nil
            metadata = [:]
        }
        let eventsURL = eventStreamSummaryPath(
            metadata["eventsPath"],
            baseDirectory: url,
            fallback: url.appendingPathComponent("events.jsonl")
        )
        return EventStreamSummaryInput(
            sessionDirectory: url,
            metadataURL: resolvedMetadataURL,
            metadata: metadata,
            eventsURL: eventsURL
        )
    }

    switch url.lastPathComponent {
    case "metadata.json", "session.json":
        let metadata = try readEventStreamSummaryJSONObject(url)
        let sessionDirectory = url.deletingLastPathComponent()
        let eventsURL = eventStreamSummaryPath(
            metadata["eventsPath"],
            baseDirectory: sessionDirectory,
            fallback: sessionDirectory.appendingPathComponent("events.jsonl")
        )
        return EventStreamSummaryInput(
            sessionDirectory: sessionDirectory,
            metadataURL: url,
            metadata: metadata,
            eventsURL: eventsURL
        )
    case "events.jsonl":
        return EventStreamSummaryInput(
            sessionDirectory: url.deletingLastPathComponent(),
            metadataURL: nil,
            metadata: [:],
            eventsURL: url
        )
    default:
        throw ComputerUseError.message("Input must be a session directory, metadata.json, session.json, or events.jsonl.")
    }
}

private func readEventStreamSummaryJSONObject(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ComputerUseError.message("Expected JSON object in \(url.path).")
    }
    return object
}

private func readEventStreamSummaryJSONL(_ url: URL) throws -> [[String: Any]] {
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

private func eventStreamSummaryPath(_ value: Any?, baseDirectory: URL, fallback: URL) -> URL {
    guard let path = value as? String, !path.isEmpty else {
        return fallback
    }
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    return baseDirectory.appendingPathComponent(path)
}

private func eventStreamSummaryWindow(from event: [String: Any]) -> [String: Any]? {
    let app = firstNestedDictionary(event, keys: ["app", "application", "appContext"])
    let window = firstNestedDictionary(event, keys: ["window", "windowContext", "targetWindow"])
    let appName = firstString(event, keys: ["appName", "applicationName", "localizedName"])
        ?? firstString(app, keys: ["name", "appName", "localizedName"])
    let bundleIdentifier = firstString(event, keys: ["bundleIdentifier", "bundleId", "appBundleIdentifier"])
        ?? firstString(app, keys: ["bundleIdentifier", "bundleId"])
    let windowTitle = firstString(event, keys: ["windowTitle", "title"])
        ?? firstString(window, keys: ["title", "windowTitle"])

    var result: [String: Any] = [:]
    if let appName {
        result["appName"] = appName
    }
    if let bundleIdentifier {
        result["bundleIdentifier"] = bundleIdentifier
    }
    if let windowTitle {
        result["windowTitle"] = windowTitle
    }
    return result.isEmpty ? nil : result
}

private func eventStreamSummaryActionType(for event: [String: Any]) -> String? {
    guard let eventType = eventStreamSummaryEventKind(event) else {
        return nil
    }
    if eventStreamSummaryActionEventTypes.contains(eventType) {
        return eventType
    }
    if eventType == "experimentalRawEvents",
       event["reason"] as? String == "scrollWheel"
    {
        return eventType
    }
    return nil
}

private func eventStreamSummaryElement(
    from event: [String: Any],
    includeText: Bool
) -> [String: Any]? {
    guard let element = firstNestedDictionary(event, keys: ["targetAccessibilityElement", "focusedAccessibilityElement"]) else {
        return nil
    }

    var result: [String: Any] = [:]
    for key in ["role", "subrole", "title", "label", "description"] {
        if let value = element[key] as? String, !value.isEmpty {
            result[key] = value
        } else if let value = element[key] as? Bool {
            result[key] = value
        }
    }
    for key in ["value", "selectedText"] {
        if let value = element[key] as? String, !value.isEmpty {
            if includeText {
                result[key] = value
            }
            result["\(key)Length"] = value.count
        } else if let value = element[key] as? Bool {
            result[key] = value
        }
    }
    if let actions = element["actions"] as? [String], !actions.isEmpty {
        result["actions"] = Array(actions.prefix(8))
    }
    if element["secureInput"] as? Bool == true {
        result["secureInput"] = true
    }
    return result.isEmpty ? nil : result
}

private func eventStreamSummaryFilteredEvent(
    line: Int,
    event: [String: Any],
    keys: [String]
) -> [String: Any] {
    var result: [String: Any] = ["line": line]
    for key in keys {
        if let value = event[key] {
            result[key] = value
        }
    }
    return result
}

private func eventStreamSummaryRuntimeInput(
    line: Int,
    event: [String: Any],
    action: [String: Any]
) -> [String: Any]? {
    guard let eventType = action["type"] as? String else {
        return nil
    }

    var result: [String: Any] = [
        "line": line,
        "sourceEventType": eventType,
        "requiresUserValue": true,
    ]
    if let element = action["element"] as? [String: Any], !element.isEmpty {
        result["target"] = element
    }

    switch eventType {
    case "keyboard.text_input":
        result["kind"] = "text"
        result["description"] = "Runtime text to enter into the observed target."
        if let textLength = action["textLength"] {
            result["textLength"] = textLength
        }
        if event["secureInput"] as? Bool == true || event["redacted"] as? Bool == true {
            result["sensitive"] = true
        }
        return result
    case "selection.changed":
        result["kind"] = "selection"
        result["description"] = "Current selection or selected-content semantics if the workflow depends on it."
        if let selectedText = event["selectedText"] as? String {
            result["selectedTextLength"] = selectedText.count
        }
        if let selectionCleared = action["selectionCleared"] {
            result["selectionCleared"] = selectionCleared
        }
        return result
    default:
        return nil
    }
}

private func eventStreamSummarySafetySignal(
    line: Int,
    event: [String: Any],
    action: [String: Any]
) -> [String: Any]? {
    guard let eventType = action["type"] as? String else {
        return nil
    }

    var reason: String?
    if eventType == "keyboard.submit" {
        reason = "submitAction"
    }

    let element = action["element"] as? [String: Any] ?? [:]
    if reason == nil, let matchedReason = eventStreamSummarySafetyKeywordReason(element: element) {
        reason = matchedReason
    }
    guard let reason else {
        return nil
    }

    var result: [String: Any] = [
        "line": line,
        "sourceEventType": eventType,
        "reason": reason,
        "confirmationRequired": true,
    ]
    if let timestamp = event["timestamp"] as? String {
        result["timestamp"] = timestamp
    }
    if let window = action["window"] as? [String: Any], !window.isEmpty {
        result["window"] = window
    }
    if !element.isEmpty {
        result["target"] = element
    }
    return result
}

private func eventStreamSummarySafetyKeywordReason(element: [String: Any]) -> String? {
    let text = ["role", "title", "label", "description", "subrole"]
        .compactMap { element[$0] as? String }
        .joined(separator: " ")
        .lowercased()
    guard !text.isEmpty else {
        return nil
    }
    for (keyword, reason) in eventStreamSummarySafetyKeywords where text.contains(keyword) {
        return reason
    }
    return nil
}

private func eventStreamSummaryIsBlockingDiagnostic(_ event: [String: Any]) -> Bool {
    guard eventStreamSummaryEventKind(event) == "debug.error",
          let reason = event["reason"] as? String
    else {
        return false
    }
    return eventStreamSummaryBlockingDiagnosticReasons.contains(reason)
}

private func eventStreamSummaryRecordingIncomplete(
    metadata: [String: Any],
    eventTypeCounts: [String: Int]
) -> Bool {
    if metadata["state"] as? String == "recording" || metadata["active"] as? Bool == true {
        return true
    }
    return eventTypeCounts["session.ended", default: 0] == 0
}

private func eventStreamSummaryLimits(
    actionEventCount: Int,
    actionSequenceStored: Int,
    runtimeInputCount: Int,
    runtimeInputsStored: Int,
    safetySignalCount: Int,
    safetySignalsStored: Int,
    targetElementCount: Int,
    targetElementsStored: Int,
    focusedElementCount: Int,
    focusedElementsStored: Int,
    selectionEventCount: Int,
    selectionEventsStored: Int,
    debugErrorCount: Int,
    debugErrorsStored: Int,
    redactionEventCount: Int,
    redactionEventsStored: Int,
    screenshotPathCount: Int,
    screenshotPathsStored: Int
) -> [String: Any] {
    var omittedCounts: [String: Int] = [:]
    omittedCounts["actionSequence"] = max(0, actionEventCount - actionSequenceStored)
    omittedCounts["runtimeInputs"] = max(0, runtimeInputCount - runtimeInputsStored)
    omittedCounts["safetySignals"] = max(0, safetySignalCount - safetySignalsStored)
    omittedCounts["targetElements"] = max(0, targetElementCount - targetElementsStored)
    omittedCounts["focusedElements"] = max(0, focusedElementCount - focusedElementsStored)
    omittedCounts["selectionEvents"] = max(0, selectionEventCount - selectionEventsStored)
    omittedCounts["debugErrors"] = max(0, debugErrorCount - debugErrorsStored)
    omittedCounts["redactionEvents"] = max(0, redactionEventCount - redactionEventsStored)
    omittedCounts["screenshotPaths"] = max(0, screenshotPathCount - screenshotPathsStored)

    let hasTruncatedSummary = omittedCounts.values.contains { $0 > 0 }
    return [
        "hasTruncatedSummary": hasTruncatedSummary,
        "limits": [
            "actionSequence": eventStreamSummaryActionSequenceLimit,
            "runtimeInputs": eventStreamSummaryRuntimeInputsLimit,
            "safetySignals": eventStreamSummarySafetySignalsLimit,
            "targetElements": eventStreamSummaryElementListLimit,
            "focusedElements": eventStreamSummaryElementListLimit,
            "selectionEvents": eventStreamSummaryElementListLimit,
            "debugErrors": eventStreamSummaryDiagnosticsLimit,
            "redactionEvents": eventStreamSummaryDiagnosticsLimit,
            "screenshotPaths": eventStreamSummaryScreenshotPathsLimit,
        ],
        "storedCounts": [
            "actionSequence": actionSequenceStored,
            "runtimeInputs": runtimeInputsStored,
            "safetySignals": safetySignalsStored,
            "targetElements": targetElementsStored,
            "focusedElements": focusedElementsStored,
            "selectionEvents": selectionEventsStored,
            "debugErrors": debugErrorsStored,
            "redactionEvents": redactionEventsStored,
            "screenshotPaths": screenshotPathsStored,
        ],
        "sourceCounts": [
            "actionSequence": actionEventCount,
            "runtimeInputs": runtimeInputCount,
            "safetySignals": safetySignalCount,
            "targetElements": targetElementCount,
            "focusedElements": focusedElementCount,
            "selectionEvents": selectionEventCount,
            "debugErrors": debugErrorCount,
            "redactionEvents": redactionEventCount,
            "screenshotPaths": screenshotPathCount,
        ],
        "omittedCounts": omittedCounts,
    ]
}

private func eventStreamSummarySkillEvidence(
    eventTypeCounts: [String: Int],
    hasActionEvents: Bool,
    hasTargetElements: Bool,
    hasFocusedElements: Bool,
    hasSelectionSignals: Bool,
    hasScreenshots: Bool,
    hasDebugErrors: Bool,
    hasBlockingDiagnostics: Bool,
    recordingIncomplete: Bool,
    sessionStartedNotFirst: Bool,
    sessionStartedCountInvalid: Bool,
    sessionEndedNotFinal: Bool,
    sessionEndedCountInvalid: Bool,
    hasRedactionSignals: Bool,
    hasSafetySignals: Bool,
    hasTruncatedSummary: Bool
) -> [String: Any] {
    [
        "hasActionEvents": hasActionEvents,
        "hasInputEvents": eventTypeCounts.keys.contains { $0.hasPrefix("keyboard.") },
        "hasPointerEvents": eventTypeCounts.keys.contains { $0.hasPrefix("mouse.") },
        "hasAXContext": eventTypeCounts["AX.focusedWindowChanged", default: 0] > 0,
        "hasTargetElements": hasTargetElements,
        "hasFocusedElements": hasFocusedElements,
        "hasSelectionSignals": hasSelectionSignals,
        "hasTerminalSignals": eventTypeCounts["terminal.value_changed", default: 0] > 0,
        "hasScreenshots": hasScreenshots,
        "hasDebugErrors": hasDebugErrors,
        "hasBlockingDiagnostics": hasBlockingDiagnostics,
        "recordingIncomplete": recordingIncomplete,
        "sessionStartedNotFirst": sessionStartedNotFirst,
        "sessionStartedCountInvalid": sessionStartedCountInvalid,
        "sessionEndedNotFinal": sessionEndedNotFinal,
        "sessionEndedCountInvalid": sessionEndedCountInvalid,
        "hasRedactionSignals": hasRedactionSignals,
        "hasSafetySignals": hasSafetySignals,
        "hasTruncatedSummary": hasTruncatedSummary,
    ]
}

private func eventStreamSummarySkillReadiness(
    evidence: [String: Any],
    hasWindowContext: Bool,
    recordingWasCancelled: Bool = false,
    recordingIncomplete: Bool = false,
    sessionStartedNotFirst: Bool = false,
    sessionStartedCountInvalid: Bool = false,
    sessionEndedNotFinal: Bool = false,
    sessionEndedCountInvalid: Bool = false
) -> [String: Any] {
    let hasActionEvents = evidence["hasActionEvents"] as? Bool == true
    let hasAXContext = evidence["hasAXContext"] as? Bool == true
    let hasTargetElements = evidence["hasTargetElements"] as? Bool == true
    let hasFocusedElements = evidence["hasFocusedElements"] as? Bool == true
    let hasSelectionSignals = evidence["hasSelectionSignals"] as? Bool == true
    let hasDebugErrors = evidence["hasDebugErrors"] as? Bool == true
    let hasBlockingDiagnostics = evidence["hasBlockingDiagnostics"] as? Bool == true
    let isRecordingIncomplete = recordingIncomplete || evidence["recordingIncomplete"] as? Bool == true
    let hasEventsBeforeSessionStarted = sessionStartedNotFirst || evidence["sessionStartedNotFirst"] as? Bool == true
    let hasInvalidSessionStartedCount = sessionStartedCountInvalid || evidence["sessionStartedCountInvalid"] as? Bool == true
    let hasEventsAfterSessionEnded = sessionEndedNotFinal || evidence["sessionEndedNotFinal"] as? Bool == true
    let hasInvalidSessionEndedCount = sessionEndedCountInvalid || evidence["sessionEndedCountInvalid"] as? Bool == true
    let hasRedactionSignals = evidence["hasRedactionSignals"] as? Bool == true
    let hasSafetySignals = evidence["hasSafetySignals"] as? Bool == true
    let hasTruncatedSummary = evidence["hasTruncatedSummary"] as? Bool == true

    var reasons: [String] = []
    if recordingWasCancelled {
        reasons.append("recording was cancelled; do not create or update a skill from this event stream")
    }
    if isRecordingIncomplete {
        reasons.append("recording is not complete; stop the recording before creating a skill")
    }
    if hasInvalidSessionStartedCount {
        reasons.append("recording must contain exactly one session.started event before creating a skill")
    }
    if hasEventsBeforeSessionStarted {
        reasons.append("recording has events before session.started; start must be the first event before creating a skill")
    }
    if hasEventsAfterSessionEnded {
        reasons.append("recording has events after session.ended; stop or cancel must be the final event before creating a skill")
    }
    if hasInvalidSessionEndedCount {
        reasons.append("recording has multiple session.ended events; stop or cancel must close the event stream exactly once")
    }
    if !hasActionEvents {
        reasons.append("recording has no high-level user action events")
    }
    if !hasWindowContext {
        reasons.append("recording has no stable app/window context")
    }
    if !hasAXContext {
        reasons.append("recording has no AX focused window context")
    }
    if !(hasTargetElements || hasFocusedElements || hasSelectionSignals) {
        reasons.append("recording has no semantic target, focused element, or selection evidence")
    }
    if hasDebugErrors {
        reasons.append("recording includes debug.error diagnostics")
    }
    if hasBlockingDiagnostics {
        reasons.append("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill")
    }
    if hasRedactionSignals {
        reasons.append("recording includes redaction or secureInput signals")
    }
    if hasSafetySignals {
        reasons.append("recording includes actions that may require explicit user confirmation")
    }
    if hasTruncatedSummary {
        reasons.append("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill")
    }

    let status: String
    let recommendedNextStep: String
    if recordingWasCancelled {
        status = "insufficient"
        recommendedNextStep = "Acknowledge the cancellation and ask the user to re-record when they want to create a skill."
    } else if isRecordingIncomplete {
        status = "insufficient"
        recommendedNextStep = "Stop the recording, then inspect the completed events before creating a skill."
    } else if hasInvalidSessionStartedCount {
        status = "insufficient"
        recommendedNextStep = "Discard this malformed recording and re-record so exactly one start event opens the event stream."
    } else if hasEventsBeforeSessionStarted {
        status = "insufficient"
        recommendedNextStep = "Discard this malformed recording and re-record so session.started is the first event."
    } else if hasEventsAfterSessionEnded {
        status = "insufficient"
        recommendedNextStep = "Discard this malformed recording and re-record so the stop or cancel event closes the event stream."
    } else if hasInvalidSessionEndedCount {
        status = "insufficient"
        recommendedNextStep = "Discard this malformed recording and re-record so the stop or cancel event closes the event stream exactly once."
    } else if hasBlockingDiagnostics {
        status = "insufficient"
        recommendedNextStep = "Fix the recording permissions or input monitoring issue, then ask the user to re-record the workflow."
    } else if !hasActionEvents {
        status = "insufficient"
        recommendedNextStep = "Ask the user to re-record after confirming permissions and demonstrating at least one workflow action."
    } else if reasons.isEmpty {
        status = "ready"
        recommendedNextStep = "Create or refine a reusable skill from the recording, then validate the final skill package."
    } else {
        status = "needsReview"
        recommendedNextStep = "Inspect events.jsonl, replace user-specific values with inputs, and refine the generated skill before packaging."
    }

    return [
        "status": status,
        "canCreateSkillDraft": hasActionEvents && !recordingWasCancelled && !isRecordingIncomplete && !hasInvalidSessionStartedCount && !hasEventsBeforeSessionStarted && !hasEventsAfterSessionEnded && !hasInvalidSessionEndedCount && !hasBlockingDiagnostics,
        "requiresHumanReview": status != "ready",
        "reasons": reasons,
        "recommendedNextStep": recommendedNextStep,
    ]
}

private func firstNestedDictionary(_ dictionary: [String: Any]?, keys: [String]) -> [String: Any]? {
    guard let dictionary else {
        return nil
    }
    for key in keys {
        if let value = dictionary[key] as? [String: Any] {
            return value
        }
    }
    return nil
}

private func firstString(_ dictionary: [String: Any]?, keys: [String]) -> String? {
    guard let dictionary else {
        return nil
    }
    for key in keys {
        if let value = dictionary[key] as? String, !value.isEmpty {
            return value
        }
    }
    return nil
}

private func eventStreamSummaryEventKind(_ event: [String: Any]) -> String? {
    (event["kind"] as? String) ?? (event["type"] as? String)
}

private extension Dictionary where Key == String, Value == Int {
    func sortedDictionary() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: sorted { $0.key < $1.key })
    }
}
