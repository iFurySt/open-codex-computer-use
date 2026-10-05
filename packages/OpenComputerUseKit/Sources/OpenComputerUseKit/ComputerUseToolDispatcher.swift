import Foundation

func normalizedElementIndexArgument(_ value: Any?) -> String? {
    if let string = value as? String {
        return string.isEmpty ? nil : string
    }

    if let integer = value as? Int {
        return String(integer)
    }

    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return nil
        }

        return normalizedElementIndexNumber(number.doubleValue)
    }

    if let double = value as? Double {
        return normalizedElementIndexNumber(double)
    }

    return nil
}

private func normalizedElementIndexNumber(_ value: Double) -> String? {
    guard value.isFinite, value.rounded(.towardZero) == value else {
        return nil
    }

    guard let integer = Int(exactly: value) else { return nil }
    return String(integer)
}

public final class ComputerUseToolDispatcher {
    private let service: ComputerUseService

    public init(service: ComputerUseService = ComputerUseService()) {
        self.service = service
    }

    public func clearSnapshotCache() { service.clearSnapshotCache() }

    func notebookElement(sessionID: String, app: String, identifiers: [String] = [], role: String? = nil) throws -> String {
        try VirtualDisplaySessionRegistry.shared.withOperation(sessionID: sessionID, app: app, windowID: nil, isAction: false) { context in
            try service.withVirtualContext(context) { try service.notebookElement(app: app, identifiers: identifiers, role: role) }
        }
    }
    func notebookValue(sessionID: String, app: String, index: String) throws -> String {
        try VirtualDisplaySessionRegistry.shared.withOperation(sessionID: sessionID, app: app, windowID: nil, isAction: false) { context in
            try service.withVirtualContext(context) { try service.notebookValue(app: app, index: index) }
        }
    }

