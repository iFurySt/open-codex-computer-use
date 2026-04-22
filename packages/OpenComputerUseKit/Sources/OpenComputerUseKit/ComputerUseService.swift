import AppKit
import ApplicationServices
import Foundation
import ImageIO

struct VisualCursorTarget: Equatable {
    let point: CGPoint
    let window: CursorTargetWindow?
}

struct VisualCursorScreenMapping: Equatable {
    let screenStateFrame: CGRect
    let appKitFrame: CGRect
}

func currentVisualCursorScreenMappings() -> [VisualCursorScreenMapping] {
    NSScreen.screens.compactMap { screen in
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return VisualCursorScreenMapping(
            screenStateFrame: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value)),
            appKitFrame: screen.frame
        )
    }
}

func screenStatePointToAppKitGlobalPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    guard let mapping = screenMappings.first(where: { $0.screenStateFrame.contains(point) }) else {
        return point
    }

    let localX = point.x - mapping.screenStateFrame.minX
    let localY = point.y - mapping.screenStateFrame.minY

    return CGPoint(
        x: mapping.appKitFrame.minX + localX,
        y: mapping.appKitFrame.maxY - localY
    )
}

func visualCursorAppKitPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    screenStatePointToAppKitGlobalPoint(
        fromScreenStatePoint: point,
        screenMappings: screenMappings
    )
}

