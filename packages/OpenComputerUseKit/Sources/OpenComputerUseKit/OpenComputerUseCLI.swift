import Foundation

public enum OpenComputerUseCLICommand: Equatable {
    case launchOnboarding
    case mcp
    case doctor
    case listApps
    case snapshot(app: String, textLimit: SnapshotTextLimit = .defaults, treeLimits: AccessibilityTreeLimits = .defaults)
    case call(OpenComputerUseCallInvocation)
    case turnEnded(payload: String?)
    case help(command: String?)
    case version
}

public enum OpenComputerUseCallInvocation: Equatable {
    case single(toolName: String, argumentsJSON: String?, argumentsFile: String?)
    case sequence(callsJSON: String?, callsFile: String?, interCallDelay: TimeInterval)
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
    case .mcp, .doctor, .listApps, .snapshot, .call:
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
          open-computer-use snapshot [--text-limit <positive-int|max>] [--max-tree-nodes <positive-int>] [--max-tree-depth <positive-int>] <app>

        Arguments:
          <app>                App name or bundle identifier to inspect.

        Options:
          --text-limit         Override the default 500 character text limit. Use `max` for full text.
          --max-tree-nodes     Override the default 1200 node accessibility tree budget.
          --max-tree-depth     Override the default 64 level accessibility tree depth.

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
    var textLimit = SnapshotTextLimit.defaults
    var maxTreeNodes: Int?
    var maxTreeDepth: Int?

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--text-limit":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--text-limit requires a positive integer or max value", helpCommand: "snapshot")
            }
            textLimit = try parseTextLimitOption(arguments[index], option: "--text-limit")
        case "--max-tree-nodes":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--max-tree-nodes requires a positive integer value", helpCommand: "snapshot")
            }
            maxTreeNodes = try parsePositiveIntegerOption(arguments[index], option: "--max-tree-nodes")
        case "--max-tree-depth":
            index += 1
            guard index < arguments.count else {
                throw OpenComputerUseCLIError(message: "--max-tree-depth requires a positive integer value", helpCommand: "snapshot")
            }
            maxTreeDepth = try parsePositiveIntegerOption(arguments[index], option: "--max-tree-depth")
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
        index += 1
    }

    guard let app else {
        throw OpenComputerUseCLIError(message: "snapshot requires an app name or bundle identifier", helpCommand: "snapshot")
    }

    return .snapshot(
        app: app,
        textLimit: textLimit,
        treeLimits: AccessibilityTreeLimits.defaults.replacing(
            maxNodeCount: maxTreeNodes,
            maxDepth: maxTreeDepth
        )
    )
}

private func parseTextLimitOption(_ value: String, option: String) throws -> SnapshotTextLimit {
    if value.lowercased() == SnapshotTextLimit.maxKeyword {
        return .max
    }

    guard let integer = Int(value), integer > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive integer or max", helpCommand: "snapshot")
    }
    return SnapshotTextLimit(maxCount: integer)
}

private func parsePositiveIntegerOption(_ value: String, option: String) throws -> Int {
    guard let integer = Int(value), integer > 0 else {
        throw OpenComputerUseCLIError(message: "\(option) must be a positive integer", helpCommand: "snapshot")
    }
    return integer
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
    index: inout Int
) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw OpenComputerUseCLIError(message: "\(option) requires a value", helpCommand: "call")
    }

    index = valueIndex
    return arguments[valueIndex]
}

private func parseTimeIntervalOptionValue(
    _ option: String,
    arguments: [String],
    index: inout Int
) throws -> TimeInterval {
    let rawValue = try parseOptionValue(option, arguments: arguments, index: &index)
    guard let value = Double(rawValue), value.isFinite, value >= 0 else {
        throw OpenComputerUseCLIError(
            message: "\(option) requires a non-negative number of seconds",
            helpCommand: "call"
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