    public func callTool(name: String, arguments: [String: Any]) throws -> ToolCallResult {
        let registry = VirtualDisplaySessionRegistry.shared
        func result(_ state: VirtualDisplayState) throws -> ToolCallResult {
            .text(String(decoding: try JSONSerialization.data(withJSONObject: state.dictionary, options: [.sortedKeys]), as: UTF8.self))
        }
        func boolean(_ key: String, default value: Bool) throws -> Bool {
            guard let raw = arguments[key] else { return value }
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw ComputerUseError.invalidArguments("\(key) must be a boolean")
            }
            return number.boolValue
        }
        func configuration() throws -> VirtualDisplayConfiguration {
            .init(width: try optionalPositiveInt("width", in: arguments) ?? 1920,
                  height: try optionalPositiveInt("height", in: arguments) ?? 1080,
                  scale: try optionalPositiveInt("scale", in: arguments) ?? 1)
        }
        switch name {
        case "prewarm_virtual_display":
            let id = try registry.prewarm(configuration: configuration(), reuseDisplay: boolean("reuse_display", default: true))
            let value: [String: Any] = ["display_id": id, "idle_displays": registry.idleDisplayStates(), "displays": registry.displayStates().map(\.dictionary)]
            return .text(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
        case "delete_virtual_display":
            guard let rawID = try optionalPositiveInt("display_id", in: arguments) else { throw ComputerUseError.invalidArguments("display_id is required") }
            guard rawID <= Int(UInt32.max) else { throw ComputerUseError.invalidArguments("display_id out of range") }
            try registry.destroyDisplay(displayID: UInt32(rawID))
            return .text("Virtual display and its sessions deleted")
        case "release_virtual_displays":
            let rawID = try optionalPositiveInt("display_id", in: arguments)
            guard rawID == nil || rawID! <= Int(UInt32.max) else { throw ComputerUseError.invalidArguments("display_id out of range") }
            try registry.releaseIdleDisplays(displayID: rawID.map(UInt32.init))
            return .text("Idle virtual displays released")
        case "create_virtual_display":
            let rawID = try optionalPositiveInt("display_id", in: arguments)
            guard rawID == nil || rawID! <= Int(UInt32.max) else { throw ComputerUseError.invalidArguments("display_id out of range") }
            return try result(registry.create(configuration: configuration(), reuseDisplay: boolean("reuse_display", default: true), displayID: rawID.map(UInt32.init)))
        case "get_app_candidates":
            guard arguments["app"] == nil || arguments["app"] is String else { throw ComputerUseError.invalidArguments("app must be a string") }
            let rawPID = try optionalPositiveInt("pid", in: arguments)
            guard rawPID == nil || rawPID! <= Int(Int32.max) else { throw ComputerUseError.invalidArguments("pid out of range") }
            let value = try registry.applicationCandidates(app: optionalString("app", in: arguments), pid: rawPID.map(Int32.init)).map(\.dictionary)
            return .text(String(decoding: try JSONSerialization.data(withJSONObject: ["candidates": value], options: [.sortedKeys]), as: UTF8.self))
        case "attach_app_to_virtual_display":
            let rawPID = try optionalPositiveInt("pid", in: arguments)
            let rawWindow = try optionalPositiveInt("window_id", in: arguments)
            guard rawPID == nil || rawPID! <= Int(Int32.max), rawWindow == nil || rawWindow! <= Int(UInt32.max) else {
                throw ComputerUseError.invalidArguments("pid/window_id out of range")
            }
            guard arguments["mode"] == nil || arguments["mode"] is String else { throw ComputerUseError.invalidArguments("mode must be a string") }
            let mode = optionalString("mode", in: arguments) ?? "adopt"
            guard ["adopt", "launch"].contains(mode) else { throw ComputerUseError.invalidArguments("mode must be adopt or launch") }
            guard arguments["new_document"] == nil || arguments["new_document"] is Bool else { throw ComputerUseError.invalidArguments("new_document must be a boolean") }
            guard arguments["app"] == nil || arguments["app"] is String else { throw ComputerUseError.invalidArguments("app must be a string") }
            return try result(registry.attach(sessionID: requireString("session_id", in: arguments),
                app: optionalString("app", in: arguments), pid: rawPID.map(Int32.init), windowID: rawWindow.map(UInt32.init), launch: mode == "launch", newDocument: boolean("new_document", default: false), manageAllWindows: boolean("manage_all_windows", default: false)))
        case "get_virtual_display_state":
            if arguments["session_id"] == nil {
                let value: [String: Any] = ["sessions": registry.states().map(\.dictionary), "idle_displays": registry.idleDisplayStates(), "displays": registry.displayStates().map(\.dictionary)]
                return .text(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
            }
            return try result(registry.state(sessionID: requireString("session_id", in: arguments)))
        case "pause_virtual_display":
            return try result(registry.pause(sessionID: requireString("session_id", in: arguments)))
        case "resume_virtual_display":
            return try result(registry.resume(sessionID: requireString("session_id", in: arguments)))
        case "destroy_virtual_display":
            try registry.destroy(sessionID: requireString("session_id", in: arguments), retainDisplay: boolean("retain_display", default: true))
            return .text("Virtual display session ended; query get_virtual_display_state for retained idle displays")
        default: break
        }
        if arguments["session_id"] != nil {
            let id = try requireString("session_id", in: arguments)
            if name == "drag" { throw ComputerUseError.message("Drag is unsupported in virtual sessions: process-targeted delivery has not been verified; global drag is forbidden") }
            if optionalString("click_method", in: arguments)?.lowercased() == "global" {
                throw ComputerUseError.invalidArguments("Global input is forbidden in virtual sessions")
            }
            let rawWindow = try optionalPositiveInt("window_id", in: arguments)
            guard rawWindow == nil || rawWindow! <= Int(UInt32.max) else { throw ComputerUseError.invalidArguments("window_id out of range") }
            return try registry.withOperation(sessionID: id, app: requireString("app", in: arguments),
                windowID: rawWindow.map(UInt32.init), isAction: name != "get_app_state") { context in
                try service.withVirtualContext(context) { try callStandardTool(name: name, arguments: arguments) }
            }
        }
        if arguments["window_id"] != nil { throw ComputerUseError.invalidArguments("window_id requires session_id") }
        return try callStandardTool(name: name, arguments: arguments)
    }

    private func callStandardTool(name: String, arguments: [String: Any]) throws -> ToolCallResult {
        switch name {
        case "list_apps":
            return service.listApps()
        case "get_app_state":
            return try service.getAppState(
                app: requireString("app", in: arguments),
                textLimit: try optionalTextLimit("text_limit", in: arguments) ?? .defaults,
                treeLimits: AccessibilityTreeLimits.defaults.replacing(
                    maxNodeCount: try optionalPositiveInt("max_tree_nodes", in: arguments),
                    maxDepth: try optionalPositiveInt("max_tree_depth", in: arguments)
                )
            )
        case "click":
            return try service.click(
                app: requireString("app", in: arguments),
                elementIndex: optionalElementIndex(in: arguments),
                x: optionalDouble("x", in: arguments),
                y: optionalDouble("y", in: arguments),
                clickCount: try optionalPositiveInt("click_count", in: arguments) ?? 1,
                mouseButton: optionalString("mouse_button", in: arguments) ?? "left",
                clickMethod: try parseClickMethod(optionalString("click_method", in: arguments))
            )
        case "perform_secondary_action":
            return try service.performSecondaryAction(
                app: requireString("app", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                action: requireString("action", in: arguments)
            )
        case "scroll":
            return try service.scroll(
                app: requireString("app", in: arguments),
                direction: requireString("direction", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                pages: optionalDouble("pages", in: arguments) ?? 1
            )
        case "drag":
            return try service.drag(
                app: requireString("app", in: arguments),
                fromX: requireDouble("from_x", in: arguments),
                fromY: requireDouble("from_y", in: arguments),
                toX: requireDouble("to_x", in: arguments),
                toY: requireDouble("to_y", in: arguments)
            )
        case "type_text":
            return try service.typeText(
                app: requireString("app", in: arguments),
                text: requireString("text", in: arguments)
            )
        case "press_key":
            return try service.pressKey(
                app: requireString("app", in: arguments),
                key: requireString("key", in: arguments)
            )
        case "set_value":
            return try service.setValue(
                app: requireString("app", in: arguments),
                elementIndex: requireElementIndex(in: arguments),
                value: requireString("value", in: arguments)
            )
        default:
            throw ComputerUseError.unsupportedTool(name)
        }
    }

    public func callToolAsResult(name: String, arguments: [String: Any]) -> ToolCallResult {
        do {
            return try callTool(name: name, arguments: arguments)
        } catch let error as VirtualDisplayLaunchReusedError {
            let data = try? JSONSerialization.data(withJSONObject: error.dictionary, options: [.sortedKeys])
            return .text(data.map { String(decoding: $0, as: UTF8.self) } ?? error.localizedDescription, isError: true)
        } catch let error as ComputerUseError {
            return ToolCallResult.text(
                error.errorDescription ?? String(describing: error),
                isError: error.toolResultIsError
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return ToolCallResult.text(message, isError: true)
        }
    }

    private func requireString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ComputerUseError.missingArgument(key)
        }

        return value
    }

    private func optionalString(_ key: String, in arguments: [String: Any]) -> String? {
        arguments[key] as? String
    }

    private func optionalTextLimit(_ key: String, in arguments: [String: Any]) throws -> SnapshotTextLimit? {
        guard let value = arguments[key] else {
            return nil
        }

        if let string = value as? String {
            guard string.lowercased() == SnapshotTextLimit.maxKeyword else {
                throw ComputerUseError.invalidArguments("\(key) must be a positive integer or max")
            }
            return .max
        }

        let maxCount = try positiveInt(from: value, key: key, expectedDescription: "a positive integer or max")
        return SnapshotTextLimit(maxCount: maxCount)
    }

    private func requireElementIndex(in arguments: [String: Any]) throws -> String {
        guard let value = optionalElementIndex(in: arguments) else {
            throw ComputerUseError.missingArgument("element_index")
        }

        return value
    }

    private func optionalElementIndex(in arguments: [String: Any]) -> String? {
        normalizedElementIndexArgument(arguments["element_index"])
    }

    private func requireDouble(_ key: String, in arguments: [String: Any]) throws -> Double {
        guard let value = optionalDouble(key, in: arguments) else {
            throw ComputerUseError.missingArgument(key)
        }

        return value
    }

    private func optionalDouble(_ key: String, in arguments: [String: Any]) -> Double? {
        if let double = arguments[key] as? Double {
            return double
        }

        if let integer = arguments[key] as? Int {
            return Double(integer)
        }

        if let number = arguments[key] as? NSNumber {
            return number.doubleValue
        }

        return nil
    }

    private func optionalPositiveInt(_ key: String, in arguments: [String: Any]) throws -> Int? {
        guard let value = arguments[key] else {
            return nil
        }

        return try positiveInt(from: value, key: key, expectedDescription: "a positive integer")
    }

    private func positiveInt(from value: Any, key: String, expectedDescription: String) throws -> Int {
        if let integer = value as? Int {
            return try validatePositiveInt(integer, key: key, expectedDescription: expectedDescription)
        }

        if let double = value as? Double {
            return try validatePositiveWholeNumber(double, key: key, expectedDescription: expectedDescription)
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
            }
            return try validatePositiveWholeNumber(number.doubleValue, key: key, expectedDescription: expectedDescription)
        }

        throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
    }

    private func validatePositiveWholeNumber(_ value: Double, key: String, expectedDescription: String) throws -> Int {
        guard value.isFinite, value.rounded(.towardZero) == value else {
            throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
        }

        guard value >= Double(Int.min), value <= Double(Int.max) else {
            throw ComputerUseError.invalidArguments("\(key) is outside the supported integer range")
        }

        guard let integer = Int(exactly: value) else {
            throw ComputerUseError.invalidArguments("\(key) is outside the supported integer range")
        }
        return try validatePositiveInt(integer, key: key, expectedDescription: expectedDescription)
    }

    private func validatePositiveInt(_ value: Int, key: String, expectedDescription: String) throws -> Int {
        guard value > 0 else {
            throw ComputerUseError.invalidArguments("\(key) must be \(expectedDescription)")
        }
        return value
    }
}

public struct OpenComputerUseCallSpec {
    public let tool: String
    public let arguments: [String: Any]

