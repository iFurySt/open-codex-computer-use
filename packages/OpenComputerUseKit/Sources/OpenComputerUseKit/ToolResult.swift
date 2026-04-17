import Foundation

public struct ToolResultContentItem: @unchecked Sendable {
    let dictionary: [String: Any]

    public static func text(_ text: String) -> ToolResultContentItem {
        ToolResultContentItem(
            dictionary: [
                "type": "text",
                "text": text,
            ]
        )
    }

    public static func pngImage(_ data: Data) -> ToolResultContentItem {
        ToolResultContentItem(
            dictionary: [
                "type": "image",
                "data": data.base64EncodedString(),
                "mimeType": "image/png",
            ]
        )
    }
}

public struct ToolCallResult: @unchecked Sendable {
    public let content: [ToolResultContentItem]
    public let isError: Bool

    public init(content: [ToolResultContentItem], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public var primaryText: String? {
        content.first(where: { $0.dictionary["type"] as? String == "text" })?.dictionary["text"] as? String
    }

    public var asDictionary: [String: Any] {
        [
            "content": content.map(\.dictionary),
            "isError": isError,
        ]
    }

    public static func text(_ text: String, isError: Bool = false) -> ToolCallResult {
        ToolCallResult(content: [.text(text)], isError: isError)
    }
}
