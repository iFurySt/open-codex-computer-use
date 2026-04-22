import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
    let targetWindowID: CGWindowID?
    let targetWindowLayer: Int?
    public let screenshotPNGData: Data?
    let mode: SnapshotMode
    let treeLines: [String]
    let focusedSummary: String?
    let selectedText: String?

    let elements: [Int: ElementRecord]

    public var renderedText: String {
        renderedText(style: .fullState)
    }

    public func renderedText(style: SnapshotTextStyle) -> String {
        var lines: [String] = []
        let displayTitle = displayWindowTitle(windowTitle, appName: app.name)
        let appReference = app.bundleIdentifier ?? app.name

        lines.append("App=\(appReference) (pid \(app.pid))")
        lines.append("Window: \(quoted(displayTitle)), App: \(app.name).")
        lines.append(contentsOf: treeLines)

        if let selectedText, !selectedText.isEmpty {
            lines.append("")
            lines.append("Selected text: [\(selectedText)]")
        } else if let focusedSummary {
            lines.append("")
            lines.append("The focused UI element is \(focusedSummary).")
        }

        return lines.joined(separator: "\n")
    }
}

public enum SnapshotTextStyle {
    case fullState
    case actionResult
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
        let screenshotPNGData = windowCapture?.pngDataIfAvailable()
        let focusedElement = preferredFocusedElement(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        let selectedText = focusedElement.flatMap(copySelectedText(_:))
        let context = RenderContext(windowBounds: windowBounds, focusedElement: focusedElement)

        var renderer = TreeRenderer(context: context)
        renderer.render(rootElement)

        return AppSnapshot(
            app: app,
            windowTitle: windowTitle,
            windowBounds: windowBounds,
            targetWindowID: windowCapture?.windowID,
            targetWindowLayer: windowCapture?.layer,
            screenshotPNGData: screenshotPNGData,
            mode: .accessibility,
            treeLines: renderer.lines,
            focusedSummary: renderer.focusedSummary,
            selectedText: selectedText,
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

        var records: [Int: ElementRecord] = [:]
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

            if focusedIdentifier == element.identifier {
                focusedSummary = "\(element.index) \(element.role)"
            }
        }

        return AppSnapshot(
            app: app,
            windowTitle: state.windowTitle,
            windowBounds: state.windowBounds.cgRect,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .fixture,
            treeLines: lines,
            focusedSummary: focusedSummary,
            selectedText: nil,
            elements: records
        )
    }
}

private struct WindowCapture {
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
    let image: CGImage?

