import Foundation
@preconcurrency import ApplicationServices
import AppKit
import Security
import OpenComputerUseKit
import os
import IOKit.pwr_mgt

typealias UnlockCancellation = LockedUseUnlockCancellation

enum LockScreenInteractor {
    /// Wake once, await complete AX publication and clear the selected field.
    /// This observes readiness, not authentication. The mechanism claim starts
    /// the short permit; the original session must separately become unlocked.
    static func wake(session: LockedUseSession, cancellation: UnlockCancellation, ui: LockUIObservation, clickTag: Int64? = nil, validationConfirmation: Bool = false, unshieldedReturn: Bool = false, returnTag: Int64? = nil) -> Bool {
        guard cancellation.allowsRequest(), session.state == .locked,
              LockedUseSession.current() == session else { return false }
        var activity: IOPMAssertionID = 0
        let status = IOPMAssertionDeclareUserActivity("Open Computer Use protected lock UI" as CFString,
            kIOPMUserActiveLocal, &activity)
        if activity != 0 { _ = IOPMAssertionRelease(activity) }
        let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "UnlockTrigger")
        logger.notice("displayWakeReturned status=\(status, privacy: .public) authenticationRequested=false")
        guard status == kIOReturnSuccess else { return false }
        let began = ProcessInfo.processInfo.systemUptime
        let deadline = began + 3
        var attempt = 0
        var confirmationAttempted = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard cancellation.allowsRequest() else { return false }
            let current = LockedUseSession.current()
            if current.userID == session.userID, current.auditSessionID == session.auditSessionID,
               current.state == .unlocked { return true }
            guard current == session else { return false }
            attempt += 1
            logger.notice("AXPublication attempt=\(attempt, privacy: .public)")
            if probe(session: session, cancellation: cancellation, logger: logger, clickTag: clickTag, validationConfirmation: validationConfirmation, confirmationAttempted: &confirmationAttempted, requestDeadline: deadline, unshieldedReturn: unshieldedReturn, returnTag: returnTag) {
                // The fallback tile can reveal the real password field only
                // after click delivery. Re-query, never reuse a stale element
                // or spend another input capability. Stay within the same limit.
                let followupDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 1.5)
                while clickTag != nil, ProcessInfo.processInfo.systemUptime < followupDeadline,
                      cancellation.allowsRequest(), LockedUseSession.current() == session {
                    Thread.sleep(forTimeInterval: 0.15)
                    logger.notice("AXPublication followup=true")
                    if probe(session: session, cancellation: cancellation, logger: logger,
                        clickTag: nil, passwordOnly: true, validationConfirmation: validationConfirmation, confirmationAttempted: &confirmationAttempted, requestDeadline: deadline, unshieldedReturn: unshieldedReturn, returnTag: returnTag) { break }
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        logger.notice("lockUISettled elapsed=\(ProcessInfo.processInfo.systemUptime - began, privacy: .public) notificationObserved=\(ui.observed, privacy: .public)")
        return cancellation.allowsRequest()
    }

