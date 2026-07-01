import Foundation

public typealias EventStreamMCPStartApprovalRequester = () throws -> EventStreamStartApprovalDecision

public final class EventStreamMCPServer: LineBasedMCPServer {
    private let dispatcher: EventStreamToolDispatcher
    private var clientSupportsElicitation = false
    private var nextRequestID = 1000

    public init(service: EventStreamService = .shared) {
        self.dispatcher = EventStreamToolDispatcher(service: service)
    }

    public func run() throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if let response = handle(line: line, startApprovalRequester: requestStartApprovalViaMCP) {
                FileHandle.standardOutput.write((response + "\n").data(using: .utf8)!)
            }
        }
    }

    public func handle(line: String) -> String? {
        handle(line: line, startApprovalRequester: nil)
    }

    public func handle(line: String, startApprovalRequester: EventStreamMCPStartApprovalRequester?) -> String? {
        do {
            guard let payload = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return try encodeJSONRPCError(id: nil, code: -32700, message: "Invalid JSON-RPC payload")
            }

            let method = payload["method"] as? String
            let id = payload["id"]
            let params = payload["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                let capabilities = params["capabilities"] as? [String: Any] ?? [:]
                clientSupportsElicitation = capabilities["elicitation"] is [String: Any]
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "protocolVersion": "2025-11-25",
                        "serverInfo": [
                            "name": "Record & Replay",
                            "version": openComputerUseVersion,
                        ],
                        "capabilities": [
                            "tools": [
                                "listChanged": false,
                            ],
                        ],
                    ]
                )
            case "notifications/initialized":
                return nil
            case "ping":
                return try encodeJSONRPCResult(id: id, result: [:])
            case "tools/list":
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "tools": EventStreamToolDefinitions.all.map(\.asDictionary),
                    ]
                )
            case "tools/call":
                let toolParams = try parseToolCallParams(payload: payload)
                let name = try parseToolName(params: toolParams)
                let arguments = try parseToolArguments(params: toolParams)
                let approvalDecision = try startApprovalDecisionIfNeeded(
                    toolName: name,
                    requester: startApprovalRequester
                )
                let result = try dispatcher.callTool(
                    name: name,
                    arguments: arguments,
                    startApprovalDecision: approvalDecision
                )
                return try encodeJSONRPCResult(
                    id: id,
                    result: result.asDictionary
                )
            default:
                if method == nil {
                    return nil
                }

                return try encodeJSONRPCError(id: id, code: -32601, message: "Method not found: \(method ?? "")")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let id = payload?["id"]
            return try? encodeJSONRPCResult(
                id: id,
                result: ToolCallResult.text(message, isError: true).asDictionary
            )
        }
    }

    private func parseToolCallParams(payload: [String: Any]) throws -> [String: Any] {
        guard let params = payload["params"] as? [String: Any] else {
            throw ComputerUseError.invalidArguments("tools/call params must be an object")
        }
        return params
    }

    private func parseToolName(params: [String: Any]) throws -> String {
        guard let name = params["name"] as? String, !name.isEmpty else {
            throw ComputerUseError.invalidArguments("tools/call params.name must be a non-empty string")
        }
        return name
    }

    private func parseToolArguments(params: [String: Any]) throws -> [String: Any] {
        guard let rawArguments = params["arguments"] else {
            return [:]
        }
        guard let arguments = rawArguments as? [String: Any] else {
            throw ComputerUseError.invalidArguments("tools/call arguments must be an object")
        }
        return arguments
    }

    private func startApprovalDecisionIfNeeded(
        toolName: String,
        requester: EventStreamMCPStartApprovalRequester?
    ) throws -> EventStreamStartApprovalDecision? {
        guard toolName == "event_stream_start" else {
            return nil
        }
        guard dispatcher.requiresMCPStartApproval else {
            return nil
        }
        guard !dispatcher.status().isActive else {
            return nil
        }
        guard clientSupportsElicitation, let requester else {
            return .cancelled
        }
        return try requester()
    }

    private func requestStartApprovalViaMCP() throws -> EventStreamStartApprovalDecision {
        let requestID = "event-stream-start-approval-\(nextRequestID)"
        nextRequestID += 1
        let request = try encode(Self.startApprovalElicitationRequest(id: requestID))
        FileHandle.standardOutput.write((request + "\n").data(using: .utf8)!)

        guard let responseLine = readLine(strippingNewline: true),
              let response = try JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any] else {
            return .cancelled
        }
        if response["error"] != nil {
            return .cancelled
        }
        guard let result = response["result"] as? [String: Any],
              let action = result["action"] as? String else {
            return .cancelled
        }
        switch action {
        case "accept":
            return .approved
        case "decline", "reject":
            return .denied
        case "cancel":
            return .cancelled
        default:
            return .cancelled
        }
    }

    private func encodeJSONRPCResult(id: Any?, result: [String: Any]) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result,
        ])
    }

    private func encodeJSONRPCError(id: Any?, code: Int, message: String) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ])
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode JSON-RPC response.")
        }

        return text
    }

    static func startApprovalElicitationRequest(id requestID: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "elicitation/create",
            "params": [
                "mode": "form",
                "message": "Open Computer Use wants to start Record & Replay and record your actions.",
                "requestedSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": [],
                ],
            ],
        ]
    }
}

