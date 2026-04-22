import AppKit
import ApplicationServices
import Foundation

struct VisualCursorTarget: Equatable {
    let point: CGPoint
    let window: CursorTargetWindow?
}

func makeVisualCursorTarget(
    at point: CGPoint,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?
) -> VisualCursorTarget {
    VisualCursorTarget(
        point: point,
        window: targetWindowID.map { CursorTargetWindow(windowID: $0, layer: targetWindowLayer ?? 0) }
    )
}

func makeVisualCursorTarget(
    localFrame: CGRect?,
    windowBounds: CGRect?,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?
) -> VisualCursorTarget? {
    guard let localFrame, let windowBounds else {
        return nil
    }

    let point = CGPoint(
        x: windowBounds.minX + localFrame.midX,
        y: windowBounds.minY + localFrame.midY
    )
    return makeVisualCursorTarget(
        at: point,
        targetWindowID: targetWindowID,
        targetWindowLayer: targetWindowLayer
    )
}

func inputFallbackDebugEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

func globalPointerFallbacksEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

let nonSettableSetValueErrorMessage = "Cannot set a value for an element that is not settable"

func setValueAttributeIsSettable(result: AXError, settable: Bool, attribute: String) throws -> Bool {
    guard result == .success else {
        throw ComputerUseError.message("AXUIElementIsAttributeSettable(\(attribute)) failed with \(result.rawValue)")
    }

    return settable
}

public final class ComputerUseService {
    private var snapshotsByApp: [String: AppSnapshot] = [:]

    public init() {}

    public func listApps() -> ToolCallResult {
        ToolCallResult.text(
            AppDiscovery.listCatalog()
                .map(\.renderedLine)
                .joined(separator: "\n")
        )
    }

    public func getAppState(app query: String) throws -> ToolCallResult {
        snapshotResult(for: try refreshSnapshot(for: query), style: .fullState)
    }

