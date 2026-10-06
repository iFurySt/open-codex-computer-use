import AppKit
import Security
import OpenComputerUseKit
import os

/// Window metadata is a conservative handoff signal, not a pixel/compositor
/// guarantee. Both guards independently retain their opaque surfaces until it
/// is continuously stable; live physical-display validation remains required.
@MainActor
final class LockScreenPresentation {
    private let original: LockedUseSession
    private var barrier = LockedUseReleaseBarrier()
    private var process: NSRunningApplication?
    private var lastState: String?
    private let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "LockPresentation")
    init(session: LockedUseSession) { original = session }

    func ready(session: LockedUseSession, requested: Bool, now: TimeInterval) -> Bool {
        let locked = requested && session.state == .locked && session.userID == original.userID
            && session.auditSessionID == original.auditSessionID
        let evidence = locked ? presentation() : nil
        let ready = barrier.observe(locked: locked, presentation: evidence, now: now)
        let state = !locked ? "waitingForLock" : evidence == nil ? "waitingForCoverage" : ready ? "ready" : "stabilizing"
        if state != lastState {
            lastState = state
            logger.notice("releaseBarrier state=\(state, privacy: .public)")
        }
        return ready
    }
    private func presentation() -> String? {
        if process == nil || process?.isTerminated == true {
            let candidates = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.loginwindow" }
            guard candidates.count == 1, let candidate = candidates.first else { return nil }
            var code: SecCode?, requirement: SecRequirement?
            guard SecCodeCopyGuestWithAttributes(nil,
                [kSecGuestAttributePid as String: NSNumber(value: candidate.processIdentifier)] as CFDictionary, [], &code) == errSecSuccess,
                let code, SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString, [], &requirement) == errSecSuccess,
                let requirement, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
            process = candidate
        }
        guard let process, !process.isTerminated,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 64 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        let backgrounds: [CGRect] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 1,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1 >= Int(CGShieldingWindowLevel()),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return rect
        }
        var fingerprint: [String] = []
        for id in displays.prefix(Int(count)).sorted() {
            let display = CGDisplayBounds(id)
            guard backgrounds.contains(where: { LockedUseShieldCoverage.covers($0, display: display) }) else { return nil }
            fingerprint.append("\(id):\(NSStringFromRect(display))")
        }
        fingerprint += backgrounds.map(NSStringFromRect).sorted()
        return fingerprint.joined(separator: "|")
    }
}