public final class EventStreamToolDispatcher {
    private let service: EventStreamService

    public init(service: EventStreamService = .shared) {
        self.service = service
    }

    public var requiresMCPStartApproval: Bool {
        service.configuredStartApprovalPolicy == .mcpElicitation
    }

    public func status() -> EventStreamRecordingStatus {
        service.status()
    }

    public func callTool(
        name: String,
        arguments: [String: Any],
        startApprovalDecision: EventStreamStartApprovalDecision? = nil
    ) throws -> ToolCallResult {
        try validateNoArguments(toolName: name, arguments: arguments)

        let status: EventStreamRecordingStatus
        switch name {
        case "event_stream_start":
            status = try service.start(approvalDecision: startApprovalDecision)
        case "event_stream_status":
            status = service.status()
        case "event_stream_stop":
            status = try service.stop()
        default:
            throw ComputerUseError.unsupportedTool(name)
        }

        return ToolCallResult.text(try mcpStatusText(status))
    }

    private func validateNoArguments(toolName: String, arguments: [String: Any]) throws {
        guard !arguments.isEmpty else {
            return
        }

        switch toolName {
        case "event_stream_start", "event_stream_status", "event_stream_stop":
            throw ComputerUseError.invalidArguments("\(toolName) does not accept arguments")
        default:
            return
        }
    }

    private func mcpStatusText(_ status: EventStreamRecordingStatus) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: mcpStatusDictionary(status),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode event stream status as JSON.")
        }
        return text
    }

    private func mcpStatusDictionary(_ status: EventStreamRecordingStatus) -> [String: Any] {
        let maximumDurationSeconds = service.configuredMaximumDurationSeconds
        if status.state == .idle, status.sessionID == nil {
            return [
                "isRecording": false,
                "maxDurationSeconds": maximumDurationSeconds,
            ]
        }

        var dictionary = status.asDictionary
        dictionary["isRecording"] = status.isActive
        dictionary["maxDurationSeconds"] = maximumDurationSeconds
        if let metadataPath = status.metadataPath {
            let metadataURL = URL(fileURLWithPath: metadataPath)
            let sessionDirectoryURL = metadataURL.deletingLastPathComponent()
            let sessionURL = sessionDirectoryURL.appendingPathComponent("session.json")
            dictionary["metadataPath"] = sessionURL.path
            dictionary["sessionPath"] = sessionURL.path
            dictionary["sessionDirectoryPath"] = sessionDirectoryURL.path
        }
        return dictionary
    }
}
