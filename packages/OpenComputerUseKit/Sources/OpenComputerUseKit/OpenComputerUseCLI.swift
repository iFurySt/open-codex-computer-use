import Foundation

public enum OpenComputerUseCLICommand: Equatable {
    case launchOnboarding
    case mcp
    case eventStream(EventStreamCLIInvocation)
    case doctor
    case listApps
    case snapshot(app: String, showFullText: Bool = false)
    case call(OpenComputerUseCallInvocation)
    case turnEnded(payload: String?)
    case help(command: String?)
    case version
}

public enum OpenComputerUseCallInvocation: Equatable {
    case single(toolName: String, argumentsJSON: String?, argumentsFile: String?)
    case sequence(callsJSON: String?, callsFile: String?, interCallDelay: TimeInterval)
}

public enum EventStreamCLIInvocation: Equatable {
    case mcp
    case start(json: Bool)
    case status(json: Bool)
    case stop(json: Bool)
    case cancel(json: Bool)
    case wait(json: Bool, sessionID: String?, timeout: TimeInterval?, notifyCommand: [String]?)
    case summarize(inputPath: String, includeText: Bool, requireAction: Bool)
    case validate(inputPath: String, strictOCU: Bool, requiredEventTypes: [String], requireSkillDraft: Bool)
    case scaffoldSkill(inputPath: String, skillName: String, description: String?, outputDirectory: String, overwrite: Bool, includeText: Bool)
}

public let openComputerUseDefaultInterCallDelay: TimeInterval = 1

public func shouldUseMacOSAppAgentProxy(
    command: OpenComputerUseCLICommand,
    proxyDisabled: Bool,
    appBundleAvailable: Bool,
    runningFromLaunchServicesAppInstance: Bool
) -> Bool {
    guard !proxyDisabled, appBundleAvailable else {
        return false
    }

    switch command {
    case .launchOnboarding:
        return !runningFromLaunchServicesAppInstance
    case .eventStream(.summarize), .eventStream(.validate), .eventStream(.scaffoldSkill):
        return false
    case .mcp, .eventStream, .doctor, .listApps, .snapshot, .call:
        return true
    case .turnEnded, .help, .version:
        return false
    }
}

public struct OpenComputerUseCLIError: LocalizedError, Equatable {
    public let message: String
    public let helpCommand: String?

    public init(message: String, helpCommand: String? = nil) {
        self.message = message
        self.helpCommand = helpCommand
    }

    public var errorDescription: String? {
        var lines = [message]
        lines.append("")
        lines.append(openComputerUseHelpText(command: helpCommand))
        return lines.joined(separator: "\n")
    }
}

public func parseOpenComputerUseCLI(arguments: [String]) throws -> OpenComputerUseCLICommand {
    guard let first = arguments.first else {
        return .launchOnboarding
    }

    switch first {
    case "-h", "--help", "help":
        if arguments.count > 2 {
            throw OpenComputerUseCLIError(message: "help accepts at most one command", helpCommand: nil)
        }

        return .help(command: arguments.dropFirst().first)
    case "-v", "--version", "version":
        guard arguments.count == 1 else {
            throw OpenComputerUseCLIError(message: "version does not accept any arguments", helpCommand: nil)
        }

        return .version
    case "mcp":
        return try parseSimpleCommand(name: "mcp", arguments: Array(arguments.dropFirst()), result: .mcp)
    case "event-stream":
        return try parseEventStream(arguments: Array(arguments.dropFirst()))
    case "doctor":
        return try parseSimpleCommand(name: "doctor", arguments: Array(arguments.dropFirst()), result: .doctor)
    case "list-apps":
        return try parseSimpleCommand(name: "list-apps", arguments: Array(arguments.dropFirst()), result: .listApps)
    case "call":
        return try parseCall(arguments: Array(arguments.dropFirst()))
    case "turn-ended":
        return try parseTurnEnded(arguments: Array(arguments.dropFirst()))
    case "snapshot":
        return try parseSnapshot(arguments: Array(arguments.dropFirst()))
    default:
        if first.hasPrefix("-") {
            throw OpenComputerUseCLIError(message: "Unknown option: \(first)", helpCommand: nil)
        }

        throw OpenComputerUseCLIError(message: "Unknown command: \(first)", helpCommand: nil)
    }
}

