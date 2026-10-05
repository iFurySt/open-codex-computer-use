import Foundation

/// Presentation of tool content without embedding image payloads in the JSON editor.
public struct VirtualDisplayNotebookOutput: Sendable {
    public let json: String
    public let uiTree: String?
    public let images: [Data]
    public init(_ result: ToolCallResult) {
        var objects: [Any] = [], notes: [String] = [], trees: [String] = [], frames: [Data] = []
        for content in result.asDictionary["content"] as? [[String: Any]] ?? [] {
            if content["type"] as? String == "image", let base64 = content["data"] as? String, let data = Data(base64Encoded: base64) {
                frames.append(data)
            } else if let text = content["text"] as? String {
                if let bytes = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: bytes) { objects.append(object) }
                else if text.hasPrefix("App=") || text.hasPrefix("Window:") { trees.append(text) }
                else { notes.append(text) }
            }
        }
        var envelope: [String: Any] = ["isError": result.isError]
        if objects.count == 1 { envelope["result"] = objects[0] }
        else if !objects.isEmpty { envelope["results"] = objects }
        if !notes.isEmpty { envelope["messages"] = notes }
        if !trees.isEmpty { envelope["ui_tree_available"] = true }
        if !frames.isEmpty { envelope["screenshots"] = frames.count }
        json = String(decoding: (try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
        uiTree = trees.isEmpty ? nil : trees.joined(separator: "\n\n")
        images = frames
    }
}
