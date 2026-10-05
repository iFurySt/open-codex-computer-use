import Foundation

public struct VirtualDisplayExampleCell: Sendable {
    public let title: String
    public let source: String
}

public enum VirtualDisplayExample {
    public static let cells: [VirtualDisplayExampleCell] = [
        cell("Prepare Calculator & TextEdit", "prepare_example"),
        cell("Inspect Calculator", "get_app_state", ["app": "com.apple.calculator"]),
        cell("Calculate 42 × 17", "calculate", ["left": "42", "operation": "*", "right": "17"]),
        cell("Inspect TextEdit", "get_app_state", ["app": "com.apple.TextEdit"]),
        cell("Write the actual result", "write_result", ["text": "${expression} = ${result}\n"]),
        cell("Inspect the finished document", "get_app_state", ["app": "com.apple.TextEdit"])
    ]
    private static func cell(_ title: String, _ tool: String, _ args: [String: String] = [:]) -> VirtualDisplayExampleCell {
        let data = try! JSONSerialization.data(withJSONObject: ["tool": tool, "args": args], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return .init(title: title, source: String(decoding: data, as: UTF8.self))
    }
    static func validatedNumber(_ value: Any?) throws -> String {
        guard let value = value as? String, value.range(of: #"^-?[0-9]{1,8}(\.[0-9]{1,6})?$"#, options: .regularExpression) != nil else {
            throw ComputerUseError.invalidArguments("Operands must be decimal strings with up to 8 integer and 6 fraction digits")
        }
        return value
    }
}

extension VirtualDisplayNotebookKernel {
    func runExample(tool: String, arguments: [String: Any]) throws -> ToolCallResult {
        let registry = VirtualDisplaySessionRegistry.shared
        let calculator = "com.apple.calculator", editor = "com.apple.TextEdit"
        func call(_ name: String, _ args: [String: Any]) throws -> ToolCallResult {
            var args = args; args["session_id"] = sessionID
            let result = try dispatcher.callTool(name: name, arguments: args)
            if result.isError { throw ComputerUseError.message(result.primaryText ?? "Example tool failed") }
            return result
        }
        func snapshot(_ app: String) throws -> ToolCallResult { try call("get_app_state", ["app": app, "text_limit": "max"]) }
        func element(_ app: String, ids: [String] = [], role: String? = nil) throws -> String {
            try dispatcher.notebookElement(sessionID: sessionID, app: app, identifiers: ids, role: role)
        }
        func press(_ identifiers: [String]) throws {
            _ = try snapshot(calculator)
            let index = try element(calculator, ids: identifiers, role: "AXButton")
            _ = try call("click", ["app": calculator, "element_index": index, "click_method": "accessibility"])
        }
        func output(_ data: [String: Any], snapshot: ToolCallResult? = nil) throws -> ToolCallResult {
            let text = String(decoding: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            return .init(content: [.text(text)] + (snapshot?.content ?? []))
        }
        switch tool {
        case "prepare_example":
            for app in [calculator, editor] {
                let state = try registry.state(sessionID: sessionID)
                let existing = state.applications.filter { $0.app.caseInsensitiveCompare(app) == .orderedSame }
                if existing.isEmpty {
                    _ = try call("attach_app_to_virtual_display", ["app": app, "mode": "launch", "new_document": app == editor, "manage_all_windows": true])
                } else {
                    guard existing.count == 1, let owned = existing.first, owned.owned,
                          app != editor || owned.documentURL != nil else {
                        throw ComputerUseError.message("Example requires its own Calculator and TextEdit document; create a fresh session")
                    }
                }
            }
            try registry.arrangeExampleWindows(sessionID: sessionID)
            return try output(registry.state(sessionID: sessionID).dictionary)
        case "calculate":
            values.removeValue(forKey: "result"); values.removeValue(forKey: "expression")
            let left = try VirtualDisplayExample.validatedNumber(arguments["left"])
            let right = try VirtualDisplayExample.validatedNumber(arguments["right"])
            let operations = ["+": ("Add", "+"), "-": ("Subtract", "−"), "*": ("Multiply", "×"), "/": ("Divide", "÷")]
            guard let key = arguments["operation"] as? String, let operation = operations[key] else { throw ComputerUseError.invalidArguments("operation must be +, -, * or /") }
            try press(["AllClear", "Clear"])
            let identifiers: [Character: String] = ["0": "Zero", "1": "One", "2": "Two", "3": "Three", "4": "Four", "5": "Five", "6": "Six", "7": "Seven", "8": "Eight", "9": "Nine", ".": "Decimal"]
            func enter(_ operand: String) throws {
                for character in operand where character != "-" {
                    guard let id = identifiers[character] else { throw ComputerUseError.invalidArguments("Unsupported digit") }
                    try press([id])
                }
                if operand.hasPrefix("-") { try press(["Negate"]) }
            }
            try enter(left); try press([operation.0]); try enter(right); try press(["Equals"])
            let state = try snapshot(calculator)
            let display = try element(calculator, ids: ["StandardInputView"])
            let raw = try dispatcher.notebookValue(sessionID: sessionID, app: calculator, index: display)
            // AX uses directional formatting characters around the displayed value.
            let result = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && ![0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x2066, 0x2067, 0x2069].contains($0.value) }.map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw ComputerUseError.message("Calculator display did not expose a result") }
            let expression = "\(left) \(operation.1) \(right)"
            values["expression"] = expression; values["result"] = result
            return try output(["expression": expression, "result": result, "source": "Calculator AX display"], snapshot: state)
        case "write_result":
            guard let result = values["result"], let expression = values["expression"] else { throw ComputerUseError.message("Run the calculate cell first; no UI result is bound") }
            let template = arguments["text"] as? String ?? "${expression} = ${result}\n"
            let text = template.replacingOccurrences(of: "${expression}", with: expression).replacingOccurrences(of: "${result}", with: result)
            _ = try registry.ownedDocument(sessionID: sessionID, app: editor)
            _ = try snapshot(editor)
            let field = try element(editor, role: "AXTextArea")
            let state = try call("set_value", ["app": editor, "element_index": field, "value": text])
            let currentField = try element(editor, role: "AXTextArea")
            guard try dispatcher.notebookValue(sessionID: sessionID, app: editor, index: currentField) == text else { throw ComputerUseError.message("TextEdit did not retain the requested result") }
            return try output(["text": text, "ui_verified": true], snapshot: state)
        default: throw ComputerUseError.unsupportedTool(tool)
        }
    }
}
