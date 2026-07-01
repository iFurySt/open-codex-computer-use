import Foundation

public struct EventStreamSkillScaffoldOptions: Equatable, Sendable {
    public let inputPath: String
    public let skillName: String
    public let description: String?
    public let outputDirectory: String
    public let overwrite: Bool
    public let includeText: Bool

    public init(
        inputPath: String,
        skillName: String,
        description: String? = nil,
        outputDirectory: String,
        overwrite: Bool = false,
        includeText: Bool = false
    ) {
        self.inputPath = inputPath
        self.skillName = skillName
        self.description = description
        self.outputDirectory = outputDirectory
        self.overwrite = overwrite
        self.includeText = includeText
    }
}

private let eventStreamSkillScaffoldPathKeys: Set<String> = [
    "sessionDir",
    "metadataPath",
    "eventsPath",
]

public func scaffoldEventStreamSkill(options: EventStreamSkillScaffoldOptions) throws -> [String: Any] {
    let skillName = options.skillName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard eventStreamSkillNameIsValid(skillName) else {
        return [
            "ok": false,
            "error": "invalidSkillName",
            "message": "skill name must use lowercase letters, numbers, and hyphens",
        ]
    }

    let validation = validateEventStreamRecording(options: EventStreamRecordingValidationOptions(
        inputPath: options.inputPath,
        strictOCU: false,
        requiredEventTypes: [],
        requireSkillDraft: true
    ))
    guard validation["ok"] as? Bool == true else {
        var result: [String: Any] = [
            "ok": false,
            "error": "recordingValidationFailed",
        ]
        if let errors = validation["errors"] {
            result["errors"] = errors
        }
        if let warnings = validation["warnings"] {
            result["warnings"] = warnings
        }
        if let skillDraftReady = validation["skillDraftReady"] {
            result["skillDraftReady"] = skillDraftReady
        }
        if let skillDraftReasons = validation["skillDraftReasons"] {
            result["skillDraftReasons"] = skillDraftReasons
        }
        return result
    }

    let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
        inputPath: options.inputPath,
        includeText: options.includeText,
        requireAction: true
    ))
    guard summary["ok"] as? Bool == true else {
        var result: [String: Any] = [
            "ok": false,
            "error": "recordingSummaryFailed",
        ]
        if let errors = summary["errors"] {
            result["errors"] = errors
        }
        if let warnings = summary["warnings"] {
            result["warnings"] = warnings
        }
        return result
    }

    let outputURL = URL(fileURLWithPath: options.outputDirectory)
    let referencesURL = outputURL.appendingPathComponent("references")
    let skillURL = outputURL.appendingPathComponent("SKILL.md")
    let summaryURL = referencesURL.appendingPathComponent("recording-summary.json")

    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
        guard options.overwrite else {
            return [
                "ok": false,
                "error": "outputDirectoryExists",
                "message": "output directory already exists",
                "outputDir": outputURL.path,
            ]
        }
        try FileManager.default.removeItem(at: outputURL)
    }

    let sanitizedSummary = eventStreamSkillSanitizedSummary(summary)
    let readiness = sanitizedSummary as? [String: Any]
    let readinessObject = readiness?["skillReadiness"] as? [String: Any]
    if readinessObject?["canCreateSkillDraft"] as? Bool != true {
        return [
            "ok": false,
            "error": "insufficientSkillReadiness",
            "message": readinessObject?["recommendedNextStep"] as? String
                ?? "Recording does not contain enough usable evidence to create a skill draft.",
            "skillReadiness": readinessObject ?? [:],
        ]
    }

    let description = options.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? "Replay a workflow captured by Open Computer Use Record & Replay for \(skillName)."

    try FileManager.default.createDirectory(at: referencesURL, withIntermediateDirectories: true)
    try eventStreamSkillRenderedMarkdown(
        skillName: skillName,
        description: description,
        summary: sanitizedSummary
    ).write(to: skillURL, atomically: true, encoding: .utf8)

    let summaryData = try JSONSerialization.data(
        withJSONObject: sanitizedSummary,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    var summaryText = String(data: summaryData, encoding: .utf8) ?? "{}"
    summaryText.append("\n")
    try summaryText.write(to: summaryURL, atomically: true, encoding: .utf8)

    return [
        "ok": true,
        "skillName": skillName,
        "outputDir": outputURL.path,
        "skillPath": skillURL.path,
        "summaryPath": summaryURL.path,
    ]
}