public func openComputerUseHelpText(command: String? = nil) -> String {
    switch command {
    case nil:
        return """
        Open Computer Use

        Usage:
          open-computer-use [command] [options]
          open-computer-use

        Commands:
          mcp                  Start the stdio MCP server.
          event-stream         Record macOS actions into a Record & Replay event stream.
          doctor               Print permission status and launch onboarding if needed.
          list-apps            Print running or recently used apps.
          snapshot <app>       Print the current accessibility snapshot for an app.
          call <tool>           Call one tool, or run a JSON array of tool calls.
          turn-ended           Notify the running MCP process that the host turn ended.
          help [command]       Show general or command-specific help.
          version              Print the CLI version.

        Global options:
          -h, --help           Show help.
          -v, --version        Show version.

        Notes:
          Running without a command launches the permission onboarding app.
          Use `open-computer-use help <command>` for command-specific help.
        """
    case "mcp":
        return """
        Usage:
          open-computer-use mcp

        Start the stdio MCP server.
        """
    case "event-stream":
        return """
        Usage:
          open-computer-use event-stream mcp
          open-computer-use event-stream start [--json]
          open-computer-use event-stream status [--json]
          open-computer-use event-stream stop [--json]
          open-computer-use event-stream cancel [--json]
          open-computer-use event-stream wait [--json] [--session-id <id>] [--timeout <seconds>] [--notify-command '<json-argv>']
          open-computer-use event-stream summarize [--json] [--include-text] [--require-action] <session-dir-or-metadata-or-events>
          open-computer-use event-stream validate [--json] [--strict-ocu] [--require-event-type <type>] [--require-skill-draft] <session-dir-or-metadata-or-events>
          open-computer-use event-stream scaffold-skill [--json] --skill-name <name> --output-dir <dir> [--description <text>] [--overwrite] [--include-text] <session-dir-or-metadata-or-events>

        Start the Record & Replay-compatible event stream MCP server, or control
        a recording through the long-lived Open Computer Use app agent.
        """
    case "doctor":
        return """
        Usage:
          open-computer-use doctor

        Print the current Accessibility and Screen Recording permission state.
        If permissions are missing, this also launches the onboarding app.
        """
    case "list-apps":
        return """
        Usage:
          open-computer-use list-apps

        Print running apps plus recently used apps that can be targeted by Computer Use.
        """
    case "snapshot":
        return """
        Usage:
          open-computer-use snapshot [--show-full-text] <app>

        Arguments:
          <app>                App name or bundle identifier to inspect.

        Options:
          --show-full-text     Do not truncate accessibility text to 500 characters.

        Print the current accessibility snapshot for the target app.
        """
    case "call":
        return """
        Usage:
          open-computer-use call <tool> [--args '<json-object>']
          open-computer-use call <tool> [--args-file <path>]
          open-computer-use call --calls '<json-array>' [--sleep <seconds>]
          open-computer-use call --calls-file <path> [--sleep <seconds>]

        Examples:
          open-computer-use call list_apps
          open-computer-use call get_app_state --args '{"app":"TextEdit"}'
          open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
          open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

        The JSON array form keeps all calls in one process so follow-up actions
        can reuse the app state and element indices captured by get_app_state.
        Sequence execution stops after the first tool result with isError=true.
        Sequence runs sleep \(formatOpenComputerUseDelay(openComputerUseDefaultInterCallDelay)) between successful operations by default.
        """
    case "turn-ended":
        return """
        Usage:
          open-computer-use turn-ended [--previous-notify <argv>] [payload]

        Notify a running local MCP process that the current host turn has ended.
        Codex legacy notify appends the after-agent JSON payload as the last argument.
        """
    case "version":
        return """
        Usage:
          open-computer-use version
          open-computer-use --version
          open-computer-use -v

        Print the CLI version.
        """
    case "help":
        return """
        Usage:
          open-computer-use help [command]

        Show general help or help for a specific command.
        """
    default:
        return """
        Unknown help topic: \(command ?? "")

        \(openComputerUseHelpText())
        """
    }
}

