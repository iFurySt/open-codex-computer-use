import Carbon.HIToolbox
import CoreGraphics
import Foundation

public struct ParsedKeyPress: Sendable {
    public struct Modifier: Sendable {
        public let flag: CGEventFlags
        public let keyCode: CGKeyCode
    }

    public let keyCode: CGKeyCode
    public let modifiers: [Modifier]
    public let displayValue: String
}

public enum KeyPressParser {
    public static func parse(_ specification: String) throws -> ParsedKeyPress {
        let tokens = specification
            .split(separator: "+")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        guard let keyToken = tokens.last else {
            throw ComputerUseError.invalidArguments("key specification is empty")
        }

        let modifiers = try tokens.dropLast().map(parseModifier(_:))
        guard let keyCode = keyCodeMap[keyToken] else {
            throw ComputerUseError.invalidArguments("unsupported key '\(specification)'")
        }

        return ParsedKeyPress(
            keyCode: keyCode,
            modifiers: modifiers,
            displayValue: keyToken
        )
    }

    private static func parseModifier(_ token: String) throws -> ParsedKeyPress.Modifier {
        switch token {
        case "cmd", "command", "super", "meta":
            return ParsedKeyPress.Modifier(flag: .maskCommand, keyCode: CGKeyCode(kVK_Command))
        case "shift":
            return ParsedKeyPress.Modifier(flag: .maskShift, keyCode: CGKeyCode(kVK_Shift))
        case "option", "alt":
            return ParsedKeyPress.Modifier(flag: .maskAlternate, keyCode: CGKeyCode(kVK_Option))
        case "control", "ctrl":
            return ParsedKeyPress.Modifier(flag: .maskControl, keyCode: CGKeyCode(kVK_Control))
        default:
            throw ComputerUseError.invalidArguments("unsupported modifier '\(token)'")
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static let keyCodeMap: [String: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        "return": CGKeyCode(kVK_Return),
        "enter": CGKeyCode(kVK_Return),
        "tab": CGKeyCode(kVK_Tab),
        "space": CGKeyCode(kVK_Space),
        "spacebar": CGKeyCode(kVK_Space),
        "escape": CGKeyCode(kVK_Escape),
        "esc": CGKeyCode(kVK_Escape),
        "delete": CGKeyCode(kVK_Delete),
        "forwarddelete": CGKeyCode(kVK_ForwardDelete),
        "up": CGKeyCode(kVK_UpArrow),
        "down": CGKeyCode(kVK_DownArrow),
        "left": CGKeyCode(kVK_LeftArrow),
        "right": CGKeyCode(kVK_RightArrow),
        "home": CGKeyCode(kVK_Home),
        "end": CGKeyCode(kVK_End),
        "pageup": CGKeyCode(kVK_PageUp),
        "pagedown": CGKeyCode(kVK_PageDown),
        "kp_0": CGKeyCode(kVK_ANSI_Keypad0),
    ]
}
