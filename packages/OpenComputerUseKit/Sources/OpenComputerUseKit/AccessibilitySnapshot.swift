import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class ElementRecord {
    let index: Int
    let identifier: String?
    let element: AXUIElement?
    let localFrame: CGRect?
    let rawActions: [String]
    let prettyActions: [String]

    init(index: Int, identifier: String?, element: AXUIElement?, localFrame: CGRect?, rawActions: [String], prettyActions: [String]) {
        self.index = index
        self.identifier = identifier
        self.element = element
        self.localFrame = localFrame
        self.rawActions = rawActions
        self.prettyActions = prettyActions
    }
}

enum SnapshotMode {
    case accessibility
    case fixture
}

public struct AppSnapshot {
    public let app: RunningAppDescriptor
    public let windowTitle: String?
    public let windowBounds: CGRect?
    public let screenshotPath: String?
    public let renderedText: String
    let mode: SnapshotMode

    let elements: [Int: ElementRecord]
}

enum SnapshotBuilder {
    static func build(for app: RunningAppDescriptor) throws -> AppSnapshot {
        if app.name == FixtureBridge.appName, let fixtureState = try FixtureBridge.readState() {
            return buildFixtureSnapshot(app: app, state: fixtureState)
        }

        let permissions = PermissionDiagnostics.current()
        guard permissions.accessibilityTrusted else {
            throw ComputerUseError.permissionDenied("Accessibility permission is required. Run `OpenComputerUse doctor` and grant access to the host terminal or app.")
        }

        let appElement = AXUIElementCreateApplication(app.pid)
        let systemWide = AXUIElementCreateSystemWide()
        let focusedApplication = copyElement(systemWide, attribute: kAXFocusedApplicationAttribute)
        let focusedWindow = preferredFocusedWindow(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        let rootElement = focusedWindow ?? appElement
        let windowTitle = stringValue(of: focusedWindow ?? appElement, attribute: kAXTitleAttribute)

        let windowCapture = WindowCapture.resolve(for: app.pid, titleHint: windowTitle)
        let windowBounds = windowCapture?.bounds
        let screenshotPath = try windowCapture?.writePNGIfAvailable()
        let focusedElement = preferredFocusedElement(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        let context = RenderContext(windowBounds: windowBounds, focusedElement: focusedElement)

        var renderer = TreeRenderer(context: context)
        renderer.render(rootElement)

        var lines: [String] = []
        lines.append("Computer Use state (OpenComputerUse 0.1.0)")
        lines.append(permissions.summary)

        if let screenshotPath {
            lines.append("Screenshot: \(screenshotPath)")
        } else {
            lines.append("Screenshot: unavailable")
        }

        lines.append("<app_state>")
        lines.append("App=\(app.bundleIdentifier ?? app.name) (pid \(app.pid))")

        if let windowBounds {
            lines.append("Window: \(quoted(windowTitle ?? app.name)), Bounds: \(format(rect: windowBounds))")
        }

        lines.append(contentsOf: renderer.lines)
        lines.append("</app_state>")

        if !renderer.identifierIndex.isEmpty {
            lines.append("<element_index>")
            for entry in renderer.identifierIndex.sorted(by: { $0.key < $1.key }) {
                lines.append(entry.value)
            }
            lines.append("</element_index>")
        }

        if let focusedSummary = renderer.focusedSummary {
            lines.append("The focused UI element is \(focusedSummary).")
        }

        return AppSnapshot(
            app: app,
            windowTitle: windowTitle,
            windowBounds: windowBounds,
            screenshotPath: screenshotPath,
            renderedText: lines.joined(separator: "\n"),
            mode: .accessibility,
            elements: renderer.records
        )
    }

    private static func firstWindow(for appElement: AXUIElement) -> AXUIElement? {
        guard let windows = copyArray(appElement, attribute: kAXWindowsAttribute) else {
            return nil
        }

        return windows.first
    }

    private static func preferredFocusedWindow(appElement: AXUIElement, appPID: pid_t, focusedApplication: AXUIElement?, systemWide: AXUIElement) -> AXUIElement? {
        if let focusedApplication, pid(of: focusedApplication) == appPID {
            return copyElement(systemWide, attribute: kAXFocusedWindowAttribute)
                ?? copyElement(focusedApplication, attribute: kAXFocusedWindowAttribute)
                ?? firstWindow(for: focusedApplication)
                ?? copyElement(appElement, attribute: kAXFocusedWindowAttribute)
                ?? firstWindow(for: appElement)
        }

        return copyElement(appElement, attribute: kAXFocusedWindowAttribute) ?? firstWindow(for: appElement)
    }

    private static func preferredFocusedElement(appElement: AXUIElement, appPID: pid_t, focusedApplication: AXUIElement?, systemWide: AXUIElement) -> AXUIElement? {
        if let focusedApplication, pid(of: focusedApplication) == appPID {
            return copyElement(systemWide, attribute: kAXFocusedUIElementAttribute)
                ?? copyElement(focusedApplication, attribute: kAXFocusedUIElementAttribute)
                ?? copyElement(appElement, attribute: kAXFocusedUIElementAttribute)
        }

        return copyElement(appElement, attribute: kAXFocusedUIElementAttribute)
    }

    private static func buildFixtureSnapshot(app: RunningAppDescriptor, state: FixtureAppState) -> AppSnapshot {
        var lines: [String] = []
        lines.append("Computer Use state (OpenComputerUse 0.1.0)")
        lines.append(PermissionDiagnostics.current().summary)
        lines.append("Screenshot: unavailable (fixture synthetic state)")
        lines.append("<app_state>")
        lines.append("App=\(app.name) (pid \(app.pid))")
        lines.append("Window: \"\(state.windowTitle)\", Bounds: \(format(rect: state.windowBounds.cgRect))")

        var records: [Int: ElementRecord] = [:]
        var identifierLines: [String] = []
        let focusedIdentifier = state.focusedIdentifier
        var focusedSummary: String?

        for element in state.elements.sorted(by: { $0.index < $1.index }) {
            let titleSegment = element.title.map { " \($0)" } ?? ""
            let valueSegment = element.value.map { " Value: \($0)" } ?? ""
            let actionsSegment = element.actions.isEmpty ? "" : " Secondary Actions: \(element.actions.joined(separator: ", "))"
            let focusSegment = focusedIdentifier == element.identifier ? " (focused)" : ""
            lines.append("\(String(repeating: "    ", count: element.index == 0 ? 0 : 1))\(element.index) \(element.role)\(titleSegment)\(focusSegment) ID: \(element.identifier)\(valueSegment)\(actionsSegment) Frame: \(element.frame.cgRect.renderedLocalFrame)")

            let record = ElementRecord(
                index: element.index,
                identifier: element.identifier,
                element: nil,
                localFrame: element.frame.cgRect,
                rawActions: element.actions,
                prettyActions: element.actions
            )
            records[element.index] = record
            identifierLines.append("\(element.identifier) -> \(element.index) @ \(element.frame.cgRect.renderedLocalFrame)")

            if focusedIdentifier == element.identifier {
                focusedSummary = "\(element.index) \(element.role)"
            }
        }

        lines.append("</app_state>")
        lines.append("<element_index>")
        lines.append(contentsOf: identifierLines.sorted())
        lines.append("</element_index>")

        if let focusedSummary {
            lines.append("The focused UI element is \(focusedSummary).")
        }

        return AppSnapshot(
            app: app,
            windowTitle: state.windowTitle,
            windowBounds: state.windowBounds.cgRect,
            screenshotPath: nil,
            renderedText: lines.joined(separator: "\n"),
            mode: .fixture,
            elements: records
        )
    }
}

private struct WindowCapture {
    let windowID: CGWindowID
    let bounds: CGRect
    let image: CGImage?

    static func resolve(for pid: pid_t, titleHint: String?) -> WindowCapture? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates = infoList.compactMap { info -> (CGWindowID, CGRect, String?, Int)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let title = info[kCGWindowName as String] as? String
            let area = Int(bounds.width * bounds.height)
            return (CGWindowID(number.uint32Value), bounds, title, area)
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if let titleHint {
                if lhs.2 == titleHint && rhs.2 != titleHint {
                    return true
                }

                if rhs.2 == titleHint && lhs.2 != titleHint {
                    return false
                }
            }

            return lhs.3 > rhs.3
        }).first else {
            return nil
        }

        let image = CGWindowListCreateImage(
            best.1,
            .optionIncludingWindow,
            best.0,
            [.bestResolution, .boundsIgnoreFraming]
        )

        return WindowCapture(windowID: best.0, bounds: best.1, image: image)
    }