public func runOpenComputerUseEventStream(
    _ invocation: EventStreamCLIInvocation,
    service: EventStreamService = .shared
) throws -> OpenComputerUseCallOutput {
    let status: EventStreamRecordingStatus
    var extraFields: [String: Any] = [:]
    switch invocation {
    case .mcp:
        throw OpenComputerUseCLIError(message: "event-stream mcp is a server command", helpCommand: "event-stream")
    case .start:
        status = try service.start()
    case .status:
        status = service.status()
    case .stop:
        status = try service.stop()
    case .cancel:
        status = try service.cancel()
    case let .wait(_, sessionID, timeout, notifyCommand):
        let result = service.waitResult(sessionID: sessionID, timeout: timeout)
        status = result.status
        extraFields["waitTimedOut"] = result.timedOut
        extraFields["waitSessionMatched"] = result.sessionMatched
        if let notifyCommand {
            let statusDictionary = status.asDictionary.merging(extraFields) { _, new in new }
            let notification = runEventStreamWaitNotification(
                command: notifyCommand,
                statusDictionary: statusDictionary,
                skipped: result.timedOut
            )
            extraFields["notification"] = notification
            return OpenComputerUseCallOutput(
                jsonObject: status.asDictionary.merging(extraFields) { _, new in new },
                hasToolError: (notification["ok"] as? Bool) == false
            )
        }
    case let .summarize(inputPath, includeText, requireAction):
        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: inputPath,
            includeText: includeText,
            requireAction: requireAction
        ))
        return OpenComputerUseCallOutput(
            jsonObject: summary,
            hasToolError: (summary["ok"] as? Bool) == false
        )
    case let .validate(inputPath, strictOCU, requiredEventTypes, requireSkillDraft):
        let validation = validateEventStreamRecording(options: EventStreamRecordingValidationOptions(
            inputPath: inputPath,
            strictOCU: strictOCU,
            requiredEventTypes: requiredEventTypes,
            requireSkillDraft: requireSkillDraft
        ))
        return OpenComputerUseCallOutput(
            jsonObject: validation,
            hasToolError: (validation["ok"] as? Bool) == false
        )
    case let .scaffoldSkill(inputPath, skillName, description, outputDirectory, overwrite, includeText):
        let result = try scaffoldEventStreamSkill(options: EventStreamSkillScaffoldOptions(
            inputPath: inputPath,
            skillName: skillName,
            description: description,
            outputDirectory: outputDirectory,
            overwrite: overwrite,
            includeText: includeText
        ))
        return OpenComputerUseCallOutput(
            jsonObject: result,
            hasToolError: (result["ok"] as? Bool) == false
        )
    }

    var dictionary = status.asDictionary
    for (key, value) in extraFields {
        dictionary[key] = value
    }
    return OpenComputerUseCallOutput(jsonObject: dictionary, hasToolError: false)
}

