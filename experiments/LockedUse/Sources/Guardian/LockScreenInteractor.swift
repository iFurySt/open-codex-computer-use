@preconcurrency import ApplicationServices
import AppKit
import Foundation
import OpenComputerUseKit

final class UnlockCancellation: @unchecked Sendable {
    private let mutex = NSLock()
    private var cancelled = false
    func cancel() { mutex.lock(); cancelled = true; mutex.unlock() }
    func allowsRequest() -> Bool { mutex.lock(); defer { mutex.unlock() }; return !cancelled }
}

enum LockScreenInteractor {
    /// Submit the unique native loginwindow secure field's advertised confirm
    /// action. Never populate/read its value or synthesize a password/Return.
    /// A true result is acceptance of a request, not an unlocked session.
    static func confirm(session: LockedUseSession, cancellation: UnlockCancellation) -> Bool {
        guard cancellation.allowsRequest(), session.state == .locked,
              LockedUseSession.current() == session, AXIsProcessTrusted() else { return false }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first else { return false }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var visited: [AXUIElement] = []
        var candidates: [AXUIElement] = []
        func visit(_ element: AXUIElement, depth: Int) {
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
            for attribute in [kAXWindowsAttribute, kAXChildrenAttribute] {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &children) == .success {
                    for child in (children as? [AXUIElement] ?? []).prefix(300 - visited.count) { visit(child, depth: depth + 1) }
                }
            }
        }
        visit(root, depth: 0)
        guard candidates.count == 1, cancellation.allowsRequest(), LockedUseSession.current() == session else { return false }
        return AXUIElementPerformAction(candidates[0], kAXConfirmAction as CFString) == .success
    }
}
