# Implementation notes — MacSessionGuard lock-detection fix

## Deviations

- **Execution order**: cook (stage 8) ran ahead of stage 6 (codex plan review) and stage 7
  (impl-notes init) — see auto-decisions #7/#8. Reason: a transient locked-screen window opened
  mid-pipeline; capturing plan.md Phase 3 step 3 (lock-screen manual probe) required acting
  immediately, and could not be reconstructed after the fact once the user unlocks.
- **`fetchFromSystem` raw-keys line**: plan.md's Phase 1 snippet (`Set(dict?.keys ?? [])`) does not
  type-check (`Dictionary.Keys` is not `ExpressibleByArrayLiteral`). Implemented as
  `dict.map { Set($0.keys) } ?? []` instead — identical runtime behavior, compiles.

## Empirical evidence captured (screen genuinely locked, 11:13 AEST)

- Standalone raw-dict probe (pre-fix, ad-hoc script): `CGSSessionScreenIsLocked=1`,
  `kCGSSessionOnConsoleKey=1` — confirms the key is present (not absent) under a simple same-user
  screen lock, so this exercises the pre-existing explicit-lock branch, not the new console-gated
  branch.
- Post-fix live probe (`OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter
  testLiveSystemProbePrintsRealLockState`): `isLocked=true isUnknown=false`, `rawKeysSeen` contains
  `CGSSessionScreenIsLocked` — satisfies plan.md Phase 3 step 3 and the PR-body checklist item
  "lock-screen manual test (step 3) run and reported isLocked=true".
- Full suite: `swift test` — 192 tests, 1 skipped (live-probe guard when env var unset), 0
  failures.

## Still outstanding (per plan.md, unchanged by this session)

- Phase 3 step 4 (FUS-via-SSH manual test, R1) — mandatory merge blocker, requires a second user
  account; NOT satisfied by a same-user screen lock (on-console stayed `true` in the probe above).
- Phase 3 step 5 (screensaver-without-password) — optional manual spot-check.
- macOS 14–15 residual (R3) — accepted in writing (auto-decisions #5), stays open.