private func runEventStreamWaitNotification(
    command: [String],
    statusDictionary: [String: Any],
    skipped: Bool
) -> [String: Any] {
    var notification: [String: Any] = [
        "attempted": false,
        "skipped": skipped,
        "ok": true,
        "command": command,
    ]

    if skipped {
        notification["reason"] = "waitTimedOut"
        return notification
    }

    guard let executable = command.first, !executable.isEmpty else {
        notification["ok"] = false
        notification["reason"] = "emptyCommand"
        return notification
    }

    let statusData: Data
    do {
        statusData = try JSONSerialization.data(
            withJSONObject: statusDictionary,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    } catch {
        notification["ok"] = false
        notification["reason"] = "statusSerializationFailed"
        notification["error"] = String(describing: error)
        return notification
    }
    let statusText = String(data: statusData, encoding: .utf8) ?? "{}"
    let timeoutSeconds = eventStreamWaitNotificationTimeoutSeconds()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(command.dropFirst())
    var environment = ProcessInfo.processInfo.environment
    environment["OPEN_COMPUTER_USE_EVENT_STREAM_STATUS_JSON"] = statusText
    if let sessionID = statusDictionary["sessionId"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID"] = sessionID
    }
    if let state = statusDictionary["state"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_STATE"] = state
    }
    if let endReason = statusDictionary["endReason"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON"] = endReason
    }
    if let metadataPath = statusDictionary["metadataPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH"] = metadataPath
    } else if let metadataPath = statusDictionary["currentSegmentMetadataPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH"] = metadataPath
    }
    if let sessionPath = statusDictionary["sessionPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH"] = sessionPath
    }
    if let eventsPath = statusDictionary["eventsPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH"] = eventsPath
    } else if let eventsPath = statusDictionary["currentSegmentEventsPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH"] = eventsPath
    }
    if let suppressedEventsPath = statusDictionary["suppressedEventsPath"] as? String {
        environment["OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH"] = suppressedEventsPath
    }
    process.environment = environment

    let inputPipe = Pipe()
    process.standardInput = inputPipe
    let stdoutNull = FileHandle(forWritingAtPath: "/dev/null")
    let stderrNull = FileHandle(forWritingAtPath: "/dev/null")
    process.standardOutput = stdoutNull ?? Pipe()
    process.standardError = stderrNull ?? Pipe()

    notification["attempted"] = true
    notification["skipped"] = false
    notification["timeoutSeconds"] = timeoutSeconds

    var didLaunch = false
    do {
        try process.run()
        didLaunch = true
        var inputData = statusData
        inputData.append(Data("\n".utf8))
        try inputPipe.fileHandleForWriting.write(contentsOf: inputData)
        try inputPipe.fileHandleForWriting.close()
    } catch {
        if process.isRunning {
            process.terminate()
        }
        try? stdoutNull?.close()
        try? stderrNull?.close()
        notification["ok"] = false
        notification["reason"] = didLaunch ? "stdinWriteFailed" : "launchFailed"
        notification["error"] = String(describing: error)
        return notification
    }

    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        process.waitUntilExit()
        semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        if process.isRunning {
            process.terminate()
        }
        notification["ok"] = false
        notification["timedOut"] = true
        notification["reason"] = "timeout"
    } else {
        let exitCode = Int(process.terminationStatus)
        notification["exitCode"] = exitCode
        notification["timedOut"] = false
        notification["ok"] = exitCode == 0
        if exitCode != 0 {
            notification["reason"] = "nonZeroExit"
        }
    }

    try? stdoutNull?.close()
    try? stderrNull?.close()
    return notification
}

private func eventStreamWaitNotificationTimeoutSeconds() -> TimeInterval {
    let fallback: TimeInterval = 10
    guard
        let value = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS"],
        let seconds = TimeInterval(value),
        seconds > 0
    else {
        return fallback
    }
    return seconds
}

private func parseSimpleCommand(
    name: String,
    arguments: [String],
    result: OpenComputerUseCLICommand
) throws -> OpenComputerUseCLICommand {
    if arguments.isEmpty {
        return result
    }

    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: name)
    }

    throw OpenComputerUseCLIError(message: "\(name) does not accept any arguments", helpCommand: name)
}

private func parseEventStream(arguments: [String]) throws -> OpenComputerUseCLICommand {
    guard let subcommand = arguments.first else {
        throw OpenComputerUseCLIError(message: "event-stream requires a subcommand", helpCommand: "event-stream")
    }

    if subcommand == "-h" || subcommand == "--help" {
        return .help(command: "event-stream")
    }

    let rest = Array(arguments.dropFirst())
    switch subcommand {
    case "mcp":
        return try parseSimpleCommand(name: "event-stream mcp", arguments: rest, result: .eventStream(.mcp))
    case "start":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(.start(json: try parseEventStreamJSONOnlyOptions(subcommand: "start", arguments: rest)))
    case "status":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(.status(json: try parseEventStreamJSONOnlyOptions(subcommand: "status", arguments: rest)))
    case "stop":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(.stop(json: try parseEventStreamJSONOnlyOptions(subcommand: "stop", arguments: rest)))
    case "cancel":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(.cancel(json: try parseEventStreamJSONOnlyOptions(subcommand: "cancel", arguments: rest)))
    case "wait":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(try parseEventStreamWait(arguments: rest))
    case "summarize":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(try parseEventStreamSummarize(arguments: rest))
    case "validate":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(try parseEventStreamValidate(arguments: rest))
    case "scaffold-skill":
        if isHelpOnly(rest) {
            return .help(command: "event-stream")
        }
        return .eventStream(try parseEventStreamScaffoldSkill(arguments: rest))
    default:
        if subcommand.hasPrefix("-") {
            throw OpenComputerUseCLIError(message: "Unknown event-stream option: \(subcommand)", helpCommand: "event-stream")
        }

        throw OpenComputerUseCLIError(message: "Unknown event-stream subcommand: \(subcommand)", helpCommand: "event-stream")
    }
}