    func writePNGIfAvailable() throws -> String? {
        guard let image else {
            return nil
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("open-computer-use", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("window-\(windowID)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        try data.write(to: fileURL)
        return fileURL.path
    }
}

private struct RenderContext {
    let windowBounds: CGRect?
    let focusedElement: AXUIElement?
}

private struct TreeRenderer {
    let context: RenderContext
    var nextIndex = 0
    var lines: [String] = []
    var records: [Int: ElementRecord] = [:]
    var identifierIndex: [String: String] = [:]
    var focusedSummary: String?
    private var visited: Set<String> = []

    init(context: RenderContext) {
        self.context = context
    }

    mutating func render(_ root: AXUIElement, depth: Int = 0) {
        guard nextIndex < 500, depth < 16 else {
            return
        }

        let identifier = opaqueIdentifier(for: root)
        guard visited.insert(identifier).inserted else {
            return
        }

        let index = nextIndex
        nextIndex += 1

        let role = stringValue(of: root, attribute: kAXRoleAttribute) ?? "AXUnknown"
        let subrole = stringValue(of: root, attribute: kAXSubroleAttribute)
        let title = stringValue(of: root, attribute: kAXTitleAttribute)
        let label = stringValue(of: root, attribute: kAXDescriptionAttribute)
        let value = sanitizedValue(of: root)
        let axIdentifier = stringValue(of: root, attribute: kAXIdentifierAttribute)
        let traits = summarizeTraits(of: root)
        let actions = copyActions(root) ?? []
        let prettyActions = actions
            .filter { $0 != kAXPressAction as String }
            .map(prettyActionName(_:))
        let localFrame = resolveLocalFrame(of: root, windowBounds: context.windowBounds)

        let roleText = humanizeRole(role: role, subrole: subrole)
        let titleSegment = title.map { " \($0)" } ?? ""
        let traitsSegment = traits.isEmpty ? "" : " (\(traits.joined(separator: ", ")))"
        let labelSegment = label.map { " Description: \($0)" } ?? ""
        let identifierSegment = axIdentifier.map { " ID: \($0)" } ?? ""
        let valueSegment = value.map { " Value: \($0)" } ?? ""
        let actionsSegment = prettyActions.isEmpty ? "" : " Secondary Actions: \(prettyActions.joined(separator: ", "))"
        let frameSegment = localFrame.map { " Frame: \($0.renderedLocalFrame)" } ?? ""

        lines.append("\(String(repeating: "    ", count: depth))\(index) \(roleText)\(titleSegment)\(traitsSegment)\(labelSegment)\(identifierSegment)\(valueSegment)\(actionsSegment)\(frameSegment)")

        let record = ElementRecord(
            index: index,
            identifier: axIdentifier,
            element: root,
            localFrame: localFrame,
            rawActions: actions,
            prettyActions: prettyActions
        )
        records[index] = record

        if let axIdentifier, let localFrame {
            identifierIndex[axIdentifier] = "\(axIdentifier) -> \(index) @ \(localFrame.renderedLocalFrame)"
        }

        if let focusedElement = context.focusedElement, CFEqual(focusedElement, root) {
            focusedSummary = "\(index) \(roleText)"
        }

        for child in children(of: root) {
            render(child, depth: depth + 1)
        }
    }

    private func opaqueIdentifier(for element: AXUIElement) -> String {
        String(CFHash(element))
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        let attributes = [kAXChildrenAttribute, kAXRowsAttribute]
        var children: [AXUIElement] = []
        var seen: Set<String> = []

        for attribute in attributes {
            guard let values = copyArray(element, attribute: attribute) else {
                continue
            }

            for child in values {
                let id = opaqueIdentifier(for: child)
                if seen.insert(id).inserted {
                    children.append(child)
                }
            }
        }

        return children
    }
}

private func summarizeTraits(of element: AXUIElement) -> [String] {
    var values: [String] = []

    if boolValue(of: element, attribute: kAXFocusedAttribute) == true {
        values.append("focused")
    }

    if boolValue(of: element, attribute: kAXSelectedAttribute) == true {
        values.append("selected")
    }

    if boolValue(of: element, attribute: kAXExpandedAttribute) == true {
        values.append("expanded")
    }

    if isSettable(of: element, attribute: kAXValueAttribute) {
        values.append("settable")
    }

    if let role = stringValue(of: element, attribute: kAXRoleAttribute), role == kAXTextFieldRole as String {
        values.append("string")
    }

    return values
}

private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    return (value as! AXUIElement)
}

private func copyArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    return value as? [AXUIElement]
}

private func copyActions(_ element: AXUIElement) -> [String]? {
    var actions: CFArray?
    let error = AXUIElementCopyActionNames(element, &actions)
    guard error == .success else {
        return nil
    }

    return actions as? [String]
}

private func stringValue(of element: AXUIElement, attribute: String) -> String? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        return value as? String
    }

    return nil
}

