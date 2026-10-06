import Foundation

public struct ToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let annotations: [String: Any]
    public let inputSchema: [String: Any]

    public init(name: String, description: String, annotations: [String: Any], inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.annotations = annotations
        self.inputSchema = inputSchema
    }

    public var asDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]

        if !annotations.isEmpty {
            dictionary["annotations"] = annotations
        }

        return dictionary
    }
}

public enum ToolDefinitions {
    public static let all: [ToolDefinition] = standard.map { definition in
        guard definition.name != "list_apps" else { return definition }
        var schema = definition.inputSchema
        var properties = schema["properties"] as? [String: Any] ?? [:]
        properties["snapshot_mode"] = stringProperty(description: "AX output: auto (default, full first then contextual diffs), full (recover baseline), or none (omit AX; capture/input checks unchanged)", enumValues: ["auto", "full", "none"])
        if definition.name == "get_app_state" {
            properties["base_snapshot_id"] = stringProperty(description: "Snapshot actually received by the caller; unavailable or incompatible baselines recover with full output")
        }
        properties["session_id"] = stringProperty(description: "Optional macOS virtual display session; enforces background-only input")
        if definition.name == "get_app_state" { properties["window_id"] = positiveIntegerProperty(description: "Select an exact managed window in session_id") }
        schema["properties"] = properties
        return ToolDefinition(name: definition.name, description: (definition.name == "drag" ? definition.description.replacingOccurrences(of: "This tool is part of plugin", with: "Virtual display sessions reject drag until a background path is verified. This tool is part of plugin") : definition.description), annotations: definition.annotations, inputSchema: schema)
    } + virtualDisplayTools

