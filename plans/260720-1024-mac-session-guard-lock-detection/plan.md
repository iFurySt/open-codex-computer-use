# Plan: Mac Session Guard console-gated absent-key fix (Proposal B, TDD)

Status: ready to implement. Chosen design: Proposal B (console-gated absent-key).
Single revertable commit target.

## Files to modify

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift` (fix)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` (tests, near line 1907 `MARK: - MacSessionGuard tests`)
- `README.md` (~L42-47, REQUIRED correction, not optional — see Docs)

Do NOT touch: `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, `AllowWhileLockedNotice`, the `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` hatch (L102-106), `MacSessionStateProvider` protocol, fakes (L2637-2652), `requireUnlocked`/`currentState`.

## Phase 1 — Tests first (write now, must fail against current code)

Add an internal seam so unit tests reach the parsing logic without mocking `CGSessionCopyCurrentDictionary`:

```swift
// internal (not private) static — reachable via @testable import, no protocol change
static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot
```

`fetchFromSystem()` becomes a thin wrapper:
```swift
private static func fetchFromSystem() -> MacSessionSnapshot {
    let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
    let rawKeys = Set(dict?.keys ?? [])
    return parseSnapshot(dict, rawKeys: rawKeys)
}
```
All existing logic (nil/empty guard, DEBUG fail-open override, key parsing) moves into `parseSnapshot`, unchanged in position — only the new on-console branch is added. `OpenComputerUseKitTests.swift` already has `@testable import OpenComputerUseKit` (L4), no import change needed.

Test file location: new tests appended after L1959 (end of existing `testMacSessionGuardRawKeysDiagnostics`), before `testSystemMacSessionStateProviderCachesWithinTTL` (L1961). Use literal key strings `"CGSSessionScreenIsLocked"` and `"kCGSSessionOnConsoleKey"` in test dict literals (do not depend on the file's private `cgSessionScreenIsLockedKey` constant so a typo in the constant would also be caught).

12 cases, each `XCTAssertEqual(isLocked)/(isUnknown)`:

| # | Test name | dict | rawKeys | isLocked | isUnknown | Proves |
|---|---|---|---|---|---|---|
| 1 | testParseSnapshotNilDictFailsClosed | `nil` | `[]` | true | true | unchanged fail-closed |
| 2 | testParseSnapshotEmptyDictFailsClosed | `[:]` | `[]` | true | true | unchanged fail-closed |
| 3 | testParseSnapshotKeyAbsentOnConsoleTrueReturnsUnlocked | `["kCGSSessionOnConsoleKey": true]` | `{key}` | **false** | **false** | **the bug regression guard** |
| 4 | testParseSnapshotKeyAbsentOnConsoleTrueNSNumberReturnsUnlocked | `["kCGSSessionOnConsoleKey": NSNumber(value:1)]` | `{key}` | false | false | NSNumber coercion reused for on-console |
| 5 | testParseSnapshotKeyAbsentOnConsoleFalseFailsClosed | `["kCGSSessionOnConsoleKey": false]` | `{key}` | true | true | off-console stays fail-closed |
| 6 | testParseSnapshotKeyAbsentOnConsoleKeyAbsentFailsClosed | `["SomeOtherKey": "x"]` | `{key}` | true | true | no console signal at all |
| 7 | testParseSnapshotKeyAbsentOnConsoleUnparseableFailsClosed | `["kCGSSessionOnConsoleKey": "garbage"]` | `{key}` | true | true | garbage type fails closed |
| 8 | testParseSnapshotKeyPresentTrueLockedRegardlessOfConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true]` | `{2 keys}` | true | false | **explicit lock signal always wins over console gate** |
| 9 | testParseSnapshotKeyPresentFalseUnlocked | `["CGSSessionScreenIsLocked": false]` | `{key}` | false | false | unchanged explicit-unlocked path |
| 10 | testParseSnapshotKeyPresentNSNumberTrueLocked | `["CGSSessionScreenIsLocked": NSNumber(value:1)]` | `{key}` | true | false | unchanged NSNumber coercion |
| 11 | testParseSnapshotKeyPresentUnparseableTypeFailsClosed | `["CGSSessionScreenIsLocked": "garbage"]` | `{key}` | true | true | unchanged fail-closed on garbage |
| 12 | testParseSnapshotKeyPresentTrueLockedWithOffConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": false]` | `{2 keys}` | true | false | explicit-lock-wins pinned for the FUS-away/switched-out shape too |