    private static func probe(session: LockedUseSession, cancellation: UnlockCancellation, logger: Logger,
        clickTag: Int64?, passwordOnly: Bool = false, validationConfirmation: Bool = false, confirmationAttempted: inout Bool, requestDeadline: TimeInterval, unshieldedReturn: Bool = false, returnTag: Int64? = nil) -> Bool {
        guard cancellation.allowsRequest(), LockedUseSession.current() == session, AXIsProcessTrusted() else { return false }
        let processes = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == "loginwindow" || $0.bundleIdentifier == "com.apple.loginwindow"
        }
        guard processes.count == 1, let process = processes.first else {
            logger.notice("AXProbe processUnavailable=true"); return false
        }
        func trusted() -> Bool {
            var code: SecCode?
            var requirement: SecRequirement?
            guard !process.isTerminated,
                  SecCodeCopyGuestWithAttributes(nil,
                    [kSecGuestAttributePid as String: NSNumber(value: process.processIdentifier)] as CFDictionary,
                    [], &code) == errSecSuccess, let code,
                  SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString,
                    [], &requirement) == errSecSuccess, let requirement else { return false }
            return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        }
        guard trusted() else { logger.notice("AXProbe processSignatureRejected=true"); return false }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.75
        var visited: [AXUIElement] = []
        var primary: [AXUIElement] = [], fallback: [AXUIElement] = []
        var enabledButtons = 0, disabledButtons = 0, unknownButtons = 0
        var complete = true
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth <= 8 else { complete = false; return }
            guard !visited.contains(where: { CFEqual($0, element) }) else { return }
            guard visited.count < 300, ProcessInfo.processInfo.systemUptime < deadline,
                  cancellation.allowsRequest() else { complete = false; return }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
               role as? String == kAXButtonRole {
                var enabled: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success,
                   let flag = enabled as? Bool {
                    if flag { enabledButtons += 1 } else { disabledButtons += 1 }
                } else { unknownButtons += 1 }
            }
            var identifier: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
            if identifier as? String == "UserPasswordTextField" { primary.append(element) }
            if identifier as? String == "FocusedUser" { fallback.append(element) }
            guard ProcessInfo.processInfo.systemUptime < deadline else { complete = false; return }
            var children: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if result == .success {
                for child in children as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
            } else if result != .noValue && result != .attributeUnsupported { complete = false }
        }
        visit(root, depth: 0)
        logger.notice("AXProbe nodes=\(visited.count, privacy: .public) primaryMatches=\(primary.count, privacy: .public) fallbackMatches=\(fallback.count, privacy: .public) complete=\(complete, privacy: .public)")
        let candidates = passwordOnly ? primary : primary.isEmpty ? fallback : primary
        let uiState = complete && candidates.count == 1 ? "candidateFound" : complete ? "candidateUnavailable" : "unknown"
        logger.notice("lockUIState=\(uiState, privacy: .public) authenticationEvidence=false")
        guard complete, candidates.count == 1, cancellation.allowsRequest(),
              LockedUseSession.current() == session, trusted() else { return false }
        var settable: DarwinBoolean = false
        let availability = AXUIElementIsAttributeSettable(candidates[0], kAXValueAttribute as CFString, &settable)
        logger.notice("AXProbe writable=\(settable.boolValue, privacy: .public) status=\(availability.rawValue, privacy: .public)")
        // Clear only the unique identifier-selected field; never read its value.
        // A successful write does not prove authentication has started.
        guard cancellation.allowsRequest(), LockedUseSession.current() == session else { return false }
        let result = cancellation.performProbe {
            AXUIElementSetAttributeValue(candidates[0], kAXValueAttribute as CFString, "" as CFString)
        }
        logger.notice("AXTrigger emptyValueWrite status=\(result?.rawValue ?? -1, privacy: .public)")
        if primary.count == 1 {
            logger.notice("AXProbe passwordUI enabledButtons=\(enabledButtons, privacy: .public) disabledButtons=\(disabledButtons, privacy: .public) unknownButtons=\(unknownButtons, privacy: .public)")
            var focused: CFTypeRef?
            let focusStatus = AXUIElementCopyAttributeValue(candidates[0], kAXFocusedAttribute as CFString, &focused)
            logger.notice("AXProbe passwordFocused=\((focused as? Bool) == true, privacy: .public) status=\(focusStatus.rawValue, privacy: .public)")
            // Return requires the explicit unshielded diagnostic or a separate
            // inherited one-pair capability admitted by both protected taps.
            if unshieldedReturn || returnTag != nil, !confirmationAttempted, result == .success,
               availability == .success, settable.boolValue, focusStatus == .success,
               (focused as? Bool) == true {
                confirmationAttempted = true
                let sent = cancellation.performProbe {
                    guard ProcessInfo.processInfo.systemUptime < requestDeadline,
                          LockedUseSession.current() == session, trusted(),
                          CGEventSource.flagsState(.combinedSessionState)
                            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty,
                          let source = CGEventSource(stateID: .privateState),
                          let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
                    else { return false }
                    // Recheck focus after signature lookup, before posting.
                    var currentFocus: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(candidates[0], kAXFocusedAttribute as CFString, &currentFocus) == .success,
                          (currentFocus as? Bool) == true,
                          LockedUseSession.current() == session,
                          ProcessInfo.processInfo.systemUptime < requestDeadline else { return false }
                    down.flags = []; up.flags = []
                    if let returnTag {
                        for event in [down, up] {
                            event.setIntegerValueField(.eventSourceUserData, value: returnTag)
                            event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(getpid()))
                            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(process.processIdentifier))
                        }
                    }
                    down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                    up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                    logger.notice("AXTrigger returnDispatching=true keyCode=36 tap=hid")
                    down.post(tap: .cghidEventTap)
                    // Always release once dispatched, even if cancellation
                    // arrives between the pair. No repeat or text payload.
                    up.post(tap: .cghidEventTap)
                    return true
                }
                logger.notice("AXTrigger returnPairQueued=\(sent == true, privacy: .public) authenticationEvidence=false")
            }
            // Validation experiment: ask the real field which actions it
            // supports before attempting one confirmation of the empty value.
            // Do not infer support from writability or synthesize a global key.
            var actions: CFArray?
            let actionStatus = AXUIElementCopyActionNames(candidates[0], &actions)
            let supportsConfirm = actionStatus == .success &&
                (actions as? [String] ?? []).contains(kAXConfirmAction)
            logger.notice("AXTrigger passwordConfirmSupported=\(supportsConfirm, privacy: .public) status=\(actionStatus.rawValue, privacy: .public)")
            if validationConfirmation, !unshieldedReturn, returnTag == nil, !confirmationAttempted, supportsConfirm, result == .success {
                confirmationAttempted = true
                let confirm = cancellation.performProbe {
                    guard LockedUseSession.current() == session, trusted() else { return AXError.cannotComplete }
                    // The traversal timeout belongs to reads. An action may
                    // need longer to reply; never exceed the original request
                    // deadline and never retry an ambiguously completed action.
                    let remaining = requestDeadline - ProcessInfo.processInfo.systemUptime
                    guard remaining >= 0.1 else {
                        logger.notice("AXTrigger passwordConfirmSkipped=deadline")
                        return AXError.cannotComplete
                    }
                    let timeout = Float(min(2, remaining))
                    let configured = AXUIElementSetMessagingTimeout(candidates[0], timeout)
                    logger.notice("AXTrigger passwordConfirmTimeout milliseconds=\(Int(timeout * 1000), privacy: .public) status=\(configured.rawValue, privacy: .public)")
                    guard configured == .success else { return configured }
                    defer { _ = AXUIElementSetMessagingTimeout(candidates[0], 0.05) }
                    logger.notice("AXTrigger passwordConfirmDispatching=true")
                    let began = ProcessInfo.processInfo.systemUptime
                    let actionResult = AXUIElementPerformAction(candidates[0], kAXConfirmAction as CFString)
                    let elapsed = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
                    logger.notice("AXTrigger passwordConfirmElapsed milliseconds=\(elapsed, privacy: .public) status=\(actionResult.rawValue, privacy: .public)")
                    return actionResult
                }
                logger.notice("AXTrigger passwordConfirm status=\(confirm?.rawValue ?? -1, privacy: .public) authenticationEvidence=false")
            }
        }
        // One window-bound session-stage click, admitted by both independent
        // filters through the inherited one-use capability. No PID-only bypass.
        guard primary.isEmpty, let clickTag else { return true }
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard result == .success,
              AXUIElementCopyAttributeValue(candidates[0], kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(candidates[0], kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return true }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              [position.x, position.y, size.width, size.height].allSatisfy({ $0.isFinite }),
              size.width > 0, size.height > 0 else { return true }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        var axWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(candidates[0], kAXWindowAttribute as CFString, &axWindow) == .success,
              let axWindow, CFGetTypeID(axWindow) == AXUIElementGetTypeID() else {
            logger.notice("AXTrigger sessionClickWindowAvailable=false"); return true
        }
        let windowElement = axWindow as! AXUIElement
        var windowPositionValue: CFTypeRef?, windowSizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &windowPositionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &windowSizeValue) == .success,
              let windowPositionValue, let windowSizeValue,
              CFGetTypeID(windowPositionValue) == AXValueGetTypeID(), CFGetTypeID(windowSizeValue) == AXValueGetTypeID() else {
            logger.notice("AXTrigger sessionClickWindowAvailable=false"); return true
        }
        var windowPosition = CGPoint.zero, windowSize = CGSize.zero
        guard AXValueGetValue(windowPositionValue as! AXValue, .cgPoint, &windowPosition),
              AXValueGetValue(windowSizeValue as! AXValue, .cgSize, &windowSize),
              [windowPosition.x, windowPosition.y, windowSize.width, windowSize.height].allSatisfy({ $0.isFinite }),
              windowSize.width > 0, windowSize.height > 0 else { return true }
        let axFrame = CGRect(origin: windowPosition, size: windowSize)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let targets = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.contains(point) && abs(frame.minX - axFrame.minX) <= 1 &&
                abs(frame.minY - axFrame.minY) <= 1 && abs(frame.width - axFrame.width) <= 1 &&
                abs(frame.height - axFrame.height) <= 1
        }
        logger.notice("AXTrigger sessionClickWindowMatches=\(targets.count, privacy: .public)")
        guard targets.count == 1,
              let windowID = targets[0][kCGWindowNumber as String] as? NSNumber,
              let source = CGEventSource(stateID: .privateState),
              let down = NSEvent.mouseEvent(with: .leftMouseDown,
                  location: CGPoint(x: point.x - axFrame.minX, y: axFrame.maxY - point.y),
                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: windowID.intValue, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)?.cgEvent,
              let up = NSEvent.mouseEvent(with: .leftMouseUp,
                  location: CGPoint(x: point.x - axFrame.minX, y: axFrame.maxY - point.y),
                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: windowID.intValue, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)?.cgEvent else {
            logger.notice("AXTrigger sessionClickTargetAvailable=false"); return true
        }
        for event in [down, up] {
            event.setSource(source)
            event.location = point
            event.flags = []
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(process.processIdentifier))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID.int64Value)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID.int64Value)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.mouseEventSubtype, value: 3)
            event.setIntegerValueField(.eventSourceUserData, value: clickTag)
            do {
                try encodeLockedUseWindowLocation(event,
                    point: CGPoint(x: point.x - axFrame.minX, y: axFrame.maxY - point.y))
            } catch {
                logger.notice("AXTrigger sessionClickWindowEncodingAvailable=false")
                return true
            }
        }
        let queued = cancellation.performProbe {
            guard LockedUseSession.current() == session, trusted() else { return false }
            // Single-variable validation experiment, enabled only by the
            // authenticated Root validation profile. Keep the same event pair
            // and both session filters; HID posting grants no input exemption.
            let tap: CGEventTapLocation = validationConfirmation ? .cghidEventTap : .cgSessionEventTap
            logger.notice("AXTrigger clickTap=\(validationConfirmation ? "hid" : "session", privacy: .public)")
            down.post(tap: tap)
            up.post(tap: tap)
            return true
        } ?? false
        logger.notice("AXTrigger sessionClickQueued=\(queued, privacy: .public)")
        return true
    }

}

/// Notifications are UI timing hints, never authentication/session evidence.
final class LockUIObservation: @unchecked Sendable {
    private let mutex = NSLock()
    private var lastHint: TimeInterval?
    private var tokens: [NSObjectProtocol] = []
    init() {
        for prefix in ["com.apple.", "com.apple.sessionagent."] {
            for suffix in ["screenIsLocked", "screenIsUnlocked", "screenLockUIIsShown"] {
                tokens.append(DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(prefix + suffix), object: nil, queue: nil) { [weak self] _ in
                        guard let self else { return }
                        self.mutex.lock(); self.lastHint = ProcessInfo.processInfo.systemUptime; self.mutex.unlock()
                    })
            }
        }
    }
    var observed: Bool { mutex.lock(); defer { mutex.unlock() }; return lastHint != nil }
    func settled(since began: TimeInterval) -> Bool {
        mutex.lock(); let hint = lastHint; mutex.unlock()
        let now = ProcessInfo.processInfo.systemUptime
        return now - began >= 3 || hint.map { now - $0 >= 1.5 } == true
    }
    deinit { for token in tokens { DistributedNotificationCenter.default().removeObserver(token) } }
}