private func parseEventStreamValidate(arguments: [String]) throws -> EventStreamCLIInvocation {
    var inputPath: String?
    var strictOCU = false
    var requiredEventTypes: [String] = []
    var requireSkillDraft = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--json":
            break
        case "--strict-ocu":
            strictOCU = true
        case "--require-skill-draft":
            requireSkillDraft = true
        case "--require-event-type":
            requiredEventTypes.append(try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream"))
        case "--metadata-path", "--session-path", "--events-path":
            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream validate accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "event-stream validate help must be requested as `open-computer-use event-stream --help`", helpCommand: "event-stream")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown event-stream validate option: \(argument)", helpCommand: "event-stream")
            }

            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream validate accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = argument
        }

        index += 1
    }

    guard let inputPath else {
        throw OpenComputerUseCLIError(message: "event-stream validate requires a session directory, metadata.json, session.json, or events.jsonl", helpCommand: "event-stream")
    }

    return .validate(
        inputPath: inputPath,
        strictOCU: strictOCU,
        requiredEventTypes: requiredEventTypes,
        requireSkillDraft: requireSkillDraft
    )
}

private func parseEventStreamSummarize(arguments: [String]) throws -> EventStreamCLIInvocation {
    var inputPath: String?
    var includeText = false
    var requireAction = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--json":
            break
        case "--include-text":
            includeText = true
        case "--require-action":
            requireAction = true
        case "--metadata-path", "--session-path", "--events-path":
            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream summarize accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "event-stream summarize help must be requested as `open-computer-use event-stream --help`", helpCommand: "event-stream")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown event-stream summarize option: \(argument)", helpCommand: "event-stream")
            }

            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream summarize accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = argument
        }

        index += 1
    }

    guard let inputPath else {
        throw OpenComputerUseCLIError(message: "event-stream summarize requires a session directory, metadata.json, session.json, or events.jsonl", helpCommand: "event-stream")
    }

    return .summarize(inputPath: inputPath, includeText: includeText, requireAction: requireAction)
}

private func parseEventStreamScaffoldSkill(arguments: [String]) throws -> EventStreamCLIInvocation {
    var inputPath: String?
    var skillName: String?
    var description: String?
    var outputDirectory: String?
    var overwrite = false
    var includeText = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--json":
            break
        case "--skill-name":
            skillName = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "--description":
            description = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "--output-dir":
            outputDirectory = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "--overwrite":
            overwrite = true
        case "--include-text":
            includeText = true
        case "--metadata-path", "--session-path", "--events-path":
            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream scaffold-skill accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = try parseOptionValue(argument, arguments: arguments, index: &index, helpCommand: "event-stream")
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "event-stream scaffold-skill help must be requested as `open-computer-use event-stream --help`", helpCommand: "event-stream")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown event-stream scaffold-skill option: \(argument)", helpCommand: "event-stream")
            }

            guard inputPath == nil else {
                throw OpenComputerUseCLIError(message: "event-stream scaffold-skill accepts exactly one input path", helpCommand: "event-stream")
            }
            inputPath = argument
        }

        index += 1
    }

    guard let inputPath else {
        throw OpenComputerUseCLIError(message: "event-stream scaffold-skill requires a session directory, metadata.json, session.json, or events.jsonl", helpCommand: "event-stream")
    }
    guard let skillName, !skillName.isEmpty else {
        throw OpenComputerUseCLIError(message: "event-stream scaffold-skill requires --skill-name", helpCommand: "event-stream")
    }
    guard let outputDirectory, !outputDirectory.isEmpty else {
        throw OpenComputerUseCLIError(message: "event-stream scaffold-skill requires --output-dir", helpCommand: "event-stream")
    }

    return .scaffoldSkill(
        inputPath: inputPath,
        skillName: skillName,
        description: description,
        outputDirectory: outputDirectory,
        overwrite: overwrite,
        includeText: includeText
    )
}