`SystemMacSessionStateProvider` cache-policy tests (new, alongside existing `testSystemMacSessionStateProviderCachesWithinTTL` at L1961) — proves R2 asymmetric caching:

| # | Test name | Scenario | Asserts |
|---|---|---|---|
| 13 | testSystemMacSessionStateProviderDoesNotCacheUnlockedSnapshot | `shouldCache` on an `isLocked: false` snapshot | returns `false` |
| 14 | testSystemMacSessionStateProviderCachesLockedSnapshot | `shouldCache` on an `isLocked: true` snapshot (locked or unknown) | returns `true` |

Run to confirm red: `swift test --filter OpenComputerUseKitTests -Xswiftc -DDEBUG 2>&1 | grep -A2 "testParseSnapshot"` (or plain `swift test` if `--filter` regex issues — see Phase 3). Cases 1,2,8,9,10,11 should already pass (unchanged behavior); case 3–7 must fail until Phase 2 lands (3 fails because current code returns locked/unknown for absent key; 4–7 fail to compile/reference `parseSnapshot` until the seam exists at all — so realistically all 11 fail first because the seam doesn't exist yet).

## Phase 2 — Fix

In `MacSessionGuard.swift`:

1. Add `private static func coerceBool(_ value: Any?) -> Bool?` (returns `value as? Bool`, else `(value as? NSNumber)?.boolValue`, else `nil`). Reuse it for both `CGSSessionScreenIsLocked` and the new on-console read — replaces the inline if/else-if at L111-117.
2. Add `let kCGSSessionOnConsoleKey = "kCGSSessionOnConsoleKey"` constant next to `cgSessionScreenIsLockedKey` (L7).
3. Extract `internal static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot` per Phase 1 seam. Body, in order (ordering is load-bearing — explicit lock signal must be checked before the console gate):
   - `guard let dict, !dict.isEmpty else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
   - `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` override — unchanged, stays first after the nil/empty guard (preserve current position, L102-106).
   - `guard let lockedValue = dict[cgSessionScreenIsLockedKey] else { ... }` — inside the else, the **new** on-console gate:
     ```swift
     if coerceBool(dict[kCGSSessionOnConsoleKey]) == true {
         return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
     }
     return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
     ```
   - `guard let isLocked = coerceBool(lockedValue) else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
   - `return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)`
4. Rewrite `fetchFromSystem()` to the 3-line wrapper in Phase 1.
5. Rewrite file-top comment (L4-6): remove the false "verified on macOS 12–15 ... and macOS 26" claim. State: absent-key-corroborated-by-on-console semantics are empirically verified ONLY on macOS 26 (Darwin 27) on this machine; `CGSSessionScreenIsLocked` present as `true` only while locked; absent key alone is ambiguous and is corroborated by `kCGSSessionOnConsoleKey`; nil/empty dict and unparseable values remain fail-closed; screensaver-without-password is presence-blind and reads UNLOCKED (on-console stays true) — a behavior change from prior fail-closed, documented not fixed.
6. Keep `requireUnlocked`'s existing `rawKeysSeen` stderr diagnostic (L139) untouched — it now also fires (rarely) for the new off-console fail-closed branch, which is correct and desired (must-incorporate: catchable from logs).
7. **Cache policy (R2 — never cache a stale-unlocked verdict across a lock transition):** add `internal static func shouldCache(_ snapshot: MacSessionSnapshot) -> Bool { snapshot.isLocked }` next to `parseSnapshot`. In `SystemMacSessionStateProvider.currentSnapshot()`, after computing `fresh`, only write `cachedSnapshot`/`cacheTimestamp` when `Self.shouldCache(fresh)` is true; when false, clear any existing `cachedSnapshot` so a subsequent call within the old TTL window cannot return it. Fail-safe direction: an unlocked snapshot is never cached (always re-fetched), so a lock happening after a cached unlocked read is still detected on the very next call; a locked/unknown snapshot may still be served stale for up to 200ms after unlocking, which costs at most one extra spurious block, never a false unlock. Update the TTL comment (L25) to state this asymmetry explicitly: "cache only holds locked/unknown snapshots; unlocked is always re-fetched so a lock transition is never masked by a stale cache entry."
8. **One-shot inferred-unlock log (R3 mitigation a / red-team note 5):** add a private final class mirroring `AllowWhileLockedNotice`'s one-shot `NSLock`-guarded pattern (e.g. `InferredUnlockNotice`), emitted the first time `parseSnapshot` takes the absent-key + on-console-true branch, writing to stderr e.g. `"[open-computer-use] lock key absent, inferred unlocked from on-console signal (verified macOS 26 only) — see MacSessionGuard.swift for scope."` Fires once per process so a wrong-direction OS is detectable from logs without per-call spam; does not change `isUnknown` (stays `false` per existing contract).

## Phase 3 — Verify

1. Unit tests: `swift test --filter OpenComputerUseKitTests` from repo root (uses root `Package.swift`; the `OpenComputerUseKitTests` target already builds `OpenComputerUseKit` — no separate target flag needed). All 12 `parseSnapshot` cases + 2 `shouldCache` cases green, all 14 pre-existing `MacSessionGuard`/dispatcher/policy tests (L1907-2146, fakes bypass `fetchFromSystem`/`parseSnapshot` entirely) remain green untouched.
2. Live probe on THIS machine (expected UNLOCKED): add one throwing-skip test so it never runs in CI by default:
   ```swift
   func testLiveSystemProbePrintsRealLockState() throws {
       guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LIVE_PROBE"] == "1" else {
           throw XCTSkip("set OPEN_COMPUTER_USE_LIVE_PROBE=1 to probe the real session dictionary")
       }
       let snap = SystemMacSessionStateProvider().currentSnapshot()
       print("[live-probe] isLocked=\(snap.isLocked) isUnknown=\(snap.isUnknown) rawKeysSeen=\(snap.rawKeysSeen.sorted())")
   }
   ```
   Run: `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState 2>&1 | grep live-probe`. Expected on this machine right now: `isLocked=false isUnknown=false`, `rawKeysSeen` containing `kCGSSessionOnConsoleKey` and NOT `CGSSessionScreenIsLocked`.
3. Manual locked-state verification (put in PR body, cannot be automated from this session): open a terminal (or keep an existing SSH/tmux session attached — running a CLI test binary needs no GUI and is unaffected by the lock itself), lock the screen (Cmd+Ctrl+Q or Apple menu → Lock Screen), then from the still-open terminal run the same `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState` command. Expected: `isLocked=true isUnknown=false`, `rawKeysSeen` containing `CGSSessionScreenIsLocked`. Unlock afterward and confirm it flips back to case 2's result.
4. **MANDATORY human verification — fast-user-switch via SSH (R1, cannot run autonomously, required before merge, blocks the PR without it):** from an SSH/tmux session into this machine (so the probe also exercises the daemon/nil-dict assumption, red-team note 7), fast-user-switch away from the console (or invoke the login window via Apple menu → Lock Screen while a second account exists, or Control-Shift-Eject/FUS shortcut), then from the still-open SSH session run `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState`. This is the single most important test in the plan: it proves the load-bearing invariant "not physically frontmost ⇒ `kCGSSessionOnConsoleKey`==false" that the whole fix rests on. **MUST report `isLocked=true`.** If it reports `isLocked=false`, the fix is unsafe as designed and must not merge. Switch back and confirm it flips to unlocked again.
5. **Manual verification — screensaver without password (R4):** enable a screensaver with no password requirement, trigger it, run the live probe from an attached terminal. Expected/accepted: `isLocked=false` (presence-blind, documented in the file-top comment and README, not a regression this fix owns).
6. Full suite sanity: `swift test` (all packages) — confirm no unrelated regressions.

**PR-body checklist (required before merge):** [ ] FUS-via-SSH manual test (step 4) run and reported `isLocked=true` [ ] lock-screen manual test (step 3) run and reported `isLocked=true` [ ] screensaver-without-password manual test (step 5) run and result matches accepted behavior [ ] accepted residual risk (macOS 14–15 unverified) stated in PR body.

## Docs

- **README.md ~L42 — REQUIRED edit (R5, not optional):** current text "any lock-state evidence that is absent, nil, or unparseable is treated as locked" now documents the pre-fix behavior as if it were still true; it must change to: "absent lock-state evidence is corroborated by the on-console signal — when the session is on-console, absent evidence is treated as unlocked; when off-console, or when evidence is nil or unparseable, it is treated as locked." Also add one clause near L42-47 noting screensaver-without-password reads unlocked (R4), matching the file-top comment.
- `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`, `docs/SECURITY.md`: validated (plan-validation round 1) — these describe dict-level nil/empty/parse-fail semantics only, which remain fail-closed post-fix; no edit required, leave untouched.
- The authoritative source-level correction is the `MacSessionGuard.swift` file-top comment (Phase 2 step 5); README.md is the required user-facing mirror of that correction.

## Acceptance Criteria

- All 12 new `parseSnapshot` unit tests pass (cases 1-12, including explicit-lock-wins with off-console); the 2 new `shouldCache` tests (13-14) pass; all 14 pre-existing lock-guard/dispatcher/policy tests still pass unmodified.
- Live probe on this machine (unlocked) reports `isLocked=false, isUnknown=false`.
- **Mandatory human verification (Phase 3 step 4): FUS-via-SSH probe reports `isLocked=true`** — PR cannot merge without this being run and reported.
- Lock-screen manual probe (Phase 3 step 3) reports `isLocked=true`; screensaver-without-password probe (Phase 3 step 5) result is recorded and matches the documented accepted behavior.
- `shouldCache` returns `false` for every `isLocked==false` snapshot and `true` otherwise; `SystemMacSessionStateProvider` never returns a cached `isLocked==false` snapshot older than the current fetch.
- `MacSessionStateProvider` protocol signature, `FakeLockedSessionProvider`/`FakeUnlockedSessionProvider`/`FakeSnapshotProvider`, `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, and the DEBUG fail-open hatch are byte-identical to before this change.
- File-top comment no longer claims unverified macOS 12–15 behavior; states verification scope as macOS 26/Darwin 27 on this machine only; documents the screensaver-without-password behavior.
- README.md ~L42-47 no longer states absent evidence is unconditionally treated as locked.
- `swift test` (full suite) is green.

## Risks + Rollback

- **Risk**: `kCGSSessionOnConsoleKey` semantics are an undocumented private-API correlation (Security's honest weakness #1) — could diverge on a future OS. Mitigated by: explicit-lock-signal-first ordering (checked before the gate, so a genuinely locked session with the key present is never affected, including off-console — case 12), fail-closed remains the default for every other branch, the `rawKeysSeen` diagnostic stays in `requireUnlocked`'s stderr log, and the new one-shot inferred-unlock log (Phase 2 step 8) makes the fail-open branch visible in the field.
- **Risk**: stale-cache-across-lock-transition — closed by R2 (shouldCache never caches `isLocked==false`); residual is bounded to <=200ms of stale-locked after an actual unlock, which costs at most one extra spurious block, never a false unlock.
- **Accepted residual risk (R3, written acceptance — not gated on OS version):** the console-gated absent-key branch is verified only on macOS 26 (Darwin 27) on this machine; macOS 14–15 (Sonoma/Sequoia, the supported versions below 26) are unverified and the fix's fail-open direction is reachable there if any of those versions omits `CGSSessionScreenIsLocked` while genuinely locked. An OS-version gate was considered and rejected: gating would keep the guard permanently fail-closed (always-blocked-as-locked) on every supported macOS except 26, which is worse than the current bug for every non-26 user and defeats the purpose of the fix. Mitigations instead of gating: (a) one-shot stderr log per process on the inferred-unlock path (Phase 2 step 8) so a wrong-direction OS is detectable from field logs; (b) file-top comment states the verification scope honestly (macOS 26/Darwin 27 only); (c) this residual must be restated in the PR body per the merge checklist. This residual stays open until field telemetry or a differently-versioned test machine confirms 14-25 behavior.
- **Rollback**: single commit; `git revert <sha>` restores the prior (safe but broken-usability) fail-closed-on-absent-key behavior with no data loss, since this touches only in-process lock-state classification, not persisted state.

## Unresolved Questions

- Should the "on-console present but unparseable type" sub-case log a diagnostic reason distinct from the generic fail-closed path? (carried from predict-gate, not resolved here)
- No macOS 14–15 (Sonoma/Sequoia) verification possible in this environment — residual risk stays open until field telemetry or a differently-versioned test machine confirms.
