import Foundation

public enum ComputerUseError: Error, LocalizedError {
    case message(String)
    case unsupportedTool(String)
    case invalidArguments(String)
    case appNotFound(String)
    case permissionDenied(String)
    case stateUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .message(let value):
            return value
        case .unsupportedTool(let name):
            return "unsupportedTool(\(name))"
        case .invalidArguments(let message):
            return "invalidArguments(\(message))"
        case .appNotFound(let app):
            return "appNotFound(\(app))"
        case .permissionDenied(let message):
            return message
        case .stateUnavailable(let message):
            return message
        }
    }
}

extension ComputerUseError {
    static func missingArgument(_ name: String) -> ComputerUseError {
        .invalidArguments("missing argument '\(name)'")
    }
}
