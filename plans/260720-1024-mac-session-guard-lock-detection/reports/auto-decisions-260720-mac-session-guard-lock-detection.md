# Auto-decisions — MacSessionGuard lock-detection fix (--auto run)

> RISK: HIGH — ran unattended

## 1. Route-card confirm skipped (10:25)
- What: R7 route executed without the confirm question.
- Why: user passed --auto to /hvn:cortex.
- Risk: none beyond the accepted unattended-run risk; card printed in chat + persisted in pipeline.md.
- Alternatives rejected: default interactive (contradicts explicit flag).
- Reversibility: full — pipeline stops at merge-ready PR; nothing merged.

## 2. Worktree mechanism adapted (10:26)
- What: session was pre-flagged as a worktree session, so EnterWorktree(name:) refused; used `git worktree add .claude/worktrees/fix-mac-session-guard-lock-detection -b fix/mac-session-guard-lock-detection origin/main` + EnterWorktree(path:).
- Why: harness enforces edit isolation; cortex worktree rule requires a fresh branch off base.
- Risk: none — identical isolation result.
- Reversibility: full — worktree removable after merge.

## 3. Locked-state verification will be manual (10:26)
- What: the fix will be live-verified in the UNLOCKED state only; the LOCKED state gets unit tests over injected session dictionaries plus a scripted manual verification procedure in the PR body.
- Why: autonomously locking the user's screen mid-session is disruptive and potentially destructive to their live work; the user explicitly asked for "deliberate testing against both real lock states", which the PR procedure preserves as a human step.
- Risk: locked-state behavior verified only via injected-dict tests until the user runs the probe while locked; mitigated by the fact that the LOCKED branch (key present = true) is the code path that already works today.
- Alternatives rejected: `pmset displaysleepnow` / ScreenSaverEngine to force a lock (disruptive, could interrupt user's active session and other running agents).
- Reversibility: n/a (verification approach, not code).

## 4. Brainstorm design auto-picked: Proposal B, console-gated (10:44)
- What: absent CGSSessionScreenIsLocked → UNLOCKED only when kCGSSessionOnConsoleKey coerces true; off-console/absent/unparseable stays fail-closed. Explicit lock key always checked first.
- Why: judge (opus) recommendation — strictly more conservative than A's bare flip (closes the fast-user-switched-away false-unlocked), ~10 extra LOC; C rejected on KISS/YAGNI + its own stale-notification false-unlocked path.
- Risk: relies on on-console correlate — addressed by red-team round-1 resolutions below.
- Alternatives rejected: A (minimal flip — false-unlocked when session backgrounded via FUS), C (multi-signal observer — over-engineered, new failure mode, author self-rejected).
- Reversibility: full until merge.

## 5. Plan-gate round 1 BLOCKED — controller adjudications (10:50)
- R1 (red-team #1, FUS correlate unverified): mandatory manual verification added to PR checklist — from SSH/tmux, fast-user-switch away, run live probe, MUST report locked. Cannot be executed autonomously (would hijack the user's console); PR stays merge-ready with explicit human-verification checklist.
- R2 (red-team #2, stale-unlocked cache): cache policy changed — NEVER cache isLocked=false snapshots; only fail-safe locked/unknown verdicts are cached (stale locked ≤200ms after unlock = one extra block, acceptable direction). Testable via extracted internal shouldCache seam + unit tests.
- R3 (red-team #3, fail-open unproven on macOS 14–25): residual ACCEPTED IN WRITING (red-team's own offered resolution) — an OS-version gate would keep the guard permanently broken (always-locked) on every supported OS except macOS 26, which is worse than the bounded residual. Mitigations: one-time stderr log when unlock is inferred from absent-key+on-console (log-based detection of a wrong-direction OS), corrected file-top comment stating the narrow verification scope, residual documented in plan + PR.
- R4 (notes 4–7): screensaver-without-password behavior documented + added to manual verification; test added for key present=true + on-console=false → locked (explicit-lock-wins pinned); FUS manual test specified to run from SSH (also exercises daemon nil-dict path).
- R5 (validation gap, README L42): README lock section correction moved from "optional" to required scope — absent evidence corroborated by on-console → unlocked; off-console/nil/unparseable → locked.
- Reversibility: full — plan-only changes, re-gated before implementation.

## 6. Plan-validation direction confirm skipped (10:55)
- What: direction locked without user stop — implement revised Proposal B plan (console-gated absent-key fix + asymmetric cache + one-shot inferred-unlock log; scope: MacSessionGuard.swift, tests, README L42).
- Why: --auto; round-2 red-team AND validation both PASS; riskiest accepted trade-off = macOS 14–15 fail-open residual accepted in writing with log-based detection (decision #5/R3).
- Risk: as documented in plan Risks section; mandatory human FUS verification remains a merge blocker in the PR checklist.
- Alternatives rejected: waiting for user confirmation (contradicts --auto); OS-version gate (worse — permanent false-locked on 14–15).
- Reversibility: single revertable commit; PR not merged by this pipeline.

## 7. Codex hop2 (plan review) timed out — resumed session re-check (11:06)
- What: on resume, a prior background `codex exec -m gpt-5.6-sol --reasoning-effort xhigh` run for stage 6 (adversarial plan review) was found to have failed with exit 124 (timeout) — see reports/codex-adversarial-plan-review-260720-report.md (transcript truncated mid-analysis, no verdict line).
- Why: environment/runtime cause unconfirmed; hop2 has now empirically timed out once in this environment.
- Decision: per the hop ladder, fall back to hop 3 (inherited-tier Claude opus/fable advisor) rather than retry hop2 a second time, to avoid spending another multi-minute budget on a hop that just failed.
- Reversibility: advisory gate only, no code affected.

## 8. Lock-window opportunism — reordered cook ahead of stage 6/7 (11:07–11:14)
- What: user reported the Mac is now physically locked and asked to retry the locked-state verification. This session is a background job whose shell keeps running under the locked console (the same mechanism the plan's FUS-via-SSH manual test relies on), so the transient locked window was used immediately: (a) ran a standalone raw-dict probe confirming `CGSSessionScreenIsLocked=1`, `kCGSSessionOnConsoleKey=1` while locked; (b) implemented Phase 1/2/3 of plan.md (parseSnapshot/coerceBool/shouldCache/InferredUnlockNotice extraction, README correction); (c) immediately ran `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState` while still locked — captured `isLocked=true isUnknown=false`, satisfying plan.md Phase 3 step 3 (lock-screen manual verification) for real, ahead of the originally-scoped stage 6 (codex plan review) and stage 7 (impl-notes init).
- Why: the locked window is transient and this evidence (Phase 3 step 3) cannot be manufactured later once the user unlocks; deferring cook to preserve strict stage order would have lost the opportunity. The plan itself was already twice red-teamed/validated (decisions #5, #6) before this reorder, so implementing it is low-risk relative to the value of the empirical capture.
- Risk: stage 6 (plan-level adversarial review) and stage 7 (impl-notes) now run retrospectively against a diff instead of a pre-implementation plan text — mitigated by running stage 6's review against the actual diff (superset of a plan-text review) immediately after.
- Note: this does NOT satisfy plan.md Phase 3 step 4 (mandatory FUS-via-SSH manual test, R1) — that scenario (on-console flips false) is different from a simple same-user screen lock (on-console stayed true here) and still requires a human with a second account, unchanged merge-blocker in the PR checklist.
- Reversibility: full — single revertable commit, PR not merged by this pipeline.

## 9. Ship-gate attestation skipped (11:30)
- What: ship-gate verdict (PASS) recorded without the interactive attestation question.
- Why: --auto.
- Risk: one human-only gate remains open (FUS-via-SSH, P1/R1) — carried into the PR body as an unchecked checklist item, not silently dropped.
- Reversibility: full — pipeline stops at merge-ready PR, nothing merged.
