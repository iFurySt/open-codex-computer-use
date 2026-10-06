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
    static func wake(session: LockedUseSession, cancellation: UnlockCancellation, ui: LockUIObservation, clickTag: Int64? = nil) -> Bool {
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
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard cancellation.allowsRequest() else { return false }
            let current = LockedUseSession.current()
            if current.userID == session.userID, current.auditSessionID == session.auditSessionID,
               current.state == .unlocked { return true }
            guard current == session else { return false }
            attempt += 1
            logger.notice("AXPublication attempt=\(attempt, privacy: .public)")
            if probe(session: session, cancellation: cancellation, logger: logger, clickTag: clickTag) {
                // The fallback tile can reveal the real password field only
                // after click delivery. Re-query, never reuse a stale element
                // or spend another input capability. Stay within the same limit.
                let followupDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 1.5)
                while clickTag != nil, ProcessInfo.processInfo.systemUptime < followupDeadline,
                      cancellation.allowsRequest(), LockedUseSession.current() == session {
                    Thread.sleep(forTimeInterval: 0.15)
                    logger.notice("AXPublication followup=true")
                    if probe(session: session, cancellation: cancellation, logger: logger,
                        clickTag: nil, passwordOnly: true) { break }
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        logger.notice("lockUISettled elapsed=\(ProcessInfo.processInfo.systemUptime - began, privacy: .public) notificationObserved=\(ui.observed, privacy: .public)")
        return cancellation.allowsRequest()
    }

    private static func probe(session: LockedUseSession, cancellation: UnlockCancellation, logger: Logger,
        clickTag: Int64?, passwordOnly: Bool = false) -> Bool {
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
        var complete = true
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth <= 8 else { complete = false; return }
            guard !visited.contains(where: { CFEqual($0, element) }) else { return }
            guard visited.count < 300, ProcessInfo.processInfo.systemUptime < deadline,
                  cancellation.allowsRequest() else { complete = false; return }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.05)
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
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
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
