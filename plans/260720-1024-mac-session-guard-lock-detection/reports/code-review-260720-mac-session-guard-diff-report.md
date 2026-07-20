# Code Review — Mac Session Guard console-gated absent-key fix

Scope: uncommitted `git diff HEAD`. Files: `MacSessionGuard.swift` (+69/−16), `OpenComputerUseKitTests.swift` (+108), `README.md` (+1/−1). LOC ~179 added. Focus: code-quality (adversarial security pass runs separately).

## Overall Assessment

Clean, disciplined implementation that matches the plan's Phase-2 spec closely. Refactor into `parseSnapshot`/`coerceBool`/`shouldCache` preserves prior branch behavior byte-for-byte on the unchanged paths and adds only the console-gated absent-key branch and the asymmetric-cache gate. Scope is respected: exactly the 3 sanctioned files changed; none of the "Do NOT touch" symbols (`MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, `AllowWhileLockedNotice`, DEBUG fail-open hatch, protocol, fakes, `requireUnlocked`/`currentState`) were modified. No blocking defects found.

## Critical Issues

None.

## High Priority

None.

## Medium Priority

- **Side effect inside an otherwise-pure parser.** `parseSnapshot` (marketed as a pure, testable seam) calls `InferredUnlockNotice.shared.emitIfNeeded()` (MacSessionGuard.swift:149), so the "unlocked" test cases (#3, #4) emit to stderr during the suite. One-shot + NSLock-guarded, so harmless and matches the `AllowWhileLockedNotice` precedent — but it couples classification with global I/O. Acceptable as-is; noting because a future caller may not expect a "parse" fn to write to stderr. No action required.

## Low Priority

- **Cache is effectively defeated for the common (unlocked) path.** By design (R2), `shouldCache` returns `false` for every unlocked snapshot, so `currentSnapshot()` clears the cache and issues a fresh `CGSessionCopyCurrentDictionary` IPC on every call while unlocked — the dominant runtime state. This is the deliberate, documented safety tradeoff (never mask a lock transition), and the IPC is a cheap local call, but the 200ms TTL now benefits only the locked/unknown state. Correct per plan; flag only so the perf characteristic is understood. No change recommended.
- **Redundant `rawKeys` parameter.** `parseSnapshot(_:rawKeys:)` re-derives nothing from `rawKeys` for logic (reads keys off `dict`); `fetchFromSystem` computes `rawKeys` from the same `dict`. A caller could pass an inconsistent set. Production callers keep them consistent and the plan mandated this exact signature for test flexibility, so this is an accepted, spec-driven smell, not a defect.

## Verification — test-vs-branch mapping

Traced all 12 `parseSnapshot` cases + 2 `shouldCache` cases against the code branches; every asserted `(isLocked, isUnknown)` pair matches the implementation:

- #1 nil / #2 empty → guard → `(true,true)` ✓
- #3 onConsole:true / #4 NSNumber(1) → absent-key branch, `coerceBool==true` → `(false,false)` ✓
- #5 onConsole:false / #6 no-console-key / #7 "garbage" → absent-key branch falls through → `(true,true)` ✓
- #8 lock:true+console:true / #12 lock:true+console:false → explicit-lock-first, `(true,false)` ✓ (console gate never consulted — ordering invariant holds)
- #9 lock:false → `(false,false)` ✓; #10 lock:NSNumber(1) → `(true,false)` ✓; #11 lock:"garbage" → `(true,true)` ✓
- #13 shouldCache(unlocked)=false ✓; #14 shouldCache(locked)=true, shouldCache(unknown)=true ✓

`coerceBool` ordering (`as? Bool` then `as? NSNumber`) preserves the exact behavior of the old inline if/else-if for both keys, including the NSNumber(1)→Bool bridge (`as? Bool` succeeds first) and NSNumber(2)-style non-0/1 falling to the `.boolValue` branch. Refactor is behavior-neutral.

Live-probe test (#`testLiveSystemProbePrintsRealLockState`) is correctly env-gated with `XCTSkip`, so it stays inert in CI — matches the reported "1 skipped".

## Thread-safety (cache change)

The `shouldCache`-gated write sits inside the same `lock`/`unlock` critical section as before; the only added statements are the `if/else` on already-fetched local `fresh`. Setting `cachedSnapshot = nil` on the unlocked branch is safe under the lock. No new shared mutable state, no new race. The pre-existing benign double-fetch window (two threads both missing cache) is unchanged and not introduced by this diff.

## Docs

README edit is scoped to the single sanctioned line and now accurately describes on-console corroboration + the screensaver-without-password caveat. File-top comment correctly drops the false macOS 12–15 verification claim and scopes verification to macOS 26/Darwin 27. Coherent — no re-litigation of the accepted 14–15 residual.

## Positive Observations (risk calibration)

- Explicit-lock-signal-first ordering is enforced and pinned by tests #8/#12 for both console values — the load-bearing invariant that keeps a genuinely-locked session safe is guarded, not just asserted in prose.
- Fail-closed remains the default on every non-corroborated branch (nil, empty, off-console, no-console-key, unparseable).

## Recommended Actions

1. None blocking. Optionally, a one-line comment on `parseSnapshot` noting the intentional stderr side effect would aid future maintainers (Medium item). Ship-ready from a code-quality standpoint.

## Metrics

- Type coverage: N/A (Swift, fully typed).
- New tests: 14 unit + 1 gated live probe. Reported suite: 192 tests, 1 skipped, 0 failures.
- Lint: not run here (no config surfaced); no obvious style deviations vs surrounding file.

## Unresolved Questions

- Manual FUS-via-SSH verification (plan Phase-3 step 4, the load-bearing "off-console ⇒ isLocked=true" proof) and lock-screen/screensaver manual probes cannot be run from this session and are not yet reflected in a PR body — these remain merge gates per the plan checklist and are outside what the diff can prove.

Status: DONE
Summary: Implementation matches the plan spec, preserves all unchanged branch behavior, respects scope, and the 14 new tests correctly map to code branches; no functional/thread-safety defects found.
Concerns/Blockers: Non-blocking — the mandatory manual FUS-via-SSH and lock-screen verifications (plan Phase-3 steps 3–5) still gate merge and cannot be executed from this session.
