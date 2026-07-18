# Pipeline — PR #3 pre-merge tail (continue all --auto)

Task: Finish all in-flight work: apply cross-review follow-up #2 (fail-closed ad-hoc release signing) to PR #3, run pre-merge review & fix, drive PR #3 to merge-ready; complete PR #2 post-merge cleanup tail.
Task source: free text — "continue all --auto" resuming prior session (PR #2 merged, PR #3 open draft, issue #4 filed).
Timestamp: 2026-07-18 23:48 (Australia/Melbourne)

ROUTE CARD — PR #3 pre-merge tail + PR #2 cleanup (--auto, no confirm — logged)
Risk: HIGH — security surface (socket peer-auth, codesign policy); scope small (1 script + 3 docs)
Familiarity: HIGH — same session lineage, cross-review + impl already done
Scope: small — tail of R21-style ship route (build done; pre-merge gate remains)

Route:
  1. Fix: fail-closed release-signing guard + doc alignment — agent:sonnet (Workflow phase Fix)
  2. Smoke verify (bash -n + 4 behavioral stub tests) — same agent
  3. Pre-merge review fan-out: correctness / security / breaking-change — inherited tier (Fable 5) (Workflow phase Review)
  4. Adversarial verify of actionable findings — inherited tier (Workflow phase Verify)
  5. Apply confirmed fixes (if any), commit, push — main loop (git ops)
  6. PR #3 reply comment + mark ready-for-review (merge-ready; merge stays with user) — main loop
  7. PR #2 tail: base sync + worktree teardown — BLOCKED/deferred (see auto-decisions)

Skips: blindspot/brainstorm/predict/plan — tail continuation, unknowns already paid (R1/R21 rationale).
Cross-review follow-up #3 (Developer-ID marker OID pinning) — deferred to issue #4 (optional; dev-workflow regression risk).
Issue #4 implementation — NOT started (6 open design questions need maintainer answers).
