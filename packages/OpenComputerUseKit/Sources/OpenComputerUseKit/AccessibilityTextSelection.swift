import ApplicationServices
import Foundation

/// AX range access shared by the service and isolated real-widget tests.
enum AccessibilityTextSelection {
    static func readRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    static func writeRange(_ range: CFRange, to element: AXUIElement) throws {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else {
            throw ComputerUseError.message("select_text could not create an accessibility range")
        }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        guard result == .success else {
            throw ComputerUseError.message("select_text range write failed with \(result.rawValue)")
        }
    }
}

/// Verify the requested effect even when full action read-back is disabled.
/// Closures allow race/refusal tests without modifying a real application's state.
func applyVerifiedTextSelection(
    target: TextSelectionTarget,
    originalValue: String,
    validate: () throws -> Void,
    readValue: () -> String?,
    writeRange: (CFRange) throws -> Void,
    readRange: () -> CFRange?
) throws {
    func requireUnchangedText() throws {
        guard let current = readValue(), current.utf16.elementsEqual(originalValue.utf16) else {
            throw ComputerUseError.stateUnavailable("select_text text changed or became unreadable; refresh app state and retry")
        }
    }
    try validate()
    try requireUnchangedText()
    try writeRange(CFRange(location: target.location, length: target.length))
    try validate()
    guard let applied = readRange(), applied.location == target.location, applied.length == target.length else {
        throw ComputerUseError.message("select_text could not verify the requested range; the app may not support accessibility selection")
    }
    try requireUnchangedText()
    try validate()
}