private func parseEventStreamJSONOnlyOptions(subcommand: String, arguments: [String]) throws -> Bool {
    if arguments.isEmpty {
        return false
    }

    if arguments.count == 1, arguments[0] == "--json" {
        return true
    }

    let invalid = arguments.first ?? ""
    throw OpenComputerUseCLIError(
        message: "Unknown event-stream \(subcommand) option: \(invalid)",
        helpCommand: "event-stream"
    )
}

private func isHelpOnly(_ arguments: [String]) -> Bool {
    arguments.count == 1 && (arguments[0] == "-h" || arguments[0] == "--help")
}

private func parseEventStreamWait(arguments: [String]) throws -> EventStreamCLIInvocation {
    var json = false
    var sessionID: String?
    var timeout: TimeInterval?
    var notifyCommand: [String]?

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--json":
            json = true
        case "--session-id":
            sessionID = try parseOptionValue("--session-id", arguments: arguments, index: &index, helpCommand: "event-stream")
        case "--timeout":
            timeout = try parseTimeIntervalOptionValue("--timeout", arguments: arguments, index: &index, helpCommand: "event-stream")
        case "--notify-command":
            let value = try parseOptionValue("--notify-command", arguments: arguments, index: &index, helpCommand: "event-stream")
            notifyCommand = try parseEventStreamNotifyCommand(value)
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "event-stream wait help must be requested as `open-computer-use event-stream --help`", helpCommand: "event-stream")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown event-stream wait option: \(argument)", helpCommand: "event-stream")
            }

            throw OpenComputerUseCLIError(message: "event-stream wait does not accept positional arguments", helpCommand: "event-stream")
        }

        index += 1
    }

    return .wait(json: json, sessionID: sessionID, timeout: timeout, notifyCommand: notifyCommand)
}

private func parseEventStreamNotifyCommand(_ value: String) throws -> [String] {
    guard let data = value.data(using: .utf8) else {
        throw OpenComputerUseCLIError(message: "--notify-command must be a JSON array of strings", helpCommand: "event-stream")
    }
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw OpenComputerUseCLIError(message: "--notify-command must be a JSON array of strings", helpCommand: "event-stream")
    }
    guard let array = object as? [Any], !array.isEmpty else {
        throw OpenComputerUseCLIError(message: "--notify-command must be a non-empty JSON array of strings", helpCommand: "event-stream")
    }
    let strings = array.compactMap { $0 as? String }
    guard strings.count == array.count, strings.allSatisfy({ !$0.isEmpty }) else {
        throw OpenComputerUseCLIError(message: "--notify-command must be a non-empty JSON array of non-empty strings", helpCommand: "event-stream")
    }
    return strings
}

private func parseTurnEnded(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "turn-ended")
    }

    var payload: String?
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--previous-notify":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw OpenComputerUseCLIError(message: "--previous-notify requires a value", helpCommand: "turn-ended")
            }
            index = valueIndex
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "turn-ended help must be requested as `open-computer-use turn-ended --help`", helpCommand: "turn-ended")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown turn-ended option: \(argument)", helpCommand: "turn-ended")
            }

            guard payload == nil else {
                throw OpenComputerUseCLIError(message: "turn-ended accepts at most one payload argument", helpCommand: "turn-ended")
            }

            payload = argument
        }

        index += 1
    }

    return .turnEnded(payload: payload)
}

