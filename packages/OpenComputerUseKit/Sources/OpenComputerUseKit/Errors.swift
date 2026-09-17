import Foundation

let computerUseNoWindowFoundMessage = "Apple event error -10005: cgWindowNotFound"

/// Official-shaped `-10005` error text plus an actionable hint.
///
/// `.readOnly` (the default) must not change the user's foreground focus, so the
/// message explains how to make the window reachable and how to opt in to the
/// legacy unhide/activate recovery.
func computerUseWindowNotFoundMessage(recoveryPolicy: SnapshotRecoveryPolicy) -> String {
    let hint = "The target app has no window on the current Space, or its window is minimized. Move the window to the current Space (or unminimize it), then retry."

    switch recoveryPolicy {
    case .readOnly:
        return "\(computerUseNoWindowFoundMessage). \(hint) Window recovery is opt-in: pass allow_window_recovery=true, or set OPEN_COMPUTER_USE_ALLOW_WINDOW_RECOVERY=1 to let Open Computer Use unhide and activate the app."
    case .allowActivation:
        return "\(computerUseNoWindowFoundMessage). \(hint)"
    }
}

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
            return "unsupportedTool(\"\(name)\")"
        case .invalidArguments(let message):
            return "invalidArguments(\"\(message)\")"
        case .appNotFound(let app):
            return "appNotFound(\"\(app)\")"
        case .permissionDenied(let message):
            return message
        case .stateUnavailable(let message):
            return message
        }
    }

    var toolResultIsError: Bool {
        true
    }
}

extension ComputerUseError {
    static func missingArgument(_ name: String) -> ComputerUseError {
        .message("Missing required argument: \(name)")
    }
}