private func boolValue(of element: AXUIElement, attribute: String) -> Bool? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    return value as? Bool
}

private func pid(of element: AXUIElement) -> pid_t {
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    return processIdentifier
}

private func isSettable(of element: AXUIElement, attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
    return error == .success && settable.boolValue
}

private func sanitizedValue(of element: AXUIElement) -> String? {
    if let string = stringValue(of: element, attribute: kAXValueAttribute) {
        return sanitizeText(string)
    }

    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    return nil
}

private func resolveLocalFrame(of element: AXUIElement, windowBounds: CGRect?) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    let positionError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
    let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    guard
        positionError == .success,
        sizeError == .success,
        let positionValue,
        let sizeValue
    else {
        return nil
    }

    let positionAXValue = positionValue as! AXValue
    let sizeAXValue = sizeValue as! AXValue
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionAXValue, .cgPoint, &position), AXValueGetValue(sizeAXValue, .cgSize, &size) else {
        return nil
    }

    let frame = CGRect(origin: position, size: size)

    guard let windowBounds else {
        return frame
    }

    return windowRelativeFrame(elementFrame: frame, windowBounds: windowBounds)
}

func windowRelativeFrame(elementFrame: CGRect, windowBounds: CGRect) -> CGRect {
    CGRect(
        x: elementFrame.minX - windowBounds.minX,
        y: elementFrame.minY - windowBounds.minY,
        width: elementFrame.width,
        height: elementFrame.height
    )
}