    public init(tool: String, arguments: [String: Any]) {
        self.tool = tool
        self.arguments = arguments
    }
}

public struct OpenComputerUseCallOutput {
    public let jsonObject: Any
    public let hasToolError: Bool

    public init(jsonObject: Any, hasToolError: Bool) {
        self.jsonObject = jsonObject
        self.hasToolError = hasToolError
    }

    public func jsonText() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode call output as JSON.")
        }
        return text
    }
}

public typealias OpenComputerUseSleepHandler = (TimeInterval) -> Void

public func runOpenComputerUseCall(
    _ invocation: OpenComputerUseCallInvocation,
    service: ComputerUseService = ComputerUseService(),
    sleepHandler: OpenComputerUseSleepHandler = { Thread.sleep(forTimeInterval: $0) }
) throws -> OpenComputerUseCallOutput {
    let dispatcher = ComputerUseToolDispatcher(service: service)

    switch invocation {
    case let .single(toolName, argumentsJSON, argumentsFile):
        let arguments = try readOpenComputerUseToolArguments(
            json: argumentsJSON,
            file: argumentsFile
        )
        let result = dispatcher.callToolAsResult(name: toolName, arguments: arguments)
        return OpenComputerUseCallOutput(
            jsonObject: result.asDictionary,
            hasToolError: result.isError
        )

    case let .sequence(callsJSON, callsFile, interCallDelay):
        let calls = try readOpenComputerUseCallSequence(json: callsJSON, file: callsFile)
        var outputs: [[String: Any]] = []
        var hasToolError = false

        for (index, call) in calls.enumerated() {
            let result = dispatcher.callToolAsResult(name: call.tool, arguments: call.arguments)
            outputs.append([
                "tool": call.tool,
                "result": result.asDictionary,
            ])

            if result.isError {
                hasToolError = true
                break
            }

            if index < calls.count - 1, interCallDelay > 0 {
                sleepHandler(interCallDelay)
            }
        }

        return OpenComputerUseCallOutput(jsonObject: outputs, hasToolError: hasToolError)
    }
}

