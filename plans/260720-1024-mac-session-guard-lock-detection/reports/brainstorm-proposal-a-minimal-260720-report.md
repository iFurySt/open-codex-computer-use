## PROPOSAL A — Minimal Apple-Semantics Fix

### Design: New Decision Table

`SystemMacSessionStateProvider.parseSessionDict(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot`

| Input | isLocked | isUnknown | Rationale |
|---|---|---|---|
| `dict == nil` | `true` | `true` | Fail-closed (unchanged) — API failure, no signal |
| `dict.isEmpty` | `true` | `true` | Fail-closed (unchanged) — treat as no signal |
| Non-empty dict, `CGSSessionScreenIsLocked` **absent** | `false` | `false` | **THE FIX** — matches observed macOS behavior: key is omitted while unlocked |
| Key present, `Bool`/`NSNumber` → `true` | `true` | `false` | Explicit locked signal (unchanged) |
| Key present, `Bool`/`NSNumber` → `false` | `false` | `false` | Explicit unlocked signal (unchanged) |
| Key present, unparseable type (String, etc.) | `true` | `true` | Fail-closed (unchanged) — malformed signal, don't trust |

Only one line changes from current code: the "key absent" branch flips from `(true, true)` to `(false, false)`. No new signals, no new dict keys read, no heuristics beyond the one already-observed key. `kCGSSessionOnConsoleKey` etc. are *not* used as corroborating evidence — deliberately, to keep the change to a single flip and avoid inventing an unverified inference chain.

### Correctness Across macOS 12–26

- **macOS 26 (this machine):** empirically verified — key absent ⇔ unlocked, key present+true ⇔ locked. Direct evidence.
- **macOS 12–15:** the file-top comment claims "verified" but that claim is now known false at least on 26; I have **no independent verification** for 12–15 and treat the old comment as unreliable, not as corroborating evidence. Apple's `CGSessionCopyCurrentDictionary` behavior around this key is undocumented private API and has reportedly shifted across releases (community reports of the key sometimes being absent-when-unlocked, sometimes present-with-false-when-unlocked). This proposal is only confidently correct on confirmed OS versions — mark 12–15 as **uncertain, needs empirical recheck**, not just trust old comments.
- Corrective action tied to this fix: rewrite the file-top comment to state exactly what was verified, on what OS, when — no unverified version claims.

### Security Failure Modes (Both Directions)

- **False-locked (availability bug):** dict nil/empty, or key present with unparseable value → still fails closed. No regression; same conservative behavior as today.
- **False-unlocked (security bug) — the risk this proposal takes on:** if some macOS version behaves oppositely (key absent while *locked*), this fix would wrongly report unlocked and let tools run against a locked screen.
  - **Bound on this risk:** narrow and falsifiable — it only fires when `CGSessionCopyCurrentDictionary()` returns a non-empty dict with the key genuinely absent. That is a single, testable, deterministic condition per-OS-version, not a heuristic guess. It is not silent: `rawKeysSeen` diagnostic already surfaces which keys were present at runtime (per scout findings, MCPAppRuntime logs this), so a future wrong-direction OS can be caught from logs rather than failing invisibly.
  - Residual mitigation available without weakening this fix: keep `OPEN_COMPUTER_USE_ALLOW_LOCKED` opt-in unchanged (per constraint) as the explicit user-controlled fallback if a given OS's absent-key semantics ever prove wrong; the default posture itself is what's changing, not the escape hatch.

### Testability

- Expose `parseSessionDict` as `internal static` (drops the `private` on the parsing logic only, keeps `fetchFromSystem` as a thin wrapper calling `CGSessionCopyCurrentDictionary()` then delegating).
- New unit tests (`@testable import`) — 6 cases matching the table: nil dict, empty dict, non-empty dict/key-absent (**the regression test for this exact bug**), key=true, key=false, key=unparseable-string.
- All 8 existing lock-policy tests (fakes `FakeLockedSessionProvider`/`FakeUnlockedSessionProvider` are untouched, protocol unchanged) continue to pass unmodified — this fix only touches the private static parsing internals of one concrete provider.

### Est. LOC Changed

- `MacSessionGuard.swift`: ~15–20 lines (extract `parseSessionDict`, flip one branch, rewrite file-top comment).
- Test file: ~40–60 lines (6 new focused test functions).
- Docs (README.md:42–47, ARCHITECTURE.md §4, RELIABILITY.md): ~10–15 lines total, correcting "blocked while locked" framing to reflect that unlocked-by-default now works, and correcting the false "verified on macOS 12-15" claim.
- **Total: ~65–95 LOC.**

### Honest Weaknesses

1. **No independent evidence for macOS 12–15** — relies on discarding an already-proven-false comment rather than proving the new claim on those versions. If Apple's key-absent semantics differ by major version, this is wrong on those versions in the security-bad direction.
2. **Single-signal design** — uses only one dict key with no corroborating signal (e.g., cross-checking `kCGSSessionOnConsoleKey` or another session key) to increase confidence in the "absent = unlocked" inference. A false-unlocked here is silent to the *tool caller* (though visible in logs).
3. **Depends entirely on continued availability of `CGSessionCopyCurrentDictionary`** — private/undocumented API; Apple could change its shape in a future release with no compile-time signal, only a runtime behavior change this proposal doesn't add extra guardrails against beyond what already exists.
4. **No runtime self-check** — nothing in this design periodically cross-validates the inference against another lock-state source (e.g., `IOPMCopyAssertionsByProcess`, IOKit, or shelling to `ioreg`); it is a pure reinterpretation of the same one signal already in use.

---

**Unresolved questions:**
- Should the file-top comment's macOS 12–15 "verified" claim be downgraded to "assumed, unverified" or fully removed pending re-test on those versions?
- Is a corroborating second signal (e.g. `kCGSSessionOnConsoleKey`) worth the added complexity to bound the false-unlocked risk further, or is the single-signal design (matching Proposal A's minimalism) acceptable given YAGNI?