    private static let virtualDisplayTools: [ToolDefinition] = [
        ToolDefinition(name: "create_virtual_display", description: "Create a macOS extended virtual display session. Requires Accessibility and Screen Recording. Reuse a matching idle display by default; otherwise create one. First creation and final release can move the Dock. Multiple sessions can coexist.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "width": positiveIntegerProperty(description: "Logical width in points; default 1920"),
            "height": positiveIntegerProperty(description: "Logical height in points; default 1080"),
            "scale": integerProperty(description: "Backing scale: 1 (default) or 2"),
            "display_id": positiveIntegerProperty(description: "Optional exact idle display to reuse; configuration must match"),
            "reuse_display": ["type": "boolean", "description": "Reuse a matching idle display; default true"]], required: [])),
        ToolDefinition(name: "get_app_candidates", description: "Read-only query of all matching running processes and their windows. app/pid filters are optional. Candidates do not authorize window movement or input; explicitly select PID and window_id for adoption.", annotations: readOnlyAnnotations(), inputSchema: objectSchema(properties: [
            "app": stringProperty(description: "Optional exact app name or bundle identifier"),
            "pid": positiveIntegerProperty(description: "Optional exact process identifier")], required: [])),
        ToolDefinition(name: "attach_app_to_virtual_display", description: "Launch a dedicated instance and return candidate windows without moving them, or adopt one explicit PID/window. Dedicated launch stays hidden until selected windows are contained; manage_all_windows explicitly authorizes all initial windows. app must be a bundle identifier for launch. Multiple applications can share a display; each process belongs to only one session. Target must not be frontmost.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "session_id": stringProperty(description: "Virtual session identifier"), "app": stringProperty(description: "Required bundle identifier for launch; optional identity check for adopt"),
            "mode": stringProperty(description: "adopt (default) or launch", enumValues: ["adopt", "launch"]),
            "manage_all_windows": ["type": "boolean", "description": "Launch only: explicitly authorize all initial windows of the verified dedicated instance. Default false; later new windows require selection"],
            "new_document": ["type": "boolean", "description": "For dedicated TextEdit launch: create a session-owned temporary text document"],
            "pid": positiveIntegerProperty(description: "Required for adopt"), "window_id": positiveIntegerProperty(description: "Required for adopt")], required: ["session_id"])),
        ToolDefinition(name: "get_virtual_display_state", description: "Inspect one virtual session, including managed applications/windows. Omit session_id to list all sessions.", annotations: readOnlyAnnotations(), inputSchema: objectSchema(properties: ["session_id": stringProperty(description: "Optional virtual session identifier; omit to list")], required: [])),
        sessionTool("pause_virtual_display", "Pause virtual-session input."),
        sessionTool("resume_virtual_display", "Validate identity and geometry, then resume a paused session."),
        ToolDefinition(name: "destroy_virtual_display", description: "Restore borrowed windows and request dedicated app termination. Retain the empty display by default to avoid hotplug; retain_display=false removes it. Unsaved content may block cleanup.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "session_id": stringProperty(description: "Virtual session identifier"),
            "retain_display": ["type": "boolean", "description": "Keep empty display for reuse; default true. False removes it and may move Dock."]], required: ["session_id"])),
        ToolDefinition(name: "prewarm_virtual_display", description: "Reserve an empty macOS virtual display without an input session. Idempotent for an idle matching configuration by default; reuse_display=false creates a new empty display. First creation can move Dock; subsequent sessions reuse it.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "reuse_display": ["type": "boolean", "description": "Reuse matching idle display; default true. False reserves a new display."],
            "width": positiveIntegerProperty(description: "Logical width; default 1920"),
            "height": positiveIntegerProperty(description: "Logical height; default 1080"),
            "scale": integerProperty(description: "Backing scale: 1 (default) or 2")], required: [])),
        ToolDefinition(name: "delete_virtual_display", description: "Safely end all sessions on this runtime's display, then remove it. Cleanup failure preserves unfinished state; never force quits apps. Display removal may move Dock.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "display_id": positiveIntegerProperty(description: "Exact owned display ID")], required: ["display_id"])),
        ToolDefinition(name: "release_virtual_displays", description: "Remove this runtime's idle virtual displays. Does not remove active sessions or foreign displays. Final release can move Dock.", annotations: defaultAnnotations(), inputSchema: objectSchema(properties: [
            "display_id": positiveIntegerProperty(description: "Optional idle display ID; omit to release all idle displays")], required: []))
    ]
    private static func sessionTool(_ name: String, _ description: String, readOnly: Bool = false) -> ToolDefinition {
        ToolDefinition(name: name, description: description, annotations: readOnly ? readOnlyAnnotations() : defaultAnnotations(),
            inputSchema: objectSchema(properties: ["session_id": stringProperty(description: "Virtual session identifier")], required: ["session_id"]))
    }

    private static let standard: [ToolDefinition] = [
        ToolDefinition(
            name: "click",
            description: "Click an element by index or pixel coordinates from screenshot. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element index to click"),
                    "x": numberProperty(description: "X coordinate in screenshot pixel coordinates"),
                    "y": numberProperty(description: "Y coordinate in screenshot pixel coordinates"),
                    "click_count": integerProperty(description: "Number of clicks. Defaults to 1"),
                    "mouse_button": stringProperty(
                        description: "Mouse button to click. Defaults to left.",
                        enumValues: ["left", "right", "middle"]
                    ),
                    "click_method": stringProperty(
                        description: "Click implementation: auto (default), accessibility, app_post, sky_click, or global. Accessibility requires element_index. app_post sends a public event directly to the target app. sky_click uses the macOS SkyLight background window path. Global may move the system pointer and requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1.",
                        enumValues: ClickMethod.allCases.map(\.rawValue)
                    ),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "drag",
            description: "Drag from one point to another using pixel coordinates. By default mouse events are posted directly to the target app and the system pointer does not move; that path cannot drive window-server drag sessions such as window moves, text selection, or Finder drag-and-drop. Those require OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 in the server process environment, which may move the real pointer. The result reports which path was used. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "from_x": numberProperty(description: "Start X coordinate"),
                    "from_y": numberProperty(description: "Start Y coordinate"),
                    "to_x": numberProperty(description: "End X coordinate"),
                    "to_y": numberProperty(description: "End Y coordinate"),
                ],
                required: ["app", "from_x", "from_y", "to_x", "to_y"]
            )
        ),
        ToolDefinition(
            name: "get_app_state",
            description: "Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app. This tool is part of plugin `Computer Use`.",
            annotations: readOnlyAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "text_limit": textLimitProperty(description: "Maximum text characters to return. Use \"max\" for full text. Defaults to 500."),
                    "max_tree_nodes": positiveIntegerProperty(description: "Maximum accessibility tree nodes to render. Defaults to 1200."),
                    "max_tree_depth": positiveIntegerProperty(description: "Maximum accessibility tree depth to render. Defaults to 64."),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: "list_apps",
            description: "List the apps on this computer. Returns the set of apps that are currently running, as well as any that have been used in the last 14 days, including details on usage frequency. This tool is part of plugin `Computer Use`.",
            annotations: readOnlyAnnotations(),
            inputSchema: objectSchema(properties: [:], required: [])
        ),
        ToolDefinition(
            name: "perform_secondary_action",
            description: "Invoke a secondary accessibility action exposed by an element. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "action": stringProperty(description: "Secondary accessibility action name"),
                ],
                required: ["app", "element_index", "action"]
            )
        ),
        ToolDefinition(
            name: "press_key",
            description: "Press a key or key-combination on the keyboard, including modifier and navigation keys.\n  - This supports xdotool's `key` syntax.\n  - Examples: \"a\", \"Return\", \"Tab\", \"super+c\", \"Up\", \"KP_0\" (for the numpad 0 key). This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "key": stringProperty(description: "Key or key combination to press"),
                ],
                required: ["app", "key"]
            )
        ),
        ToolDefinition(
            name: "scroll",
            description: "Scroll an element in a direction by a number of pages. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "direction": stringProperty(description: "Scroll direction: up, down, left, or right"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "pages": numberProperty(description: "Number of pages to scroll. Fractional values are supported. Defaults to 1"),
                ],
                required: ["app", "element_index", "direction"]
            )
        ),
        ToolDefinition(
            name: "set_value",
            description: "Set the value of a settable accessibility element. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "element_index": stringProperty(description: "Element identifier"),
                    "value": stringProperty(description: "Value to assign"),
                ],
                required: ["app", "element_index", "value"]
            )
        ),
        ToolDefinition(
            name: "type_text",
            description: "Type literal text using keyboard input. This tool is part of plugin `Computer Use`.",
            annotations: defaultAnnotations(),
            inputSchema: objectSchema(
                properties: [
                    "app": stringProperty(description: "App name or bundle identifier"),
                    "text": stringProperty(description: "Literal text to type"),
                ],
                required: ["app", "text"]
            )
        ),
    ]
}