func makeVisualCursorTarget(
    at point: CGPoint,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> VisualCursorTarget {
    VisualCursorTarget(
        point: screenStatePointToAppKitGlobalPoint(
            fromScreenStatePoint: point,
            screenMappings: screenMappings
        ),
        window: targetWindowID.map { CursorTargetWindow(windowID: $0, layer: targetWindowLayer ?? 0) }
    )
}

func makeVisualCursorTarget(
    localFrame: CGRect?,
    windowBounds: CGRect?,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
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
        targetWindowLayer: targetWindowLayer,
        screenMappings: screenMappings
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

func screenshotPixelScale(
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGSize {
    guard
        let screenshotPixelSize,
        let windowBounds,
        windowBounds.width > 0,
        windowBounds.height > 0,
        screenshotPixelSize.width > 0,
        screenshotPixelSize.height > 0
    else {
        return CGSize(width: 1, height: 1)
    }

    return CGSize(
        width: screenshotPixelSize.width / windowBounds.width,
        height: screenshotPixelSize.height / windowBounds.height
    )
}

func screenshotPixelToWindowPoint(
    _ point: CGPoint,
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGPoint {
    let scale = screenshotPixelScale(
        screenshotPixelSize: screenshotPixelSize,
        windowBounds: windowBounds
    )
    return CGPoint(
        x: point.x / scale.width,
        y: point.y / scale.height
    )
}

let nonSettableSetValueErrorMessage = "Cannot set a value for an element that is not settable"

func setValueAttributeIsSettable(result: AXError, settable: Bool, attribute: String) throws -> Bool {
    guard result == .success else {
        throw ComputerUseError.message("AXUIElementIsAttributeSettable(\(attribute)) failed with \(result.rawValue)")
    }

    return settable
}

func invalidSecondaryActionErrorMessage(action: String, elementIndex: Int) -> String {
    "\(action) is not a valid secondary action for \(elementIndex)"
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
            let cursorTarget: VisualCursorTarget?
            if let elementIndex {
                let record = try lookupElement(snapshot: snapshot, index: elementIndex)
                guard let identifier = record.identifier else {
                    throw ComputerUseError.invalidArguments("fixture click requires an identifier-backed element")
                }
                cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
                moveVisualCursor(to: cursorTarget)
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier))
            } else if let x, let y {
                let identifier = try fixtureIdentifier(at: CGPoint(x: x, y: y), snapshot: snapshot)
                cursorTarget = fixtureVisualCursorTarget(identifier: identifier, snapshot: snapshot)
                moveVisualCursor(to: cursorTarget)
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier, x: x, y: y))
            } else {
                throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
            }

            Thread.sleep(forTimeInterval: 0.15)
            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
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
                if !(try performAXClickSequence(
                    on: record,
                    snapshot: snapshot,
                    button: button,
                    clickCount: clickCount,
                    includeNearbyHitTesting: true
                )) {
                    try performNonAXClickFallback(
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
            let screenshotPoint = CGPoint(x: x, y: y)
            let point = screenshotPixelToWindowPointInSnapshot(snapshot: snapshot, point: screenshotPoint)
            let targetPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: point)
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            moveVisualCursor(to: cursorTarget)

            do {
                if let record = try hitTestElement(at: point, in: snapshot) ?? bestElement(containing: point, in: snapshot),
                   (try performAXClickSequence(
                       on: record,
                       snapshot: snapshot,
                       button: button,
                       clickCount: clickCount,
                       includeNearbyHitTesting: false
                   )) {
                    // handled
                } else {
                    try performNonAXClickFallback(
                        at: targetPoint,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "x=\(Int(screenshotPoint.x)) y=\(Int(screenshotPoint.y))",
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
                throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
            }

            return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
        }

        guard let rawAction = matchingAction(requested: action, record: record) else {
            throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
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

    public func scroll(app query: String, direction: String, elementIndex: String, pages: Double) throws -> ToolCallResult {
        let normalized = direction.lowercased()
        guard ["up", "down", "left", "right"].contains(normalized) else {
            throw ComputerUseError.message("Invalid scroll direction: \(direction)")
        }
        guard pages.isFinite, pages > 0 else {
            throw ComputerUseError.message("pages must be > 0")
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

        if let repeatCount = integralScrollPageCount(pages),
           let rawAction = record.rawActions.first(where: { $0.caseInsensitiveCompare("AXScroll\(normalized.capitalized)ByPage") == .orderedSame }),
           let element = record.element {
            for _ in 0..<repeatCount {
                _ = AXUIElementPerformAction(element, rawAction as CFString)
                Thread.sleep(forTimeInterval: 0.05)
            }
        } else if let point = try globalPoint(for: record, snapshot: snapshot) {
            try performScrollEvent(
                at: point,
                direction: normalized,
                pages: pages,
                targetDescription: "element_index=\(elementIndex)",
                snapshot: snapshot
            )
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

        let start = try screenshotToGlobalPoint(snapshot: snapshot, x: fromX, y: fromY)
        let end = try screenshotToGlobalPoint(snapshot: snapshot, x: toX, y: toY)
        try performDragEvent(
            from: start,
            to: end,
            targetDescription: "from=(\(Int(fromX)), \(Int(fromY))) to=(\(Int(toX)), \(Int(toY)))",
            snapshot: snapshot
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

            let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
            moveVisualCursor(to: cursorTarget)
            try FixtureBridge.post(FixtureCommand(kind: "set_value", identifier: identifier, value: value))
            Thread.sleep(forTimeInterval: 0.15)
            settleVisualCursor(at: cursorTarget)
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

    private func invalidSecondaryActionMessage(action: String, record: ElementRecord) -> String {
        invalidSecondaryActionErrorMessage(action: action, elementIndex: record.index)
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

            if try performAction(named: kAXConfirmAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try performAction(named: "AXOpen", on: element, availableActions: record.rawActions, repeatCount: clickCount) {
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

    private func performAXClickSequence(
        on record: ElementRecord,
        snapshot: AppSnapshot,
        button: MouseButtonKind,
        clickCount: Int,
        includeNearbyHitTesting: Bool
    ) throws -> Bool {
        if try performPreferredClick(on: record, button: button, clickCount: clickCount) {
            Thread.sleep(forTimeInterval: 0.15)
            return true
        }

        for candidate in descendantClickCandidates(for: record, snapshot: snapshot) {
            if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                Thread.sleep(forTimeInterval: 0.15)
                return true
            }
        }

        if includeNearbyHitTesting {
            for localPoint in clickActionPoints(for: record) {
                guard let hitRecord = try hitTestElement(at: localPoint, in: snapshot) ?? bestElement(containing: localPoint, in: snapshot) else {
                    continue
                }

                if try performPreferredClick(on: hitRecord, button: button, clickCount: clickCount) {
                    Thread.sleep(forTimeInterval: 0.15)
                    return true
                }

                for candidate in descendantClickCandidates(for: hitRecord, snapshot: snapshot) {
                    if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                        Thread.sleep(forTimeInterval: 0.15)
                        return true
                    }
                }
            }
        }

        guard button == .left, let element = record.element else {
            return false
        }

        if try activateClickTarget(element: element, availableActions: record.rawActions) {
            Thread.sleep(forTimeInterval: 0.15)
            return true
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
            case .attributeUnsupported where action.caseInsensitiveCompare("AXOpen") == .orderedSame:
                return true
            case .failure, .actionUnsupported, .attributeUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
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
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
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

    private func localCenter(for record: ElementRecord) -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func clickActionPoints(for record: ElementRecord) -> [CGPoint] {
        guard let frame = record.localFrame else {
            return []
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let leading = CGPoint(
            x: frame.minX + min(max(frame.width * 0.3, 20), max(frame.width - 4, 20)),
            y: frame.midY
        )

        if abs(leading.x - center.x) < 1 {
            return [center]
        }

        return [center, leading]
    }

    private func descendantClickCandidates(for record: ElementRecord, snapshot: AppSnapshot) -> [ElementRecord] {
        guard let element = record.element else {
            return []
        }

        return descendantClickCandidates(of: element, windowBounds: snapshot.windowBounds)
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
    }

    private func descendantClickCandidates(of element: AXUIElement, windowBounds: CGRect?, depth: Int = 0) -> [ElementRecord] {
        guard depth < 3 else {
            return []
        }

        var results: [ElementRecord] = []
        for child in copyChildren(of: element) {
            let rawActions = copyActions(for: child) ?? []
            results.append(
                ElementRecord(
                    index: -1,
                    identifier: nil,
                    element: child,
                    localFrame: localFrame(of: child, windowBounds: windowBounds),
                    rawActions: rawActions,
                    prettyActions: rawActions
                )
            )
            results.append(contentsOf: descendantClickCandidates(of: child, windowBounds: windowBounds, depth: depth + 1))
        }

        return results
    }

    private func copyActions(for element: AXUIElement) -> [String]? {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success else {
            return nil
        }

        return actions as? [String]
    }

    private func copyChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let value else {
            return []
        }

        return value as? [AXUIElement] ?? []
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

        return try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: CGPoint(x: frame.midX, y: frame.midY)
        )
    }

    private func screenshotToGlobalPoint(snapshot: AppSnapshot, x: Double, y: Double) throws -> CGPoint {
        try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: screenshotPixelToWindowPointInSnapshot(
                snapshot: snapshot,
                point: CGPoint(x: x, y: y)
            )
        )
    }

    private func screenshotPixelToWindowPointInSnapshot(snapshot: AppSnapshot, point: CGPoint) -> CGPoint {
        screenshotPixelToWindowPoint(
            point,
            screenshotPixelSize: screenshotPixelSize(snapshot: snapshot),
            windowBounds: snapshot.windowBounds
        )
    }

    private func screenshotPixelSize(snapshot: AppSnapshot) -> CGSize? {
        guard
            let screenshotPNGData = snapshot.screenshotPNGData,
            let imageSource = CGImageSourceCreateWithData(screenshotPNGData as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
            pixelWidth > 0,
            pixelHeight > 0
        else {
            return nil
        }

        return CGSize(width: pixelWidth, height: pixelHeight)
    }

    private func windowPointToGlobalPoint(snapshot: AppSnapshot, point: CGPoint) throws -> CGPoint {
        guard let windowBounds = snapshot.windowBounds else {
            let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
            throw ComputerUseError.stateUnavailable("No window bounds are available for \(appReference). Run get_app_state after bringing the app on screen.")
        }

        return CGPoint(x: windowBounds.minX + point.x, y: windowBounds.minY + point.y)
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

    private func fixtureVisualCursorTarget(identifier: String, snapshot: AppSnapshot) -> VisualCursorTarget? {
        let record = snapshot.elements.values.first { $0.identifier == identifier }
        return record.flatMap { visualCursorTarget(for: $0, snapshot: snapshot) }
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

    private func integralScrollPageCount(_ pages: Double) -> Int? {
        let rounded = pages.rounded(.toNearestOrAwayFromZero)
        guard abs(pages - rounded) < 0.000001 else {
            return nil
        }
        return max(Int(rounded), 1)
    }

    private func performScrollEvent(
        at point: CGPoint,
        direction: String,
        pages: Double,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "scroll",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.scrollGlobally(at: point, direction: direction, pages: pages)
            return
        }

        try InputSimulation.scrollTargeted(at: point, direction: direction, pages: pages, pid: snapshot.app.pid)
    }

    private func performDragEvent(
        from start: CGPoint,
        to end: CGPoint,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "drag",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.dragGlobally(from: start, to: end)
            return
        }

        try InputSimulation.dragTargeted(from: start, to: end, pid: snapshot.app.pid)
    }

    private func performNonAXClickFallback(
        at point: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        do {
            try InputSimulation.clickTargeted(
                at: point,
                button: button,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
            return
        } catch {
            guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
                throw ComputerUseError.message(
                    "click could not be handled through accessibility, and global pointer fallback is disabled. Set OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 to allow physical-pointer fallback for this process."
                )
            }
        }

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
