# FUS-via-SSH gate — verification attempt & finding

Task: close the last open PR #5 checkbox — the fast-user-switch-away (FUS) invariant the lock-detection fix rests on.

## Invariant under test
`parseSnapshot` infers unlocked from an absent `CGSSessionScreenIsLocked` key **only** when
`kCGSSessionOnConsoleKey == true`. The fix is safe iff a genuine session-not-owning-console
(FUS-away or second account) actually reports `onConsole == false`, so the guard fails closed
(`isLocked=true`) there. A same-user screen lock keeps `onConsole == true` and therefore does NOT
exercise this branch.

## What automation confirmed
- Built a live poller (mirrors `parseSnapshot` classification) and sampled the real system 416×
  over ~3 min while the same user was active. Every sample: `onConsole=true lockKey=ABSENT ->
  unlocked (inferred on-console)`. Matches the fix's expected same-user-active behavior exactly and
  reproduces the original bug's root cause (lock key genuinely absent on this OS).
- Attempted to trigger FUS-away programmatically to drive the off-console branch:
  `SACSwitchToLoginWindow` (login.framework) resolves but returns **EINVAL (22)** for every
  signature tried (no-arg, `Int32` 0/1, nil pointer). The FUS switch cannot be invoked from a
  background / non-GUI process.

## Finding: the box is genuinely human-only (now empirically grounded)
The EINVAL from a headless context is the same condition the checkbox describes: FUS-away requires
a human at the physical machine (or a real loginwindow/GUI context), and specifically an SSH/tmux
session that stays open across the switch. It cannot be automated from this background job — which
is precisely why the PR marks it human-only. This is not a fix gap; it is an OS constraint on who
can flip the console owner.

Theoretical grounding for confidence: `kCGSSessionOnConsoleKey` is, by CGSession definition, "does
this session own the console." FUS-away hands the console to another session, so the departed
session's value is definitionally `false` → `parseSnapshot` returns `isLocked=true` (fail-closed).
The off-console branch is also already unit-tested.

## Human recipe (attempted with user, ~12:00–13:11)
1. Baseline confirmed on-console: `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter
   testLiveSystemProbePrintsRealLockState` printed `isLocked=false isUnknown=false` while the user
   was active (matches automation sample above).
2. Blocked on step 2 (fast-user-switch away): this Mac has **no inbound SSH** and **Fast User
   Switching is disabled** — the Apple menu shows only About/Settings/App Store/Recent
   Items/Force Quit/Sleep/Restart/Shut Down/Lock Screen/Log Out, no "Login Window..." or user list.
   Enabling FUS requires a System Settings change (Control Center toggle); the only other way to
   get off-console is Log Out, which ends the session entirely rather than switching it to the
   background — not equivalent to the intended test and destructive to the working session.

## Decision — accepted risk, closed without live off-console verification
User chose to accept this as residual risk rather than force a system-setting change or logout
just to run the test. Closed out in PR #5 body (checklist item now `[x]` marked
"closed out as accepted risk" with explanation) and via PR comment
(https://github.com/vietairs/open-codex-computer-use/pull/5#issuecomment-5018428722).

Confidence basis for accepting: (1) automated `SACSwitchToLoginWindow` call from a background
process returns `EINVAL` — the switch is gated to real interactive GUI action, so this box is
non-automatable in principle, not just inconvenient here; (2) `kCGSSessionOnConsoleKey` is defined
as "session owns console" — FUS-away flips it to `false` by definition for the departed session;
(3) the off-console branch (`false` → `isLocked=true`, fail-closed) is already covered by
`parseSnapshot` unit tests, so the logic path itself has test coverage even without a live OS
round-trip.

## Merge status
Nothing else blocks merge: suite green (192/1 skipped), all independent reviews PASS/clean, ship-gate
PASS. The FUS-via-SSH box is now closed as an accepted, documented residual risk — no live
off-console verification was obtained on this machine, and that limitation is recorded in the PR.