private func eventStreamSkillNameIsValid(_ name: String) -> Bool {
    guard (3 ... 64).contains(name.count) else {
        return false
    }
    guard let first = name.first, let last = name.last, first.isLetterOrNumberASCII, last.isLetterOrNumberASCII else {
        return false
    }
    return name.allSatisfy { character in
        character.isLowercaseLetterASCII || character.isNumberASCII || character == "-"
    }
}

private func eventStreamSkillSanitizedSummary(_ value: Any) -> Any {
    if let dictionary = value as? [String: Any] {
        var sanitized: [String: Any] = [:]
        for (key, child) in dictionary {
            if eventStreamSkillScaffoldPathKeys.contains(key) {
                sanitized[key] = "<recording-\(key)>"
            } else if key == "screenshotPaths", let paths = child as? [Any] {
                sanitized[key] = paths.map { item in
                    guard let path = item as? String else {
                        return item
                    }
                    return URL(fileURLWithPath: path).lastPathComponent
                }
            } else {
                sanitized[key] = eventStreamSkillSanitizedSummary(child)
            }
        }
        return sanitized
    }
    if let array = value as? [Any] {
        return array.map { eventStreamSkillSanitizedSummary($0) }
    }
    return value
}

private func eventStreamSkillRenderedMarkdown(
    skillName: String,
    description: String,
    summary: Any
) -> String {
    let summary = summary as? [String: Any] ?? [:]
    let windows = summary["windows"] as? [[String: Any]] ?? []
    let windowItems = windows.prefix(10).map { window in
        let app = (window["appName"] as? String) ?? (window["bundleIdentifier"] as? String) ?? "Unknown app"
        if let title = window["windowTitle"] as? String, !title.isEmpty {
            return "\(app) / \(title)"
        }
        return app
    }

    let actions = summary["actionSequence"] as? [[String: Any]] ?? []
    let actionItems = actions.prefix(30).map(eventStreamSkillActionDescription)
    let runtimeInputs = summary["runtimeInputs"] as? [[String: Any]] ?? []
    var inputItems = runtimeInputs.prefix(30).map(eventStreamSkillRuntimeInputDescription)
    if inputItems.isEmpty {
        inputItems = actions.prefix(30).compactMap(eventStreamSkillInputDescription)
    }
    let warnings = (summary["warnings"] as? [Any] ?? []).map { "\($0)" }
    let evidence = summary["skillEvidence"] as? [String: Any] ?? [:]
    let readiness = summary["skillReadiness"] as? [String: Any] ?? [:]
    let readinessReasons = (readiness["reasons"] as? [Any] ?? []).map { "\($0)" }
    let safetySignals = summary["safetySignals"] as? [[String: Any]] ?? []
    let safetyItems = safetySignals.prefix(20).map(eventStreamSkillSafetySignalDescription)
    let summaryLimits = summary["summaryLimits"] as? [String: Any] ?? [:]
    let summaryLimitItems = eventStreamSkillSummaryLimitDescriptions(summaryLimits)

    return """
    ---
    name: \(eventStreamSkillFrontmatterValue(skillName))
    description: \(eventStreamSkillFrontmatterValue(description))
    ---

    # \(eventStreamSkillTitle(from: skillName))

    ## Purpose

    Replay or adapt the workflow captured with Open Computer Use Record & Replay. This is a generated draft: preserve the observed sequence, but replace user-specific values with explicit inputs before using it on real data.

    ## Inputs To Confirm

    - The user's concrete goal for this replay.
    - Required app/account/login state.
    - Any names, paths, message text, dates, or account-specific values that were redacted or should be parameterized.
    - Whether any step sends, deletes, purchases, uploads, approves, or otherwise changes external state.

    ## Runtime Inputs

    \(eventStreamSkillMarkdownList(inputItems, fallback: "No text or selection inputs were inferred. Still ask the user for any values that should vary between replays."))

    ## Workflow Readiness

    - Status: \(readiness["status"] ?? "unknown")
    - Can create skill draft: \(eventStreamSkillBoolString(readiness["canCreateSkillDraft"]))
    - Requires human review: \(eventStreamSkillBoolString(readiness["requiresHumanReview"]))
    - Recommended next step: \(readiness["recommendedNextStep"] ?? "Inspect `events.jsonl` before finalizing this skill.")

    \(eventStreamSkillMarkdownList(readinessReasons, fallback: "No readiness issues were detected by the summary helper."))

    ## Summary Limits

    \(eventStreamSkillMarkdownList(summaryLimitItems, fallback: "No high-volume summary fields were truncated."))

    ## Recorded Context

    \(eventStreamSkillMarkdownList(windowItems, fallback: "No stable app/window context was captured; inspect `references/recording-summary.json`."))

    ## Agent Replay Procedure

    - Before replaying UI actions, check whether a connector, API, or dedicated tool can perform the stable semantic operation more reliably than desktop automation; use Computer Use for visually dependent verification, unsupported UI interactions, or when manipulating the interface is itself the workflow.
    - Start by calling `get_app_state` for the recorded app or the app the user names; verify the expected window or equivalent screen is present.
    - For each observed step, resolve the current target by visible label, role, title, or neighboring text from `references/recording-summary.json`; use `element_index` actions when a semantic element is available.
    - Use coordinate clicks or drags only as a last resort after refreshing the screenshot and confirming the coordinate system still matches the current window.
    - For text entry, collect the runtime value from the user or task context, focus the observed input target, then use `type_text` or `set_value` according to the current app state.
    - Pause and ask for explicit confirmation before sends, deletes, purchases, approvals, uploads, or other externally visible changes.

    ## Replay Steps

    \(eventStreamSkillMarkdownList(actionItems, fallback: "No high-level action sequence was captured; ask the user to re-record after fixing permissions."))

    ## Evidence

    - Event count: \(summary["eventCount"] ?? "unknown")
    - Action event count: \(summary["actionEventCount"] ?? "unknown")
    - End reason: \(summary["endReason"] ?? "unknown")
    - Has AX context: \(eventStreamSkillBoolString(evidence["hasAXContext"]))
    - Has target elements: \(eventStreamSkillBoolString(evidence["hasTargetElements"]))
    - Has redaction signals: \(eventStreamSkillBoolString(evidence["hasRedactionSignals"]))
    - Has safety signals: \(eventStreamSkillBoolString(evidence["hasSafetySignals"]))

    ## Warnings

    \(eventStreamSkillMarkdownList(warnings, fallback: "No summary warnings were reported."))

    ## Safety

    - Do not reconstruct passwords, OTPs, API keys, terminal buffers, or other redacted values.
    - Ask for confirmation before externally visible or destructive actions.
    - Prefer semantic targets, labels, app names, and keyboard shortcuts over raw coordinates.
    - Re-check the current app state before executing each step; recorded UI positions may drift.

    ### Confirmation Signals

    \(eventStreamSkillMarkdownList(safetyItems, fallback: "No specific confirmation-sensitive actions were detected by the summary helper. Still ask before externally visible changes."))

    ## Verification

    - Before packaging this skill, rerun `open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadata-or-session>` on the source recording.
    - Compare the final app state with the user's requested outcome, not just the recorded event sequence.
    - If replay behavior depends on missing AX targets, screenshots, or redacted text, refine this draft against `events.jsonl` before installing it.
    - If `summaryLimits.hasTruncatedSummary` is true, inspect the original `events.jsonl` for omitted steps before finalizing this skill.

    ## Finalizing The Skill

    - Treat this directory as a skill draft, not a standalone runbook or replay plan.
    - Read and follow the `skill-creator` skill before packaging or installing the skill.
    - Complete the `skill-creator` workflow, including validation, before reporting that this skill was created.
    - Keep reusable workflow intent, prerequisites, runtime inputs, safety confirmations, and verification steps in the skill; omit raw event logs and user-specific values.
    - The final deliverable should be an actual discoverable skill directory, not only this generated Markdown draft.

    ## Source

    The generated summary is stored in `references/recording-summary.json`. Treat `events.jsonl` from the original recording as the primary evidence when refining this draft.
    """
}

