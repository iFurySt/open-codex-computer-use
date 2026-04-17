import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum MouseButtonKind: String {
    case left
    case right
    case middle

    var cgButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }

    var downEvent: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .middle:
            return .otherMouseDown
        }
    }

    var upEvent: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .middle:
            return .otherMouseUp
        }
    }
}

enum InputSimulation {
    static func bringAppToFrontForGlobalPointerInput(_ app: RunningAppDescriptor) {
        app.runningApplication.activate()
        Thread.sleep(forTimeInterval: 0.25)
    }

    static func clickGlobally(at point: CGPoint, button: MouseButtonKind, clickCount: Int) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ComputerUseError.message("Failed to create HID event source.")
        }

        for _ in 0..<max(clickCount, 1) {
            try postMouseEvent(type: .mouseMoved, source: source, point: point, button: button.cgButton, clickState: clickCount)
            try postMouseEvent(type: button.downEvent, source: source, point: point, button: button.cgButton, clickState: clickCount)
            try postMouseEvent(type: button.upEvent, source: source, point: point, button: button.cgButton, clickState: clickCount)
        }
    }

    static func scrollGlobally(at point: CGPoint, direction: String, pages: Int) throws {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: wheel1(direction: direction, pages: pages), wheel2: wheel2(direction: direction, pages: pages), wheel3: 0) else {
            throw ComputerUseError.message("Failed to create scroll event.")
        }

        event.location = point
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    static func dragGlobally(from start: CGPoint, to end: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ComputerUseError.message("Failed to create HID event source.")
        }

        try postMouseEvent(type: .mouseMoved, source: source, point: start, button: .left, clickState: 1)
        try postMouseEvent(type: .leftMouseDown, source: source, point: start, button: .left, clickState: 1)

        for step in 1...10 {
            let progress = CGFloat(step) / 10
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )
            try postMouseEvent(type: .leftMouseDragged, source: source, point: point, button: .left, clickState: 1)
        }

        try postMouseEvent(type: .leftMouseUp, source: source, point: end, button: .left, clickState: 1)
    }

    static func typeText(_ text: String, pid: pid_t) throws {
        for character in text.utf16 {
            var mutableCharacter = character
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw ComputerUseError.message("Failed to create keyboard event.")
            }

            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutableCharacter)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutableCharacter)
            down.postToPid(pid)
            up.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    static func pressKey(_ specification: String, pid: pid_t) throws {
        let parsed = try KeyPressParser.parse(specification)
        var activeFlags: CGEventFlags = []

        for modifier in parsed.modifiers {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: modifier.keyCode, keyDown: true) else {
                throw ComputerUseError.message("Failed to create modifier key down event.")
            }

            activeFlags.insert(modifier.flag)
            event.flags = activeFlags
            event.postToPid(pid)
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: false) else {
            throw ComputerUseError.message("Failed to create key event.")
        }

        keyDown.flags = activeFlags
        keyUp.flags = activeFlags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)

        for modifier in parsed.modifiers.reversed() {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: modifier.keyCode, keyDown: false) else {
                throw ComputerUseError.message("Failed to create modifier key up event.")
            }

            event.flags = activeFlags
            event.postToPid(pid)
            activeFlags.remove(modifier.flag)
        }

        Thread.sleep(forTimeInterval: 0.1)
    }

    private static func postMouseEvent(type: CGEventType, source: CGEventSource, point: CGPoint, button: CGMouseButton, clickState: Int) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            throw ComputerUseError.message("Failed to create mouse event \(type.rawValue).")
        }

        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.03)
    }

    private static func wheel1(direction: String, pages: Int) -> Int32 {
        switch direction {
        case "up":
            return Int32(12 * max(pages, 1))
        case "down":
            return Int32(-12 * max(pages, 1))
        default:
            return 0
        }
    }

    private static func wheel2(direction: String, pages: Int) -> Int32 {
        switch direction {
        case "left":
            return Int32(12 * max(pages, 1))
        case "right":
            return Int32(-12 * max(pages, 1))
        default:
            return 0
        }
    }
}
