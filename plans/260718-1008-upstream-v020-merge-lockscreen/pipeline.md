# Cortex Pipeline — upstream v0.2.0 merge + lock-screen capability

Task: Sync fork vietairs/open-codex-computer-use with upstream iFurySt/open-codex-computer-use (v0.1.51 → v0.2.0), merge all locally developed features, verify/develop agents-work-while-screen-locked capability.
Task source: free text (/hvn:cortex --auto)
Mode: --auto (fully autonomous; ultracode on; Workflow engine)
Date: 2026-07-18 10:08 AEST

## ROUTE CARD
Risk: medium — upstream v0.2.0 breaking snapshot change (text_limit) overlaps files changed by both local features; no auth/payment/schema surface.
Familiarity: high — own fork; prior research (Stage Manager gap analysis, lockscreen research plans/260615-1505) exists.
Scope: multi-phase — 3-way merge (local main + origin/main + upstream/main) → capability gap analysis → conditional feature dev → ship.

Key facts discovered at classify time:
- merge-base with upstream: 40b1fc4 (v0.1.51 release)
- local main (506eb65): +Stage Manager background control (5418115), +install fix — UNPUSHED
- origin/main (83581f9): +lock-screen guard / app-screen validation / menu-bar status (f3db3b5+83581f9, duplicated commit pair) — NOT in local main
- upstream/main (c8a7758): 17 commits, v0.1.52→v0.2.0 (tree budget, breaking text_limit, Windows UTF-8, numeric element_index, anonymous web click controls)
- conflict surface: AccessibilitySnapshot.swift, ComputerUseService.swift, ComputerUseToolDispatcher.swift, MacOSAppAgentProxy.swift, tests, README, ARCHITECTURE.md

Route:
  1. Worktree isolation (EnterWorktree, branch from local main tip) — main-loop (git state)
  2. Parallel analysis fan-out — Workflow, 3 agents (upstream semantics / our features / lock-screen capability verdict), model sonnet
  3. Merge origin/main (lock-screen) into branch — main-loop git + guided resolution
  4. Merge upstream/main (v0.2.0) into branch — main-loop git + guided resolution
  5. Build + test (swift build/test, packages/OpenComputerUseKit) — delegated/inline
  6. Lock-screen capability verdict; develop gap if missing — Workflow/agents if dev needed
  7. Adversarial review (correctness/regression lenses, inherited tier) — Workflow
  8. Commit, push branch to origin, gh pr create --draft — main-loop (ship; never merge)

Skips (--auto, logged in auto-decisions): route-card confirm; brainstorm (scope concrete); /hvn-predict persona debate folded into stage-7 adversarial review; ship-gate attestation converted to logged decision; /hvn-* skill delegation replaced by direct Workflow/Agent equivalents (background job, harness-enforced EnterWorktree).