private func eventStreamSkillRuntimeInputDescription(_ input: [String: Any]) -> String {
    let kind = input["kind"].map { "\($0)" } ?? "value"
    let target = eventStreamSkillTargetDescription(input["target"] as? [String: Any] ?? [:])
    let suffix: String
    if let textLength = input["textLength"] as? Int {
        suffix = " (\(textLength) recorded characters; use a fresh runtime value)."
    } else if let selectedTextLength = input["selectedTextLength"] as? Int {
        suffix = " (\(selectedTextLength) recorded selected characters; confirm current semantics)."
    } else {
        suffix = "."
    }
    let sensitivity = input["sensitive"] as? Bool == true ? " Treat this as sensitive input." : ""

    switch kind {
    case "text":
        return "Runtime text for \(target)\(suffix)\(sensitivity)"
    case "selection":
        return "Runtime selection or selected-content meaning for \(target)\(suffix)"
    default:
        return "Runtime \(kind) for \(target)\(suffix)"
    }
}

private func eventStreamSkillSafetySignalDescription(_ signal: [String: Any]) -> String {
    let sourceEventType = signal["sourceEventType"].map { "\($0)" } ?? "recorded action"
    let reason = signal["reason"].map { "\($0)" } ?? "confirmationRequired"
    let target = eventStreamSkillTargetDescription(signal["target"] as? [String: Any] ?? [:])
    let linePrefix: String
    if let line = signal["line"] as? Int {
        linePrefix = "Line \(line): "
    } else {
        linePrefix = ""
    }
    return "\(linePrefix)`\(sourceEventType)` matched \(reason) on \(target); ask for explicit confirmation before replaying this step."
}

