import Foundation
@preconcurrency import ApplicationServices
import AppKit
import Security
import OpenComputerUseKit
import os
import IOKit.pwr_mgt

typealias UnlockCancellation = LockedUseUnlockCancellation

enum LockScreenInteractor {
    /// Wake once, await a complete AX publication, clear the selected field and
    /// request one semantic press. Neither native return code proves an unlock;
    /// the Broker's plugin and original session must establish it independently.
    static func wake(session: LockedUseSession, cancellation: UnlockCancellation, ui: LockUIObservation) -> Bool {
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
            if probe(session: session, cancellation: cancellation, logger: logger) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        logger.notice("lockUISettled elapsed=\(ProcessInfo.processInfo.systemUptime - began, privacy: .public) notificationObserved=\(ui.observed, privacy: .public)")
        return cancellation.allowsRequest()
    }

    private static func probe(session: LockedUseSession, cancellation: UnlockCancellation, logger: Logger) -> Bool {
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
        let candidates = primary.isEmpty ? fallback : primary
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
        guard result == .success, fallback.count == 1, cancellation.allowsRequest(),
              LockedUseSession.current() == session, trusted() else { return true }
        // One supported semantic action first; do not synthesize Return or
        // treat the action's return code as a successful session unlock.
        let pressed = cancellation.performProbe {
            AXUIElementPerformAction(fallback[0], kAXPressAction as CFString)
        }
        logger.notice("AXTrigger focusedUserPress status=\(pressed?.rawValue ?? -1, privacy: .public) authenticationEvidence=false")
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