    public func click(app query: String, elementIndex: String?, x: Double?, y: Double?, clickCount: Int, mouseButton: String) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        let button = MouseButtonKind(rawValue: mouseButton.lowercased()) ?? .left
        if snapshot.mode == .fixture {
            if let elementIndex {
                let record = try lookupElement(snapshot: snapshot, index: elementIndex)
                guard let identifier = record.identifier else {
                    throw ComputerUseError.invalidArguments("fixture click requires an identifier-backed element")
                }
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier))
            } else if let x, let y {
                let identifier = try fixtureIdentifier(at: CGPoint(x: x, y: y), snapshot: snapshot)
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier, x: x, y: y))
            } else {
                throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
            }

            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        if let elementIndex {
            let record = try lookupElement(snapshot: snapshot, index: elementIndex)
            guard let targetPoint = try globalPoint(for: record, snapshot: snapshot) else {
                throw ComputerUseError.stateUnavailable("element \(elementIndex) has no clickable frame")
            }
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            moveVisualCursor(to: cursorTarget)

            do {
                if try performPreferredClick(on: record, button: button, clickCount: clickCount) {
                    Thread.sleep(forTimeInterval: 0.15)
                } else {
                    try performGlobalClickFallback(
                        at: targetPoint,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "element_index=\(elementIndex)",
                        snapshot: snapshot
                    )
                }
            } catch {
                settleVisualCursor(at: cursorTarget)
                throw error
            }

            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
        } else if let x, let y {
            let point = CGPoint(x: x, y: y)
            let targetPoint = try screenshotToGlobalPoint(snapshot: snapshot, x: x, y: y)
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            moveVisualCursor(to: cursorTarget)

            do {
                if let record = try hitTestElement(at: point, in: snapshot) ?? bestElement(containing: point, in: snapshot),
                   try performPreferredClick(on: record, button: button, clickCount: clickCount) {
                    Thread.sleep(forTimeInterval: 0.15)
                } else {
                    try performGlobalClickFallback(
                        at: targetPoint,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "x=\(Int(point.x)) y=\(Int(point.y))",
                        snapshot: snapshot
                    )
                }
            } catch {
                settleVisualCursor(at: cursorTarget)
                throw error
            }

            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
        } else {
            throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
        }

        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func performSecondaryAction(app query: String, elementIndex: String, action: String) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard action.caseInsensitiveCompare("Raise") == .orderedSame else {
                throw ComputerUseError.invalidArguments("fixture mode only supports the Raise secondary action")
            }

            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard let rawAction = matchingAction(requested: action, record: record) else {
            throw ComputerUseError.invalidArguments("element \(elementIndex) does not expose action '\(action)'")
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        let result = AXUIElementPerformAction(element, rawAction as CFString)
        guard result == .success else {
            throw ComputerUseError.message("AXUIElementPerformAction failed with \(result.rawValue)")
        }

        Thread.sleep(forTimeInterval: 0.15)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func scroll(app query: String, direction: String, elementIndex: String, pages: Int) throws -> ToolCallResult {
        let normalized = direction.lowercased()
        guard ["up", "down", "left", "right"].contains(normalized) else {
            throw ComputerUseError.invalidArguments("scroll direction must be one of up/down/left/right")
        }

        let snapshot = try currentSnapshot(for: query)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture scroll requires an identifier-backed element")
            }
            try FixtureBridge.post(FixtureCommand(kind: "scroll", identifier: identifier, direction: normalized, pages: pages))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        if let rawAction = record.rawActions.first(where: { $0.caseInsensitiveCompare("AXScroll\(normalized.capitalized)ByPage") == .orderedSame }), let element = record.element {
            for _ in 0..<max(pages, 1) {
                _ = AXUIElementPerformAction(element, rawAction as CFString)
                Thread.sleep(forTimeInterval: 0.05)
            }
        } else if let point = try globalPoint(for: record, snapshot: snapshot) {
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.scrollGlobally(at: point, direction: normalized, pages: pages)
        } else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no scrollable frame")
        }

        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func drag(app query: String, fromX: Double, fromY: Double, toX: Double, toY: Double) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "drag", identifier: "fixture-drag-pad", x: fromX, y: fromY, toX: toX, toY: toY))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
        try InputSimulation.dragGlobally(
            from: try screenshotToGlobalPoint(snapshot: snapshot, x: fromX, y: fromY),
            to: try screenshotToGlobalPoint(snapshot: snapshot, x: toX, y: toY)
        )
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func typeText(app query: String, text: String) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "type_text", identifier: "fixture-input", value: text))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        try InputSimulation.typeText(text, pid: snapshot.app.pid)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func pressKey(app query: String, key: String) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "press_key", identifier: "fixture-key-capture", value: key))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        try InputSimulation.pressKey(key, pid: snapshot.app.pid)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    public func setValue(app query: String, elementIndex: String, value: String) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture set_value requires a known element identifier")
            }

            try FixtureBridge.post(FixtureCommand(kind: "set_value", identifier: identifier, value: value))
            Thread.sleep(forTimeInterval: 0.15)
            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        guard try isSettableForSetValue(element: element, attribute: kAXValueAttribute) else {
            throw ComputerUseError.message(nonSettableSetValueErrorMessage)
        }

        let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
        moveVisualCursor(to: cursorTarget)

        do {
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
            guard result == .success else {
                throw ComputerUseError.message("AXUIElementSetAttributeValue failed with \(result.rawValue)")
            }

            Thread.sleep(forTimeInterval: 0.1)
        } catch {
            settleVisualCursor(at: cursorTarget)
            throw error
        }

        settleVisualCursor(at: cursorTarget)
        return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
    }

    private func currentSnapshot(for query: String) throws -> AppSnapshot {
        if let snapshot = snapshotsByApp[query.lowercased()] {
            return snapshot
        }

        return try refreshSnapshot(for: query)
    }

    @discardableResult
    private func refreshSnapshot(for query: String) throws -> AppSnapshot {
        let app = try AppDiscovery.resolve(query)
        let snapshot = try SnapshotBuilder.build(for: app)

        let keys = Set([
            query.lowercased(),
            app.name.lowercased(),
            (app.bundleIdentifier ?? "").lowercased(),
        ].filter { !$0.isEmpty })

        for key in keys {
            snapshotsByApp[key] = snapshot
        }

        return snapshot
    }

    private func lookupElement(snapshot: AppSnapshot, index: String) throws -> ElementRecord {
        guard let parsedIndex = Int(index), let record = snapshot.elements[parsedIndex] else {
            throw ComputerUseError.invalidArguments("unknown element_index '\(index)'")
        }

        return record
    }

    private func matchingAction(requested: String, record: ElementRecord) -> String? {
        if let exact = record.rawActions.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
            return exact
        }

        if let pretty = zip(record.rawActions, record.prettyActions).first(where: { $0.1.caseInsensitiveCompare(requested) == .orderedSame }) {
            return pretty.0
        }

        return nil
    }

    private func performPreferredClick(on record: ElementRecord, button: MouseButtonKind, clickCount: Int) throws -> Bool {
        guard let element = record.element else {
            return false
        }

        switch button {
        case .left:
            if try performAction(named: kAXPressAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try activateClickTarget(element: element, availableActions: record.rawActions) {
                return true
            }

            if try performAction(named: kAXConfirmAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .right:
            if try performAction(named: kAXShowMenuAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .middle:
            break
        }

        return false
    }

    private func performAction(named action: String, on element: AXUIElement, availableActions: [String], repeatCount: Int = 1) throws -> Bool {
        guard availableActions.contains(where: { $0.caseInsensitiveCompare(action) == .orderedSame }) else {
            return false
        }

        let attempts = max(repeatCount, 1)
        for index in 0..<attempts {
            let result = AXUIElementPerformAction(element, action as CFString)
            switch result {
            case .success:
                if index < attempts - 1 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            case .actionUnsupported, .cannotComplete, .noValue:
                return false
            default:
                throw ComputerUseError.message("AXUIElementPerformAction(\(action)) failed with \(result.rawValue)")
            }
        }

        return true
    }

    private func activateClickTarget(element: AXUIElement, availableActions: [String]) throws -> Bool {
        var activated = false

        if try performAction(named: kAXRaiseAction as String, on: element, availableActions: availableActions) {
            activated = true
        }

        if try setBoolAttribute(named: kAXMainAttribute, on: element) {
            activated = true
        }

        if try setBoolAttribute(named: kAXFocusedAttribute, on: element) {
            activated = true
        }

        return activated
    }

    private func setBoolAttribute(named attribute: String, on element: AXUIElement) throws -> Bool {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        switch result {
        case .success:
            return true
        case .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue(\(attribute)) failed with \(result.rawValue)")
        }
    }

    private func isSettable(element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func isSettableForSetValue(element: AXUIElement, attribute: String) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return try setValueAttributeIsSettable(
            result: result,
            settable: settable.boolValue,
            attribute: attribute
        )
    }

    private func bestElement(containing point: CGPoint, in snapshot: AppSnapshot) -> ElementRecord? {
        snapshot.elements.values
            .filter { $0.localFrame?.contains(point) ?? false }
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
            .first
    }

    private func hitTestElement(at point: CGPoint, in snapshot: AppSnapshot) throws -> ElementRecord? {
        let appElement = AXUIElementCreateApplication(snapshot.app.pid)
        let globalPoint = try screenshotToGlobalPoint(snapshot: snapshot, x: Double(point.x), y: Double(point.y))
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(appElement, Float(globalPoint.x), Float(globalPoint.y), &hitElement)
        guard result == .success, let hitElement else {
            return nil
        }

        let rawActions = copyActions(for: hitElement) ?? []
        return ElementRecord(
            index: -1,
            identifier: nil,
            element: hitElement,
            localFrame: localFrame(of: hitElement, windowBounds: snapshot.windowBounds),
            rawActions: rawActions,
            prettyActions: rawActions
        )
    }

    private func clickPriority(for record: ElementRecord) -> Int {
        if record.rawActions.contains(where: {
            $0.caseInsensitiveCompare(kAXPressAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXConfirmAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXShowMenuAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXRaiseAction as String) == .orderedSame
        }) {
            return 0
        }

        if let element = record.element,
           isSettable(element: element, attribute: kAXMainAttribute) ||
           isSettable(element: element, attribute: kAXFocusedAttribute) {
            return 1
        }

        return 2
    }

    private func frameArea(of record: ElementRecord) -> CGFloat {
        guard let frame = record.localFrame else {
            return .greatestFiniteMagnitude
        }

        return frame.width * frame.height
    }

    private func copyActions(for element: AXUIElement) -> [String]? {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success else {
            return nil
        }

        return actions as? [String]
    }

    private func localFrame(of element: AXUIElement, windowBounds: CGRect?) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard
            positionResult == .success,
            sizeResult == .success,
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

    private func globalPoint(for record: ElementRecord, snapshot: AppSnapshot) throws -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return try screenshotToGlobalPoint(snapshot: snapshot, x: frame.midX, y: frame.midY)
    }

    private func screenshotToGlobalPoint(snapshot: AppSnapshot, x: Double, y: Double) throws -> CGPoint {
        guard let windowBounds = snapshot.windowBounds else {
            let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
            throw ComputerUseError.stateUnavailable("No window bounds are available for \(appReference). Run get_app_state after bringing the app on screen.")
        }

        return CGPoint(x: windowBounds.minX + x, y: windowBounds.minY + y)
    }

    private func fixtureIdentifier(at point: CGPoint, snapshot: AppSnapshot) throws -> String {
        let candidates = snapshot.elements.values
            .filter { $0.identifier != nil && ($0.localFrame?.contains(point) ?? false) }
            .sorted { lhs, rhs in
                let lhsArea = (lhs.localFrame?.width ?? 0) * (lhs.localFrame?.height ?? 0)
                let rhsArea = (rhs.localFrame?.width ?? 0) * (rhs.localFrame?.height ?? 0)
                return lhsArea < rhsArea
            }

        guard let identifier = candidates.first?.identifier else {
            throw ComputerUseError.invalidArguments("No fixture element contains coordinate (\(Int(point.x)), \(Int(point.y)))")
        }

        return identifier
    }

    private func visualCursorTarget(for record: ElementRecord, snapshot: AppSnapshot) -> VisualCursorTarget? {
        makeVisualCursorTarget(
            localFrame: record.localFrame,
            windowBounds: snapshot.windowBounds,
            targetWindowID: snapshot.targetWindowID,
            targetWindowLayer: snapshot.targetWindowLayer
        )
    }

    private func moveVisualCursor(to target: VisualCursorTarget?) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.moveCursor(to: target.point, in: target.window)
        }
    }

    private func settleVisualCursor(at target: VisualCursorTarget?) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.settle(at: target.point, in: target.window)
        }
    }

    private func pulseVisualCursor(at target: VisualCursorTarget?, clickCount: Int, mouseButton: MouseButtonKind) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.pulseClick(
                at: target.point,
                clickCount: clickCount,
                mouseButton: mouseButton,
                in: target.window
            )
        }
    }

    private func debugInputFallback(tool: String, targetDescription: String, snapshot: AppSnapshot) {
        guard inputFallbackDebugEnabled(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
        fputs(
            "[open-computer-use] global pointer fallback tool=\(tool) app=\(appReference) target=\(targetDescription)\n",
            stderr
        )
    }

    private func performGlobalClickFallback(
        at point: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
            throw ComputerUseError.message(
                "click could not be handled through accessibility, and global pointer fallback is disabled. Set OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 to allow physical-pointer fallback for this process."
            )
        }

        debugInputFallback(
            tool: "click",
            targetDescription: targetDescription,
            snapshot: snapshot
        )
        InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
        try InputSimulation.clickGlobally(at: point, button: button, clickCount: clickCount)
    }

    private func snapshotResult(for snapshot: AppSnapshot, style: SnapshotTextStyle) -> ToolCallResult {
        var content = [ToolResultContentItem.text(snapshot.renderedText(style: style))]
        if let screenshotPNGData = snapshot.screenshotPNGData {
            content.append(.pngImage(screenshotPNGData))
        }
        return ToolCallResult(content: content)
    }
}
