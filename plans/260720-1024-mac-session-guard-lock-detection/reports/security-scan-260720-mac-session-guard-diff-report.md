# Security scan: mac-session-guard lock-detection diff (uncommitted, `git diff HEAD`)

Scope: `MacSessionGuard.swift`, `OpenComputerUseKitTests.swift`, `README.md`. Mechanical scan against
Proposal B (console-gated absent-key) design; residual macOS 14-15 gap not re-litigated.

## Fail-closed ordering — verified line-by-line

`parseSnapshot` (`MacSessionGuard.swift:135-158`):
1. Nil/empty dict → `isLocked: true, isUnknown: true` (line 136-138). Unchanged fail-closed path.
2. `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` backdoor (line 139-143) — **pre-existing**,
   confirmed identical in `git show HEAD` (line 102-104 of prior version). Compiled out entirely
   in release builds (`#if DEBUG`), not introduced by this diff.
3. Explicit-key check runs **first**: `guard let lockedValue = dict[cgSessionScreenIsLockedKey]`
   (line 147). Only the `else` (key absent) branch reaches the new console-gate logic
   (line 148-151). Any dict where the explicit key is present — locked or unlocked, on-console or
   off — is fully decided before the console-gate code executes and never touches it. This
   matches the "explicit signal always wins" design and is proven correct, not just asserted:
   `testParseSnapshotKeyPresentTrueLockedRegardlessOfConsole` and
   `testParseSnapshotKeyPresentTrueLockedWithOffConsole` (tests file, both new) construct dicts
   with the explicit key present *and* on-console true/false and assert `isLocked == true` either
   way.
4. Absent-key branch: `coerceBool(dict[kCGSSessionOnConsoleKey]) == true` is the only way to reach
   `isLocked: false`. Any other value (missing key, `false`, non-bool/non-NSNumber, NSNull) falls
   through to `return MacSessionSnapshot(isLocked: true, isUnknown: true, ...)` — fail-closed
   default preserved. Covered by 5 new tests (nil dict, empty dict, on-console false, on-console
   key absent, on-console unparseable) all asserting `isLocked == true, isUnknown == true`.
5. Explicit key present but unparseable value → `coerceBool` returns nil → fail-closed (line
   154-156), unchanged from prior behavior, now shared via `coerceBool` helper (dedup only).

No new fail-open path found. The only behavior change matches the documented, accepted residual:
absent key + on-console true now infers unlocked (screensaver-without-password case), gated by a
one-shot stderr notice (`InferredUnlockNotice`, line 80-95) for field-log detectability.

## Caching change (R2)

`shouldCache` now returns `snapshot.isLocked` (line 172-174) instead of unconditionally caching.
Every `isUnknown: true` snapshot also has `isLocked: true` in all code paths, so this is a strict
narrowing: only locked/unknown snapshots are cached; unlocked is always re-fetched. This closes a
stale-cache-masks-relock class of bug — a security hardening, not a regression. New tests
(`testSystemMacSessionStateProviderDoesNotCacheUnlockedSnapshot`,
`testSystemMacSessionStateProviderCachesLockedSnapshot`) exercise both branches directly.

## Other checks

- No hardcoded secrets/credentials; only env var **names** (`OPEN_COMPUTER_USE_ALLOW_LOCKED`,
  `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN`, `OPEN_COMPUTER_USE_LIVE_PROBE`) appear, no values.
- No dependency/build-config changes — `git diff --stat` touches only the 3 named files; no
  `Package.swift`/`Package.resolved`/CI config in the diff.
- No injection surfaces (no shell exec, eval, string-built commands/queries) added.
- Singletons (`AllowWhileLockedNotice`, new `InferredUnlockNotice`) both use `@unchecked Sendable`
  + `NSLock` guarding a single `Bool`, consistent pattern, no unguarded mutable shared state.
- New test `testLiveSystemProbePrintsRealLockState` is gated by `XCTSkip` unless
  `OPEN_COMPUTER_USE_LIVE_PROBE=1` is set — no default-run side effect, no assertion on real
  session state (print-only), does not affect production code paths.
- README wording accurately reflects the new on-console corroboration behavior and documents the
  screensaver-without-password caveat as a known, accepted non-regression — no doc/behavior
  mismatch found.
- No caller of `requireUnlocked`/`currentState` changed in this diff; the public
  `MacSessionGuard` API surface and `blockWhileLocked`/`allowWhileLocked` gating (lines 189-203)
  are untouched, so no new unauthenticated-caller bypass was introduced at the guard boundary.

Status: DONE
Summary: Explicit `CGSSessionScreenIsLocked` key always wins over the new console-gate branch (verified literally in code and by two targeted tests); every other path stays fail-closed; the only behavior change is the documented/accepted screensaver-without-password residual, and the caching change strictly narrows what gets cached (security hardening). No secrets, no build/dependency changes, no new bypass surface.
Concerns/Blockers: none.
