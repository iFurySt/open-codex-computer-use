## Pre-merge review round (`c9085db`)

Applied cross-review **follow-up #2** and ran a fresh 3-lens review (correctness / security / breaking-change, strong-tier, each actionable finding adversarially verified by execution).

### Applied in `c9085db`
- **Fail-closed release signing** — `scripts/build-open-computer-use-app.sh` now refuses a release build whose signing would resolve to ad-hoc/unsigned, *before* any build work runs. Explicit override: `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` (loud warning that peer-auth ships inactive). Debug builds untouched. Verified: guard fires on explicit `adhoc` and on `auto`-fallback with zero side effects; override path and debug path behaviorally unchanged.
- **CI reconciliation (review-found, must-fix)** — the guard would have broken every tag push on forks without signing secrets: `release.yml`'s no-secrets path sets `CODESIGN_MODE=adhoc` for the npm artifacts. That path now sets the override explicitly and labels the consequence in the build log. *Maintainer call still open:* if you'd rather tag releases hard-require signing secrets, drop those two lines instead — see question below.
- **Doc truth alignment (review-found)** — `SECURITY.md`/`ARCHITECTURE.md` still quoted the team-only requirement; since `2ddecd1` the implementation also pins the agent's **bundle identifier** (team-only fallback when unbundled). Docs now match. README's "in signed release builds" corrected: enforcement activates in **any** Team-ID-signed agent build, including Dev bundles auto-signed with an Apple Development cert.

### Reviewed and NOT applied
- **Refuted (correctness, medium):** claimed cascade where a rejected peer triggers the client's stale-agent recovery (unlink live socket → orphan agent → spawn duplicates). Empirically disproven: the client dies on SIGPIPE at the `terminate` write before ever reaching unlink/relaunch. Residual UX wart (rejected invocations exit silently, reject reason only on agent stderr) — worth folding into the #4 work, not a blocker here.
- **Low, non-blocking:** (a) `ALLOW_ADHOC_RELEASE=1` + `CODESIGN_MODE=identity` with no identity set produces an unsigned build labeled as mode=none (pre-existing subshell `exit` swallow; fail-closed without the override); (b) the bundle-ID-pin requirement string itself has no unit test (private IO layer).
- **Deferred (unchanged):** Developer-ID marker OID pinning and the per-session capability model — both tracked in #4.

### State
Mechanism previously judged sound by both cross-review advisors; this round found no defect in the peer-auth code itself. Marking **ready for review** — merge remains your call.

**Open question:** should tag-push releases *require* signing secrets (fail CI) instead of explicitly opting into ad-hoc artifacts? Current choice preserves existing CI behavior.
