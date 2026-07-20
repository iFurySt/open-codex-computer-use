# Predict Gate: MacSessionGuard Console-Gated Absent-Key Fix (Proposal B)

Scope: `fetchFromSystem()`/new `parseSessionDict` seam, MacSessionGuard.swift lines ~97-119, file-top comment. Grounded against live source (read 260720).

## Per-Persona Top Concerns

**Security Engineer** — Console-gate repurposes `kCGSSessionOnConsoleKey` (undocumented purpose: console ownership, not lock state) as a locked/unlocked proxy. Only safe because the explicit-locked branch (`CGSSessionScreenIsLocked` present=true) is checked first and short-circuits — confirmed in source, line 107 guard precedes the fallthrough. If a future OS ever sets key-absent while genuinely locked, this ordering is the *only* thing preventing false-unlocked. Opt-in (`OPEN_COMPUTER_USE_ALLOW_LOCKED`) and DEBUG-only `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` (line 103) are separate paths, unaffected — but the DEBUG override sits *before* the key-presence check today; extraction must not reorder it after the console gate.

**macOS Platform Engineer** — On-console semantics correlation is empirically confirmed only for this machine/macOS 26; the file-top comment's "verified 12-15" claim (line 4) is already false per bug context and must not be reasserted. Screen-sharing-to-console-user and remote KVM are unanalyzed edge cases (proposal's own open question). Cache TTL (`sessionStateCacheTTL = 0.200s`, line 26) is pre-existing and out of scope for this fix — flag only if the extraction touches `currentSnapshot()`; it should touch only `fetchFromSystem`/`parseSessionDict`.

**API Contract Reviewer** — `MacSessionSnapshot` fields (isLocked/isUnknown/rawKeysSeen) and `MacSessionStateProvider` protocol are untouched; both call sites (`ComputerUseToolDispatcher.callTool` line 50, `MCPAppRuntime.applicationDidFinishLaunching` line 61) consume the public surface only, so no contract break. Real exposure: `MCPAppRuntime`'s startup diagnostic reads `isUnknown`/`rawKeysSeen` for operator-facing status — after the fix, `isUnknown` will flip from "usually true" to "usually false" on unlocked machines at every launch, changing displayed state, not just internals.

**QA Engineer** — Existing 14 tests bypass `fetchFromSystem` entirely via fakes (`FakeLockedSessionProvider`, `FakeUnlockedSessionProvider`) — zero prior coverage of the actual bug. The `parseSessionDict` seam is mandatory, not optional, for any regression guard. Verifying the true system-lock case without locking an active dev/CI screen is impractical — coverage must come from synthetic dicts via `@testable import`, with at most one manual real-lock spot-check at PR time.

**Operator Advocate** — `AllowWhileLockedNotice.emitIfNeeded()` (line 64) must remain gated strictly on the actual-locked-and-policy-allows path; must confirm it does not spuriously fire once absent-key+on-console-true now resolves to unlocked. stderr diagnostic text (line 139, "Treating as locked") must stay accurate post-fix — it should now fire far less often on this user's machine, and that reduction is itself evidence the fix works, not a regression.

## Debate Resolution

Security's and Platform Engineer's core disagreement — "is on-console a safe-enough proxy" — resolves in favor of shipping *because* the explicit-locked branch is checked first (verified in source) and the residual risk is bounded to a not-currently-observed OS behavior, not a currently-exploitable path; QA's mandatory ordering-regression test (locked key present=true must win regardless of on-console) is the concrete artifact that operationalizes this resolution. API Contract Reviewer's finding is downgraded from "contract risk" to "verification item" since no signature changes — just requires a manual check of `MCPAppRuntime` startup text pre/post fix. All five converge: proceed with Proposal B as scoped, contingent on the must-incorporate test table already specified plus P5/P8 mitigations below. No STOP trigger fires.

**Verdict: GO (conditional on P1, P5, P7, P8 mitigations landing in the same PR).**

## Predictions

| # | Predicted issue/outcome | Severity | Required mitigation |
|---|---|---|---|
| P1 | Future/edge OS presents key-absent + on-console=true while genuinely locked → false-unlocked | Critical (unproven, no current evidence) | Regression test: locked-key-present=true must short-circuit and win over console gate, regardless of on-console value; keep `rawKeysSeen` diagnostic live |
| P2 | Screen-sharing/remote-KVM-to-console-user presents on-console=true with ambiguous local lock state | Medium | Document as known limitation in code comment; out of scope for local-automation target usage |
| P3 | File-top comment reasserts false "verified macOS 12-15" claim if not edited | Medium | Edit comment to state absent-key+on-console semantics verified only on macOS 26 (Darwin 27), this machine |
| P4 | Implementer skips `parseSessionDict` extraction, leaves bug fix untestable via `@testable import` | High | Seam extraction is mandatory acceptance criterion, not optional refactor |
| P5 | DEBUG-only `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` override (line 103) reordered/dropped during extraction | Medium | Preserve exact check ordering: nil-dict → DEBUG override → explicit-locked-key → absent-key/console-gate |
| P6 | Cache TTL (200ms) touched incidentally during refactor, introducing stale-lock race at lock instant | Low | Scope diff strictly to `fetchFromSystem`/`parseSessionDict`; do not modify `currentSnapshot()` caching |
| P7 | Typo/miscoercion in literal `"kCGSSessionOnConsoleKey"` silently makes gate always fail-closed (fix becomes no-op, tests may not catch if only asserting "still fail-closed") | Medium | Explicit test asserting key-absent+on-console=true → isLocked=false, isUnknown=false (positive assertion, not just fail-closed check) |
| P8 | `MCPAppRuntime` startup diagnostic text/menu-bar status stops matching reality once `isUnknown` flips false-by-default on unlocked machines | Medium | Manual check of `MCPAppRuntime` diagnostic output pre/post fix on this unlocked machine |
| P9 | `AllowWhileLockedNotice.emitIfNeeded()` spuriously fires post-fix on unlocked sessions | Low | Confirm notice only reachable via actual-locked + opt-in policy path, unchanged by this diff |
| P10 | QA cannot exercise real system-lock state repeatedly without disrupting active session | Low | Rely on synthetic-dict unit tests via seam; one manual real-lock spot-check suffices, not repeated |

## Unresolved Questions
- Should on-console-key-present-but-unparseable log a distinct diagnostic reason vs. generic fail-closed (raised by proposal author, not resolved here)?
- No independent verification available on macOS 16-25 (Ventura/Sonoma) in this environment — P1's residual risk cannot be fully closed pre-merge, only bounded.
