import Foundation
import ApplicationServices

// macOS CGSession lock state keys — absent-key-corroborated-by-on-console semantics below are
// empirically verified ONLY on macOS 26 (Darwin 27) on this machine.
// CGSSessionScreenIsLocked: Bool — present as true only while locked.
// Absent key alone is ambiguous: corroborated by kCGSSessionOnConsoleKey (see parseSnapshot).
// Nil/empty dict and unparseable values remain fail-closed (treated as locked).
// Screensaver-without-password is presence-blind and reads UNLOCKED (on-console stays true) —
// a behavior change from prior fail-closed, documented not fixed.
let cgSessionScreenIsLockedKey = "CGSSessionScreenIsLocked"
let kCGSSessionOnConsoleKey = "kCGSSessionOnConsoleKey"

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

// TTL for CGSessionCopyCurrentDictionary cache — 200ms balances IPC cost vs responsiveness.
// Cache only holds locked/unknown snapshots; unlocked is always re-fetched so a lock transition
// is never masked by a stale cache entry (see shouldCache).
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

// Process-global one-shot stderr notice, emitted the first time the absent-key + on-console
// branch infers "unlocked" — makes a wrong-direction OS (see file-top residual) detectable
// from field logs without per-call spam.
private final class InferredUnlockNotice: @unchecked Sendable {
    static let shared = InferredUnlockNotice()
    private let lock = NSLock()
    private var emitted = false

    func emitIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !emitted else { return }
        emitted = true
        fputs("[open-computer-use] lock key absent, inferred unlocked from on-console signal (verified macOS 26 only) — see MacSessionGuard.swift for scope.\n", stderr)
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
        // R2: never cache a stale-unlocked verdict across a lock transition — cache only holds
        // locked/unknown snapshots; unlocked is always re-fetched so a lock transition is never
        // masked by a stale cache entry.
        if Self.shouldCache(fresh) {
            cachedSnapshot = fresh
            cacheTimestamp = now
        } else {
            cachedSnapshot = nil
        }
        lock.unlock()
        return fresh
    }

    private static func fetchFromSystem() -> MacSessionSnapshot {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        let rawKeys: Set<String> = dict.map { Set($0.keys) } ?? []
        return parseSnapshot(dict, rawKeys: rawKeys)
    }

    // Reachable via @testable import for unit coverage; not part of the public API.
    internal static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot {
        guard let dict, !dict.isEmpty else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LOCK_FAIL_OPEN"] == "1" {
            return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
        }
        #endif
        // Ordering is load-bearing: the explicit lock signal is always checked before the
        // console gate, so a genuinely locked session with the key present is never affected
        // by the new branch below, including when off-console (e.g. FUS-away).
        guard let lockedValue = dict[cgSessionScreenIsLockedKey] else {
            if coerceBool(dict[kCGSSessionOnConsoleKey]) == true {
                InferredUnlockNotice.shared.emitIfNeeded()
                return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
            }
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        guard let isLocked = coerceBool(lockedValue) else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)
    }

    private static func coerceBool(_ value: Any?) -> Bool? {
        if let boolVal = value as? Bool {
            return boolVal
        }
        if let numVal = value as? NSNumber {
            return numVal.boolValue
        }
        return nil
    }

    // R2: cache only holds locked/unknown snapshots; unlocked is always re-fetched so a lock
    // transition is never masked by a stale cache entry.
    internal static func shouldCache(_ snapshot: MacSessionSnapshot) -> Bool {
        snapshot.isLocked
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
