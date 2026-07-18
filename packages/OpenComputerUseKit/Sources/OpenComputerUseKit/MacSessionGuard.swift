import Foundation
import ApplicationServices

// macOS CGSession lock state keys — verified on macOS 12–15 (Monterey–Sequoia) and macOS 26
// CGSSessionScreenIsLocked: Bool — true when session is locked
// Key absent or dict nil/empty → treat as locked (fail-closed)
let cgSessionScreenIsLockedKey = "CGSSessionScreenIsLocked"

public protocol MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot
}

public struct MacSessionSnapshot {
    public let isLocked: Bool
    public let isUnknown: Bool   // true when dict was nil/empty/parse-failed
    public let rawKeysSeen: Set<String>

    public init(isLocked: Bool, isUnknown: Bool, rawKeysSeen: Set<String>) {
        self.isLocked = isLocked
        self.isUnknown = isUnknown
        self.rawKeysSeen = rawKeysSeen
    }
}

// TTL for CGSessionCopyCurrentDictionary cache — 200ms balances IPC cost vs responsiveness
private let sessionStateCacheTTL: TimeInterval = 0.200

// Behavior when the screen is locked. Default fail-closed (block); opt-in allow is
// enabled with OPEN_COMPUTER_USE_ALLOW_LOCKED and permits best-effort control while locked.
//
// Why "best-effort" and opt-in only: every action tool delivers input process-targeted —
// accessibility (AXUIElementPerformAction / AXUIElementSetAttributeValue) or CGEvent.postToPid
// — not through the global HID event tap (globalPointerFallbacksEnabled() defaults false).
// Process-targeted delivery keeps working while the login window owns the screen, so an agent
// can still read the AX tree and drive an accessibility-controllable app. What does NOT work
// while locked: window screenshots (the OS returns blank for security; WindowCapture already
// yields a nil image for off-screen windows), and any coordinate-only path that needs a visible
// cursor. The default stays blocked so the security guarantee is unchanged unless the operator
// explicitly opts in.
public enum MacSessionLockPolicy: String, Sendable {
    case blockWhileLocked
    case allowWhileLocked

    public static let environmentKey = "OPEN_COMPUTER_USE_ALLOW_LOCKED"

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> MacSessionLockPolicy {
        let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "1", "true", "yes", "on", "allow":
            return .allowWhileLocked
        default:
            return .blockWhileLocked
        }
    }
}

// Process-global one-shot stderr notice, emitted the first time allow-while-locked lets a
// locked action through, so operators see the degraded contract without per-call spam.
private final class AllowWhileLockedNotice: @unchecked Sendable {
    static let shared = AllowWhileLockedNotice()
    private let lock = NSLock()
    private var emitted = false

    func emitIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !emitted else { return }
        emitted = true
        fputs("[open-computer-use] \(MacSessionLockPolicy.environmentKey) is set — permitting best-effort Computer Use while macOS is locked. Screenshots are unavailable while locked and input is delivered process-targeted (accessibility) only; this is not equivalent to an unlocked, logged-in session.\n", stderr)
    }
}

public final class SystemMacSessionStateProvider: MacSessionStateProvider {
    private var cachedSnapshot: MacSessionSnapshot?
    private var cacheTimestamp: TimeInterval = 0
    // Lock for thread-safe cache access
    private let lock = NSLock()

    public init() {}

    public func currentSnapshot() -> MacSessionSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let cached = cachedSnapshot, (now - cacheTimestamp) < sessionStateCacheTTL {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let fresh = Self.fetchFromSystem()
        lock.lock()
        cachedSnapshot = fresh
        cacheTimestamp = now
        lock.unlock()
        return fresh
    }

    private static func fetchFromSystem() -> MacSessionSnapshot {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any], !dict.isEmpty else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        }
        let rawKeys = Set(dict.keys)
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LOCK_FAIL_OPEN"] == "1" {
            return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
        }
        #endif
        guard let lockedValue = dict[cgSessionScreenIsLockedKey] else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        let isLocked: Bool
        if let boolVal = lockedValue as? Bool {
            isLocked = boolVal
        } else if let numVal = lockedValue as? NSNumber {
            isLocked = numVal.boolValue
        } else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)
    }
}

public struct MacSessionGuard {
    private let provider: MacSessionStateProvider
    private let policy: MacSessionLockPolicy

    public init(
        provider: MacSessionStateProvider = SystemMacSessionStateProvider(),
        policy: MacSessionLockPolicy = .fromEnvironment()
    ) {
        self.provider = provider
        self.policy = policy
    }

    public func requireUnlocked(for toolName: String) throws {
        let snapshot = provider.currentSnapshot()
        guard snapshot.isLocked else { return }

        if snapshot.isUnknown {
            fputs("[open-computer-use] Lock state unknown — CGSessionCopyCurrentDictionary returned nil/empty/parse-failed (keys: \(snapshot.rawKeysSeen.sorted().joined(separator: ","))). Treating as locked.\n", stderr)
        }

        switch policy {
        case .blockWhileLocked:
            throw ComputerUseError.stateUnavailable("Computer Use cannot run while macOS is locked. Unlock the Mac, run open-computer-use inside a dedicated logged-in desktop session, or set \(MacSessionLockPolicy.environmentKey)=1 to permit best-effort accessibility control while locked (screenshots stay unavailable while locked).")
        case .allowWhileLocked:
            AllowWhileLockedNotice.shared.emitIfNeeded()
        }
    }

    // Current snapshot for menu bar status display (never throws)
    public func currentState() -> MacSessionSnapshot {
        return provider.currentSnapshot()
    }
}
