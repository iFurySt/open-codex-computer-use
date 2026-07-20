Gaps found:

1. **README.md L42 now-false behavioral claim not corrected (requirement #12 under-honored).** Line 42 states: "any lock-state evidence that is **absent**, nil, or unparseable is treated as locked." The fix inverts exactly this for the absent case: absent `CGSSessionScreenIsLocked` + `kCGSSessionOnConsoleKey==true` → UNLOCKED. The plan's Docs section searched README only for a *macOS-version* claim, found none, and downgraded the README edit to "optional / skip if changelog noise." But the required mitigation names "README.md ~42-47 where the 'blocked while locked' framing... appear[s]... to reflect that unlocked-by-default now works." After this fix, L42 documents the old buggy semantics as intended behavior. This is a required, not optional, correction (small: L42 should say absent evidence is corroborated by on-console — on-console→unlocked, off-console/absent/nil/unparseable→locked). The plan must not ship code that contradicts its own README.

Non-gaps (verified against live source, plan is correct):
- Proposal B match, `parseSnapshot` seam signature, thin `fetchFromSystem` wrapper: correct (renamed from `parseSessionDict` — cosmetic only).
- Ordering: present-key handled before console gate via `guard let lockedValue = dict[key] else {<gate>}`; explicit-lock never overridden (test #8 guards it). Correct.
- `kCGSSessionOnConsoleKey` literal + shared `coerceBool`; absent+onconsole true→(false,false), false/absent/unparseable→(true,true). Correct (tests 3-7).
- nil/empty + unparseable-lock fail-closed unchanged; ALLOW_LOCKED untouched. Correct (do-not-touch list + tests 1,2,11).
- DEBUG `LOCK_FAIL_OPEN` hatch kept at its pre-key-check position (L102-106). Correct.
- `rawKeysSeen` + `requireUnlocked` stderr diagnostic preserved. Correct.
- File-top comment L4 false "macOS 12–15" claim corrected to Darwin 27 only. Correct.
- 11-case table covers full required regression matrix + NSNumber; existing fake-based policy tests bypass the seam, stay green. Correct.
- Proposal C rejected; no observer added. Correct.
- ARCHITECTURE.md L97 / RELIABILITY.md L33 / SECURITY.md L36 refer to *dict* nil/empty/parse-fail (still fail-closed post-fix), not key-absent — plan's "no edit required" there is defensible.

Verdict: BLOCKED