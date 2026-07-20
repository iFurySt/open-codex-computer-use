# Pipeline — MacSessionGuard lock-detection fix

Task: Fix MacSessionGuard treating absent CGSSessionScreenIsLocked key as "locked" — on macOS 26 the key is omitted when genuinely unlocked, so the guard can never observe "unlocked". Security-sensitive: fix must not weaken the fail-closed posture for genuinely-locked/unknown states.
Task source: free text via /hvn:cortex --auto (bug proven in prior session; memory: lock-detection-false-positive-and-shared-agent-race)
Timestamp: 2026-07-20 10:24 AEST
Autonomy: --auto (all interactive stops skipped + logged to reports/auto-decisions-260720-mac-session-guard-lock-detection.md)

## Classification
- Risk: HIGH — fail-closed security guard (lock policy, SECURITY.md surface, prior security decision PR #2); over-correction would allow tools while genuinely locked without opt-in. Keywords: security, lock/login.
- Familiarity: HIGH — root cause empirically proven on this machine (standalone probe; MacSessionGuard.swift:107-109); fork built this feature.
- Scope: SMALL — MacSessionGuard.swift + OpenComputerUseKitTests.swift; all R7 gates kept, stages lean.

## Route (R7)
0. Worktree isolation — branch fix/mac-session-guard-lock-detection off origin/main — main-loop (harness EnterWorktree; session pre-flagged as worktree → manual `git worktree add` + path entry)
1. blindspot --deep — parallel scouts (haiku) via Workflow
2. brainstorm --html — 3 proposals (sonnet) + judge (opus) via Workflow; main-loop publishes Artifact; --auto auto-picks recommendation
3. predict — persona debate (sonnet high); report → reports/predict-260720-mac-session-guard-lock-detection.md
4. plan --tdd — planner (sonnet high)
5. red-team + validate — 2 parallel (opus); --auto logs direction decision
6. codex adversarial-review <plan> — main-loop external; hop 2 `codex exec -m gpt-5.6-sol --reasoning-effort xhigh` (plugin lacks feature; CLI 0.144.4 present)
7. impl-notes init — main-loop
8. cook (no --auto, TDD) — implementer (sonnet): failing tests → fix → swift test + live probe (unlocked state)
9. impl-notes review — main-loop
10. code-review ∥ security-scan — parallel (opus reviewer; sonnet scanner)
11. codex adversarial-review <diff> — main-loop external, same hop ladder
12. ship-gate --hard — main-loop verdict; --auto logs skipped attestation
13. ship: commit → push origin (vietairs fork only) → draft PR → pre-merge review & fix (parallel fable/opus lenses) → STOP merge-ready (no merge)
14. deferred: post-merge base sync (git pull --ff-only) + local worktree teardown on later resume; remote branch kept

Skips: none of R7's stages. Interactive stops skipped per --auto, each logged.
Constraint: locked-state live verification never locks the user's screen autonomously — unlocked state probed live; locked state gets a scripted manual verification procedure documented in the PR.
