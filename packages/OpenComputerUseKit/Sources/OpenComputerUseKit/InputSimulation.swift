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
    static let maxKeyboardUnicodeChunkLength = 64

    static func prepareAppForGlobalPointerInput(_ app: RunningAppDescriptor) {
        if raiseAppWindowViaAccessibility(pid: app.pid) {
            Thread.sleep(forTimeInterval: 0.12)
            return
        }

        _ = app.runningApplication.activate(options: [.activateAllWindows])
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

    static func clickTargeted(at point: CGPoint, button: MouseButtonKind, clickCount: Int, pid: pid_t) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw ComputerUseError.message("Failed to create targeted event source.")
        }

        for _ in 0..<max(clickCount, 1) {
            try postMouseEventToPid(type: .mouseMoved, source: source, point: point, button: button.cgButton, clickState: clickCount, pid: pid)
            try postMouseEventToPid(type: button.downEvent, source: source, point: point, button: button.cgButton, clickState: clickCount, pid: pid)
            try postMouseEventToPid(type: button.upEvent, source: source, point: point, button: button.cgButton, clickState: clickCount, pid: pid)
        }
    }

    static func scrollTargeted(at point: CGPoint, direction: String, pages: Double, pid: pid_t) throws {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: wheel1(direction: direction, pages: pages), wheel2: wheel2(direction: direction, pages: pages), wheel3: 0) else {
            throw ComputerUseError.message("Failed to create scroll event.")
        }

        event.location = point
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.1)
    }

    static func scrollGlobally(at point: CGPoint, direction: String, pages: Double) throws {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: wheel1(direction: direction, pages: pages), wheel2: wheel2(direction: direction, pages: pages), wheel3: 0) else {
            throw ComputerUseError.message("Failed to create scroll event.")
        }

        event.location = point
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    static func dragTargeted(from start: CGPoint, to end: CGPoint, pid: pid_t) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw ComputerUseError.message("Failed to create targeted event source.")
        }

        try postMouseEventToPid(type: .mouseMoved, source: source, point: start, button: .left, clickState: 1, pid: pid)
        try postMouseEventToPid(type: .leftMouseDown, source: source, point: start, button: .left, clickState: 1, pid: pid)

        for step in 1...10 {
            let progress = CGFloat(step) / 10
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )
            try postMouseEventToPid(type: .leftMouseDragged, source: source, point: point, button: .left, clickState: 1, pid: pid)
        }

        try postMouseEventToPid(type: .leftMouseUp, source: source, point: end, button: .left, clickState: 1, pid: pid)
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
        for chunk in keyboardUnicodeChunks(for: text) {
            var mutableChunk = chunk
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw ComputerUseError.message("Failed to create keyboard event.")
            }

            mutableChunk.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return
                }

                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            down.postToPid(pid)
            up.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    static func keyboardUnicodeChunks(for text: String, maxUTF16Units: Int = maxKeyboardUnicodeChunkLength) -> [[UniChar]] {
        precondition(maxUTF16Units > 0, "maxUTF16Units must be positive")

        var chunks: [[UniChar]] = []
        var current: [UniChar] = []

        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > maxUTF16Units {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }

            current.append(contentsOf: units)
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
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

    private static func postMouseEventToPid(type: CGEventType, source: CGEventSource, point: CGPoint, button: CGMouseButton, clickState: Int, pid: pid_t) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            throw ComputerUseError.message("Failed to create mouse event \(type.rawValue).")
        }

        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.03)
    }

    private static func raiseAppWindowViaAccessibility(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = preferredWindow(for: appElement) else {
            return false
        }

        if performAction(named: kAXRaiseAction as String, on: window) {
            return true
        }

        if setBoolAttribute(named: kAXMainAttribute as String, on: window) {
            return true
        }

        if setBoolAttribute(named: kAXFocusedAttribute as String, on: window) {
            return true
        }

        return false
    }

    private static func preferredWindow(for appElement: AXUIElement) -> AXUIElement? {
        copyElement(appElement, attribute: kAXFocusedWindowAttribute)
            ?? copyArray(appElement, attribute: kAXWindowsAttribute)?.first
    }

    private static func performAction(named action: String, on element: AXUIElement) -> Bool {
        guard availableActions(for: element).contains(where: { $0.caseInsensitiveCompare(action) == .orderedSame }) else {
            return false
        }

        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    private static func setBoolAttribute(named attribute: String, on element: AXUIElement) -> Bool {
        guard isSettable(element: element, attribute: attribute) else {
            return false
        }

        return AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue) == .success
    }

    private static func isSettable(element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private static func availableActions(for element: AXUIElement) -> [String] {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success, let actions else {
            return []
        }

        return actions as? [String] ?? []
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func copyArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private static func wheel1(direction: String, pages: Double) -> Int32 {
        switch direction {
        case "up":
            return scrollWheelDelta(for: pages)
        case "down":
            return -scrollWheelDelta(for: pages)
        default:
            return 0
        }
    }

    private static func wheel2(direction: String, pages: Double) -> Int32 {
        switch direction {
        case "left":
            return scrollWheelDelta(for: pages)
        case "right":
            return -scrollWheelDelta(for: pages)
        default:
            return 0
        }
    }

    private static func scrollWheelDelta(for pages: Double) -> Int32 {
        let rawValue = (12.0 * pages).rounded(.toNearestOrAwayFromZero)
        let clamped = min(Double(Int32.max), max(1, rawValue))
        return Int32(clamped)
    }
}
