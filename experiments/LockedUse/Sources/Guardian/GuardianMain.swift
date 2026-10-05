import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Darwin
import Foundation
import OpenComputerUseKit

func emit(_ event: String, details: [String: Any] = [:]) {
    var value = details
    value["event"] = event
    value["uptime"] = ProcessInfo.processInfo.systemUptime
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

@main
struct GuardianMain {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        do {
            switch Array(CommandLine.arguments.dropFirst()) {
            case ["--shield-preview"]:
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let preview = ShieldPreview()
                try preview.start()
                withExtendedLifetime(preview) { app.run() }
                guard preview.passed else { throw GuardianError.message("Shield preview ended before completing coverage") }
            case ["--fixture-ax-self-test"]:
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let guardian = try DisplayGuardian(session: .current())
                Task { @MainActor in
                    do { try guardian.runFixtureAXSelfTest() }
                    catch { emit("error", details: ["message": String(describing: error)]) }
                    app.stop(nil)
                    if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                        app.postEvent(event, atStart: true)
                    }
                }
                app.run()
                guard guardian.fixtureAXSelfTestPassed else { throw GuardianError.message("Fixture AX self-test failed") }
            case ["--request-lock"]:
                let lock = ScreenLock()
                guard lock.available else { throw GuardianError.message("Relock SPI unavailable") }
                lock.request()
                emit("lockRequested", details: ["confirmed": false, "unlockRequested": false])
            case ["--peer-self-test"]:
                var descriptors: [Int32] = [-1, -1]
                guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                    throw GuardianError.message("socketpair failed")
                }
                defer { close(descriptors[0]); close(descriptors[1]) }
                let requirement = "identifier \"dev.opencomputeruse.locked-use.guardian.dev\" and anchor apple generic"
                let identity = try LockedUsePeerIdentity.verified(socket: descriptors[0], requirement: requirement)
                guard identity.userID == geteuid(), identity.processID == getpid(),
                      identity.auditSessionID == LockedUseSession.current().auditSessionID else {
                    throw GuardianError.message("Kernel peer identity disagrees with the current process")
                }
                var denied = false
                do { _ = try LockedUsePeerIdentity.verified(socket: descriptors[0], requirement: "identifier \"dev.invalid.client\"") }
                catch { denied = true }
                guard denied else { throw GuardianError.message("Wrong signing identifier was accepted") }
                guard let team = identity.teamIdentifier else { throw GuardianError.message("Developer ID team is missing") }
                let approval = try LockedUseClientApprovals.Approval(userID: identity.userID, role: .guardian,
                    signingIdentifier: identity.signingIdentifier, teamIdentifier: team)
                let records = try LockedUseClientApprovals(approvals: [approval])
                _ = try records.verifiedPeer(socket: descriptors[0], role: .guardian)
                var wrongRoleDenied = false
                do { _ = try records.verifiedPeer(socket: descriptors[0], role: .client) }
                catch { wrongRoleDenied = true }
                guard wrongRoleDenied else { throw GuardianError.message("Unapproved role was accepted") }
                emit("peerSelfTest", details: ["verified": true, "wrongSignerRejected": denied,
                    "identifier": identity.signingIdentifier, "auditSessionMatches": true,
                    "approvedRoleVerified": true, "wrongRoleRejected": wrongRoleDenied])
            case ["--request-permissions"]:
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                _ = CGRequestListenEventAccess()
                emit("permissionRequests", details: ["accessibility": AXIsProcessTrusted(),
                    "inputMonitoring": CGPreflightListenEventAccess()])
            case ["--diagnose"]:
                emit("diagnostics", details: ["accessibility": AXIsProcessTrusted(),
                    "inputMonitoring": CGPreflightListenEventAccess(),
                    "screenRecording": CGPreflightScreenCaptureAccess(),
                    "lockSPIAvailable": ScreenLock().available,
                    "secureInput": IsSecureEventInputEnabled(),
                    "session": LockedUseSession.current().state.rawValue,
                    "backendValidated": false])
            case ["--inspect-loginwindow"]:
                try inspectLoginwindow()
            case ["--watchdog"]:
                try runWatchdog()
            case ["--rehearse", "--confirm-lock-test"]:
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let guardian = try DisplayGuardian(session: .current())
                try guardian.start()
                withExtendedLifetime(guardian) { app.run() }
                if LockedUseSession.current().state == .locked { try inspectLoginwindow() }
            default:
                fputs("Usage: OpenComputerUseGuardian --diagnose | --request-permissions | --inspect-loginwindow | --shield-preview | --rehearse --confirm-lock-test\nPreview shows a 15-second countdown without locking. Rehearsal consumes local input and locks the Mac. No unlock is attempted.\n", stderr)
                exit(64)
            }
        } catch {
            emit("error", details: ["message": String(describing: error)])
            exit(1)
        }
    }

    /// Read only structure and available actions. Never fetch values, names,
    /// descriptions, selected text, or any authorization password context.
    @MainActor static func inspectLoginwindow() throws {
        guard AXIsProcessTrusted() else { throw GuardianError.message("Accessibility permission is required") }
        guard LockedUseSession.current().state == .locked else {
            throw GuardianError.message("Inspect loginwindow only during a manually locked, completed user session")
        }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first else {
            throw GuardianError.message("No loginwindow process")
        }
        var count = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        func visit(_ element: AXUIElement, depth: Int) {
            guard count < 300, depth < 12, ProcessInfo.processInfo.systemUptime < deadline else { return }
            count += 1
            func string(_ attribute: String) -> String {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
                return value as? String ?? ""
            }
            var actions: CFArray?
            let actionStatus = AXUIElementCopyActionNames(element, &actions)
            emit("axStructure", details: ["depth": depth, "role": string(kAXRoleAttribute),
                "subrole": string(kAXSubroleAttribute), "actions": actions as? [String] ?? [],
                "actionStatus": actionStatus.rawValue])
            var children: CFTypeRef?
            let childrenStatus = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if childrenStatus == .success {
                for child in (children as? [AXUIElement] ?? []).prefix(300 - count) { visit(child, depth: depth + 1) }
            } else {
                emit("axChildrenUnavailable", details: ["depth": depth, "status": childrenStatus.rawValue])
            }
        }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        visit(root, depth: 0)
        emit("inspectionComplete", details: ["nodes": count, "unlockRequested": false])
    }
}