private func parseSnapshot(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.isEmpty {
        throw OpenComputerUseCLIError(message: "snapshot requires an app name or bundle identifier", helpCommand: "snapshot")
    }

    if arguments.count == 1, let value = arguments.first, value == "-h" || value == "--help" {
        return .help(command: "snapshot")
    }

    var app: String?
    var showFullText = false

    for argument in arguments {
        switch argument {
        case "--show-full-text":
            showFullText = true
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "snapshot help must be requested as `open-computer-use snapshot --help`", helpCommand: "snapshot")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown snapshot option: \(argument)", helpCommand: "snapshot")
            }

            guard app == nil else {
                throw OpenComputerUseCLIError(message: "snapshot accepts exactly one <app> argument", helpCommand: "snapshot")
            }

            app = argument
        }
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "snapshot requires an app name or bundle identifier", helpCommand: "snapshot")
    }

    return .snapshot(app: app, showFullText: showFullText)
}

private func parseCall(arguments: [String]) throws -> OpenComputerUseCLICommand {
    if arguments.count == 1, let option = arguments.first, option == "-h" || option == "--help" {
        return .help(command: "call")
    }

    var toolName: String?
    var argumentsJSON: String?
    var argumentsFile: String?
    var callsJSON: String?
    var callsFile: String?
    var interCallDelay = openComputerUseDefaultInterCallDelay

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--args":
            argumentsJSON = try parseOptionValue("--args", arguments: arguments, index: &index)
        case "--args-file":
            argumentsFile = try parseOptionValue("--args-file", arguments: arguments, index: &index)
        case "--calls":
            callsJSON = try parseOptionValue("--calls", arguments: arguments, index: &index)
        case "--calls-file":
            callsFile = try parseOptionValue("--calls-file", arguments: arguments, index: &index)
        case "--sleep":
            interCallDelay = try parseTimeIntervalOptionValue("--sleep", arguments: arguments, index: &index)
        case "-h", "--help":
            throw OpenComputerUseCLIError(message: "call help must be requested as `open-computer-use call --help`", helpCommand: "call")
        default:
            if argument.hasPrefix("-") {
                throw OpenComputerUseCLIError(message: "Unknown call option: \(argument)", helpCommand: "call")
            }

            guard toolName == nil else {
                throw OpenComputerUseCLIError(message: "call accepts at most one tool name", helpCommand: "call")
            }

            toolName = argument
        }

        index += 1
    }

    let hasSequenceInput = callsJSON != nil || callsFile != nil
    if hasSequenceInput {
        if callsJSON != nil, callsFile != nil {
            throw OpenComputerUseCLIError(message: "Use either --calls or --calls-file, not both", helpCommand: "call")
        }

        if toolName != nil || argumentsJSON != nil || argumentsFile != nil {
            throw OpenComputerUseCLIError(
                message: "call sequence does not accept a tool name, --args, or --args-file",
                helpCommand: "call"
            )
        }

        return .call(.sequence(
            callsJSON: callsJSON,
            callsFile: callsFile,
            interCallDelay: interCallDelay
        ))
    }

    if argumentsJSON != nil, argumentsFile != nil {
        throw OpenComputerUseCLIError(message: "Use either --args or --args-file, not both", helpCommand: "call")
    }

    if interCallDelay != openComputerUseDefaultInterCallDelay {
        throw OpenComputerUseCLIError(
            message: "--sleep is only supported with --calls or --calls-file",
            helpCommand: "call"
        )
    }

    guard let toolName else {
        throw OpenComputerUseCLIError(message: "call requires a tool name or --calls/--calls-file", helpCommand: "call")
    }

    return .call(.single(toolName: toolName, argumentsJSON: argumentsJSON, argumentsFile: argumentsFile))
}

private func parseOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String = "call"
) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw OpenComputerUseCLIError(message: "\(option) requires a value", helpCommand: helpCommand)
    }

    index = valueIndex
    return arguments[valueIndex]
}

private func parseTimeIntervalOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int,
    helpCommand: String = "call"
) throws -> TimeInterval {
    let rawValue = try parseOptionValue(option, arguments: arguments, index: &index, helpCommand: helpCommand)
    guard let value = Double(rawValue), value.isFinite, value >= 0 else {
        throw OpenComputerUseCLIError(
            message: "\(option) requires a non-negative number of seconds",
            helpCommand: helpCommand
        )
    }

    return value
}

private func formatOpenComputerUseDelay(_ delay: TimeInterval) -> String {
    if delay.rounded() == delay {
        return "\(Int(delay))s"
    }

    return "\(delay)s"
}
