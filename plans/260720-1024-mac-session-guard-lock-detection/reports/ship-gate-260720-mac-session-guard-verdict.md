# Ship-gate — MacSessionGuard console-gated absent-key fix

**Verdict: PASS (--hard, R7 route) — merge-ready pending one outstanding human-only verification.**

## Predicted vs actual (predict-260720-mac-session-guard-lock-detection.md)

| # | Prediction | Resolution |
|---|---|---|
| P1 | Future OS: key-absent+on-console=true while genuinely locked → false-unlocked | Mitigated: explicit-lock-first ordering pinned by tests #8/#12 (both code-review and adversarial-diff-review traced this line-by-line); residual bounded, accepted in writing (plan.md Risks, R3) |
| P2 | Screen-sharing/remote-KVM ambiguous on-console | Documented as known limitation (out of scope) |
| P3 | File-top comment reasserts false "verified 12-15" claim | Fixed — states macOS 26/Darwin 27 only |
| P4 | `parseSessionDict`/`parseSnapshot` seam skipped | Extracted as `internal static func parseSnapshot` — mandatory acceptance criterion met |
| P5 | DEBUG `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` reordered | Confirmed unchanged position (first branch after nil/empty guard) by code-review + adversarial-diff-review |
| P6 | Cache TTL touched incidentally | Superseded by red-team R2 (auto-decisions #5) — `currentSnapshot()` caching was *intentionally* revised (asymmetric `shouldCache`), a scoped, tested, plan-directed change, not an incidental touch |
| P7 | Key-string typo silently no-ops the fix | Explicit positive-assertion tests (#3, #4) catch this; both reviewers traced literal key strings against test dict literals |
| P8 | `MCPAppRuntime` startup diagnostic drifts from reality | Checked by inspection (`MCPAppRuntime.swift:62-63`): fires only on `isUnknown`, which still only means nil/empty/parse-fail post-fix — text remains accurate, file untouched (out of scope) |
| P9 | `AllowWhileLockedNotice` spuriously fires post-fix | `AllowWhileLockedNotice` untouched, gated only via `MacSessionGuard.requireUnlocked`'s policy switch — unaffected |
| P10 | Real system-lock unrepeatable without disruption | One real lock-screen spot-check captured live during this session (see below) — no repeated disruption needed |

All GO-conditional mitigations (P1, P5, P7, P8) are satisfied.

## Plan-vs-shipped reconciliation

- Scope: exactly the 3 files plan.md named (`MacSessionGuard.swift`, `OpenComputerUseKitTests.swift`, `README.md`); "Do NOT touch" list untouched — confirmed by 2 independent reviewers.
- One documented deviation (impl-notes.md): `fetchFromSystem`'s raw-keys line implemented as `dict.map { Set($0.keys) } ?? []` instead of the plan snippet's `Set(dict?.keys ?? [])`, which does not type-check in Swift. Behavior-identical.
- Execution-order deviation (auto-decisions #7/#8): cook ran ahead of the codex plan-review and impl-notes-init stages to capture a transient locked-screen window; the adversarial diff review afterward covers the same attack surface against the actual code (a superset of a plan-text-only review).

## Gates run

- Unit tests: `swift test` — 192 tests, 1 skipped (env-gated live probe), 0 failures.
- Live probe, screen genuinely locked (captured live this session): `isLocked=true isUnknown=false`, `rawKeysSeen` contains `CGSSessionScreenIsLocked` — satisfies plan.md Phase 3 step 3.
- Code review (opus): DONE_WITH_CONCERNS — code ship-ready; concern is process only (manual gate below).
- Security scan (sonnet): DONE — no secrets, no bypass, fail-closed ordering verified.
- Adversarial diff review (opus, hop-3 fallback after codex hop-2 timeout — auto-decisions #7): **Verdict: PASS** — all 6 attack-surface items checked against actual code, zero BLOCKER.

## Outstanding merge blocker (unchanged by this session, human-only)

**Plan.md Phase 3 step 4 (R1) — mandatory FUS-via-SSH manual test:** from an SSH/tmux session, fast-user-switch away from the console (or use a second account's login window), then from that still-open session run `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState`. Must report `isLocked=true`. This proves the load-bearing invariant "not physically frontmost ⇒ kCGSSessionOnConsoleKey==false" that the whole fix rests on — a simple same-user screen lock (already captured, see above) does not exercise it, since `kCGSSessionOnConsoleKey` stayed `true` in that probe. Cannot be run autonomously (requires a second account / physically switching away); goes in the PR body as an unchecked checklist item for the user to run before merging.

**PR-body checklist:**
- [x] Lock-screen manual test (step 3) — run, reported `isLocked=true`
- [ ] FUS-via-SSH manual test (step 4) — **required before merge**
- [ ] Screensaver-without-password manual test (step 5) — optional spot-check
- [x] Accepted residual risk (macOS 14–15 unverified) stated in PR body

## --auto note

Ship-gate attestation question skipped per --auto; this verdict stands as the logged decision (auto-decisions entry to follow). Merge itself is never performed by this pipeline regardless of mode.