enum GuardianError: Error { case message(String) }

/// Separate process with no AppKit dependency in its loop. Inherited heartbeat
/// loss always requests relock. It never trusts a command claiming lock success.
func runWatchdog() throws {
    let initial = LockedUseSession.current()
    guard initial.state == .unlocked, initial.userID != nil, initial.auditSessionID != nil,
          isatty(STDIN_FILENO) == 0 else { throw GuardianError.message("Watchdog requires an inherited pipe and an unlocked GUI session") }
    let lock = ScreenLock()
    guard lock.available else { throw GuardianError.message("Relock SPI is unavailable") }
    let pipe = HeartbeatPipe(STDIN_FILENO)
    var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    var lastLock = -Double.infinity
    var stopping = false
    _ = HeartbeatPipe.send(82, to: STDOUT_FILENO) // R = actual watchdog initialized
    while true {
        let now = ProcessInfo.processInfo.systemUptime
        let bytes = pipe.drain(allowed: [72, 76]) // H heartbeat, L guardian saw lock
        if bytes.contains(72), !stopping, now - lastHeartbeat < 1.5 { lastHeartbeat = now }
        if pipe.failed || now - lastHeartbeat >= 1.5 { stopping = true }
        let current = LockedUseSession.current()
        let same = current.userID == initial.userID && current.auditSessionID == initial.auditSessionID
        if bytes.contains(76), same, current.state == .locked { return }
        if stopping {
            if same, current.state == .locked { return }
            if now - lastLock >= 0.5 { lock.request(); lastLock = now }
        } else if !same || current.state == .unavailable { stopping = true }
        _ = HeartbeatPipe.send(72, to: STDOUT_FILENO)
        Thread.sleep(forTimeInterval: 0.1)
    }
}