    static func resolve(for pid: pid_t, titleHint: String?) -> WindowCapture? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates = infoList.compactMap { info -> (CGWindowID, Int, CGRect, String?, Int)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? Int,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let title = info[kCGWindowName as String] as? String
            let area = Int(bounds.width * bounds.height)
            return (CGWindowID(number.uint32Value), layer, bounds, title, area)
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if let titleHint {
                if lhs.3 == titleHint && rhs.3 != titleHint {
                    return true
                }

                if rhs.3 == titleHint && lhs.3 != titleHint {
                    return false
                }
            }

            return lhs.4 > rhs.4
        }).first else {
            return nil
        }

        let image = captureImage(windowID: best.0, bounds: best.2)

        return WindowCapture(windowID: best.0, layer: best.1, bounds: best.2, image: image)
    }

    private static func captureImage(windowID: CGWindowID, bounds: CGRect) -> CGImage? {
        try? BlockingAsyncBridge.run {
            let shareableContent = try await SCShareableContent.current
            guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let scaleFactor = bestEffortScaleFactor(for: bounds)
            let captureSize = window.frame.isEmpty ? bounds.size : window.frame.size
            configuration.width = max(1, Int(ceil(captureSize.width * scaleFactor)))
            configuration.height = max(1, Int(ceil(captureSize.height * scaleFactor)))
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: window)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    private static func bestEffortScaleFactor(for bounds: CGRect) -> CGFloat {
        NSScreen.screens.first(where: { $0.frame.intersects(bounds) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
    }

    func pngDataIfAvailable() -> Data? {
        guard let image else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }
}

private final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private enum BlockingAsyncBridge {
    static func run<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = AsyncResultBox<T>()

        Task.detached {
            do {
                resultBox.result = .success(try await operation())
            } catch {
                resultBox.result = .failure(error)
            }

            semaphore.signal()
        }

        waitForSignal(semaphore)
        return try resultBox.result?.get() ?? {
            throw ComputerUseError.message("ScreenCaptureKit screenshot task finished without producing a result.")
        }()
    }

    private static func waitForSignal(_ semaphore: DispatchSemaphore) {
        if Thread.isMainThread {
            while semaphore.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            return
        }

        semaphore.wait()
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

        let role = stringValue(of: root, attribute: kAXRoleAttribute) ?? "AXUnknown"
        let subrole = stringValue(of: root, attribute: kAXSubroleAttribute)
        let baseRoleText = roleDescription(of: root, role: role, subrole: subrole)
        let label = stringValue(of: root, attribute: kAXDescriptionAttribute)
        let help = stringValue(of: root, attribute: kAXHelpAttribute)
        let value = sanitizedValue(of: root)
        let axIdentifier = displayIdentifier(stringValue(of: root, attribute: kAXIdentifierAttribute))
        let traits = summarizeTraits(of: root)
        let actions = copyActions(root) ?? []
        let prettyActions = meaningfulActions(actions, role: role)
        let localFrame = resolveLocalFrame(of: root, windowBounds: context.windowBounds)
        let rowTexts = role == kAXRowRole as String ? flattenedRowTexts(of: root) : []
        let childElements = children(of: root)
        let title = preferredDisplayTitle(
            for: root,
            role: role,
            label: label,
            identifier: axIdentifier,
            explicitValue: value,
            rowTexts: rowTexts
        )
        let inlineRowSummary = outlineRowSummary(for: root, role: role)
        let hidesChildren = shouldSuppressChildren(
            role: role,
            title: title,
            label: label,
            help: help,
            value: value,
            identifier: axIdentifier,
            traits: traits,
            actions: prettyActions,
            children: childElements
        )
        let roleText = displayRoleText(
            baseRoleText: baseRoleText,
            role: role,
            title: title,
            label: label,
            suppressChildren: hidesChildren
        )

        if shouldElideNode(role: role, title: title, label: label, value: value, identifier: axIdentifier, traits: traits, actions: prettyActions, childCount: childElements.count) {
            for child in childElements {
                render(child, depth: depth)
            }
            return
        }

        nextIndex += 1

        let traitsSegment = traits.isEmpty ? "" : " (\(traits.joined(separator: ", ")))"
        let titleSegment = title.map { " \($0)" } ?? ""
        let rowSummarySegment = inlineRowSummary.map { " \($0)" } ?? ""
        let labelSegment = label != nil && label != title ? " Description: \(label!)" : ""
        let helpSegment = {
            guard let help else {
                return ""
            }
            if help == title || help == label {
                return ""
            }
            return ", Help: \(help)"
        }()
        let identifierSegment = displayIdentifierSegment(for: root, role: role, identifier: axIdentifier, title: title)
        let valueSegment = formattedValueSegment(for: root, roleText: roleText, title: title, value: value)
        let actionsPrefix = (title != nil || inlineRowSummary != nil) ? ", Secondary Actions: " : " Secondary Actions: "
        let actionsSegment = prettyActions.isEmpty ? "" : "\(actionsPrefix)\(prettyActions.joined(separator: ", "))"
        let linePrefix = roleText.isEmpty ? "\(index)" : "\(index) \(roleText)"

        lines.append("\(String(repeating: "\t", count: depth + 1))\(linePrefix)\(traitsSegment)\(titleSegment)\(rowSummarySegment)\(labelSegment)\(helpSegment)\(identifierSegment)\(valueSegment)\(actionsSegment)")

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
            focusedSummary = roleText.isEmpty ? "\(index)" : "\(index) \(roleText)"
        }

        if role == kAXRowRole as String, boolValue(of: root, attribute: kAXSelectedAttribute) != true {
            for text in Array(rowTexts.dropFirst()) {
                lines.append(text)
            }
            return
        }

        if hidesChildren {
            return
        }

        for child in childElements {
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
            guard let sourceValues = copyArray(element, attribute: attribute) else {
                continue
            }

            if attribute == kAXChildrenAttribute,
               let rows = copyArray(element, attribute: kAXRowsAttribute),
               !rows.isEmpty
            {
                continue
            }

            let values = attribute == kAXRowsAttribute
                ? visibleRows(in: sourceValues, parent: element)
                : sourceValues

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

    if let selected = boolValue(of: element, attribute: kAXSelectedAttribute) {
        values.append(selected ? "selected" : "selectable")
    }

    if let expanded = boolValue(of: element, attribute: kAXExpandedAttribute) {
        values.append(expanded ? "expanded" : "collapsed")
    }

    if boolValue(of: element, attribute: kAXEnabledAttribute) == false {
        values.append("disabled")
    }

    if isSettable(of: element, attribute: kAXValueAttribute) {
        values.append("settable")
    }

    if let valueType = valueTypeTrait(of: element) {
        values.append(valueType)
    }

    return values
}

private func valueTypeTrait(of element: AXUIElement) -> String? {
    guard isSettable(of: element, attribute: kAXValueAttribute) else {
        return nil
    }

    guard let value = attributeValue(of: element, attribute: kAXValueAttribute) else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        return "string"
    }

    if value is NSNumber {
        return "float"
    }

    return nil
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

private func attributeValue(of element: AXUIElement, attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
        return nil
    }

    return value
}

private func stringValue(of element: AXUIElement, attribute: String) -> String? {
    guard let value = attributeValue(of: element, attribute: attribute) else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        return value as? String
    }

    return nil
}

