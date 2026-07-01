import Foundation

public enum EventStreamToolDefinitions {
    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "event_stream_start",
            description: "Start recording the user's actions for up to 30 minutes. If a recording is already active, return that active session instead of starting another one.",
            annotations: eventStreamAnnotations(readOnly: false, idempotent: false),
            inputSchema: eventStreamEmptyObjectSchema()
        ),
        ToolDefinition(
            name: "event_stream_status",
            description: "Get the current or most recent Record & Replay recording status including paths to metadata and events during the recording.",
            annotations: eventStreamAnnotations(readOnly: true, idempotent: true),
            inputSchema: eventStreamEmptyObjectSchema()
        ),
        ToolDefinition(
            name: "event_stream_stop",
            description: "Stop the active event stream recording if one is running and return status including paths to metadata and events during the recording.",
            annotations: eventStreamAnnotations(readOnly: false, idempotent: true),
            inputSchema: eventStreamEmptyObjectSchema()
        ),
    ]
}

private func eventStreamEmptyObjectSchema() -> [String: Any] {
    [
        "type": "object",
        "properties": [:],
        "additionalProperties": false,
    ]
}

private func eventStreamAnnotations(readOnly: Bool, idempotent: Bool) -> [String: Any] {
    [
        "destructiveHint": false,
        "idempotentHint": idempotent,
        "openWorldHint": false,
        "readOnlyHint": readOnly,
    ]
}