private func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties,
        "additionalProperties": false,
    ]

    if !required.isEmpty {
        schema["required"] = required
    }

    return schema
}

private func defaultAnnotations() -> [String: Any] {
    [
        "destructiveHint": false,
        "openWorldHint": false,
    ]
}

private func readOnlyAnnotations() -> [String: Any] {
    [
        "destructiveHint": false,
        "idempotentHint": true,
        "openWorldHint": false,
        "readOnlyHint": true,
    ]
}

private func stringProperty(description: String, enumValues: [String]? = nil) -> [String: Any] {
    var property: [String: Any] = [
        "type": "string",
        "description": description,
    ]

    if let enumValues {
        property["enum"] = enumValues
    }

    return property
}

private func integerProperty(description: String) -> [String: Any] {
    [
        "type": "integer",
        "description": description,
    ]
}

private func positiveIntegerProperty(description: String) -> [String: Any] {
    [
        "type": "integer",
        "minimum": 1,
        "description": description,
    ]
}

private func textLimitProperty(description: String) -> [String: Any] {
    [
        "anyOf": [
            [
                "type": "integer",
                "minimum": 1,
            ],
            [
                "type": "string",
                "enum": [SnapshotTextLimit.maxKeyword],
            ],
        ],
        "description": description,
    ]
}

private func numberProperty(description: String) -> [String: Any] {
    [
        "type": "number",
        "description": description,
    ]
}