private func copySelectedText(_ element: AXUIElement) -> String? {
    guard let value = stringValue(of: element, attribute: kAXSelectedTextAttribute) else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func boolValue(of element: AXUIElement, attribute: String) -> Bool? {
    guard let value = attributeValue(of: element, attribute: attribute) else {
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

    guard let value = attributeValue(of: element, attribute: kAXValueAttribute) else {
        return nil
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    return nil
}

private func preferredDisplayTitle(
    for element: AXUIElement,
    role: String,
    label: String?,
    identifier: String?,
    explicitValue: String?,
    rowTexts: [String]
) -> String? {
    if let title = stringValue(of: element, attribute: kAXTitleAttribute), !title.isEmpty {
        return sanitizeText(title)
    }

    if role == kAXRowRole as String {
        return rowTexts.first
    }

    if (role == kAXOutlineRole as String || role == kAXListRole as String), let identifier {
        return identifier
    }

    if (role == kAXButtonRole as String || role == kAXPopUpButtonRole as String), let label, !label.isEmpty {
        return sanitizeText(label)
    }

    guard roleDescription(of: element, role: role, subrole: stringValue(of: element, attribute: kAXSubroleAttribute)) == "search text field" else {
        return nil
    }

    return explicitValue
}

private func outlineRowSummary(for element: AXUIElement, role: String) -> String? {
    guard role == kAXOutlineRole as String || role == kAXListRole as String else {
        return nil
    }

    guard let allRows = copyArray(element, attribute: kAXRowsAttribute), !allRows.isEmpty else {
        return nil
    }

    let visibleRows = visibleRows(in: allRows, parent: element)
    guard !visibleRows.isEmpty, visibleRows.count < allRows.count else {
        return nil
    }

    return "(showing 0-\(visibleRows.count - 1) of \(allRows.count) items)"
}

private func formattedValueSegment(for element: AXUIElement, roleText: String, title: String?, value: String?) -> String {
    guard let value, !value.isEmpty else {
        return ""
    }

    if roleText == "search text field", title == value {
        return ""
    }

    if title == nil, let role = stringValue(of: element, attribute: kAXRoleAttribute), role == kAXStaticTextRole as String {
        return " \(value)"
    }

    if ["scroll bar", "value indicator"].contains(roleText) {
        return " \(value)"
    }

    return " Value: \(value)"
}

private func displayIdentifierSegment(for element: AXUIElement, role: String, identifier: String?, title: String?) -> String {
    guard let identifier else {
        return ""
    }

    if (role == kAXOutlineRole as String || role == kAXListRole as String), title == identifier {
        return ""
    }

    return " ID: \(identifier)"
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

private func shouldElideNode(
    role: String,
    title: String?,
    label: String?,
    value: String?,
    identifier: String?,
    traits: [String],
    actions: [String],
    childCount: Int
) -> Bool {
    guard childCount == 1 else {
        return false
    }

    let genericRoles = [kAXGroupRole as String, kAXUnknownRole as String]
    guard genericRoles.contains(role) else {
        return false
    }

    return title == nil
        && label == nil
        && value == nil
        && identifier == nil
        && traits.isEmpty
        && actions.isEmpty
}

private func shouldSuppressChildren(
    role: String,
    title: String?,
    label: String?,
    help: String?,
    value: String?,
    identifier: String?,
    traits: [String],
    actions: [String],
    children: [AXUIElement]
) -> Bool {
    guard role == kAXGroupRole as String else {
        return false
    }

    guard
        title == nil,
        label == nil,
        help == nil,
        value == nil,
        identifier == nil,
        traits.isEmpty,
        actions.isEmpty,
        !children.isEmpty
    else {
        return false
    }

    return children.allSatisfy { child in
        stringValue(of: child, attribute: kAXRoleAttribute) == kAXStaticTextRole as String
    }
}

private func displayRoleText(
    baseRoleText: String,
    role: String,
    title: String?,
    label: String?,
    suppressChildren: Bool
) -> String {
    if suppressChildren {
        return "container"
    }

    if baseRoleText == "radio group", role == kAXRadioGroupRole as String, title == nil, label != nil {
        return ""
    }

    return baseRoleText
}

func windowRelativeFrame(elementFrame: CGRect, windowBounds: CGRect) -> CGRect {
    CGRect(
        x: elementFrame.minX - windowBounds.minX,
        y: elementFrame.minY - windowBounds.minY,
        width: elementFrame.width,
        height: elementFrame.height
    )
}

private func roleDescription(of element: AXUIElement, role: String, subrole: String?) -> String {
    if role == kAXRowRole as String {
        return "row"
    }

    if let roleDescription = stringValue(of: element, attribute: kAXRoleDescriptionAttribute), !roleDescription.isEmpty {
        return roleDescription.lowercased()
    }

    if let subrole, subrole == kAXStandardWindowSubrole as String {
        return "standard window"
    }

    return humanizeAXToken(role)
}

private func meaningfulActions(_ values: [String], role: String) -> [String] {
    values
        .filter {
            ![
                kAXPressAction as String,
                "AXShowDefaultUI",
                "AXShowAlternateUI",
                "AXShowMenu",
                "AXConfirm",
            ].contains($0)
        }
        .filter {
            guard role == kAXScrollAreaRole as String else {
                return true
            }

            if values.contains("AXScrollUpByPage") || values.contains("AXScrollDownByPage") {
                return $0 != "AXScrollLeftByPage" && $0 != "AXScrollRightByPage"
            }

            return true
        }
        .map(prettyActionName(_:))
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

private func flattenedRowTexts(of element: AXUIElement) -> [String] {
    let cells = copyArray(element, attribute: kAXChildrenAttribute) ?? []
    let texts = cells
        .flatMap { descendantTexts(of: $0) }
        .map(sanitizeText)
        .filter { !$0.isEmpty }

    var unique: [String] = []
    var seen: Set<String> = []
    for text in texts {
        if seen.insert(text).inserted {
            unique.append(text)
        }
    }

    return unique
}

private func descendantTexts(of element: AXUIElement, depth: Int = 0) -> [String] {
    guard depth < 4 else {
        return []
    }

    var values: [String] = []
    let role = stringValue(of: element, attribute: kAXRoleAttribute) ?? ""
    if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
        if let value = sanitizedValue(of: element) {
            values.append(value)
        } else if let title = stringValue(of: element, attribute: kAXTitleAttribute) {
            values.append(sanitizeText(title))
        }
    }

    for child in copyArray(element, attribute: kAXChildrenAttribute) ?? [] {
        values.append(contentsOf: descendantTexts(of: child, depth: depth + 1))
    }

    return values
}

private func visibleRows(in rows: [AXUIElement], parent: AXUIElement) -> [AXUIElement] {
    guard let parentFrame = resolveLocalFrame(of: parent, windowBounds: nil) else {
        return Array(rows.prefix(20))
    }

    let visible = rows.filter { row in
        guard let rowFrame = resolveLocalFrame(of: row, windowBounds: nil) else {
            return false
        }

        return rowFrame.intersects(parentFrame)
    }

    if visible.isEmpty {
        return Array(rows.prefix(20))
    }

    return Array(visible.prefix(20))
}

private func displayIdentifier(_ value: String?) -> String? {
    guard let value, !value.isEmpty, !value.hasPrefix("_NS:") else {
        return nil
    }

    return value
}

private func displayWindowTitle(_ value: String?, appName: String) -> String {
    guard let value, !value.isEmpty else {
        return appName
    }

    if value.hasPrefix("\(appName) –") {
        return appName
    }

    return value
}

private func quoted(_ value: String) -> String {
    "\"\(value)\""
}

private extension CGRect {
    var renderedLocalFrame: String {
        "x=\(Int(origin.x)), y=\(Int(origin.y)), w=\(Int(width)), h=\(Int(height))"
    }
}
