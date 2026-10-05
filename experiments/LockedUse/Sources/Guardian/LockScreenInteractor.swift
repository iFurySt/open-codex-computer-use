@preconcurrency import ApplicationServices
import AppKit
import Foundation
import OpenComputerUseKit
import os
import Security

final class UnlockCancellation: @unchecked Sendable {
    private let mutex = NSLock()
    private var cancelled = false
    func cancel() { mutex.lock(); cancelled = true; mutex.unlock() }
    func allowsRequest() -> Bool { mutex.lock(); defer { mutex.unlock() }; return !cancelled }
}

enum LockScreenInteractor {
    /// Submit the unique native loginwindow secure field's advertised confirm
    /// action, or a fixed Return to the verified nonmodal loginwindow focus.
    /// Never populate/read a field value or synthesize a password.
    /// A true result is acceptance of a request, not an unlocked session.
    static func confirm(session: LockedUseSession, cancellation: UnlockCancellation) -> Bool {
        guard cancellation.allowsRequest(), session.state == .locked,
              LockedUseSession.current() == session, AXIsProcessTrusted() else { return false }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first else { return false }
        func trustedProcess() -> Bool {
            var code: SecCode?
            var requirement: SecRequirement?
            guard SecCodeCopyGuestWithAttributes(nil,
                [kSecGuestAttributePid as String: NSNumber(value: process.processIdentifier)] as CFDictionary,
                [], &code) == errSecSuccess, let code,
                SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString,
                    [], &requirement) == errSecSuccess, let requirement else { return false }
            return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        }
        guard trustedProcess() else { return false }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "UnlockTrigger")
        var attempt = 0
        var visited: [AXUIElement] = []
        var candidates: [AXUIElement] = []
        var ownerButtons: [AXUIElement] = []
        var selectedOwner = false
        let ownerLabels = Set([NSUserName(), NSFullUserName()].filter { !$0.isEmpty })
        func visit(_ element: AXUIElement, depth: Int, inAccountList: Bool = false) {
            guard depth < 12, visited.count < 300, ProcessInfo.processInfo.systemUptime < deadline,
                  cancellation.allowsRequest(), !visited.contains(where: { CFEqual($0, element) }) else { return }
            visited.append(element)
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
               role as? String == kAXSecureTextFieldSubrole || role as? String == kAXTextFieldRole {
                var subrole: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
                var actions: CFArray?
                if (role as? String == "AXSecureTextField" || subrole as? String == kAXSecureTextFieldSubrole),
                   AXUIElementCopyActionNames(element, &actions) == .success,
                   (actions as? [String] ?? []).contains(kAXConfirmAction) { candidates.append(element) }
            } else if role as? String == "AXSecureTextField" {
                var actions: CFArray?
                if AXUIElementCopyActionNames(element, &actions) == .success,
                   (actions as? [String] ?? []).contains(kAXConfirmAction) { candidates.append(element) }
            }
            // Public account selector labels only; never read AXValue or any
            // secure-field title/description. Keep labels out of all logs.
            if role as? String == kAXButtonRole, inAccountList {
                var actions: CFArray?
                _ = AXUIElementCopyActionNames(element, &actions)
                if (actions as? [String] ?? []).contains(kAXPressAction) {
                    let matchesOwner = [kAXTitleAttribute, kAXDescriptionAttribute].contains { attribute in
                        var label: CFTypeRef?
                        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &label) == .success,
                              let label = label as? String else { return false }
                        return ownerLabels.contains(label)
                    }
                    if matchesOwner { ownerButtons.append(element) }
                }
            }
            if attempt == 1 {
                var actions: CFArray?
                _ = AXUIElementCopyActionNames(element, &actions)
                logger.notice("node depth=\(depth, privacy: .public) role=\(role as? String ?? "", privacy: .public) confirmAvailable=\((actions as? [String] ?? []).contains(kAXConfirmAction), privacy: .public)")
            }
            for attribute in [kAXWindowsAttribute, kAXChildrenAttribute, kAXContentsAttribute, kAXVisibleChildrenAttribute] {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &children) == .success {
                    for child in (children as? [AXUIElement] ?? []).prefix(300 - visited.count) { visit(child, depth: depth + 1, inAccountList: inAccountList || role as? String == kAXScrollAreaRole) }
                }
            }
        }
        // The session lock flag precedes publication of loginwindow's AX UI.
        // Wait only within the original bounded request, without changing the
        // protected session or choosing a guessed control.
        while ProcessInfo.processInfo.systemUptime < deadline,
              cancellation.allowsRequest(), LockedUseSession.current() == session {
            attempt += 1; visited.removeAll(); candidates.removeAll(); ownerButtons.removeAll()
            visit(root, depth: 0)
            logger.notice("scan attempt=\(attempt, privacy: .public) nodes=\(visited.count, privacy: .public) candidates=\(candidates.count, privacy: .public)")
            if candidates.count == 1 {
                guard cancellation.allowsRequest(), LockedUseSession.current() == session, trustedProcess() else { return false }
                let status = AXUIElementPerformAction(candidates[0], kAXConfirmAction as CFString)
                logger.notice("confirm status=\(status.rawValue, privacy: .public)")
                return status == .success
            }
            if candidates.count > 1 || ownerButtons.count > 1 { return false }
            if candidates.isEmpty, !selectedOwner, ownerButtons.count == 1 {
                guard cancellation.allowsRequest(), LockedUseSession.current() == session, trustedProcess() else { return false }
                selectedOwner = true
                let status = AXUIElementPerformAction(ownerButtons[0], kAXPressAction as CFString)
                logger.notice("ownerSelection status=\(status.rawValue, privacy: .public)")
                if status != .success { return false }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // On some OS versions the lock UI does not publish its secure field
        // through AX. Start its native authentication transaction with a fixed
        // process-bound Return. No arbitrary key, target or text is accepted.
        guard cancellation.allowsRequest(), LockedUseSession.current() == session,
              trustedProcess(), ProcessInfo.processInfo.systemUptime < deadline + 0.2 else { return false }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let window = unsafeDowncast(focused, to: AXUIElement.self)
        var pid: pid_t = 0
        var role: CFTypeRef?
        var modal: CFTypeRef?
        guard AXUIElementGetPid(window, &pid) == .success, pid == process.processIdentifier,
              AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXWindowRole,
              AXUIElementCopyAttributeValue(window, kAXModalAttribute as CFString, &modal) == .success,
              modal as? Bool == false,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false),
              cancellation.allowsRequest(), LockedUseSession.current() == session, trustedProcess() else {
            logger.notice("fixedReturnUnavailable")
            return false
        }
        down.postToPid(process.processIdentifier)
        up.postToPid(process.processIdentifier)
        logger.notice("fixedReturnPosted")
        return true
    }
}
