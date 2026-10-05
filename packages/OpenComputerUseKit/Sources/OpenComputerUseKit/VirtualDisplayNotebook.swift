import Foundation

/// A notebook kernel shares its dispatcher/snapshot cache across cells, but never
/// executes a shell or permits a cell to escape its owning virtual session.
public final class VirtualDisplayNotebookKernel: @unchecked Sendable {
    private let lock = NSLock()
    private let dispatcher = ComputerUseToolDispatcher()
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }

    public static func boundCommand(source: String, sessionID: String, app: String? = nil) throws -> OpenComputerUseCallSpec {
        guard let bytes = source.data(using: .utf8),
              let command = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let tool = command["tool"] as? String else {
            throw ComputerUseError.invalidArguments("Cell must contain an object with tool and args, for example {\"tool\":\"get_app_state\",\"args\":{}}")
        }
        let allowed = ["get_virtual_display_state", "pause_virtual_display", "resume_virtual_display", "attach_app_to_virtual_display",
                       "get_app_state", "click", "scroll", "drag", "type_text", "press_key", "set_value", "perform_secondary_action"]
        guard allowed.contains(tool) else { throw ComputerUseError.invalidArguments("This cell kernel supports session-bound OCU tools only; create/end sessions through the workspace") }
        guard command["args"] == nil || command["args"] is [String: Any] else { throw ComputerUseError.invalidArguments("Cell args must be an object") }
        var arguments = command["args"] as? [String: Any] ?? [:]
        if let supplied = arguments["session_id"] {
            guard let supplied = supplied as? String, supplied == sessionID || supplied == "$session" else {
                throw ComputerUseError.invalidArguments("Cell session_id must match this notebook's session")
            }
        }
        arguments["session_id"] = sessionID
        if arguments["app"] == nil || arguments["app"] as? String == "$app" {
            if let app { arguments["app"] = app }
        }
        return .init(tool: tool, arguments: arguments)
    }

    public func run(source: String, app: String? = nil) throws -> ToolCallResult {
        lock.lock(); defer { lock.unlock() }
        let command = try Self.boundCommand(source: source, sessionID: sessionID, app: app)
        return dispatcher.callToolAsResult(name: command.tool, arguments: command.arguments)
    }
}
