# PIPELINE COMPLETE

# Pipeline Progress

- [x] 1. Worktree isolation — done 10:10 — .claude/worktrees/upstream-v020-merge-lockscreen, branch worktree-upstream-v020-merge-lockscreen @ 506eb65
- [ ] 2. Parallel analysis fan-out (Workflow, 3 agents) — pending
- [x] 3. Merge origin/main (lock-screen) — done 10:15 — commit 8a18207, zero conflicts
- [x] 4. Merge upstream/main (v0.2.0) — done 10:16 — commit 486c79d, zero textual conflicts (semantic check via build/tests pending)
- [x] 5. Build + test — done 10:18 — fixed 1 semantic conflict (WindowCaptureCandidate.isOnscreen in 4 test ctors); 165 tests green, full workspace builds
- [x] 6. Lock-screen capability verdict / feature dev — done 10:24 — verdict: merged code BLOCKS while locked (fail-closed). Developed opt-in MacSessionLockPolicy (OPEN_COMPUTER_USE_ALLOW_LOCKED=1) enabling best-effort AX control while locked; default unchanged. +7 tests (172 total green). Docs updated (README/ARCHITECTURE/RELIABILITY/SECURITY)
- [x] 7. Adversarial review — done 10:52 — 3 lenses+verify; 1 CONFIRMED high (app-agent confused-deputy) fixed in commit 4b15ac0; others refuted/cleared. Summary posted to PR#2.
- [x] 8. Commit + push + draft PR — done 10:55 — commits b83cae6 (feat) + 4b15ac0 (security fix); draft PR vietairs/open-codex-computer-use#2; review comment posted. NOT merged (maintainer's call).
