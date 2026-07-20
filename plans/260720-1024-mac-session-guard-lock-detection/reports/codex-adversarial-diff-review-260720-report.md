# Codex-style adversarial diff review — MacSessionGuard console-gated absent-key fix

Reviewer stance: adversarial gate (standing in for timed-out external review). Scope = the 6
attack-surface items; general code-quality/security handled by the two parallel reviewers.

## 1. Decision-table correctness (12-row trace vs `parseSnapshot` body) — PASS
Traced each row line-by-line against L135-158. `guard let lockedValue = dict[lockKey]` means the
explicit-lock branch is entered whenever the key is present; the console gate lives only inside its
`else`, so the explicit signal is structurally checked before the gate.
- R1 nil→L136 (T,T); R2 empty→L136 isEmpty (T,T); R3 onConsole=true→L148 (F,F);
  R4 onConsole=NSNumber1→coerceBool→(F,F); R5 onConsole=false→L152 (T,T);
  R6 other-key→coerceBool(nil)!=true→L152 (T,T); R7 onConsole="garbage"→coerceBool nil→(T,T);
  R8 lock=true+console=true→present, skips gate→(T,F) explicit wins; R9 lock=false→(F,F);
  R10 lock=NSNumber1→(T,F); R11 lock="garbage"→L154 guard→(T,T);
  R12 lock=true+console=false→present, skips gate→(T,F) explicit wins off-console.
All 12 match the plan table exactly. Ordering invariant holds.

## 2. Cache asymmetry / thread-safety — PASS
`shouldCache(fresh) == fresh.isLocked`. The only non-nil value ever assigned to `cachedSnapshot`
(L119) is gated on `isLocked==true`; the unlocked branch (L122) assigns nil. Therefore the cache
can never physically hold an `isLocked==false` snapshot, so the fast-path `return cached` (L110)
can only ever return locked/unknown — no window serves a stale unlocked verdict. `NSLock` wraps
every read and every write of `cachedSnapshot`/`cacheTimestamp`; `MacSessionSnapshot` is a value
struct so `cached` is returned by copy. Check-then-act is non-atomic across the released lock, but
the only possible outcome is a redundant re-fetch, never an unlocked cache entry. Stale-locked ≤TTL
after an unlock is the accepted safe-direction residual (spurious block, never false unlock).
Note: leaving `cacheTimestamp` stale on the nil branch is harmless — the fast path requires a
non-nil `cachedSnapshot` first.

## 3. `coerceBool` garbage rejection — PASS
`value as? Bool` then `value as? NSNumber` then nil. Swift bridging: `"garbage" as? Bool`→nil and
String does not bridge to NSNumber→nil→fail closed. `NSNull`, arbitrary objects → nil → fail
closed. `__NSCFBoolean`/Int correctly route through the NSNumber arm. On-console gate uses
`coerceBool(...) == true`, so both nil and Optional(false) evaluate false → fail closed. Correct.

## 4. Test-matrix completeness — PASS (1 NOTE)
All 14 names present (L1963-2058) and every parseSnapshot test asserts BOTH `isLocked` and
`isUnknown`; assertion polarity matches the plan table for all 12 rows + the 2 shouldCache tests.
NOTE (non-blocking): the R2 *integration* behavior (currentSnapshot actually clearing the cache on
an unlocked fresh fetch) is proven only at the pure-function level of `shouldCache`; no test drives
`currentSnapshot()` across a lock→unlock transition. Acceptable given CGSession is unmockable here,
but the clear-on-unlock wiring (L118-123) rests on code inspection, not a test.

## 5. Doc-claim accuracy — PASS
File-top comment (L4-10) drops the false "verified on macOS 12–15" claim, scopes verification to
macOS 26/Darwin 27 on this machine, and documents the screensaver-without-password unlocked read.
README L42 accurately mirrors: on-console→absent=unlocked; off-console/nil/unparseable=locked; plus
the screensaver clause. Coherent with the code and with each other.

## 6. Scope discipline — PASS
Only README.md, MacSessionGuard.swift, tests touched. `MacSessionLockPolicy`,
`OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, `AllowWhileLockedNotice`, `MacSessionStateProvider`
protocol, the Fakes, and `requireUnlocked`/`currentState` are byte-identical. The `#if DEBUG`
fail-open hatch is unchanged in logic and preserved in position (first after the nil/empty guard);
its relocation from `fetchFromSystem` into `parseSnapshot` is explicitly directed by plan Phase 2
step 3, so it is in-scope, not a violation.

## Cross-cutting NOTE (already-tracked merge gate, not a code defect)
The entire fix rests on the invariant "genuinely locked + lock-key-absent ⇒ on-console==false".
impl-notes confirms the only empirical lock capture had `CGSSessionScreenIsLocked` PRESENT (same-user
lock), which exercises the OLD explicit branch, NOT the new console-gated branch. The load-bearing
FUS-away/login-window probe (plan Phase 3 step 4 / R1) is still UNRUN and is a stated mandatory
merge blocker. Nothing in this diff can substitute for it. The code is correct as written, but the
gate must remain closed until step 4 reports `isLocked=true`. This is the plan's own gate, restated
here so the verdict is not read as clearing it.

## Findings summary
No BLOCKER against the diff itself. Two NOTEs: (a) R2 integration untested at currentSnapshot level;
(b) FUS-away R1 empirical gate still unrun — keep the merge blocked on it per the plan checklist.
The code, decision table, cache asymmetry, coerceBool, tests, docs, and scope are all sound.

Verdict: PASS