private func eventStreamSkillSummaryLimitDescriptions(_ limits: [String: Any]) -> [String] {
    guard limits["hasTruncatedSummary"] as? Bool == true else {
        return []
    }
    let omittedCounts = limits["omittedCounts"] as? [String: Any] ?? [:]
    return omittedCounts
        .compactMap { key, value -> (String, Int)? in
            if let intValue = value as? Int, intValue > 0 {
                return (key, intValue)
            }
            return nil
        }
        .sorted { $0.0 < $1.0 }
        .map { key, count in
            "\(count) \(key) item(s) were omitted from `references/recording-summary.json`; inspect the original `events.jsonl` before finalizing replay steps."
        }
}

private func eventStreamSkillInputDescription(_ action: [String: Any]) -> String? {
    guard let actionType = action["type"] as? String else {
        return nil
    }
    let target = eventStreamSkillTargetDescription(action["element"] as? [String: Any] ?? [:])

    switch actionType {
    case "keyboard.text_input":
        if let textLength = action["textLength"] as? Int {
            return "Runtime text for \(target) (\(textLength) recorded characters; recorded literal text is omitted by default)."
        }
        return "Runtime text for \(target); recorded literal text is omitted by default."
    case "selection.changed":
        return "Current selection or selected content semantics if the workflow depends on the recorded selection."
    default:
        return nil
    }
}

