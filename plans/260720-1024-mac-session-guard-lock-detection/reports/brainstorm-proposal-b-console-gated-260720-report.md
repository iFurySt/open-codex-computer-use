# Proposal B — Console-Gated Absent-Key Fix

## Design: Decision Table

| Input to parse | isLocked | isUnknown | Rationale |
|---|---|---|---|
| `CGSessionCopyCurrentDictionary()` returns nil/empty dict | `true` | `true` | **UNCHANGED** — fail-closed, no signal at all |
| `CGSSessionScreenIsLocked` **present**, Bool/NSNumber → `true` | `true` | `false` | **UNCHANGED** — explicit locked signal |
| `CGSSessionScreenIsLocked` **present**, Bool/NSNumber → `false` | `false` | `false` | **UNCHANGED** — explicit unlocked signal |
| `CGSSessionScreenIsLocked` present but unparseable type | `true` | `true` | **UNCHANGED** — fail-closed on garbage |
| `CGSSessionScreenIsLocked` **absent**, `kCGSSessionOnConsoleKey` == `true` | `false` | `false` | **CHANGED** (was locked/unknown) — this is the fix |
| `CGSSessionScreenIsLocked` **absent**, `kCGSSessionOnConsoleKey` == `false`/absent/unparseable | `true` | `true` | **NEW branch** — off-console or ambiguous, stays fail-closed |

`kCGSSessionOnConsoleKey` parsing itself reuses the same Bool/NSNumber coercion, unparseable → treat as false (fail-closed).

## Correctness Across macOS 12–26

- **Empirically confirmed (this machine, macOS 26/Darwin 27):** unlocked + on-console → key absent, `kCGSSessionOnConsoleKey: 1` present.
- **Historical behavior (macOS 12–15, per community reports/Apple sample code circa 2010s–2020s, NOT independently re-verified this session):** `CGSSessionScreenIsLocked` was reportedly present as `false` when unlocked on older releases, not absent. If that older behavior still holds on some OS versions, this fix is a no-op there (key present+false already handled, console gate never triggers) — safe either way.
- **Uncertainty flag:** I have not verified on 16–25 (Ventura/Sonoma). The console gate degrades gracefully if the absent-key behavior varies by version — worst case it's overly conservative (still fail-closed) on a version where absent means something else, never overly permissive, because it requires the *additional* on-console signal before trusting "absent = unlocked."

## Security Failure Modes (Both Directions)

**False-locked (availability bug):** Off-console sessions (screen sharing to a non-console user, fast-user-switched-out session, SSH/daemon with no console dict at all → nil dict) will show locked/unknown even if genuinely unlocked. Acceptable — this is the existing fail-closed posture, not a regression; it just means the console gate is narrower than the true "unlocked" set.

**False-unlocked (security bug) — the one that matters:** Could the console gate ever fire while the screen is genuinely locked?
- `kCGSSessionOnConsoleKey` reflects whether *this login session* owns the console display, not whether the lock overlay is showing. Empirically, when the screen *is* locked, `CGSSessionScreenIsLocked` is present (`true`) — that branch is checked **first** and short-circuits before the absent-key/console-gate branch is ever reached. So the console gate only fires when the OS has *already* omitted the lock key entirely.
- Residual risk: an OS version/edge-case where the screen is locked AND the key is absent AND on-console is true. No evidence this occurs (locking is normally what causes the key to appear, per Apple's ScreenSaverEngine/loginwindow lock semantics), but it is *not provably impossible* — this is the honest gap. Mitigate by keeping `OPEN_COMPUTER_USE_ALLOW_LOCKED` opt-in unrelated and unaffected, and by fast-follow telemetry (log `rawKeysSeen` when this branch fires, already surfaced via `MCPAppRuntime` diagnostic) to catch anomalies in the field.
- **Fast-user-switching:** a switched-away session is off-console (`kCGSSessionOnConsoleKey` false/absent) → falls into fail-closed branch, not the gate. Correct.
- **SSH/daemon contexts:** typically get nil/empty dict (no session console info) → existing fail-closed nil-dict branch. Correct, unaffected.

## Testability

- Add internal seam: `static func parseSessionDict(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot` per scout recommendation, moving lines 98–119 logic in, extended to read `kCGSSessionOnConsoleKey`.
- New cases via `@testable import`: (1) key absent + on-console true → unlocked; (2) key absent + on-console false → fail-closed; (3) key absent + on-console absent → fail-closed; (4) key absent + on-console unparseable → fail-closed; (5) both keys absent (nil-ish) → existing fail-closed unaffected; (6) locked key present true, on-console irrelevant → still locked (regression guard proving console gate never overrides an explicit lock signal).
- All 14 existing tests (fakes bypass `fetchFromSystem` entirely) remain green untouched — protocol/fakes API unaffected.

## Est. LOC Changed

~25–35 LOC: extend `parseSessionDict` (or extract it, +seam), add on-console read/coerce helper (reuse existing Bool/NSNumber coercion), 6 new test functions (~40 LOC test-side, not counted above), file-top comment correction (~5 lines).

## Honest Weaknesses

1. On-console semantics are being repurposed as a locked/unlocked proxy — that's not their documented purpose; correctness rests on an empirical correlation, not a documented Apple contract, and Apple could change this in a future OS with no notice (private CGS API, no stability guarantee — same risk the *existing* code already carries).
2. Not verified on macOS 16–25; only 26 is empirically confirmed. The file-top comment must be corrected to state "absent-key = unlocked confirmed only on macOS 26" rather than reasserting the false 12–15 claim.
3. Screen-sharing-to-console-user edge case (remote user views the *same* console session) not analyzed — plausible this presents as on-console+key-absent while a physical observer sees something different; low real-world relevance for this project's target usage (local automation agent) but unresolved.
4. No production telemetry yet confirms zero false-unlocked incidents in the field — recommend a monitoring period before removing the diagnostic logging in `MCPAppRuntime`.

## Unresolved Questions

- Should the on-console read failure (key present but unparseable type) log a distinct diagnostic reason vs. the generic fail-closed path, to speed future triage?
- Is there budget/appetite to empirically verify on an intermediate macOS version (e.g., Sonoma 14) before merge, given the file-top comment currently makes a blanket 12–26 claim?