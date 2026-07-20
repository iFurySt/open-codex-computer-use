PROPOSAL C — Multi-signal state tracking (distributed notifications cross-check)

**Design**: Keep `fetchFromSystem()` as primary source but add a background `DistributedNotificationCenter` observer registered at process start, listening for `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`. Maintain a `lastKnownFromNotification: Bool?` mutable state (actor/lock-protected). Parse decision table becomes:

| CGSession dict | Notification cache | Result |
|---|---|---|
| nil/empty dict | any | isLocked=true, isUnknown=true (fail-closed, unchanged) |
| key absent | notif says locked | isLocked=true, isUnknown=false |
| key absent | notif says unlocked | isLocked=false, isUnknown=false |
| key absent | no notif seen yet (nil) | isLocked=true, isUnknown=true (fail-closed) — cannot yet confirm unlocked |
| key=true (Bool/NSNumber) | any | isLocked=true, isUnknown=false (dict always wins when present) |
| key=false | any | isLocked=false, isUnknown=false |
| unparseable type | any | isLocked=true, isUnknown=true (fail-closed, unchanged) |

**Correctness across macOS 12-26**: `com.apple.screenIsLocked`/`screenIsUnlocked` are long-standing, widely-used private-but-stable distributed notifications (used since ~10.x for lock-state watchers). Behavior is consistent historically, but Apple has never documented them publicly — no contractual guarantee they fire in every path (e.g., fast user switching, some remote-desktop/VNC sessions, screen-saver-vs-lock distinction changed in later macOS). Honest uncertainty: cannot verify notification reliability on this machine without live testing; scout found no existing test/observation confirming they fire for this environment's lock/unlock cycle.

**Security failure modes**:
- False-locked (availability bug): if notifications never arrive and dict key stays absent → permanently isUnknown=true → same behavior as pre-fix (annoying but safe).
- False-unlocked (security bug, the dangerous direction): only reachable via the "key absent + notif says unlocked" row. This requires the *notification* to have fired correctly for the current session — if a stale/incorrect notification arrives (e.g., missed lock notification, cross-session leakage in edge cases), the guard would incorrectly report unlocked while the screen is actually locked. This is a **new attack surface** not present in Proposal A/B (simple key-absent-means-unlocked). Bounded only by trusting notification correctness, which is unverifiable/undocumented.
- Process-lifecycle pitfall: notifications missed before listener starts (agent launched after lock event) — cache stays nil, falls to fail-closed row, acceptable. But agent processes without a run loop (CLI/dispatcher-style invocation, not `MCPAppRuntime`) never receive distributed notifications at all — `DistributedNotificationCenter` delivery requires a running run loop. Scout confirms `ComputerUseToolDispatcher.callTool()` is a call site — unclear if it always runs inside `MCPAppRuntime`'s run loop or can be invoked standalone; if the former, notification observer never gets a chance to fire, and the design silently degrades to Proposal A/B's absent-key logic anyway, making the added complexity useless in that path.

**Testability**: Requires injecting/mocking `DistributedNotificationCenter` — no protocol seam exists for it today; would need a new `NotificationObserving` abstraction plus a fake, doubling test surface vs. a pure dict-parsing seam. Must test: notif-before-dict-read ordering races, notif never received, notif received then session dict starts reporting key again (must not let stale notif override a fresher dict signal — table above naively lets dict `key present` win, but that requires additional recency/staleness logic not shown, adding more surface).

**Est. LOC changed**: ~150-220 (new observer class + actor-safe state + wiring at process start + protocol/fake extensions + tests) — 3-4x larger than a pure dict-parsing fix.

**Honest weaknesses**: This is over-engineering for the stated bug. The empirical bug is fully explained and fully fixable by correcting the dict-parsing logic alone (key-absent ≠ locked). Adding a second signal (a) introduces an undocumented/private API dependency, (b) creates the one false-unlocked path this fix must avoid bounding tightly, (c) may not even fire in the dispatcher's process context (run-loop dependency), and (d) costs 3-4x the LOC and test surface for a correctness gain that is unproven (no repro showing the dict-only fix is actually wrong). Recommend against Proposal C unless a controlled test shows the corrected dict parsing alone still misses cases the notifications would catch — no such evidence currently exists.

**Unresolved questions**:
- Does `ComputerUseToolDispatcher.callTool()` always execute inside `MCPAppRuntime`'s run loop, or can it be invoked from a context with no run loop (breaking notification delivery)?
- Is there any documented/observed case where the corrected dict-only parsing (absent key → unlocked) is wrong on macOS 12-25, that would justify the added notification cross-check?