public func readOpenComputerUseToolArguments(
    json: String?,
    file: String?
) throws -> [String: Any] {
    guard let source = try readOpenComputerUseJSONSource(json: json, file: file) else {
        return [:]
    }

    let object = try decodeOpenComputerUseJSONObject(source)
    guard let arguments = object as? [String: Any] else {
        throw OpenComputerUseCLIError(message: "--args must be a JSON object", helpCommand: "call")
    }

    return arguments
}

public func readOpenComputerUseCallSequence(
    json: String?,
    file: String?
) throws -> [OpenComputerUseCallSpec] {
    guard let source = try readOpenComputerUseJSONSource(json: json, file: file) else {
        throw OpenComputerUseCLIError(message: "call sequence requires --calls or --calls-file", helpCommand: "call")
    }

    let object = try decodeOpenComputerUseJSONObject(source)
    guard let array = object as? [Any] else {
        throw OpenComputerUseCLIError(message: "--calls must be a JSON array", helpCommand: "call")
    }

    return try array.enumerated().map { index, item in
        guard let dictionary = item as? [String: Any] else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) must be a JSON object",
                helpCommand: "call"
            )
        }

        guard let tool = (dictionary["tool"] ?? dictionary["name"]) as? String, !tool.isEmpty else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) requires a non-empty tool",
                helpCommand: "call"
            )
        }

        let rawArguments = dictionary["args"] ?? dictionary["arguments"] ?? [:]
        guard let arguments = rawArguments as? [String: Any] else {
            throw OpenComputerUseCLIError(
                message: "call sequence item #\(index + 1) args must be a JSON object",
                helpCommand: "call"
            )
        }

        return OpenComputerUseCallSpec(tool: tool, arguments: arguments)
    }
}

private func readOpenComputerUseJSONSource(json: String?, file: String?) throws -> String? {
    if json != nil, file != nil {
        throw OpenComputerUseCLIError(message: "Use either inline JSON or a JSON file, not both", helpCommand: "call")
    }

    if let json {
        return json
    }

    guard let file else {
        return nil
    }

    do {
        return try String(contentsOfFile: file, encoding: .utf8)
    } catch {
        throw OpenComputerUseCLIError(
            message: "Unable to read JSON file \(file): \(error.localizedDescription)",
            helpCommand: "call"
        )
    }
}

private func decodeOpenComputerUseJSONObject(_ source: String) throws -> Any {
    guard let data = source.data(using: .utf8) else {
        throw OpenComputerUseCLIError(message: "JSON input must be UTF-8 text", helpCommand: "call")
    }

    do {
        return try JSONSerialization.jsonObject(with: data)
    } catch {
        throw OpenComputerUseCLIError(
            message: "Invalid JSON input: \(error.localizedDescription)",
            helpCommand: "call"
        )
    }
}