private func humanizeRole(role: String, subrole: String?) -> String {
    if let subrole, subrole == kAXStandardWindowSubrole as String {
        return "standard window"
    }

    return humanizeAXToken(role)
}

private func prettyActionName(_ value: String) -> String {
    let stripped = value.hasPrefix("AX") ? String(value.dropFirst(2)) : value
    let withoutPage = stripped.replacingOccurrences(of: "ByPage", with: "")
    return splitCamelCase(withoutPage)
}

private func humanizeAXToken(_ value: String) -> String {
    let stripped = value.hasPrefix("AX") ? String(value.dropFirst(2)) : value
    return splitCamelCase(stripped).lowercased()
}

private func splitCamelCase(_ value: String) -> String {
    var result = ""
    for character in value {
        if character.isUppercase, !result.isEmpty {
            result.append(" ")
        }
        result.append(character)
    }
    return result
}

private func sanitizeText(_ value: String) -> String {
    let collapsed = value
        .replacingOccurrences(of: "\n", with: "\\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if collapsed.count > 160 {
        return String(collapsed.prefix(160)) + "..."
    }

    return collapsed
}

private func quoted(_ value: String) -> String {
    "\"\(value)\""
}

private func format(rect: CGRect) -> String {
    "x=\(Int(rect.origin.x)), y=\(Int(rect.origin.y)), w=\(Int(rect.width)), h=\(Int(rect.height))"
}

private extension CGRect {
    var renderedLocalFrame: String {
        "x=\(Int(origin.x)), y=\(Int(origin.y)), w=\(Int(width)), h=\(Int(height))"
    }
}