private func eventStreamSkillActionDescription(_ action: [String: Any]) -> String {
    let actionType = action["type"] as? String
    let prefix: String
    if let line = action["line"] as? Int {
        prefix = "Line \(line): "
    } else {
        prefix = ""
    }

    let window = action["window"] as? [String: Any] ?? [:]
    let target = eventStreamSkillTargetDescription(action["element"] as? [String: Any] ?? [:])
    let app = (window["appName"] as? String) ?? (window["bundleIdentifier"] as? String) ?? "the recorded app"

    switch actionType {
    case "mouse.click":
        return "\(prefix)Click \(target) in \(app)."
    case "mouse.context_menu":
        return "\(prefix)Open the context menu on \(target) in \(app)."
    case "mouse.drag":
        return "\(prefix)Drag from the recorded start location to end location in \(app)."
    case "keyboard.text_input":
        if let textLength = action["textLength"] as? Int {
            return "\(prefix)Enter user-provided text into \(target) (\(textLength) recorded characters)."
        }
        return "\(prefix)Enter user-provided text into \(target)."
    case "keyboard.submit":
        return "\(prefix)Submit the current focused control in \(app)."
    case "keyboard.shortcut":
        let key = action["key"].map { "\($0)" } ?? ""
        let modifiers = action["modifiers"] as? [String] ?? []
        let chord = (modifiers + [key]).filter { !$0.isEmpty }.joined(separator: "+")
        return "\(prefix)Press shortcut `\(chord)` in \(app)."
    case "terminal.value_changed":
        return "\(prefix)Observe terminal output/state change; keep command/output values sanitized."
    case "selection.changed":
        return "\(prefix)Use the recorded selection change as context, but do not rely on stale selected text."
    case "experimentalRawEvents":
        if action["reason"] as? String == "scrollWheel" {
            return "\(prefix)Scroll in \(app) using the recorded wheel direction; re-check the visible state after scrolling."
        }
        return "\(prefix)Replay raw input evidence in \(app) only after inspecting the original `events.jsonl`."
    default:
        return "\(prefix)Replay `\(actionType ?? "unknown")` using the recorded context."
    }
}

private func eventStreamSkillTargetDescription(_ element: [String: Any]) -> String {
    let targetBits = ["role", "title", "label", "description"].compactMap { key -> String? in
        guard let value = element[key] as? String, !value.isEmpty else {
            return nil
        }
        return "\(key)=\(String(reflecting: value))"
    }
    return targetBits.isEmpty ? "the observed target" : targetBits.joined(separator: ", ")
}

private func eventStreamSkillMarkdownList(_ items: [String], fallback: String) -> String {
    let effectiveItems = items.isEmpty ? [fallback] : items
    return effectiveItems.map { "- \($0)" }.joined(separator: "\n")
}

private func eventStreamSkillFrontmatterValue(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func eventStreamSkillTitle(from skillName: String) -> String {
    skillName
        .split(separator: "-")
        .map { part in
            guard let first = part.first else {
                return ""
            }
            return first.uppercased() + part.dropFirst()
        }
        .joined(separator: " ")
}

private func eventStreamSkillBoolString(_ value: Any?) -> String {
    if let bool = value as? Bool {
        return bool ? "true" : "false"
    }
    return "false"
}

private extension Character {
    var isLowercaseLetterASCII: Bool {
        guard let scalar = unicodeScalars.only else {
            return false
        }
        return scalar.value >= 97 && scalar.value <= 122
    }

    var isNumberASCII: Bool {
        guard let scalar = unicodeScalars.only else {
            return false
        }
        return scalar.value >= 48 && scalar.value <= 57
    }

    var isLetterOrNumberASCII: Bool {
        isLowercaseLetterASCII || isNumberASCII
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Character.UnicodeScalarView {
    var only: UnicodeScalar? {
        count == 1 ? first : nil
    }
}
