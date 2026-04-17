import Foundation

public struct ToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]

    public var asDictionary: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }
}

public enum ToolDefinitions {
    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "list_apps",
            description: "List running or recently visible macOS applications. Read-only and low intrusion.",
            inputSchema: objectSchema(properties: [:], required: [])
        ),
        ToolDefinition(
            name: "get_app_state",
            description: "Capture the current accessibility tree and screenshot metadata for an app without activating it when possible. Usually call this first before deciding on an action tool.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "click",
            description: "Click an accessibility element or a screenshot-relative coordinate. Prefer this only when a direct AX action is required; coordinate fallback may bring the app forward and use the real pointer.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "element_index": stringProperty(description: "Accessibility element index from get_app_state."),
                    "x": numberProperty(description: "Screenshot-relative X coordinate."),
                    "y": numberProperty(description: "Screenshot-relative Y coordinate."),
                    "click_count": integerProperty(description: "How many clicks to send.", defaultValue: 1),
                    "mouse_button": stringProperty(
                        description: "Mouse button to use.",
                        enumValues: ["left", "right", "middle"],
                        defaultValue: "left"
                    ),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "perform_secondary_action",
            description: "Invoke a listed accessibility secondary action such as Raise or Show menu. Prefer this over coordinate clicks when get_app_state already exposed the desired AX action.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "element_index": stringProperty(description: "Accessibility element index from get_app_state."),
                    "action": stringProperty(description: "Secondary action name from get_app_state."),
                ],
                required: ["app", "element_index", "action"]
            )
        ),
        ToolDefinition(
            name: "scroll",
            description: "Scroll an accessibility element in a direction by pages. Prefers AX page-scroll actions and only falls back to global wheel events when AX scrolling is unavailable.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "direction": stringProperty(description: "One of up, down, left, right.", enumValues: ["up", "down", "left", "right"]),
                    "element_index": stringProperty(description: "Accessibility element index from get_app_state."),
                    "pages": integerProperty(description: "Number of pages to scroll.", defaultValue: 1),
                ],
                required: ["app", "direction", "element_index"]
            )
        ),
        ToolDefinition(
            name: "drag",
            description: "Drag from one screenshot-relative coordinate to another. This uses global mouse events, moves the real pointer, and may need to bring the target app forward.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "from_x": numberProperty(description: "Screenshot-relative start X coordinate."),
                    "from_y": numberProperty(description: "Screenshot-relative start Y coordinate."),
                    "to_x": numberProperty(description: "Screenshot-relative end X coordinate."),
                    "to_y": numberProperty(description: "Screenshot-relative end Y coordinate."),
                ],
                required: ["app", "from_x", "from_y", "to_x", "to_y"]
            )
        ),
        ToolDefinition(
            name: "type_text",
            description: "Type literal text into the focused control of an app. Sends keyboard events directly to the target app PID, which usually avoids moving the real pointer or activating the app first.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "text": stringProperty(description: "Literal text to type."),
                ],
                required: ["app", "text"]
            )
        ),
        ToolDefinition(
            name: "press_key",
            description: "Press a key or key combination using xdotool-style syntax. Prefer keyboard shortcuts like super+n when available; events are sent directly to the target app PID.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "key": stringProperty(description: "Key or chord such as Return, Tab, command+a, or super+c."),
                ],
                required: ["app", "key"]
            )
        ),
        ToolDefinition(
            name: "set_value",
            description: "Set the value of a settable accessibility element. Prefer this over click plus type_text when the target control already exposes an AX value.",
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier."),
                    "element_index": stringProperty(description: "Accessibility element index from get_app_state."),
                    "value": stringProperty(description: "String value to assign."),
                ],
                required: ["app", "element_index", "value"]
            )
        ),
    ]
}

private func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties,
    ]

    if !required.isEmpty {
        schema["required"] = required
    }

    return schema
}

private func stringProperty(description: String, enumValues: [String]? = nil, defaultValue: String? = nil) -> [String: Any] {
    var property: [String: Any] = [
        "type": "string",
        "description": description,
    ]

    if let enumValues {
        property["enum"] = enumValues
    }

    if let defaultValue {
        property["default"] = defaultValue
    }

    return property
}

private func integerProperty(description: String, defaultValue: Int? = nil) -> [String: Any] {
    var property: [String: Any] = [
        "type": "integer",
        "description": description,
    ]

    if let defaultValue {
        property["default"] = defaultValue
    }

    return property
}

private func numberProperty(description: String) -> [String: Any] {
    [
        "type": "number",
        "description": description,
    ]
}
