Reading additional input from stdin...
[2m2026-07-20T01:03:06.125044Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125074Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125087Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125091Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125101Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125104Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:06.125108Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
OpenAI Codex v0.144.4
--------
[1mworkdir:[0m /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[1mmodel:[0m gpt-5.6-sol
[1mprovider:[0m openai
[1mapproval:[0m on-request
[1msandbox:[0m read-only
[1mreasoning effort:[0m xhigh
[1mreasoning summaries:[0m none
[1msession id:[0m 019f7d0c-4b0b-75a2-a79b-7c7da9332112
--------
[36muser[0m
Adversarial cross-model gate review of an implementation plan for a SECURITY-SENSITIVE macOS lock-detection fix. Read plans/260720-1024-mac-session-guard-lock-detection/plan.md and packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift (current, pre-fix source). Context: CGSSessionScreenIsLocked is empirically absent when unlocked on macOS 26; current code treats absent as locked, so the guard can never report unlocked. The plan gates absent-key->unlocked on kCGSSessionOnConsoleKey==true, never caches unlocked snapshots, adds a one-shot inferred-unlock stderr log, and accepts a written macOS 14-15 residual. Attack the plan: parse decision-table correctness, cache asymmetry semantics/thread-safety, validity of the on-console inference, test-matrix completeness, doc-claim accuracy. Do NOT re-litigate the already-accepted macOS 14-15 residual unless its documentation is incoherent. Output: numbered findings each tagged BLOCKER or NOTE, then a final line exactly "Verdict: PASS" or "Verdict: BLOCKED". Max 50 lines.
[2m2026-07-20T01:03:07.883048Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883075Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883080Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883084Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883087Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883102Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:03:07.883105Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1m[33mwarning:[0m[0m Skill descriptions were shortened to fit the 2% skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest.
[1mhook:[0m [2mSessionStart[0m
[1mhook:[0m [2mSessionStart[0m
[1mhook:[0m [2mSessionStart[0m
[1mhook:[0m [2mSessionStart[0m
[1mhook:[0m [2mSessionStart[0m
[1mhook:[0m [2mSessionStart[0m Completed
[1mhook:[0m [2mSessionStart[0m Failed
[1mhook:[0m [2mSessionStart[0m Completed
[1mhook:[0m [2mSessionStart[0m Completed
[1mhook:[0m [2mSessionStart[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m
[1mhook:[0m [2mUserPromptSubmit[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m Failed
[1mhook:[0m [2mUserPromptSubmit[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m Completed
[1mhook:[0m [2mUserPromptSubmit[0m Failed
[35m[3mcodex[0m[0m
I’m using the code-review skill for the adversarial gate and will delegate independent checks of the decision table, cache/concurrency behavior, and inference/tests/docs. I’ll first load the repository’s mandatory context and the current plan/source, then reconcile findings against direct file evidence.
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "wc -l README.md docs/REPO_COLLAB_GUIDE.md docs/ARCHITECTURE.md docs/design-docs/core-beliefs.md .agents/rules/primary-workflow.md .agents/rules/development-rules.md .agents/rules/orchestration-protocol.md .agents/rules/documentation-management.md /Users/hvnguyen/.agents/skills/ck-code-review/SKILL.md && sed -n '1,260p' /Users/hvnguyen/.agents/skills/ck-code-review/SKILL.md"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[31m exited 1 in 0ms:[0m
wc: .agents/rules/primary-workflow.md: open: No such file or directory
wc: .agents/rules/development-rules.md: open: No such file or directory
wc: .agents/rules/orchestration-protocol.md: open: No such file or directory
wc: .agents/rules/documentation-management.md: open: No such file or directory
     185 README.md
      47 docs/REPO_COLLAB_GUIDE.md
     185 docs/ARCHITECTURE.md
      12 docs/design-docs/core-beliefs.md
     208 /Users/hvnguyen/.agents/skills/ck-code-review/SKILL.md
     637 total

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,260p' /Users/hvnguyen/.agents/skills/ck-code-review/SKILL.md"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
---
name: ck:code-review
description: "Review code quality with evidence-based rigor. Supports input modes: pending changes, PR number, commit hash, and codebase scan. Focuses on bugs, regressions, maintainability, reliability, and verification gaps."
user-invocable: true
when_to_use: "Invoke to review diffs, PRs, commits, or full codebases."
category: utilities
keywords: [review, quality, verification, reliability]
argument-hint: "[#PR | COMMIT | --pending | codebase [parallel]]"
metadata:
  author: claudekit
  version: "2.0.0"
---

# Code Review

Production-readiness code review with technical rigor, evidence-based claims, and verification over performative responses. Reviews focus on production risks, regression paths, and whether the implementation matches the requested change.

## Input Modes

Auto-detect from arguments. If ambiguous or no arguments, prompt via `AskUserQuestion`.

| Input | Mode | What Gets Reviewed |
|-------|------|--------------------|
| `#123` or PR URL | **PR** | Full PR diff fetched via `gh pr diff` |
| `abc1234` (7+ hex chars) | **Commit** | Single commit diff via `git show` |
| `--pending` | **Pending** | Staged + unstaged changes via `git diff` |
| *(no args, recent changes)* | **Default** | Recent changes in context |
| `codebase` | **Codebase** | Full codebase scan |
| `codebase parallel` | **Codebase+** | Parallel multi-reviewer audit |

**Resolution details:** `references/input-mode-resolution.md`

### No Arguments

If invoked WITHOUT arguments and no recent changes in context, use `AskUserQuestion` with header "Review Target", question "What would you like to review?":

| Option | Description |
|--------|-------------|
| Pending changes | Review staged/unstaged git diff |
| Enter PR number | Fetch and review a specific PR |
| Enter commit hash | Review a specific commit |
| Full codebase scan | Deep codebase analysis |
| Parallel codebase audit | Multi-reviewer codebase scan |

## Core Principle

**YAGNI**, **KISS**, **DRY** always. Technical correctness over social comfort.
**Be honest, be brutal, straight to the point, and be concise.**

Default assumption: reviewed code may be AI-assisted. Do not trust polished shape, confident comments, or happy-path tests. Verify behavior, project-rule compliance, and scope discipline from evidence.

No rubber-stamp reviews. The reviewer is not trying to please the author or preserve momentum; the reviewer enforces the rulebook and blocks defects, regressions, hidden scope drift, and AI-slop patterns.

Verify before implementing. Ask before assuming. Evidence before claims.

## Practices

| Practice | When | Reference |
|----------|------|-----------|
| **Spec compliance** | After implementing from plan/spec, BEFORE quality review | `references/spec-compliance-review.md` |
| Receiving feedback | Unclear feedback, external reviewers, needs prioritization | `references/code-review-reception.md` |
| Requesting review | After tasks, before merge, stuck on problem | `references/requesting-code-review.md` |
| Verification gates | Before any completion claim, commit, PR | `references/verification-before-completion.md` |
| Edge case scouting | After implementation, before review | `references/edge-case-scouting.md` |
| **Checklist review** | Pre-landing, `/ck:ship` pipeline, security audit | `references/checklist-workflow.md` |
| **Task-managed reviews** | Multi-file features (3+ files), parallel reviewers, fix cycles | `references/task-management-reviews.md` |

## Quick Decision Tree

```
SITUATION?
│
├─ Input mode? → Resolve diff (references/input-mode-resolution.md)
│   ├─ #PR / URL → fetch PR diff
│   ├─ commit hash → git show
│   ├─ --pending → git diff (staged + unstaged)
│   ├─ codebase → full scan (references/codebase-scan-workflow.md)
│   ├─ codebase parallel → parallel audit (references/parallel-review-workflow.md)
│   └─ default → recent changes in context
│
├─ Received feedback → STOP if unclear, verify if external, implement if human partner
├─ Completed work from plan/spec:
│   ├─ Stage 1: Spec compliance review (references/spec-compliance-review.md)
│   │   └─ PASS? → Stage 2 │ FAIL? → Fix → Re-review Stage 1
│   ├─ Stage 2: Code quality review (code-reviewer subagent)
│   │   └─ Scout edge cases → Review standards, performance
│   └─ Verification gate → Run required tests/builds before claims
├─ Completed work (no plan) → Scout → Code quality → Verification
├─ Pre-landing / ship → Load checklists → Two-pass review → Verification
├─ Multi-file feature (3+ files) → Create review pipeline tasks (scout→review→fix→verify)
└─ About to claim status → RUN verification command FIRST
```

### Review Protocol

**Stage 1 — Spec Compliance** (load `references/spec-compliance-review.md`)
- Does code match what was requested?
- Any missing requirements? Any unjustified extras?
- MUST pass before Stage 2

**Stage 2 — Code Quality** (code-reviewer subagent)
- Only runs AFTER spec compliance passes
- Standards, security, performance, edge cases

**Final Verification**
- Runs AFTER Stage 2 passes
- Re-run the relevant tests, build, lint, or manual reproduction
- Verify accepted findings are fixed and no new regression is introduced
- Critical findings block merge until fixed and re-verified

## Receiving Feedback

**Pattern:** READ → UNDERSTAND → VERIFY → EVALUATE → RESPOND → IMPLEMENT
No performative agreement. Verify before implementing. Push back if wrong.

**Full protocol:** `references/code-review-reception.md`

## Requesting Review

**When:** After each task, major features, before merge

**Process:**
1. **Scout edge cases first** (see below)
2. Get SHAs: `BASE_SHA=$(git rev-parse HEAD~1)` and `HEAD_SHA=$(git rev-parse HEAD)`
3. Dispatch code-reviewer subagent with: WHAT, PLAN, BASE_SHA, HEAD_SHA, DESCRIPTION
4. Fix Critical immediately, Important before proceeding

**Full protocol:** `references/requesting-code-review.md`

## Edge Case Scouting

**When:** After implementation, before requesting code-reviewer

**Process:**
1. Invoke `/ck:scout` with edge-case-focused prompt
2. Scout analyzes: affected files, data flows, error paths, boundary conditions
3. Review scout findings for potential issues
4. Address critical gaps before code review

**Full protocol:** `references/edge-case-scouting.md`

## Task-Managed Review Pipeline

**When:** Multi-file features (3+ changed files), parallel code-reviewer scopes, review cycles with Critical fix iterations.

**Fallback:** Task tools (`TaskCreate`/`TaskUpdate`/`TaskGet`/`TaskList`) are CLI-only — unavailable in VSCode extension. If they error, use `TodoWrite` for tracking and run pipeline sequentially. Review quality is identical.

**Pipeline:** scout → review → fix → verify (each a Task with dependency chain)

```
TaskCreate: "Scout edge cases"         → pending
TaskCreate: "Review implementation"    → pending, blockedBy: [scout]
TaskCreate: "Fix critical issues"      → pending, blockedBy: [review]
TaskCreate: "Verify fixes pass"        → pending, blockedBy: [fix]
```

**Parallel reviews:** Spawn scoped code-reviewer subagents for independent file groups (e.g., backend + frontend). Fix task blocks on all reviewers completing.

**Re-review cycles:** If fixes introduce new issues, create cycle-2 review task. Limit 3 cycles, escalate to user after.

**Full protocol:** `references/task-management-reviews.md`

## Verification Gates

**Iron Law:** NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE

**Gate:** IDENTIFY command → RUN full → READ output → VERIFY confirms → THEN claim

**Requirements:**
- Tests pass: Output shows 0 failures
- Build succeeds: Exit 0
- Bug fixed: Original symptom passes
- Requirements met: Checklist verified

**Red Flags:** "should"/"probably"/"seems to", satisfaction before verification, trusting agent reports

**Full protocol:** `references/verification-before-completion.md`

## Integration with Workflows

- **Subagent-Driven:** Scout → Review → Verify before next task
- **Pull Requests:** Scout → Code quality → Verify → Merge
- **Task Pipeline:** Create review tasks with dependencies → auto-unblock through chain
- **Cook Handoff:** Cook completes phase → review pipeline tasks → all complete → cook proceeds
- **PR Review:** `/ck:code-review #123` → fetch diff → full review pipeline on PR changes
- **Commit Review:** `/ck:code-review abc1234` → review specific commit with full pipeline

## Codebase Analysis Subcommands

| Subcommand | Reference | Purpose |
|------------|-----------|---------|
| `/ck:code-review codebase` | `references/codebase-scan-workflow.md` | Scan & analyze the codebase |
| `/ck:code-review codebase parallel` | `references/parallel-review-workflow.md` | Ultrathink edge cases, then parallel verify |

## Bottom Line

1. Resolve input mode first — know WHAT you're reviewing
2. Technical rigor over social performance
3. Scout edge cases before review
4. Evidence before claims

Verify. Scout. Question. Then implement. Evidence. Then claim.

## Workflow Position

**Typically follows:** `/ck:cook` (review after implementation), `/ck:fix` (review after bug fix)
**Typically precedes:** `/ck:ship` (ship after review passes)
**Related:** `/ck:scout` (scout before reviewing), `/ck:test` (test before reviewing)

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'docs/design-docs/core-beliefs.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# 核心理念

这些理念用于约束这个模板在项目早期的默认方向。

## Agent-First 的工作原则

- 人来定方向，Agent 负责执行和推进。
- 仓库内可追溯的知识，比私有上下文更重要。
- Agent 反复失败时，优先修脚手架和环境，不是继续加 prompt 压力。
- 短而稳定的入口文档，比越来越长的大 prompt 更可靠。
- 能变成机械检查的约束，就不要只停留在口头规范。
- 速度很重要，但无节制地堆积熵会迅速拖垮效率，所以要持续整理和收口。

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' '/Users/hvnguyen/.agents/skills/ck-code-review/references/checklist-workflow.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# Checklist-Based Review Workflow

How to apply structured review checklists during code review.

## When to Use

- Pre-landing review (from `/ck:ship` pipeline)
- Explicit request for checklist review
- Security audit before release
- Code-reviewer agent when reviewing significant changes (10+ files or security-sensitive)

## Workflow

### 1. Auto-Detect Project Type

```bash
# Check for web app frameworks
if grep -qE '"(react|vue|svelte|next|nuxt|angular)"' package.json 2>/dev/null; then
  echo "web-app"
# Check for API patterns
elif ls src/routes/ src/api/ src/controllers/ app/controllers/ 2>/dev/null | head -1; then
  echo "api"
else
  echo "base-only"
fi
```

### 2. Load Checklists

Always load: `checklists/base.md`

Overlay based on detection:
- `web-app` → also load `checklists/web-app.md`
- `api` → also load `checklists/api.md`
- Both detected → load both overlays

### 3. Get the Diff

```bash
git fetch origin main --quiet
git diff origin/main
```

**CRITICAL:** Read the FULL diff before flagging anything. Checklist suppressions require full context.

### 4. Two-Pass Review

**Pass 1 (CRITICAL) — Run first:**
- Scan diff against ALL critical categories (base + overlays)
- Each finding must include: `[file:line]`, problem, fix
- These block `/ship` pipeline

**Pass 2 (INFORMATIONAL) — Run second:**
- Scan diff against ALL informational categories (base + overlays)
- Same format: `[file:line]`, problem, fix
- Included in PR body but don't block

### 5. Check Suppressions

Before reporting any finding, verify it's NOT in the suppressions list (bottom of `base.md`).

Key suppressions:
- Already addressed in the diff
- Readability-aiding redundancy
- Style/formatting issues
- "Consider using X" when Y works fine

### 6. Output

```
Pre-Landing Review: N issues (X critical, Y informational)

**CRITICAL** (blocking):
- [src/auth/login.ts:42] User input is interpolated directly into a query
  Fix: Use the project's parameterized query helper before passing user input

**Issues** (non-blocking):
- [src/api/users.ts:88] Magic number 30 for pagination limit
  Fix: Extract to constant `DEFAULT_PAGE_SIZE = 30`
```

### 7. Critical Issue Resolution

For each critical issue, use `AskUserQuestion`:
- Problem with `file:line`
- Recommended fix
- Options:
  - A) Fix now (recommended)
  - B) Acknowledge and proceed
  - C) False positive — skip

If user chose A (fix): apply fixes, commit, then re-run tests before continuing.

## Integration with /ck:ship

The ship pipeline calls this workflow at Step 4. Critical findings block the pipeline. Informational findings are included in the PR body.

## Integration with /ck:code-review

When invoked as part of standard code review, the checklist augments (not replaces) the existing scout → review → fix → verify pipeline. Checklist findings are merged with code-reviewer's own findings.

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'docs/REPO_COLLAB_GUIDE.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# 仓库协作约定

这份文档定义的是一个 Agent-first 仓库的默认协作方式。真正和技术栈强相关的约束，建议拆到相邻专题文档里维护，不要把这里写成大杂烩。

## 开发原则

- 优先选择简单、清晰、可观测的方案，不要堆难以维护的复杂度。
- 以 Agent 可读、可执行为目标组织仓库；重要信息如果只存在聊天记录和脑子里，等于不存在。
- 代码、文档、测试、配置和发布记录要尽量同源更新。
- 如果 Agent 在同一类问题上反复失败，优先修环境、修脚手架、修规范，不要把“多试几次 prompt”当主方案。
- 每次修 bug，都顺手检查测试和文档是否该补强，尽量让同类问题只修一次。

## 文档纪律

- `AGENTS.md` 只做路由，不要在里面堆一大坨规则。
- `docs/` 是仓库级知识的正式来源。
- 行为一旦变化，对应文档就要在同一次改动里同步更新。
- 仓库内文件、目录、脚本入口和文档链接一律使用相对路径，不要写任何机器相关的绝对路径。
- 比起继续往大文档里堆内容，更推荐新增一份边界清楚的小文档。

## Git 与评审

- commit 尽量保持范围清晰、描述准确。
- `git push` 前先同步远端最新代码，避免把过期分支状态直接推上去。
- 提交或发 PR 前，确认文档、示例、脚本和 history 是否已经反映最终状态。
- 复杂或高风险改动，先落一份 execution plan 到 `docs/exec-plans/`。
- 评审里尽量引用仓库内文件，不要依赖只有少数人知道的上下文。

## 测试与验证

- 每次有实质性代码变更，都应该让验证能力比改之前更强一点。
- 优先沉淀成仓库里可直接运行的命令和脚本。
- 如果项目包含 UI，要保证本地能独立启动、验证。
- 如果项目依赖 logs、metrics、traces，最好能提供本地或 CI 可用的访问路径。
- 即使项目还没接入真实业务构建链路，仓库级 CI 也应该先能跑起来。

## CI/CD 与交付方式

- CI 至少要守住仓库可读性和基础安全，不要等项目变大后再补。
- CD 骨架应该优先产出明确制品和 provenance，而不是过早假设部署目标。
- 未来接入真实技术栈时，优先在现有流水线上扩展，不要另起一套临时脚本把它绕开。

## 配置卫生

- 示例配置和实际默认值要尽量一致。
- 所有启动所需的环境变量和外部依赖都要写清楚。
- 不要让关键初始化步骤只存在 README 的角落里，能脚本化就脚本化。

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'README.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
import Foundation
import ApplicationServices

// macOS CGSession lock state keys — verified on macOS 12–15 (Monterey–Sequoia) and macOS 26
// CGSSessionScreenIsLocked: Bool — true when session is locked
// Key absent or dict nil/empty → treat as locked (fail-closed)
let cgSessionScreenIsLockedKey = "CGSSessionScreenIsLocked"

public protocol MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot
}

public struct MacSessionSnapshot {
    public let isLocked: Bool
    public let isUnknown: Bool   // true when dict was nil/empty/parse-failed
    public let rawKeysSeen: Set<String>

    public init(isLocked: Bool, isUnknown: Bool, rawKeysSeen: Set<String>) {
        self.isLocked = isLocked
        self.isUnknown = isUnknown
        self.rawKeysSeen = rawKeysSeen
    }
}

// TTL for CGSessionCopyCurrentDictionary cache — 200ms balances IPC cost vs responsiveness
private let sessionStateCacheTTL: TimeInterval = 0.200

// Behavior when the screen is locked. Default fail-closed (block); opt-in allow is
// enabled with OPEN_COMPUTER_USE_ALLOW_LOCKED and permits best-effort control while locked.
//
// Why "best-effort" and opt-in only: every action tool delivers input process-targeted —
// accessibility (AXUIElementPerformAction / AXUIElementSetAttributeValue) or CGEvent.postToPid
// — not through the global HID event tap (globalPointerFallbacksEnabled() defaults false).
// Process-targeted delivery keeps working while the login window owns the screen, so an agent
// can still read the AX tree and drive an accessibility-controllable app. What does NOT work
// while locked: window screenshots (the OS returns blank for security; WindowCapture already
// yields a nil image for off-screen windows), and any coordinate-only path that needs a visible
// cursor. The default stays blocked so the security guarantee is unchanged unless the operator
// explicitly opts in.
public enum MacSessionLockPolicy: String, Sendable {
    case blockWhileLocked
    case allowWhileLocked

    public static let environmentKey = "OPEN_COMPUTER_USE_ALLOW_LOCKED"

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> MacSessionLockPolicy {
        let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "1", "true", "yes", "on", "allow":
            return .allowWhileLocked
        default:
            return .blockWhileLocked
        }
    }
}

// Process-global one-shot stderr notice, emitted the first time allow-while-locked lets a
// locked action through, so operators see the degraded contract without per-call spam.
private final class AllowWhileLockedNotice: @unchecked Sendable {
    static let shared = AllowWhileLockedNotice()
    private let lock = NSLock()
    private var emitted = false

    func emitIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !emitted else { return }
        emitted = true
        fputs("[open-computer-use] \(MacSessionLockPolicy.environmentKey) is set — permitting best-effort Computer Use while macOS is locked. Screenshots are unavailable while locked and input is delivered process-targeted (accessibility) only; this is not equivalent to an unlocked, logged-in session.\n", stderr)
    }
}

public final class SystemMacSessionStateProvider: MacSessionStateProvider {
    private var cachedSnapshot: MacSessionSnapshot?
    private var cacheTimestamp: TimeInterval = 0
    // Lock for thread-safe cache access
    private let lock = NSLock()

    public init() {}

    public func currentSnapshot() -> MacSessionSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let cached = cachedSnapshot, (now - cacheTimestamp) < sessionStateCacheTTL {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let fresh = Self.fetchFromSystem()
        lock.lock()
        cachedSnapshot = fresh
        cacheTimestamp = now
        lock.unlock()
        return fresh
    }

    private static func fetchFromSystem() -> MacSessionSnapshot {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any], !dict.isEmpty else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        }
        let rawKeys = Set(dict.keys)
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LOCK_FAIL_OPEN"] == "1" {
            return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
        }
        #endif
        guard let lockedValue = dict[cgSessionScreenIsLockedKey] else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        let isLocked: Bool
        if let boolVal = lockedValue as? Bool {
            isLocked = boolVal
        } else if let numVal = lockedValue as? NSNumber {
            isLocked = numVal.boolValue
        } else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)
    }
}

public struct MacSessionGuard {
    private let provider: MacSessionStateProvider
    private let policy: MacSessionLockPolicy

    public init(
        provider: MacSessionStateProvider = SystemMacSessionStateProvider(),
        policy: MacSessionLockPolicy = .fromEnvironment()
    ) {
        self.provider = provider
        self.policy = policy
    }

    public func requireUnlocked(for toolName: String) throws {
        let snapshot = provider.currentSnapshot()
        guard snapshot.isLocked else { return }

        if snapshot.isUnknown {
            fputs("[open-computer-use] Lock state unknown — CGSessionCopyCurrentDictionary returned nil/empty/parse-failed (keys: \(snapshot.rawKeysSeen.sorted().joined(separator: ","))). Treating as locked.\n", stderr)
        }

        switch policy {
        case .blockWhileLocked:
            throw ComputerUseError.stateUnavailable("Computer Use cannot run while macOS is locked. Unlock the Mac, run open-computer-use inside a dedicated logged-in desktop session, or set \(MacSessionLockPolicy.environmentKey)=1 to permit best-effort accessibility control while locked (screenshots stay unavailable while locked).")
        case .allowWhileLocked:
            AllowWhileLockedNotice.shared.emitIfNeeded()
        }
    }

    // Current snapshot for menu bar status display (never throws)
    public func currentState() -> MacSessionSnapshot {
        return provider.currentSnapshot()
    }
}

[32m succeeded in 0ms:[0m
# open-computer-use

[![English](https://img.shields.io/badge/English-Click-yellow)](./README.md)
[![简体中文](https://img.shields.io/badge/简体中文-点击查看-orange)](./README.zh-CN.md)
[![Release](https://img.shields.io/github/v/release/iFurySt/open-codex-computer-use)](https://github.com/iFurySt/open-codex-computer-use/releases)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/iFurySt/open-codex-computer-use)
<a href="https://llmapis.com?source=https%3A%2F%2Fgithub.com%2FiFurySt%2Fopen-codex-computer-use" target="_blank"><img src="https://llmapis.com/api/badge/iFurySt/open-codex-computer-use" alt="LLMAPIS" width="20" /></a>

> [!TIP]
> Interested in Browser Use? Check out [open-browser-use](https://github.com/iFurySt/open-codex-browser-use).

---

`open-computer-use` is an open-source `Computer Use` service wrapped as `MCP`. Any AI agent or MCP client can use it to run Computer Use on macOS, Linux, and Windows.

This project was inspired by OpenAI's [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/). It showed that non-intrusive CUA can be built on top of Accessibility, so I decided to build an open-source version.

I started this repo with my [harness template](https://github.com/iFurySt/harness-template), a template for quickly spinning up AI-first projects. It has been one of our most useful workflows lately, especially for nearly 100% AI-generated projects. I also wrote [a post](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/) about the methodology behind it.

## Demos

### Codex App and Codex CLI

[![Open Computer Use custom demo cover](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

<sub><em>`open-computer-use` used as Computer Use in Codex App and Codex CLI, matching the official experience.</em></sub>

### Gemini CLI

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI connects to `open-computer-use` through MCP and runs full Computer Use actions.</em></sub>

### Linux

https://github.com/user-attachments/assets/e036b1c8-2200-4896-abd4-19225915cf66

<sub><em>`open-computer-use` running on Linux.</em></sub>

## Limitations

**Lock Screen:** By default, Computer Use is blocked while macOS is locked (fail-closed). `CGSessionCopyCurrentDictionary` is unavailable to unprivileged processes when the session is locked; any lock-state evidence that is absent, nil, or unparseable is treated as locked. For fully attended, screenshot-driven automation, unlock the Mac or use a dedicated logged-in desktop session.

For unattended agents (Claude Code, Codex) that must keep working while the screen is locked, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` to opt into **best-effort** control while locked. This works because every action tool delivers input process-targeted — accessibility actions (`AXUIElementPerformAction` / `AXUIElementSetAttributeValue`) or `CGEvent.postToPid`, never the global HID event tap — which keeps functioning while the login window owns the screen. Under this opt-in an agent can still read the accessibility tree via `get_app_state` and drive an accessibility-controllable app with element-targeted `click` / `type_text` / `scroll` / `set_value`. **Known limitations while locked:** window screenshots return blank (macOS blocks capture for security, so `get_app_state` yields the AX tree without an image) and coordinate-only paths that need a visible cursor are unreliable — prefer element-targeted (`element_index`) actions.

**Trust boundary (read before enabling):** the opt-in is off by default. When you run from the `.app` bundle, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` in the shell that first launches the agent — the policy is fixed for that agent's lifetime (quit it from the menu bar to change it) and is passed only through the trusted launch environment, not the per-call IPC channel, so another process cannot flip it against a running agent. The app-agent socket is peer-authenticated: on each connection the agent checks the caller's uid (`getpeereid`) and, whenever the agent binary carries a Team Identifier (any signed build, including Dev bundles auto-signed with an Apple Development certificate), requires the connecting process to be code-signed by the same developer (Team Identifier) — and, when the agent runs from a bundle, with the agent's own bundle identifier — via its audit token. This **raises the bar** — a foreign, unsigned, or other-developer binary can no longer connect and drive the agent. It does **not** make the agent safe on an untrusted machine: a process running as your user can still `exec` the legitimate, same-developer-signed CLI (it lives at a fixed path in the app bundle) and relay commands through it, so same-uid code you don't control can still reuse the agent's Accessibility grant — including while the screen is locked. Unsigned local `swift build` binaries fall back to same-uid trust only (a one-time stderr notice is printed). The release build script refuses to produce an ad-hoc-signed/unsigned release bundle unless `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` is set explicitly, so a distributed release cannot ship with peer authentication silently inactive. **For hostile or multi-tenant machines, use a dedicated logged-in session — do not rely on peer-auth or the locked opt-in as an isolation boundary.**

## Quick Start

```bash
npm i -g open-computer-use
```

The npm package also exposes `ocu` as the short CLI alias.

> [!IMPORTANT]
> The macOS runtime requires macOS 14.0 or later.

**On macOS, run it once and grant `Accessibility` and `Screen Recording`. Windows and Linux do not need this step.**

```bash
open-computer-use
# or
ocu
```

Before using it, install it into your agent:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
```

Or add it to your own client manually:

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
```

### Skill

Install the skill directly:

```bash
# Install for Codex
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y
npx skills ls -g -a codex | rg 'open-computer-use'
```

Install for Claude Code:

```bash
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use -y
```

Update an existing global install, including the Codex install created above:

```bash
npx skills update open-computer-use -g -y
```

You can also manually download and install the
[`open-computer-use` skill](./skills/open-computer-use).

## More

Besides the MCP JSON config above, you can also use the built-in commands:

```bash
# Install into Codex by writing to ~/.codex/config.toml
open-computer-use install-codex-mcp
ocu install-codex-mcp

# Install as a Codex plugin, mainly for Codex App
open-computer-use install-codex-plugin

# Install into Claude Code by writing to ~/.claude.json
open-computer-use install-claude-mcp

# Install into Gemini CLI for the current project by writing to ./.gemini/settings.json
open-computer-use install-gemini-mcp

# Install into Gemini CLI user config instead
open-computer-use install-gemini-mcp --scope user

# Install into opencode by writing to ~/.config/opencode/opencode.json (or the active config file)
open-computer-use install-opencode-mcp

# Call a single Computer Use tool and print the MCP-style JSON result
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'

# Run a sequence in one process so element_index state can be reused
# Sequence runs sleep 1s between successful operations by default
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

# Check permissions; onboarding only opens when something is missing
open-computer-use doctor

# Run local validation from a source checkout
make smoke
OPEN_COMPUTER_USE_STRESS_LOOPS=20 make stress
make agent-smoke
make agent-smoke SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=claude,codex --command=open-computer-use
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=claude,codex --command=open-computer-use
OPEN_COMPUTER_USE_HERMES_PROVIDER=anthropic OPEN_COMPUTER_USE_HERMES_MODEL=claude-opus-4-20250514 make agent-smoke AGENTS=hermes SCENARIO=fixture-full
node ./scripts/run-agent-smoke-tests.mjs --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514
node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=hermes --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --hermes-max-turns=12

# Show help
open-computer-use -h
ocu -h
```

## Cursor Motion

Cursor Motion is an open-source cursor motion system for macOS, based on public information shared by members of the Software.Inc team. You can download the app from the [Releases page](https://github.com/iFurySt/open-codex-computer-use/releases).

[![Cursor Motion custom demo cover](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## Star History

<a href="https://www.star-history.com/?repos=iFurySt%2Fopen-codex-computer-use&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
    <img alt="Star History Chart for open-computer-use" src="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
  </picture>
</a>

## License

[MIT](./LICENSE)

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'docs/ARCHITECTURE.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# 架构总览

这个仓库当前已经从模板收敛成一个本地 `computer-use` 项目。主线仍是 Swift 实现的 macOS automation MCP server，同时新增了实验性的 Windows 和 Linux runtime，用独立 Go 二进制暴露同一组 9 个 Computer Use tools。

## 当前目录结构

- `apps/OpenComputerUse`
  主入口，负责 `mcp`、`doctor`、`list-apps`、`snapshot`、`call`、`turn-ended` 等 CLI 命令，以及 `-h` / `--help` / `-v` / `--version` 这类全局参数；不带参数启动时会先检查权限，只有缺失时才进入无 Dock 图标的 app 模式权限引导窗口，`doctor` 也只会在检测到缺失权限时拉起这套 onboarding UI。
- `apps/OpenComputerUseFixture`
  本地 GUI fixture app，用来承载低风险、可预测的点击/输入/滚动/拖拽验证路径。
- `apps/OpenComputerUseSmokeSuite`
  端到端 smoke runner，会拉起 fixture 和 MCP server，并通过 JSON-RPC 真实调用 9 个 tools；同时也支持单独的 visual cursor idle smoke，用跨进程 observation file 断言等待下一次 move 时是 anchored tip + tiny rotate wobble，而不是横向漂移。
- `apps/OpenComputerUseWindows`
  实验性 Windows runtime。它不依赖 Swift 或 `.app` bundle，Go CLI/MCP 入口会嵌入 PowerShell UI Automation bridge，构建产物是 `open-computer-use.exe`，并随已有 npm 包的 `dist/windows/<arch>/` bundled artifacts 分发。
- `apps/OpenComputerUseLinux`
  实验性 Linux runtime。它不依赖 Swift 或 `.app` bundle，Go CLI/MCP 入口会嵌入 Python AT-SPI bridge，构建产物是 `open-computer-use`，并随已有 npm 包的 `dist/linux/<arch>/` bundled artifacts 分发。
- `packages/OpenComputerUseKit`
  核心库，包含：
  - MCP stdio transport 与 tool registry
  - app discovery
  - Accessibility / 窗口 snapshot
  - 键鼠输入模拟
  - software cursor overlay
  - fixture test bridge
- `experiments/CursorMotion`
  独立的 Swift cursor motion lab，用于试验 `Bezier + arc + spring` 参数模型、调参 UI 和独立渲染，不直接耦合主 MCP runtime。
- `experiments/StandaloneCursor`
  新的独立 Swift cursor viewer，直接复用 `scripts/cursor-motion-re/official_cursor_motion.py` 里收敛出来的候选路径、score 与 raw spring timeline，用来观察更贴近 binary lift 的表现。
- `scripts/`
  仓库级自动化命令，包括 smoke test、`.app` 打包入口、Windows `.exe` / Linux binary 构建入口、npm 分发脚本，以及 `scripts/computer-use-cli/` 这个用于探测官方 bundled `computer-use` 的 Go helper。
- `skills/`
  面向 agent runtime 的可安装 skill。当前 `skills/open-computer-use/SKILL.md` 只作为轻量入口和目录，安装、MCP/CLI 使用、排障等细节拆到相邻 `references/` 文件里按需加载；`scripts/package-skill.sh` 负责校验并打包 `.zip` / `.skill` 制品。
- `docs/`
  逆向分析、执行计划、history 和项目约束。

## 运行分层

### 1. App Mode 层

- `OpenComputerUse` 默认 app 模式会拉起 `PermissionOnboardingApp`。
- app bundle 以 `LSUIElement` agent-style 形态运行，默认不在 Dock 暴露常驻图标，但仍可按需显示权限窗口。
- 当用户从终端执行 macOS 版 `open-computer-use mcp`、`doctor`、`call`、`snapshot` 或 `list-apps` 时，CLI 会先通过 LaunchServices 启动同一个 `.app` bundle 的隐藏 app agent，并通过用户临时目录下的 Unix domain socket 转发请求；真正调用 Accessibility、ScreenCaptureKit 和动作 tools 的进程始终是 `Open Computer Use.app`，不是 iTerm / Terminal / Node launcher。
- 主窗口负责渲染 `Accessibility` / `Screen & System Audio Recording` 两类权限卡片、`Allow` / `Done` 状态和 relaunch 后的状态收敛；当两项权限都已完成时会自动关闭，不再要求用户手动退出。
- 辅助 drag panel 会跳转到对应的 `System Settings` 页面；点击 `Allow` 后，panel 会从主窗口里的按钮位置做一段 spring + curved frame 的入场，再落到 `System Settings` 内容区下沿。panel 默认保持在窗口右侧内容区下方居中并固定贴近窗口底边，不再依赖实时扫描权限页内部 `+ / -` 控件行；窗口层级上会显式排在当前 `System Settings` 窗口之上，避免被权限列表内容盖住，同时尽量减少对系统设置自身滚动区域的干扰。panel 内也补了显式返回按钮，允许用户中断当前 guidance、回到 onboarding 主窗口重新选择权限步骤。
- 权限状态会合并 TCC 持久授权记录与当前 app 进程的 runtime preflight：TCC 中任一匹配 client 已授权即可视为 granted，避免 CLI 子进程与 GUI app 对授权状态看到不一致的结果；如果当前 `.app` 进程已经通过 `AXIsProcessTrusted()` / `CGPreflightScreenCaptureAccess()`，也会立即视为 granted，避免 stale 或不匹配的 TCC path 记录让 onboarding 浮层继续停留。正式 release 仍以 CI 打出来的 `Open Computer Use.app` 为准，而本地 debug/dev 打包现在显式命名为 `Open Computer Use (Dev).app`，并在 dev bundle 运行时优先认当前 dev 副本，避免系统设置里出现两个完全同名的条目。

### 2. MCP 层

- 面向 MCP host 的外部 transport 仍是 `stdio`；macOS 终端 CLI 到 `.app` app agent 之间额外有一层本地 Unix domain socket 代理，用来保证真实 automation 运行在 app bundle 权限身份下。
- 该 socket 有**对端认证**（`SocketPeerAuthenticator` + 纯策略 `AppAgentPeerAuthPolicy`）：`acceptLoop` 对每个连接先 `getpeereid` 校验同 uid，再经 `LOCAL_PEERTOKEN` audit token + `SecCodeCopyGuestWithAttributes` 要求对端满足 `anchor apple generic and identifier "<agent bundle id>" and certificate leaf[subject.OU] = "<agent TeamID>"`（同开发者签名且 pin 本 app 的 bundle identifier；agent 非 bundle 运行时仅 team pin）。未签名 dev 构建退化为仅同 uid（打印一次提示）。详见 `docs/SECURITY.md`。
- 当 `OPEN_COMPUTER_USE_VISUAL_CURSOR` 未被显式关闭时，`mcp` 命令会切到一个最小 AppKit runtime：主线程保留 event loop 承载 overlay UI，stdio server 仍在后台线程串行读取与响应。
- 请求 framing 采用一行一个 JSON-RPC message。
- 当前支持的 method：
  - `initialize`
  - `notifications/initialized`
  - `notifications/turn-ended`
  - `ping`
  - `tools/list`
  - `tools/call`
- `notifications/turn-ended` 是开源版显式的 turn boundary hook；收到后会清理当前进程里的 visual cursor overlay。CLI `open-computer-use turn-ended [payload]` 也会通过 macOS distributed notification 通知正在运行的 AppKit MCP 进程执行同一类清理，用于接 Codex legacy notify 的 after-agent payload。

### 3. Tool Service 层

- `ComputerUseService` 负责把 Computer Use tool 请求映射到本地能力，`ComputerUseToolDispatcher` 则把 9 个 tool 的参数解析与 service 方法分发收敛成 MCP server 和 `open-computer-use call` 共用的一层。
- `list_apps` 通过 Spotlight metadata query 拉取标准 application 目录里的 app bundle，并读取 `kMDItemUseCount` / `kMDItemLastUsedDate_Ranking` 这类系统元数据；再与 `NSWorkspace` 的运行态 app 合并，输出“当前运行中 + 近 14 天用过”的视图。
- `get_app_state` 优先走真实 AX / 窗口截图；真实 app 必须同时有未最小化的 `AXWindow` 和可匹配的 on-screen `CGWindow`。如果目标 app 只是隐藏或暂时没有 on-screen window，会先 best-effort unhide / activate / `open -b` / `AXRaise` 并短暂重试，以贴近官方 `computer-use` 会把 Lark / Electron 窗口拉回再采集的行为；恢复后仍无法匹配时返回官方风格的 `Apple event error -10005: cgWindowNotFound`，不再把 application 根节点或无截图窗口伪装成可操作状态。当目标是仓库内 fixture app 时，回退到 fixture 导出的合成状态。真实 AX tree 默认在 macOS、Linux、Windows 上最多渲染 1200 个节点、64 层深度；显式 `get_app_state` / `snapshot` 可通过 `max_tree_nodes` / `max_tree_depth` 覆盖预算，action tools 的刷新结果仍使用默认预算。snapshot 文本默认截断到 500 字符；显式 `get_app_state` / `snapshot` 可通过 `text_limit` 正整数或 `"max"` 覆盖，action tools 的刷新结果仍使用 500 字符默认值。对 Electron/WebView 这类深层 UI 会压缩空 `AXGroup` / `AXUnknown` wrapper、过滤 `AXScrollToVisible` 噪音和空字符串属性，避免 action-critical 的输入框被无语义容器挤出节点预算；但如果匿名通用节点暴露 `AXPress` / `AXConfirm` / `AXOpen` 且 frame 有效、尺寸紧凑，会保留为带窗口相对 `Frame` 的 `button`，让 icon-only Web 控件仍能获得可区分的 `element_index`，同时继续过滤零尺寸或覆盖大面积页面的匿名点击容器。对原生 open panel / Finder column view 这类把内容放在 `AXContents` / `AXVisibleChildren` 里的控件，也会把可见文件项纳入元素树。
- MCP `tools/list` 的 description / input schema 当前按官方 `computer-use` 的 9 个 tools 文案和参数面收敛，尽量减少 host 侧提示词和 tool surface 偏差。
- `open-computer-use call <tool> --args '{...}'` 会直接输出 MCP-style JSON result；`open-computer-use call --calls '[...]'` / `--calls-file <path>` 会在同一进程里顺序执行 JSON 数组里的 tool calls，并复用同一个 `ComputerUseService` 内存态，因此 `get_app_state` 之后的 action tool 可以继续使用同一轮 snapshot 的 `element_index`。序列执行默认会在成功的相邻操作之间 sleep 1 秒，也可以用 `--sleep <seconds>` 覆盖；遇到 `isError=true` 的 tool result 后停止。
- 对真实 app 的 `get_app_state` / action tool 入口，当前只保留一层密码管理器 bundle denylist：bundle-id 直传时直接返回 safety denial；名称匹配时默认不解析到这些 app。终端、Chrome / Atlas 和系统组件不再属于内置阻止目标。
- 普通 app 的 element frame 当前按“窗口左上角为原点”的 window-relative 坐标输出，便于后续把 `element_index` 和截图坐标统一到同一套参考系。
- `click` / `set_value` 在执行真实动作前后，会额外驱动一层透明 `SoftwareCursorOverlay` window：两者的移动阶段现在共用一条 heading-driven 的官方风格 motion 内核，显式把“当前 cursor 朝向”和“最终 resting pose”一起喂给选路器，优先生成需要时先掉头、再沿车头方向推进的 C 形/单侧大弧轨迹；首次显示时按官方 binary 的 fresh state 从 AppKit 全局 `(0,0)` window origin 生成起点，后续动作继续复用上一帧 visible tip。真正显示出来的 cursor 不再直接等于 path sample，而是经过一层独立的 visual dynamics 状态，把 visible tip、velocity、angle 和 fog/offset 持续推进。`click` 结尾会衔接 click pulse 和更明显但仍然很小的 rotate wobble，`set_value` 则只做 settle / idle，不给 pulse；两者收尾后会在目标点继续保持 idle 状态，等待下一次动作时 tip 保持 anchored、只保留可感知的小角度摆动；只有连续 30 秒没有新动作时才做 cleanup，这样连续 tool call 不会反复从 fresh `(0,0)` 起步；如果宿主在任务 / turn 结束时发出 `turn-ended`，cursor 会立即消失并清掉本轮位置状态。
- overlay 的 visual style 不再自己从官方 app bundle 裁 `SoftwareCursor` 小图；主 MCP runtime 现在和 `CursorMotion` 一样优先渲染仓库里沉淀的 `official-software-cursor-window-252.png` baseline，只有资源缺失时才退回 `OpenComputerUseKit` 内部的程序化 pointer/fog fallback。命中点 anchor 仍固定在 `126x126` 画布里的同一组 tip-offset 上；glyph 自身的 neutral heading 继续沿用 `CursorMotion` / 官方 baseline 的 `-3π/4`。主 runtime overlay window 按 AppKit 全局坐标移动，因此在把 AX / `CGWindowList` 产出的 y-down screen-space 点击目标喂给 overlay 之前，会先转换成对应屏幕的 AppKit 全局坐标；路径选路用屏幕上实际可见的 AppKit forward heading，进入 visual dynamics / render state 前则把 velocity 的 y 轴翻回 CursorMotion 的 y-down screen state，再交给 AppKit 绘制层做角度和 `dy` 翻转。程序化 fallback 保留 neutral artwork correction，把它的天然轮廓轴对齐到 `CursorMotion` / 官方 baseline 的 `-3π/4` forward 方向，但不让实验线依赖 runtime 代码。
- overlay 的层级不再固定 `.floating`；现在会跟随 snapshot 命中的目标 window id / layer，把自己排到该目标 window 之上，而不是粗暴压到所有前台 app 最上层。
- overlay 的曲线路径不再只按固定 Bezier 模板生成；当前主线采用 reverse-engineering 约束下的 heading-driven candidate 族，候选只保留 `direct` / `turn` / `brake` / `orbit` 这些能稳定产出单侧主弧的 family，并继续保留 target-window 命中策略作为同类候选间的 tie-break。原始 binary lift 恢复出来的 `20` 条路径和 score 仍然保留在独立的 `StandaloneCursor` viewer / Python 重建脚本里，用于对照分析，不再直接作为 runtime 默认 chooser。
- overlay 的 progress 曲线也不再是固定 `easeInOut`；主线现在复用官方 `response=1.4`、`dampingFraction=0.9`、`dt=1/240` 的 spring/`VelocityVerlet` 形状，默认 move 时长对齐已恢复出的 close-enough endpoint-lock 时间 `343 / 240 = 1.4291667s`，不再按路径距离额外压缩。
- overlay 不再依赖临时 `terminal settle` 补丁来修尾；主线现在统一改成“路径层给目标点，visual dynamics 层给可见姿态”的双层模型，所以 move 末段、pulse 和 idle 共用同一套状态，不会再出现 endpoint 锁住后只剩原地翻角的收尾。
- overlay 的渲染输入也从单一 `rotation` 扩展成 `rotation + cursorBodyOffset + fogOffset + fogScale`，让速度滞后能真正体现在画面上，而不是只存在于主循环内部状态；其中 `rotation` 现在按二进制里 `SoftwareCursorStyle.angle + CursorView._animatedAngleOffsetDegrees` 的分层去近似，不再把“跟随运动方向的主朝向”和“小幅 wiggle offset”压成同一个受限小角度。
- 动作型 tools 对普通 app 采用“非侵入优先，物理指针路径显式 opt-in”策略：
  - `perform_secondary_action` 只执行目标元素已经暴露出来的 AX action；无效 action 返回官方风格的 `... is not a valid secondary action for ...`，fixture 的 `Raise` 路径也不再为了测试去准备全局物理指针输入
  - `set_value` 会先用 `AXUIElementIsAttributeSettable(kAXValueAttribute)` 判断目标是否真的是可设置值元素，只有 settable 时才调用 `AXUIElementSetAttributeValue`；不可设置时返回官方风格的 non-settable 错误，不退到键盘输入、剪贴板或未公开的文本替换接口
  - element-targeted `click` 的左键路径会先试原生列表的 `AXSelectedChildren` 选择，再试 `AXPress` / `AXConfirm` / `AXOpen` 这类真正语义化的激活动作；如果目标本身不可点，还会继续尝试其子孙 AX 元素（例如 Finder sidebar row 下面暴露 `AXOpen` 的 cell）和命中点附近的 AX hit-test 结果，最后才会退到 `postToPid` 定向鼠标事件。`AXRaise` / `kAXMainAttribute` / `kAXFocusedAttribute` 这类 activation-only fallback 只允许窗口级元素使用，避免普通静态文本或容器把“获得焦点”误报成“点击已处理”；`click_count > 1` 也会优先重复可用的 AX action
  - 对 renderer 合成的 summary `text` 行，`click` 不再默认点击父容器中心；这类元素使用左侧安全锚点。对普通 row/container/text 的后代候选，也会过滤右侧紧凑 hover action（例如 Lark / Electron 会话列表里的“完成”勾），避免把主行点击误操作成 side action；Electron/Lark 这类 app 的 WebArea 合成文本会优先寻找紧邻的行级 `AXPress` 祖先并静默执行，避免用物理鼠标点行。浏览器 WebArea（例如 Chrome/GitHub）不走这条 Electron-scoped 行级祖先点击优化，仍保留通用 link/container 点击路径。命中点如果只反查到覆盖整页的 Electron/WebArea 级 AX 元素，不再继续扫描整个大容器的子孙候选，避免一次行点击被远处的可点击元素截走。
  - `AXUIElementCopyElementAtPosition` 做坐标命中，尽量把 coordinate click 反解成可操作 AX 元素
  - `CGEvent.postToPid` 定向发送键盘事件，避免为了 `type_text` / `press_key` 抢前台；`type_text` 会把文本按 Unicode extended grapheme cluster 聚合成小批量 `keyboardSetUnicodeString` 事件，避免中文标点、emoji / 代理对和组合字符被逐个 UTF-16 code unit 拆开后在 Electron 富文本输入框里乱序或变形。如果当前 focused element 的 `AXValue` 可设置，`type_text` 会优先按可编辑内容追加并写回 `AXValue`，这覆盖 Feishu / Electron 富文本输入框不可靠接收后台键盘事件的场景，并会过滤已知占位提示，避免把 placeholder 拼进草稿；如果当前 focused element 不是可编辑文本目标，`type_text` 会报错要求先 click 文本输入区或使用 `set_value`，不再把无效果的后台键盘投递当成成功；`press_key` 的 xdotool parser 覆盖官方 binary key table 里常见的 `BackSpace`、`Page_Up`、`Prior` / `Next`、`F1...F12` 和 `KP_*` alias
  - `scroll.pages` 对齐官方 `1.0.755` 的 `number` schema，支持小数页数；整数页且目标暴露 `AXScroll*ByPage` 时优先走 AX action，否则用 `CGEvent.postToPid` 向目标进程定向发送 scroll event
  - `drag` 仍是 coordinate-only API，但默认不再使用全局 `.cghidEventTap` mouse event；默认改为 `CGEvent.postToPid` 定向发送 mouse move / down / dragged / up 事件，避免移动用户真实硬件光标；这些 coordinate tool 的 `x/y` 先按 screenshot pixel 坐标解释，再依据截图像素尺寸与目标 window bounds 的比例映射回 window point / Quartz global 坐标，避免 Retina 窗口上把 2x 像素误当成 1x point 导致点击落到错误位置
  - `click` / `scroll` / `drag` 默认不会走全局 `.cghidEventTap`，因此不会移动或抢占用户真实鼠标；`OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` 只作为本地诊断开关保留，不作为正常 OCU/OBU 验证路径。默认路径不再为了 fallback 调用 `NSRunningApplication.activate`

**Input simulation is PID-targeted by default.** All keyboard and mouse events are dispatched to the target app's PID via `CGEvent.postToPid` or AX `performAction`, so the target app does not need to be frontmost and the user's hardware cursor is never moved. Global pointer fallbacks (`clickGlobally` / `scrollGlobally` / `dragGlobally`) exist in the codebase but are gated behind `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` and are never active in production use. This design enables full background operation — MCP tools can drive any app without stealing focus or disrupting the user's active workflow.

### 4. Lock Screen Guard & App-Screen Session

新增三个模块，统一由 `ComputerUseToolDispatcher` 在 tool call 入口处协调：

**`MacSessionGuard`** (`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift`)
- 每次 tool call 入口调用 `CGSessionCopyCurrentDictionary` 检查 `CGSSessionScreenIsLocked` 键。
- 字典缺失、为空或解析失败 → `isUnknown = true`，视为已锁（fail-closed），返回错误并记录 "Lock state unknown" 指示器。
- **锁屏策略 `MacSessionLockPolicy`**（`.fromEnvironment()` 读取 `OPEN_COMPUTER_USE_ALLOW_LOCKED`）：
  - `.blockWhileLocked`（默认）：锁定时拒绝所有 action tool，行为与原先一致。
  - `.allowWhileLocked`（`OPEN_COMPUTER_USE_ALLOW_LOCKED=1` 显式开启）：锁定时放行所有 tool，做 best-effort 控制。可行的原因是所有 action 都走 process-targeted 投递（AX `performAction`/`setAttributeValue` 或 `CGEvent.postToPid`，默认不经过全局 HID event tap），登录窗口占据屏幕时仍能送达目标进程。首次放行时向 stderr 打印一次降级提示。**锁定时的限制**：窗口截图返回空图（系统安全限制，`get_app_state` 只回传 AX tree 不含 image），依赖可见光标的 coordinate-only 路径不可靠 —— 应优先用 `element_index` 定位的 action。
- `tools/list` 调用不受 lock guard 拦截。
- 协议：`MacSessionStateProvider`（可注入用于单元测试）；真实实现：`SystemMacSessionStateProvider`。

**`AppScreenSession`** (`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppScreenSession.swift`)
- 维护 `SnapshotIdentity`（pid、target window ID、window bounds、截图像素尺寸、captureGeneration）。
- action call 执行前与保存的 identity 比对；bounds 超 8pt 容差、windowID 变更、pid/截图尺寸变化 → 返回 `appScreenStaleStateError`，要求重新 `get_app_state`。
- `get_app_state` 成功后更新 identity；turn-ended 不清除（连续 turn 间可复用）。

**`ControlActivityStore`** (`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ControlActivityStore.swift`)
- 汇总所有连接的状态（idle / active / locked / permissionMissing / recentError）。
- `ControlActivityEvent` 只携带 toolName、app name/bundle id、pid，不携带 args/文本/截图。
- 供 `ControlStatusMenuController` 订阅，驱动状态菜单 UI。

**`ControlStatusMenuController`** (`apps/OpenComputerUse/Sources/OpenComputerUse/ControlStatusMenuController.swift`)
- 在 App Mode (app-agent) 运行时呈现 macOS 菜单栏状态项，显示连接数和最近活动。
- Restart 菜单项：app-agent 模式启用；direct AppKit MCP 模式禁用（宿主需自行重启进程）。
- 诊断文本 Copy 只包含元数据，不含 AX 树内容或 action 参数。

### 5. Fixture Bridge

- `OpenComputerUseFixture` 会把自己的窗口与元素状态写到临时 JSON 文件。
- 对 fixture 的 `get_app_state` 和少量测试专用动作，会通过 `FixtureBridge` 走显式 command 通道。
- 这个 bridge 只服务于仓库内 deterministic smoke path，不是面向真实第三方 app 的能力边界。
- 因为 SwiftPM 裸 executable 形式启动的 fixture 没有稳定的 bundle identifier，`list_apps` 会仅对 `OpenComputerUseFixture` 注入一个内部 synthetic identifier，保证 smoke suite 仍能覆盖 `list_apps`，普通第三方 app 仍按真实 bundle id 输出。

### 5. Cursor Lab

- `StandaloneCursor` 是一个新的独立 SwiftUI/AppKit demo target，可通过 `swift run StandaloneCursor` 本地启动。
- 这条线优先验证 Python 重建脚本已经收敛出来的核心：`20` 条候选路径、`measure + score`、`prefer in-bounds then lowest-score` 选路，以及 `response=1.4` / `dampingFraction=0.9` / `dt=1/240` 的 raw spring timeline。
- 当前它刻意不引入 speculative 的 wall-clock duration 映射，也不复用 `CursorMotion` 里更偏视觉手感试验的 pose dynamics。
- `CursorMotion` 是一个单独的 SwiftUI demo target，可通过 `swift run CursorMotion` 本地启动。
- 这条线优先验证 motion model 本身：当前主线是 heading-driven 的 turn / brake / orbit / direct candidate 族、spring progress、独立 visual dynamics 和 debug UI；moving 阶段真正画出来的箭头角度会持续跟随 visual dynamics 的主 heading，接近停住后再平滑回到默认 resting pose，并在 idle 阶段保留原地小摆角。
- lab 的 cursor 视觉继续以 `scripts/render-synthesized-software-cursor.swift` 为参考：优先使用仓库里保存的官方 `252x252` runtime baseline 图，缺失时再退回脚本里的 procedural pointer/fog 近似；settle 态也改成中心固定的小幅摆角，而不是继续沿 XY 轻微漂移。
- 当前它不接真实 tool call，也不回写主 `SoftwareCursorOverlay`，目的是把实验噪音与产品行为边界隔离开。

### 6. Windows Runtime

- Windows runtime 位于 `apps/OpenComputerUseWindows`，以 Go 维护 CLI、`call --calls` sequence、MCP JSON-RPC、tool schema 和进程内 snapshot cache。
- 构建入口是 `scripts/build-open-computer-use-windows.sh --arch arm64|amd64`，默认输出到 `dist/windows/<arch>/open-computer-use.exe`；npm release package 会把两个 Windows artifact 内置到已有 root/alias packages，Node launcher 按 `process.platform/process.arch` 自动选择。
- Go runtime 通过 `go:embed` 带上 `runtime.ps1`，执行 tool call 时临时落盘并调用 Windows PowerShell。PowerShell bridge 使用 `System.Windows.Automation` 做 app/window/element discovery、tree rendering、UIA pattern action、ValuePattern set value 和 ScrollPattern scroll；当目标 app 不暴露对应 pattern 时，fallback 到 `PostMessage` / `SendMessage` 形式的 Win32 window message。
- Windows runtime 默认只连接已经运行的 app，不会在 `get_app_state` 找不到进程时自动 `Start-Process`，也不会默认允许 `SetFocus` secondary action；这两条前台抢占路径分别需要 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` 和 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1` 显式打开。`type_text` 默认优先对可写文本控件的 child HWND 发送 `EM_SETSEL` / `EM_REPLACESEL`，不再默认走可能触发前台激活的 UIA `ValuePattern.SetValue` fallback；需要旧行为时必须设置 `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1`。UIA pattern 和 Win32 message fallback 本身仍是 best-effort：很多控件可以在后台响应，但 Windows 没有一套对所有 GUI toolkit 都等价于 macOS AX 的后台键鼠输入模型。
- 这 9 个 tool 的协议面与 macOS 主线保持一致：`list_apps`、`get_app_state`、`click`、`perform_secondary_action`、`scroll`、`drag`、`type_text`、`press_key`、`set_value`。其中 element-targeted action 会优先复用上一轮 `get_app_state` 的 runtime id / automation metadata，coordinate action 使用 screenshot/window-relative 坐标。
- Windows UI Automation 需要运行在已登录用户的桌面 session 里。通过 SSH 作为脱离桌面的后台进程运行时，PowerShell 可以启动并返回 JSON，但系统可能不给它暴露顶层窗口；这种情况下 `list_apps` 会是空，`get_app_state` 可能返回 `appNotFound(...)`。
- 当前 Windows 侧仍是功能性第一版：没有 visual cursor overlay、没有 installer/onboarding、没有 code signing，也没有独立的 Windows smoke fixture。后续 TODO 记录在 `docs/exec-plans/active/20260422-windows-computer-use-runtime.md`。

### 7. Linux Runtime

- Linux runtime 位于 `apps/OpenComputerUseLinux`，以 Go 维护 CLI、`call --calls` sequence、MCP JSON-RPC、tool schema 和进程内 snapshot cache。
- 构建入口是 `scripts/build-open-computer-use-linux.sh --arch arm64|amd64`，默认输出到 `dist/linux/<arch>/open-computer-use`；npm release package 会把两个 Linux artifact 内置到已有 root/alias packages，Node launcher 按 `process.platform/process.arch` 自动选择。
- Go runtime 通过 `go:embed` 带上 `runtime.py`，执行 tool call 时临时落盘并调用 `python3`。Python bridge 使用 GNOME/GObject Introspection 暴露的 AT-SPI2 接口做 app/window discovery、accessibility tree rendering、semantic action、editable text、value set，以及 best-effort 的 key/mouse fallback。
- Linux 上最接近 macOS AX 的是 AT-SPI2/D-Bus accessibility，而不是一套统一的后台键鼠输入模型。第一版优先使用元素暴露的 AT-SPI action、EditableText 和 Value 接口；coordinate `click` / `drag` 与 `press_key` 使用 AT-SPI event synthesis fallback，在 Wayland 下只能按 best-effort 处理。
- Linux runtime 需要运行在已登录桌面用户 session 里。缺少 `XDG_RUNTIME_DIR`、`DBUS_SESSION_BUS_ADDRESS` 或 display 环境时，Go runtime 会在启动 Python AT-SPI bridge 前尝试从 `/run/user/<uid>` 和常见桌面进程自动发现当前用户的 session bus、display / Wayland 值；纯 SSH tty 如果找不到已登录桌面 session，可以启动二进制，但不能直接 inspect 或操作 GUI session。
- `get_app_state` 的 accessibility tree 在 GTK/GNOME app 上可能很深，Linux bridge 使用与 macOS / Windows 一致的 1200 节点、64 层默认 tree budget，并支持显式提高 `max_tree_nodes` / `max_tree_depth`。截图通过 GDK root window best-effort capture；GNOME Wayland 可能返回黑图，bridge 会检测全黑采样并省略 image block。
- 这 9 个 tool 的协议面与 macOS / Windows 保持一致：`list_apps`、`get_app_state`、`click`、`perform_secondary_action`、`scroll`、`drag`、`type_text`、`press_key`、`set_value`。其中 element-targeted action 会优先复用上一轮 `get_app_state` 的 runtime path metadata，coordinate action 使用 screenshot/window-relative 坐标。
- 当前 Linux 侧仍是功能性第一版：没有 visual cursor overlay、没有 installer/desktop entry，也没有独立 Linux fixture。后续 TODO 记录在 `docs/exec-plans/active/20260422-linux-computer-use-runtime.md`。

## 关键边界

- 开源版当前不复刻官方闭源实现里的 caller signing、私有 IPC、完整 overlay choreography 和 plugin 自安装逻辑。
- 因为官方 `SkyComputerUseClient` 带有宿主侧 launch constraints，普通 stdio MCP client 在本机上可能被系统直接杀掉；如果要探测官方 bundled `computer-use`，`scripts/computer-use-cli` 的 app-server 模式现在只适合做工具清单和协议面观察。官方 `1.0.755` 的真实 tool call 还会经过 service-side sender authorization / active IPC client 追踪，外部 raw helper 即使走已签名 Codex binary，也可能返回 `Sender process is not authenticated`；需要真实使用官方工具时应走正常 Codex agent/tool 调用链，开源版则继续提供可直连的 `open-computer-use` MCP server。
- 当前权限引导已经具备可运行 app、深链、拖拽辅助，以及一版更接近官方的 accessory panel 入场动画和返回 affordance；点击链路也已经补上独立 visual cursor、官方 asset fallback 和相对目标 window 的排序逻辑，并且在 overlay 可见期间会持续重申“排在目标 window 之上”，避免用户手动激活目标 app 后 cursor 被目标窗口重新盖住；但整体还没有完全复刻官方那套嵌入式 choreography / host 集成 / session approval 体验。
- screenshot 当前通过 `ScreenCaptureKit` 捕获目标窗口，并以 MCP `image` content block 的 base64 PNG 返回，不再把普通 app 截图落盘到仓库或临时目录；编码前会按最大尺寸和目标字节数自适应缩小，避免复杂页面的大 PNG 触发 host 侧 MCP result 降级，同时 coordinate tools 继续按实际返回的 screenshot pixel 尺寸映射坐标；单次 ScreenCaptureKit capture 会设置超时，超时后省略 image block 而不是卡住整个 `get_app_state`。
- 会话状态现在是进程内内存态，保存每个 app 最近一次 snapshot 和 element index 映射。

## 主要验证路径

- 单元测试：`swift test`
- standalone cursor 构建：`swift build --product StandaloneCursor`
- cursor lab 构建：`swift build --product CursorMotion`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`（标准 9-tool smoke + visual cursor idle smoke；脚本默认以 headless 模式启动内部 fixture，避免在用户桌面弹出测试窗口）
- app 打包：`./scripts/build-open-computer-use-app.sh debug`
- 权限 onboarding 端到端回归：`./scripts/run-permission-onboarding-e2e.sh`（需要当前 macOS 对被测 `open-computer-use` 已授予 Accessibility 与 Screen Recording；默认禁用 app-agent proxy 来测试当前 CLI 运行态，可用 `OPEN_COMPUTER_USE_E2E_CLI=/path/to/open-computer-use` 指定被测 CLI，或用 `OPEN_COMPUTER_USE_E2E_DISABLE_APP_AGENT_PROXY=0` 显式覆盖默认代理行为）
- npm staging：`node ./scripts/npm/build-packages.mjs`
- release tgz：`./scripts/release-package.sh`
- skill 打包：`npm run package:skill`
- Windows runtime 单测：`(cd apps/OpenComputerUseWindows && go test ./...)`
- Windows exe 构建：`./scripts/build-open-computer-use-windows.sh --arch arm64`
- Linux runtime 单测：`(cd apps/OpenComputerUseLinux && go test ./...)`
- Linux binary 构建：`./scripts/build-open-computer-use-linux.sh --arch arm64`
- 对比样本：`artifacts/tool-comparisons/20260417-focus-behavior/`
- 手工诊断：
  - `open-computer-use doctor`
  - `open-computer-use snapshot <app>`
  - `open-computer-use call list_apps`
  - `open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}}]'`

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,280p' 'plans/260720-1024-mac-session-guard-lock-detection/plan.md'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# Plan: Mac Session Guard console-gated absent-key fix (Proposal B, TDD)

Status: ready to implement. Chosen design: Proposal B (console-gated absent-key).
Single revertable commit target.

## Files to modify

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift` (fix)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` (tests, near line 1907 `MARK: - MacSessionGuard tests`)
- `README.md` (~L42-47, REQUIRED correction, not optional — see Docs)

Do NOT touch: `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, `AllowWhileLockedNotice`, the `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` hatch (L102-106), `MacSessionStateProvider` protocol, fakes (L2637-2652), `requireUnlocked`/`currentState`.

## Phase 1 — Tests first (write now, must fail against current code)

Add an internal seam so unit tests reach the parsing logic without mocking `CGSessionCopyCurrentDictionary`:

```swift
// internal (not private) static — reachable via @testable import, no protocol change
static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot
```

`fetchFromSystem()` becomes a thin wrapper:
```swift
private static func fetchFromSystem() -> MacSessionSnapshot {
    let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
    let rawKeys = Set(dict?.keys ?? [])
    return parseSnapshot(dict, rawKeys: rawKeys)
}
```
All existing logic (nil/empty guard, DEBUG fail-open override, key parsing) moves into `parseSnapshot`, unchanged in position — only the new on-console branch is added. `OpenComputerUseKitTests.swift` already has `@testable import OpenComputerUseKit` (L4), no import change needed.

Test file location: new tests appended after L1959 (end of existing `testMacSessionGuardRawKeysDiagnostics`), before `testSystemMacSessionStateProviderCachesWithinTTL` (L1961). Use literal key strings `"CGSSessionScreenIsLocked"` and `"kCGSSessionOnConsoleKey"` in test dict literals (do not depend on the file's private `cgSessionScreenIsLockedKey` constant so a typo in the constant would also be caught).

12 cases, each `XCTAssertEqual(isLocked)/(isUnknown)`:

| # | Test name | dict | rawKeys | isLocked | isUnknown | Proves |
|---|---|---|---|---|---|---|
| 1 | testParseSnapshotNilDictFailsClosed | `nil` | `[]` | true | true | unchanged fail-closed |
| 2 | testParseSnapshotEmptyDictFailsClosed | `[:]` | `[]` | true | true | unchanged fail-closed |
| 3 | testParseSnapshotKeyAbsentOnConsoleTrueReturnsUnlocked | `["kCGSSessionOnConsoleKey": true]` | `{key}` | **false** | **false** | **the bug regression guard** |
| 4 | testParseSnapshotKeyAbsentOnConsoleTrueNSNumberReturnsUnlocked | `["kCGSSessionOnConsoleKey": NSNumber(value:1)]` | `{key}` | false | false | NSNumber coercion reused for on-console |
| 5 | testParseSnapshotKeyAbsentOnConsoleFalseFailsClosed | `["kCGSSessionOnConsoleKey": false]` | `{key}` | true | true | off-console stays fail-closed |
| 6 | testParseSnapshotKeyAbsentOnConsoleKeyAbsentFailsClosed | `["SomeOtherKey": "x"]` | `{key}` | true | true | no console signal at all |
| 7 | testParseSnapshotKeyAbsentOnConsoleUnparseableFailsClosed | `["kCGSSessionOnConsoleKey": "garbage"]` | `{key}` | true | true | garbage type fails closed |
| 8 | testParseSnapshotKeyPresentTrueLockedRegardlessOfConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true]` | `{2 keys}` | true | false | **explicit lock signal always wins over console gate** |
| 9 | testParseSnapshotKeyPresentFalseUnlocked | `["CGSSessionScreenIsLocked": false]` | `{key}` | false | false | unchanged explicit-unlocked path |
| 10 | testParseSnapshotKeyPresentNSNumberTrueLocked | `["CGSSessionScreenIsLocked": NSNumber(value:1)]` | `{key}` | true | false | unchanged NSNumber coercion |
| 11 | testParseSnapshotKeyPresentUnparseableTypeFailsClosed | `["CGSSessionScreenIsLocked": "garbage"]` | `{key}` | true | true | unchanged fail-closed on garbage |
| 12 | testParseSnapshotKeyPresentTrueLockedWithOffConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": false]` | `{2 keys}` | true | false | explicit-lock-wins pinned for the FUS-away/switched-out shape too |

`SystemMacSessionStateProvider` cache-policy tests (new, alongside existing `testSystemMacSessionStateProviderCachesWithinTTL` at L1961) — proves R2 asymmetric caching:

| # | Test name | Scenario | Asserts |
|---|---|---|---|
| 13 | testSystemMacSessionStateProviderDoesNotCacheUnlockedSnapshot | `shouldCache` on an `isLocked: false` snapshot | returns `false` |
| 14 | testSystemMacSessionStateProviderCachesLockedSnapshot | `shouldCache` on an `isLocked: true` snapshot (locked or unknown) | returns `true` |

Run to confirm red: `swift test --filter OpenComputerUseKitTests -Xswiftc -DDEBUG 2>&1 | grep -A2 "testParseSnapshot"` (or plain `swift test` if `--filter` regex issues — see Phase 3). Cases 1,2,8,9,10,11 should already pass (unchanged behavior); case 3–7 must fail until Phase 2 lands (3 fails because current code returns locked/unknown for absent key; 4–7 fail to compile/reference `parseSnapshot` until the seam exists at all — so realistically all 11 fail first because the seam doesn't exist yet).

## Phase 2 — Fix

In `MacSessionGuard.swift`:

1. Add `private static func coerceBool(_ value: Any?) -> Bool?` (returns `value as? Bool`, else `(value as? NSNumber)?.boolValue`, else `nil`). Reuse it for both `CGSSessionScreenIsLocked` and the new on-console read — replaces the inline if/else-if at L111-117.
2. Add `let kCGSSessionOnConsoleKey = "kCGSSessionOnConsoleKey"` constant next to `cgSessionScreenIsLockedKey` (L7).
3. Extract `internal static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot` per Phase 1 seam. Body, in order (ordering is load-bearing — explicit lock signal must be checked before the console gate):
   - `guard let dict, !dict.isEmpty else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
   - `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` override — unchanged, stays first after the nil/empty guard (preserve current position, L102-106).
   - `guard let lockedValue = dict[cgSessionScreenIsLockedKey] else { ... }` — inside the else, the **new** on-console gate:
     ```swift
     if coerceBool(dict[kCGSSessionOnConsoleKey]) == true {
         return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
     }
     return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
     ```
   - `guard let isLocked = coerceBool(lockedValue) else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
   - `return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)`
4. Rewrite `fetchFromSystem()` to the 3-line wrapper in Phase 1.
5. Rewrite file-top comment (L4-6): remove the false "verified on macOS 12–15 ... and macOS 26" claim. State: absent-key-corroborated-by-on-console semantics are empirically verified ONLY on macOS 26 (Darwin 27) on this machine; `CGSSessionScreenIsLocked` present as `true` only while locked; absent key alone is ambiguous and is corroborated by `kCGSSessionOnConsoleKey`; nil/empty dict and unparseable values remain fail-closed; screensaver-without-password is presence-blind and reads UNLOCKED (on-console stays true) — a behavior change from prior fail-closed, documented not fixed.
6. Keep `requireUnlocked`'s existing `rawKeysSeen` stderr diagnostic (L139) untouched — it now also fires (rarely) for the new off-console fail-closed branch, which is correct and desired (must-incorporate: catchable from logs).
7. **Cache policy (R2 — never cache a stale-unlocked verdict across a lock transition):** add `internal static func shouldCache(_ snapshot: MacSessionSnapshot) -> Bool { snapshot.isLocked }` next to `parseSnapshot`. In `SystemMacSessionStateProvider.currentSnapshot()`, after computing `fresh`, only write `cachedSnapshot`/`cacheTimestamp` when `Self.shouldCache(fresh)` is true; when false, clear any existing `cachedSnapshot` so a subsequent call within the old TTL window cannot return it. Fail-safe direction: an unlocked snapshot is never cached (always re-fetched), so a lock happening after a cached unlocked read is still detected on the very next call; a locked/unknown snapshot may still be served stale for up to 200ms after unlocking, which costs at most one extra spurious block, never a false unlock. Update the TTL comment (L25) to state this asymmetry explicitly: "cache only holds locked/unknown snapshots; unlocked is always re-fetched so a lock transition is never masked by a stale cache entry."
8. **One-shot inferred-unlock log (R3 mitigation a / red-team note 5):** add a private final class mirroring `AllowWhileLockedNotice`'s one-shot `NSLock`-guarded pattern (e.g. `InferredUnlockNotice`), emitted the first time `parseSnapshot` takes the absent-key + on-console-true branch, writing to stderr e.g. `"[open-computer-use] lock key absent, inferred unlocked from on-console signal (verified macOS 26 only) — see MacSessionGuard.swift for scope."` Fires once per process so a wrong-direction OS is detectable from logs without per-call spam; does not change `isUnknown` (stays `false` per existing contract).

## Phase 3 — Verify

1. Unit tests: `swift test --filter OpenComputerUseKitTests` from repo root (uses root `Package.swift`; the `OpenComputerUseKitTests` target already builds `OpenComputerUseKit` — no separate target flag needed). All 12 `parseSnapshot` cases + 2 `shouldCache` cases green, all 14 pre-existing `MacSessionGuard`/dispatcher/policy tests (L1907-2146, fakes bypass `fetchFromSystem`/`parseSnapshot` entirely) remain green untouched.
2. Live probe on THIS machine (expected UNLOCKED): add one throwing-skip test so it never runs in CI by default:
   ```swift
   func testLiveSystemProbePrintsRealLockState() throws {
       guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LIVE_PROBE"] == "1" else {
           throw XCTSkip("set OPEN_COMPUTER_USE_LIVE_PROBE=1 to probe the real session dictionary")
       }
       let snap = SystemMacSessionStateProvider().currentSnapshot()
       print("[live-probe] isLocked=\(snap.isLocked) isUnknown=\(snap.isUnknown) rawKeysSeen=\(snap.rawKeysSeen.sorted())")
   }
   ```
   Run: `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState 2>&1 | grep live-probe`. Expected on this machine right now: `isLocked=false isUnknown=false`, `rawKeysSeen` containing `kCGSSessionOnConsoleKey` and NOT `CGSSessionScreenIsLocked`.
3. Manual locked-state verification (put in PR body, cannot be automated from this session): open a terminal (or keep an existing SSH/tmux session attached — running a CLI test binary needs no GUI and is unaffected by the lock itself), lock the screen (Cmd+Ctrl+Q or Apple menu → Lock Screen), then from the still-open terminal run the same `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState` command. Expected: `isLocked=true isUnknown=false`, `rawKeysSeen` containing `CGSSessionScreenIsLocked`. Unlock afterward and confirm it flips back to case 2's result.
4. **MANDATORY human verification — fast-user-switch via SSH (R1, cannot run autonomously, required before merge, blocks the PR without it):** from an SSH/tmux session into this machine (so the probe also exercises the daemon/nil-dict assumption, red-team note 7), fast-user-switch away from the console (or invoke the login window via Apple menu → Lock Screen while a second account exists, or Control-Shift-Eject/FUS shortcut), then from the still-open SSH session run `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState`. This is the single most important test in the plan: it proves the load-bearing invariant "not physically frontmost ⇒ `kCGSSessionOnConsoleKey`==false" that the whole fix rests on. **MUST report `isLocked=true`.** If it reports `isLocked=false`, the fix is unsafe as designed and must not merge. Switch back and confirm it flips to unlocked again.
5. **Manual verification — screensaver without password (R4):** enable a screensaver with no password requirement, trigger it, run the live probe from an attached terminal. Expected/accepted: `isLocked=false` (presence-blind, documented in the file-top comment and README, not a regression this fix owns).
6. Full suite sanity: `swift test` (all packages) — confirm no unrelated regressions.

**PR-body checklist (required before merge):** [ ] FUS-via-SSH manual test (step 4) run and reported `isLocked=true` [ ] lock-screen manual test (step 3) run and reported `isLocked=true` [ ] screensaver-without-password manual test (step 5) run and result matches accepted behavior [ ] accepted residual risk (macOS 14–15 unverified) stated in PR body.

## Docs

- **README.md ~L42 — REQUIRED edit (R5, not optional):** current text "any lock-state evidence that is absent, nil, or unparseable is treated as locked" now documents the pre-fix behavior as if it were still true; it must change to: "absent lock-state evidence is corroborated by the on-console signal — when the session is on-console, absent evidence is treated as unlocked; when off-console, or when evidence is nil or unparseable, it is treated as locked." Also add one clause near L42-47 noting screensaver-without-password reads unlocked (R4), matching the file-top comment.
- `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`, `docs/SECURITY.md`: validated (plan-validation round 1) — these describe dict-level nil/empty/parse-fail semantics only, which remain fail-closed post-fix; no edit required, leave untouched.
- The authoritative source-level correction is the `MacSessionGuard.swift` file-top comment (Phase 2 step 5); README.md is the required user-facing mirror of that correction.

## Acceptance Criteria

- All 12 new `parseSnapshot` unit tests pass (cases 1-12, including explicit-lock-wins with off-console); the 2 new `shouldCache` tests (13-14) pass; all 14 pre-existing lock-guard/dispatcher/policy tests still pass unmodified.
- Live probe on this machine (unlocked) reports `isLocked=false, isUnknown=false`.
- **Mandatory human verification (Phase 3 step 4): FUS-via-SSH probe reports `isLocked=true`** — PR cannot merge without this being run and reported.
- Lock-screen manual probe (Phase 3 step 3) reports `isLocked=true`; screensaver-without-password probe (Phase 3 step 5) result is recorded and matches the documented accepted behavior.
- `shouldCache` returns `false` for every `isLocked==false` snapshot and `true` otherwise; `SystemMacSessionStateProvider` never returns a cached `isLocked==false` snapshot older than the current fetch.
- `MacSessionStateProvider` protocol signature, `FakeLockedSessionProvider`/`FakeUnlockedSessionProvider`/`FakeSnapshotProvider`, `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, and the DEBUG fail-open hatch are byte-identical to before this change.
- File-top comment no longer claims unverified macOS 12–15 behavior; states verification scope as macOS 26/Darwin 27 on this machine only; documents the screensaver-without-password behavior.
- README.md ~L42-47 no longer states absent evidence is unconditionally treated as locked.
- `swift test` (full suite) is green.

## Risks + Rollback

- **Risk**: `kCGSSessionOnConsoleKey` semantics are an undocumented private-API correlation (Security's honest weakness #1) — could diverge on a future OS. Mitigated by: explicit-lock-signal-first ordering (checked before the gate, so a genuinely locked session with the key present is never affected, including off-console — case 12), fail-closed remains the default for every other branch, the `rawKeysSeen` diagnostic stays in `requireUnlocked`'s stderr log, and the new one-shot inferred-unlock log (Phase 2 step 8) makes the fail-open branch visible in the field.
- **Risk**: stale-cache-across-lock-transition — closed by R2 (shouldCache never caches `isLocked==false`); residual is bounded to <=200ms of stale-locked after an actual unlock, which costs at most one extra spurious block, never a false unlock.
- **Accepted residual risk (R3, written acceptance — not gated on OS version):** the console-gated absent-key branch is verified only on macOS 26 (Darwin 27) on this machine; macOS 14–15 (Sonoma/Sequoia, the supported versions below 26) are unverified and the fix's fail-open direction is reachable there if any of those versions omits `CGSSessionScreenIsLocked` while genuinely locked. An OS-version gate was considered and rejected: gating would keep the guard permanently fail-closed (always-blocked-as-locked) on every supported macOS except 26, which is worse than the current bug for every non-26 user and defeats the purpose of the fix. Mitigations instead of gating: (a) one-shot stderr log per process on the inferred-unlock path (Phase 2 step 8) so a wrong-direction OS is detectable from field logs; (b) file-top comment states the verification scope honestly (macOS 26/Darwin 27 only); (c) this residual must be restated in the PR body per the merge checklist. This residual stays open until field telemetry or a differently-versioned test machine confirms 14-25 behavior.
- **Rollback**: single commit; `git revert <sha>` restores the prior (safe but broken-usability) fail-closed-on-absent-key behavior with no data loss, since this touches only in-process lock-state classification, not persisted state.

## Unresolved Questions

- Should the "on-console present but unparseable type" sub-case log a diagnostic reason distinct from the generic fail-closed path? (carried from predict-gate, not resolved here)
- No macOS 14–15 (Sonoma/Sequoia) verification possible in this environment — residual risk stays open until field telemetry or a differently-versioned test machine confirms.

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,320p' /Users/hvnguyen/.agents/skills/ck-code-review/checklists/base.md"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[31m exited 1 in 0ms:[0m
sed: /Users/hvnguyen/.agents/skills/ck-code-review/checklists/base.md: No such file or directory

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "rg --files /Users/hvnguyen/.agents/skills/ck-code-review | rg 'checklists/base\\.md"'$|base'"\\.md"'$'"'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
/Users/hvnguyen/.agents/skills/ck-code-review/references/checklists/base.md

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1,360p' /Users/hvnguyen/.agents/skills/ck-code-review/references/checklists/base.md"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
# Base Review Checklist

Universal checklist for all project types. Two-pass model: critical (blocking) + informational (non-blocking).

## Instructions

Review `git diff origin/main` for the issues below. Be specific — cite `file:line` and suggest fixes. Skip anything that's fine. Only flag real problems.

**Output format:**

```
Pre-Landing Review: N issues (X critical, Y informational)

**CRITICAL** (blocking):
- [file:line] Problem description
  Fix: suggested fix

**Issues** (non-blocking):
- [file:line] Problem description
  Fix: suggested fix
```

If no issues: `Pre-Landing Review: No issues found.`

Be terse. One line problem, one line fix. No preamble.

---

## Pass 1 — CRITICAL (blocking)

### Injection & Data Safety
- String interpolation in SQL/database queries (even with type casting — use parameterized queries)
- Unsanitized user input written to database or rendered in HTML
- Raw HTML output from user-controlled data (`innerHTML`, `dangerouslySetInnerHTML`, `html_safe`, `raw()`, `| safe`)
- Command injection via string concatenation in shell commands (use argument arrays)
- Path traversal via user input in file operations

### Race Conditions & Concurrency
- Read-check-write without atomic operations (check-then-set should be atomic WHERE + UPDATE)
- Find-or-create without unique database constraint (concurrent calls create duplicates)
- Status transitions without atomic WHERE old_status + UPDATE new_status
- Shared mutable state accessed without synchronization

### Security Boundaries
- Missing authentication checks on new endpoints/routes
- Privilege escalation paths (user can access/modify another user's data — IDOR)
- Secrets in logs, error responses, or client-side code
- LLM/AI output written to database or used in queries without validation
- JWT/token comparison using `==` instead of constant-time comparison

### Auth & Access Control
- New API endpoints without auth middleware
- Missing authorization check (authenticated but not authorized)
- Admin-only operations accessible to regular users
- Session fixation or token reuse defects

---

## Pass 2 — INFORMATIONAL (non-blocking)

### Conditional Side Effects
- Code branches on condition but forgets side effect on one branch (e.g., sets status but not associated data)
- Log messages claiming action happened but action was conditionally skipped

### Magic Numbers & String Coupling
- Bare numeric literals used in multiple files — should be named constants
- Error message strings used as query filters elsewhere (grep for the string)

### Dead Code & Consistency
- Variables assigned but never read
- Stale comments describing old behavior after code changed
- Import/require statements for unused modules

### Test Gaps
- Missing negative-path tests (error cases, validation failures)
- Assertions on type/status but not side effects (e.g., checks status but not that email was sent)
- Missing integration tests for security enforcement (auth, rate limiting, access control)

### Type Coercion at Boundaries
- Values crossing language/system boundaries where type could change (string vs number)
- Hash/digest inputs that don't normalize types before serialization

### Performance
- O(n*m) lookups in views/templates (array search inside loops — use hash/map lookup)
- Missing pagination on list endpoints returning unbounded results
- N+1 queries: loading associations inside loops without eager loading
- Unbounded queries without LIMIT

---

## Suppressions — DO NOT flag these

- Redundancy that aids readability (e.g., `present?` redundant with length check)
- "Add comment explaining why this threshold was chosen" — thresholds change, comments rot
- "This assertion could be tighter" when assertion already covers the behavior
- Consistency-only changes (wrapping a value to match how another constant is guarded)
- Harmless no-ops (e.g., `.filter()` on array that never contains the filtered value)
- ANYTHING already addressed in the diff being reviewed — read the FULL diff before commenting
- Style/formatting issues (use a linter for that)
- "Consider using X instead of Y" when Y works fine

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[2m2026-07-20T01:04:21.795538Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795561Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795566Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795569Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795572Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795575Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.795578Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[2m2026-07-20T01:04:21.865512Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865534Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865544Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865552Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865560Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865565Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:21.865571Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[2m2026-07-20T01:04:35.757689Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757722Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757729Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757734Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757738Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757743Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.757751Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[2m2026-07-20T01:04:35.832310Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832334Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832341Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832346Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832349Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832353Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:35.832356Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[2m2026-07-20T01:04:48.757122Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757145Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757151Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757155Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757159Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757163Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.757168Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[2m2026-07-20T01:04:48.841078Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/cortex/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841105Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/hvn-cook/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841112Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/design-router/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841117Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/ship-gate/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841122Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/impl-notes/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841126Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.codex/skills/blindspot/SKILL.md: missing YAML frontmatter delimited by ---
[2m2026-07-20T01:04:48.841130Z[0m [31mERROR[0m [2mcodex_core::session::session[0m[2m:[0m failed to load skill /Users/hvnguyen/.agents/skills/idea-evaluator vibe-research-workflow intro-drafter tech-paper-template benchmark-paper-template pre-submission-reviewer figure-designer/SKILL.md: missing YAML frontmatter delimited by ---
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "wc -l plans/260720-1024-mac-session-guard-lock-detection/plan.md packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift && nl -ba plans/260720-1024-mac-session-guard-lock-detection/plan.md | sed -n '1,180p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
     134 plans/260720-1024-mac-session-guard-lock-detection/plan.md
     154 packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift
     288 total
     1	# Plan: Mac Session Guard console-gated absent-key fix (Proposal B, TDD)
     2	
     3	Status: ready to implement. Chosen design: Proposal B (console-gated absent-key).
     4	Single revertable commit target.
     5	
     6	## Files to modify
     7	
     8	- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift` (fix)
     9	- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` (tests, near line 1907 `MARK: - MacSessionGuard tests`)
    10	- `README.md` (~L42-47, REQUIRED correction, not optional — see Docs)
    11	
    12	Do NOT touch: `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, `AllowWhileLockedNotice`, the `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` hatch (L102-106), `MacSessionStateProvider` protocol, fakes (L2637-2652), `requireUnlocked`/`currentState`.
    13	
    14	## Phase 1 — Tests first (write now, must fail against current code)
    15	
    16	Add an internal seam so unit tests reach the parsing logic without mocking `CGSessionCopyCurrentDictionary`:
    17	
    18	```swift
    19	// internal (not private) static — reachable via @testable import, no protocol change
    20	static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot
    21	```
    22	
    23	`fetchFromSystem()` becomes a thin wrapper:
    24	```swift
    25	private static func fetchFromSystem() -> MacSessionSnapshot {
    26	    let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
    27	    let rawKeys = Set(dict?.keys ?? [])
    28	    return parseSnapshot(dict, rawKeys: rawKeys)
    29	}
    30	```
    31	All existing logic (nil/empty guard, DEBUG fail-open override, key parsing) moves into `parseSnapshot`, unchanged in position — only the new on-console branch is added. `OpenComputerUseKitTests.swift` already has `@testable import OpenComputerUseKit` (L4), no import change needed.
    32	
    33	Test file location: new tests appended after L1959 (end of existing `testMacSessionGuardRawKeysDiagnostics`), before `testSystemMacSessionStateProviderCachesWithinTTL` (L1961). Use literal key strings `"CGSSessionScreenIsLocked"` and `"kCGSSessionOnConsoleKey"` in test dict literals (do not depend on the file's private `cgSessionScreenIsLockedKey` constant so a typo in the constant would also be caught).
    34	
    35	12 cases, each `XCTAssertEqual(isLocked)/(isUnknown)`:
    36	
    37	| # | Test name | dict | rawKeys | isLocked | isUnknown | Proves |
    38	|---|---|---|---|---|---|---|
    39	| 1 | testParseSnapshotNilDictFailsClosed | `nil` | `[]` | true | true | unchanged fail-closed |
    40	| 2 | testParseSnapshotEmptyDictFailsClosed | `[:]` | `[]` | true | true | unchanged fail-closed |
    41	| 3 | testParseSnapshotKeyAbsentOnConsoleTrueReturnsUnlocked | `["kCGSSessionOnConsoleKey": true]` | `{key}` | **false** | **false** | **the bug regression guard** |
    42	| 4 | testParseSnapshotKeyAbsentOnConsoleTrueNSNumberReturnsUnlocked | `["kCGSSessionOnConsoleKey": NSNumber(value:1)]` | `{key}` | false | false | NSNumber coercion reused for on-console |
    43	| 5 | testParseSnapshotKeyAbsentOnConsoleFalseFailsClosed | `["kCGSSessionOnConsoleKey": false]` | `{key}` | true | true | off-console stays fail-closed |
    44	| 6 | testParseSnapshotKeyAbsentOnConsoleKeyAbsentFailsClosed | `["SomeOtherKey": "x"]` | `{key}` | true | true | no console signal at all |
    45	| 7 | testParseSnapshotKeyAbsentOnConsoleUnparseableFailsClosed | `["kCGSSessionOnConsoleKey": "garbage"]` | `{key}` | true | true | garbage type fails closed |
    46	| 8 | testParseSnapshotKeyPresentTrueLockedRegardlessOfConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true]` | `{2 keys}` | true | false | **explicit lock signal always wins over console gate** |
    47	| 9 | testParseSnapshotKeyPresentFalseUnlocked | `["CGSSessionScreenIsLocked": false]` | `{key}` | false | false | unchanged explicit-unlocked path |
    48	| 10 | testParseSnapshotKeyPresentNSNumberTrueLocked | `["CGSSessionScreenIsLocked": NSNumber(value:1)]` | `{key}` | true | false | unchanged NSNumber coercion |
    49	| 11 | testParseSnapshotKeyPresentUnparseableTypeFailsClosed | `["CGSSessionScreenIsLocked": "garbage"]` | `{key}` | true | true | unchanged fail-closed on garbage |
    50	| 12 | testParseSnapshotKeyPresentTrueLockedWithOffConsole | `["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": false]` | `{2 keys}` | true | false | explicit-lock-wins pinned for the FUS-away/switched-out shape too |
    51	
    52	`SystemMacSessionStateProvider` cache-policy tests (new, alongside existing `testSystemMacSessionStateProviderCachesWithinTTL` at L1961) — proves R2 asymmetric caching:
    53	
    54	| # | Test name | Scenario | Asserts |
    55	|---|---|---|---|
    56	| 13 | testSystemMacSessionStateProviderDoesNotCacheUnlockedSnapshot | `shouldCache` on an `isLocked: false` snapshot | returns `false` |
    57	| 14 | testSystemMacSessionStateProviderCachesLockedSnapshot | `shouldCache` on an `isLocked: true` snapshot (locked or unknown) | returns `true` |
    58	
    59	Run to confirm red: `swift test --filter OpenComputerUseKitTests -Xswiftc -DDEBUG 2>&1 | grep -A2 "testParseSnapshot"` (or plain `swift test` if `--filter` regex issues — see Phase 3). Cases 1,2,8,9,10,11 should already pass (unchanged behavior); case 3–7 must fail until Phase 2 lands (3 fails because current code returns locked/unknown for absent key; 4–7 fail to compile/reference `parseSnapshot` until the seam exists at all — so realistically all 11 fail first because the seam doesn't exist yet).
    60	
    61	## Phase 2 — Fix
    62	
    63	In `MacSessionGuard.swift`:
    64	
    65	1. Add `private static func coerceBool(_ value: Any?) -> Bool?` (returns `value as? Bool`, else `(value as? NSNumber)?.boolValue`, else `nil`). Reuse it for both `CGSSessionScreenIsLocked` and the new on-console read — replaces the inline if/else-if at L111-117.
    66	2. Add `let kCGSSessionOnConsoleKey = "kCGSSessionOnConsoleKey"` constant next to `cgSessionScreenIsLockedKey` (L7).
    67	3. Extract `internal static func parseSnapshot(_ dict: [String: Any]?, rawKeys: Set<String>) -> MacSessionSnapshot` per Phase 1 seam. Body, in order (ordering is load-bearing — explicit lock signal must be checked before the console gate):
    68	   - `guard let dict, !dict.isEmpty else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
    69	   - `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` override — unchanged, stays first after the nil/empty guard (preserve current position, L102-106).
    70	   - `guard let lockedValue = dict[cgSessionScreenIsLockedKey] else { ... }` — inside the else, the **new** on-console gate:
    71	     ```swift
    72	     if coerceBool(dict[kCGSSessionOnConsoleKey]) == true {
    73	         return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
    74	     }
    75	     return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
    76	     ```
    77	   - `guard let isLocked = coerceBool(lockedValue) else { return .init(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys) }`
    78	   - `return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)`
    79	4. Rewrite `fetchFromSystem()` to the 3-line wrapper in Phase 1.
    80	5. Rewrite file-top comment (L4-6): remove the false "verified on macOS 12–15 ... and macOS 26" claim. State: absent-key-corroborated-by-on-console semantics are empirically verified ONLY on macOS 26 (Darwin 27) on this machine; `CGSSessionScreenIsLocked` present as `true` only while locked; absent key alone is ambiguous and is corroborated by `kCGSSessionOnConsoleKey`; nil/empty dict and unparseable values remain fail-closed; screensaver-without-password is presence-blind and reads UNLOCKED (on-console stays true) — a behavior change from prior fail-closed, documented not fixed.
    81	6. Keep `requireUnlocked`'s existing `rawKeysSeen` stderr diagnostic (L139) untouched — it now also fires (rarely) for the new off-console fail-closed branch, which is correct and desired (must-incorporate: catchable from logs).
    82	7. **Cache policy (R2 — never cache a stale-unlocked verdict across a lock transition):** add `internal static func shouldCache(_ snapshot: MacSessionSnapshot) -> Bool { snapshot.isLocked }` next to `parseSnapshot`. In `SystemMacSessionStateProvider.currentSnapshot()`, after computing `fresh`, only write `cachedSnapshot`/`cacheTimestamp` when `Self.shouldCache(fresh)` is true; when false, clear any existing `cachedSnapshot` so a subsequent call within the old TTL window cannot return it. Fail-safe direction: an unlocked snapshot is never cached (always re-fetched), so a lock happening after a cached unlocked read is still detected on the very next call; a locked/unknown snapshot may still be served stale for up to 200ms after unlocking, which costs at most one extra spurious block, never a false unlock. Update the TTL comment (L25) to state this asymmetry explicitly: "cache only holds locked/unknown snapshots; unlocked is always re-fetched so a lock transition is never masked by a stale cache entry."
    83	8. **One-shot inferred-unlock log (R3 mitigation a / red-team note 5):** add a private final class mirroring `AllowWhileLockedNotice`'s one-shot `NSLock`-guarded pattern (e.g. `InferredUnlockNotice`), emitted the first time `parseSnapshot` takes the absent-key + on-console-true branch, writing to stderr e.g. `"[open-computer-use] lock key absent, inferred unlocked from on-console signal (verified macOS 26 only) — see MacSessionGuard.swift for scope."` Fires once per process so a wrong-direction OS is detectable from logs without per-call spam; does not change `isUnknown` (stays `false` per existing contract).
    84	
    85	## Phase 3 — Verify
    86	
    87	1. Unit tests: `swift test --filter OpenComputerUseKitTests` from repo root (uses root `Package.swift`; the `OpenComputerUseKitTests` target already builds `OpenComputerUseKit` — no separate target flag needed). All 12 `parseSnapshot` cases + 2 `shouldCache` cases green, all 14 pre-existing `MacSessionGuard`/dispatcher/policy tests (L1907-2146, fakes bypass `fetchFromSystem`/`parseSnapshot` entirely) remain green untouched.
    88	2. Live probe on THIS machine (expected UNLOCKED): add one throwing-skip test so it never runs in CI by default:
    89	   ```swift
    90	   func testLiveSystemProbePrintsRealLockState() throws {
    91	       guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LIVE_PROBE"] == "1" else {
    92	           throw XCTSkip("set OPEN_COMPUTER_USE_LIVE_PROBE=1 to probe the real session dictionary")
    93	       }
    94	       let snap = SystemMacSessionStateProvider().currentSnapshot()
    95	       print("[live-probe] isLocked=\(snap.isLocked) isUnknown=\(snap.isUnknown) rawKeysSeen=\(snap.rawKeysSeen.sorted())")
    96	   }
    97	   ```
    98	   Run: `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState 2>&1 | grep live-probe`. Expected on this machine right now: `isLocked=false isUnknown=false`, `rawKeysSeen` containing `kCGSSessionOnConsoleKey` and NOT `CGSSessionScreenIsLocked`.
    99	3. Manual locked-state verification (put in PR body, cannot be automated from this session): open a terminal (or keep an existing SSH/tmux session attached — running a CLI test binary needs no GUI and is unaffected by the lock itself), lock the screen (Cmd+Ctrl+Q or Apple menu → Lock Screen), then from the still-open terminal run the same `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState` command. Expected: `isLocked=true isUnknown=false`, `rawKeysSeen` containing `CGSSessionScreenIsLocked`. Unlock afterward and confirm it flips back to case 2's result.
   100	4. **MANDATORY human verification — fast-user-switch via SSH (R1, cannot run autonomously, required before merge, blocks the PR without it):** from an SSH/tmux session into this machine (so the probe also exercises the daemon/nil-dict assumption, red-team note 7), fast-user-switch away from the console (or invoke the login window via Apple menu → Lock Screen while a second account exists, or Control-Shift-Eject/FUS shortcut), then from the still-open SSH session run `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState`. This is the single most important test in the plan: it proves the load-bearing invariant "not physically frontmost ⇒ `kCGSSessionOnConsoleKey`==false" that the whole fix rests on. **MUST report `isLocked=true`.** If it reports `isLocked=false`, the fix is unsafe as designed and must not merge. Switch back and confirm it flips to unlocked again.
   101	5. **Manual verification — screensaver without password (R4):** enable a screensaver with no password requirement, trigger it, run the live probe from an attached terminal. Expected/accepted: `isLocked=false` (presence-blind, documented in the file-top comment and README, not a regression this fix owns).
   102	6. Full suite sanity: `swift test` (all packages) — confirm no unrelated regressions.
   103	
   104	**PR-body checklist (required before merge):** [ ] FUS-via-SSH manual test (step 4) run and reported `isLocked=true` [ ] lock-screen manual test (step 3) run and reported `isLocked=true` [ ] screensaver-without-password manual test (step 5) run and result matches accepted behavior [ ] accepted residual risk (macOS 14–15 unverified) stated in PR body.
   105	
   106	## Docs
   107	
   108	- **README.md ~L42 — REQUIRED edit (R5, not optional):** current text "any lock-state evidence that is absent, nil, or unparseable is treated as locked" now documents the pre-fix behavior as if it were still true; it must change to: "absent lock-state evidence is corroborated by the on-console signal — when the session is on-console, absent evidence is treated as unlocked; when off-console, or when evidence is nil or unparseable, it is treated as locked." Also add one clause near L42-47 noting screensaver-without-password reads unlocked (R4), matching the file-top comment.
   109	- `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`, `docs/SECURITY.md`: validated (plan-validation round 1) — these describe dict-level nil/empty/parse-fail semantics only, which remain fail-closed post-fix; no edit required, leave untouched.
   110	- The authoritative source-level correction is the `MacSessionGuard.swift` file-top comment (Phase 2 step 5); README.md is the required user-facing mirror of that correction.
   111	
   112	## Acceptance Criteria
   113	
   114	- All 12 new `parseSnapshot` unit tests pass (cases 1-12, including explicit-lock-wins with off-console); the 2 new `shouldCache` tests (13-14) pass; all 14 pre-existing lock-guard/dispatcher/policy tests still pass unmodified.
   115	- Live probe on this machine (unlocked) reports `isLocked=false, isUnknown=false`.
   116	- **Mandatory human verification (Phase 3 step 4): FUS-via-SSH probe reports `isLocked=true`** — PR cannot merge without this being run and reported.
   117	- Lock-screen manual probe (Phase 3 step 3) reports `isLocked=true`; screensaver-without-password probe (Phase 3 step 5) result is recorded and matches the documented accepted behavior.
   118	- `shouldCache` returns `false` for every `isLocked==false` snapshot and `true` otherwise; `SystemMacSessionStateProvider` never returns a cached `isLocked==false` snapshot older than the current fetch.
   119	- `MacSessionStateProvider` protocol signature, `FakeLockedSessionProvider`/`FakeUnlockedSessionProvider`/`FakeSnapshotProvider`, `MacSessionLockPolicy`, `OPEN_COMPUTER_USE_ALLOW_LOCKED` parsing, and the DEBUG fail-open hatch are byte-identical to before this change.
   120	- File-top comment no longer claims unverified macOS 12–15 behavior; states verification scope as macOS 26/Darwin 27 on this machine only; documents the screensaver-without-password behavior.
   121	- README.md ~L42-47 no longer states absent evidence is unconditionally treated as locked.
   122	- `swift test` (full suite) is green.
   123	
   124	## Risks + Rollback
   125	
   126	- **Risk**: `kCGSSessionOnConsoleKey` semantics are an undocumented private-API correlation (Security's honest weakness #1) — could diverge on a future OS. Mitigated by: explicit-lock-signal-first ordering (checked before the gate, so a genuinely locked session with the key present is never affected, including off-console — case 12), fail-closed remains the default for every other branch, the `rawKeysSeen` diagnostic stays in `requireUnlocked`'s stderr log, and the new one-shot inferred-unlock log (Phase 2 step 8) makes the fail-open branch visible in the field.
   127	- **Risk**: stale-cache-across-lock-transition — closed by R2 (shouldCache never caches `isLocked==false`); residual is bounded to <=200ms of stale-locked after an actual unlock, which costs at most one extra spurious block, never a false unlock.
   128	- **Accepted residual risk (R3, written acceptance — not gated on OS version):** the console-gated absent-key branch is verified only on macOS 26 (Darwin 27) on this machine; macOS 14–15 (Sonoma/Sequoia, the supported versions below 26) are unverified and the fix's fail-open direction is reachable there if any of those versions omits `CGSSessionScreenIsLocked` while genuinely locked. An OS-version gate was considered and rejected: gating would keep the guard permanently fail-closed (always-blocked-as-locked) on every supported macOS except 26, which is worse than the current bug for every non-26 user and defeats the purpose of the fix. Mitigations instead of gating: (a) one-shot stderr log per process on the inferred-unlock path (Phase 2 step 8) so a wrong-direction OS is detectable from field logs; (b) file-top comment states the verification scope honestly (macOS 26/Darwin 27 only); (c) this residual must be restated in the PR body per the merge checklist. This residual stays open until field telemetry or a differently-versioned test machine confirms 14-25 behavior.
   129	- **Rollback**: single commit; `git revert <sha>` restores the prior (safe but broken-usability) fail-closed-on-absent-key behavior with no data loss, since this touches only in-process lock-state classification, not persisted state.
   130	
   131	## Unresolved Questions
   132	
   133	- Should the "on-console present but unparseable type" sub-case log a diagnostic reason distinct from the generic fail-closed path? (carried from predict-gate, not resolved here)
   134	- No macOS 14–15 (Sonoma/Sequoia) verification possible in this environment — residual risk stays open until field telemetry or a differently-versioned test machine confirms.

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[35m[3mcodex[0m[0m
The first concrete risk is in the cache plan, not the truth table: because the system fetch remains outside the mutex, concurrent callers can complete out of order. I’m tracing provider lifetime/call concurrency now to decide whether that is a theoretical note or a merge blocker.
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "rg -n \"SystemMacSessionStateProvider|MacSessionGuard\\(|requireUnlocked\\(|currentState\\(\\)\" packages apps | head -240"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift:73:public final class SystemMacSessionStateProvider: MacSessionStateProvider {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift:127:        provider: MacSessionStateProvider = SystemMacSessionStateProvider(),
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift:134:    public func requireUnlocked(for toolName: String) throws {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift:151:    public func currentState() -> MacSessionSnapshot {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:43:    public init(service: ComputerUseService = ComputerUseService(), guard macSessionGuard: MacSessionGuard = MacSessionGuard()) {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:50:        try macSessionGuard.requireUnlocked(for: name)
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:275:    guard macSessionGuard: MacSessionGuard = MacSessionGuard(),
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:306:            guard: MacSessionGuard(provider: FakeUnlockedSessionProvider())
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:323:            guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()),
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:655:        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:687:        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:698:        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1911:        let guard_ = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1912:        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click")) { error in
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1920:        let guard_ = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1921:        XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1926:        let guard_ = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1927:        XCTAssertThrowsError(try guard_.requireUnlocked(for: "get_app_state")) { error in
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1936:        let guard_ = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1937:        XCTAssertThrowsError(try guard_.requireUnlocked(for: "scroll")) { error in
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1946:        let guard_ = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1947:        XCTAssertThrowsError(try guard_.requireUnlocked(for: "type_text")) { error in
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1961:    func testSystemMacSessionStateProviderCachesWithinTTL() {
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1963:        // SystemMacSessionStateProvider directly without mocking CGSessionCopyCurrentDictionary.
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1974:        let guard1 = MacSessionGuard(provider: provider)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1975:        XCTAssertNoThrow(try guard1.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1976:        XCTAssertNoThrow(try guard1.requireUnlocked(for: "scroll"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1978:        // caching is in SystemMacSessionStateProvider specifically
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1980:        // Document: SystemMacSessionStateProvider adds 200ms TTL on top
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:1986:        let lockedGuard = MacSessionGuard(provider: FakeLockedSessionProvider())
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2021:        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .blockWhileLocked)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2022:        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2026:        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2030:            XCTAssertNoThrow(try guard_.requireUnlocked(for: tool), "Opt-in policy should permit \(tool) while locked")
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2040:        let blockGuard = MacSessionGuard(provider: unknownLocked, policy: .blockWhileLocked)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2041:        XCTAssertThrowsError(try blockGuard.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2042:        let allowGuard = MacSessionGuard(provider: unknownLocked, policy: .allowWhileLocked)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2043:        XCTAssertNoThrow(try allowGuard.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2048:            let guard_ = MacSessionGuard(provider: FakeUnlockedSessionProvider(), policy: policy)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2049:            XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2056:        let optInGuard = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift:2138:        let unlockedGuard = MacSessionGuard(provider: FakeUnlockedSessionProvider())
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:61:        let startupSnapshot = MacSessionGuard().currentState()

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "nl -ba apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift | sed -n '1,110p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "nl -ba packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift | sed -n '1890,2165p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
     1	import AppKit
     2	import Foundation
     3	import OpenComputerUseKit
     4	
     5	final class MCPAppRuntime: NSObject, NSApplicationDelegate {
     6	    private let server: StdioMCPServer
     7	    private var runtimeError: Error?
     8	    private var turnEndedObserver: NSObjectProtocol?
     9	    private let connectionID = ControlConnectionID()
    10	    private var statusMenu: ControlStatusMenuController?
    11	
    12	    private init(server: StdioMCPServer) {
    13	        self.server = server
    14	    }
    15	
    16	    @MainActor
    17	    static func run(server: StdioMCPServer) throws {
    18	        let application = NSApplication.shared
    19	        application.setActivationPolicy(.accessory)
    20	
    21	        let delegate = MCPAppRuntime(server: server)
    22	        application.delegate = delegate
    23	        application.run()
    24	
    25	        if let runtimeError = delegate.runtimeError {
    26	            throw runtimeError
    27	        }
    28	    }
    29	
    30	    func applicationDidFinishLaunching(_ notification: Notification) {
    31	        // Register direct AppKit MCP connection (not app-agent mode)
    32	        ControlActivityStore.shared.registerConnection(connectionID, isAppAgentMode: false)
    33	
    34	        // Install status menu — restart disabled in direct MCP mode (DoS vector)
    35	        let menu = ControlStatusMenuController()
    36	        menu.restartAction = nil
    37	        menu.openPermissionWindowAction = {
    38	            PermissionOnboardingApp.present()
    39	        }
    40	        menu.copyDiagnosticsAction = { [weak self] in
    41	            self?.copyDiagnosticsToClipboard()
    42	        }
    43	        menu.quitAction = {
    44	            NSApp.terminate(nil)
    45	        }
    46	        menu.install()
    47	        statusMenu = menu
    48	
    49	        turnEndedObserver = DistributedNotificationCenter.default().addObserver(
    50	            forName: openComputerUseTurnEndedNotificationName,
    51	            object: nil,
    52	            queue: .main
    53	        ) { _ in
    54	            Task { @MainActor in
    55	                resetOpenComputerUseVisualCursor()
    56	            }
    57	        }
    58	        Thread.detachNewThreadSelector(#selector(processStandardIO), toTarget: self, with: nil)
    59	
    60	        // Proactive startup check — warn if CGSSessionScreenIsLocked key is absent (version skew indicator)
    61	        let startupSnapshot = MacSessionGuard().currentState()
    62	        if startupSnapshot.isUnknown {
    63	            fputs("[open-computer-use] WARNING: CGSSessionScreenIsLocked key absent from CGSessionCopyCurrentDictionary at startup (keys seen: \(startupSnapshot.rawKeysSeen.sorted().joined(separator: ","))). Lock detection will treat all states as locked. Verify macOS version compatibility.\n", stderr)
    64	        }
    65	    }
    66	
    67	    func applicationWillTerminate(_ notification: Notification) {
    68	        if let turnEndedObserver {
    69	            DistributedNotificationCenter.default().removeObserver(turnEndedObserver)
    70	        }
    71	        ControlActivityStore.shared.unregisterConnection(connectionID)
    72	        statusMenu?.uninstall()
    73	    }
    74	
    75	    private func copyDiagnosticsToClipboard() {
    76	        let permissions = PermissionDiagnostics.current()
    77	        let lines: [String] = [
    78	            "Open Computer Use diagnostics",
    79	            "Mode: direct AppKit MCP (not app-agent)",
    80	            "Note: To restart, relaunch the host process.",
    81	            "",
    82	            permissions.summary,
    83	        ]
    84	        let text = lines.joined(separator: "\n")
    85	        NSPasteboard.general.clearContents()
    86	        NSPasteboard.general.setString(text, forType: .string)
    87	    }
    88	
    89	    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    90	        false
    91	    }
    92	
    93	    @objc
    94	    private func processStandardIO() {
    95	        do {
    96	            try server.run()
    97	        } catch {
    98	            runtimeError = error
    99	        }
   100	
   101	        DispatchQueue.main.async {
   102	            NSApp.terminate(nil)
   103	        }
   104	    }
   105	}

[32m succeeded in 0ms:[0m
  1890	            restingTipPosition: restingTipPosition,
  1891	            phase: (.pi / 2) + (.pi / CGFloat(0.8))
  1892	        )
  1893	
  1894	        XCTAssertEqual(positivePose.tipPosition.x, restingTipPosition.x, accuracy: 0.0001)
  1895	        XCTAssertEqual(positivePose.tipPosition.y, restingTipPosition.y, accuracy: 0.0001)
  1896	        XCTAssertGreaterThan(positivePose.angleOffset, 0)
  1897	        XCTAssertLessThanOrEqual(abs(positivePose.angleOffset), visualCursorIdleRotationAmplitude() + 0.0001)
  1898	        XCTAssertGreaterThan(abs(positivePose.angleOffset), 0.08)
  1899	
  1900	        XCTAssertEqual(negativePose.tipPosition.x, restingTipPosition.x, accuracy: 0.0001)
  1901	        XCTAssertEqual(negativePose.tipPosition.y, restingTipPosition.y, accuracy: 0.0001)
  1902	        XCTAssertLessThan(negativePose.angleOffset, 0)
  1903	        XCTAssertLessThanOrEqual(abs(negativePose.angleOffset), visualCursorIdleRotationAmplitude() + 0.0001)
  1904	        XCTAssertGreaterThan(abs(negativePose.angleOffset), 0.08)
  1905	    }
  1906	
  1907	    // MARK: - MacSessionGuard tests
  1908	
  1909	    func testMacSessionGuardBlocksWhenLocked() {
  1910	        let provider = FakeLockedSessionProvider()
  1911	        let guard_ = MacSessionGuard(provider: provider)
  1912	        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click")) { error in
  1913	            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
  1914	            XCTAssertTrue(msg.contains("macOS is locked"))
  1915	        }
  1916	    }
  1917	
  1918	    func testMacSessionGuardAllowsWhenUnlocked() {
  1919	        let provider = FakeUnlockedSessionProvider()
  1920	        let guard_ = MacSessionGuard(provider: provider)
  1921	        XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
  1922	    }
  1923	
  1924	    func testMacSessionGuardFailsClosedOnNilDictionary() {
  1925	        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: []))
  1926	        let guard_ = MacSessionGuard(provider: provider)
  1927	        XCTAssertThrowsError(try guard_.requireUnlocked(for: "get_app_state")) { error in
  1928	            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
  1929	            XCTAssertTrue(msg.contains("macOS is locked"))
  1930	        }
  1931	    }
  1932	
  1933	    func testMacSessionGuardFailsClosedOnEmptyDictionary() {
  1934	        // Empty dict → isUnknown = true, isLocked = true — same result as nil
  1935	        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: []))
  1936	        let guard_ = MacSessionGuard(provider: provider)
  1937	        XCTAssertThrowsError(try guard_.requireUnlocked(for: "scroll")) { error in
  1938	            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
  1939	            XCTAssertTrue(msg.contains("macOS is locked"))
  1940	        }
  1941	    }
  1942	
  1943	    func testMacSessionGuardFailsClosedOnParseFailed() {
  1944	        // parse-failed produces isUnknown = true, isLocked = true
  1945	        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: ["SomeKey"]))
  1946	        let guard_ = MacSessionGuard(provider: provider)
  1947	        XCTAssertThrowsError(try guard_.requireUnlocked(for: "type_text")) { error in
  1948	            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
  1949	            XCTAssertTrue(msg.contains("macOS is locked"))
  1950	        }
  1951	    }
  1952	
  1953	    func testMacSessionGuardRawKeysDiagnostics() {
  1954	        let keys: Set<String> = ["CGSSessionScreenIsLocked", "CGSSessionUserIDKey"]
  1955	        let snapshot = MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: keys)
  1956	        XCTAssertEqual(snapshot.rawKeysSeen, keys)
  1957	        XCTAssertFalse(snapshot.isUnknown)
  1958	        XCTAssertFalse(snapshot.isLocked)
  1959	    }
  1960	
  1961	    func testSystemMacSessionStateProviderCachesWithinTTL() {
  1962	        // Uses a fake provider to verify the caching concept — we cannot test
  1963	        // SystemMacSessionStateProvider directly without mocking CGSessionCopyCurrentDictionary.
  1964	        // This test documents the intended behavior.
  1965	        var callCount = 0
  1966	        final class CountingProvider: MacSessionStateProvider {
  1967	            var count = 0
  1968	            func currentSnapshot() -> MacSessionSnapshot {
  1969	                count += 1
  1970	                return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
  1971	            }
  1972	        }
  1973	        let provider = CountingProvider()
  1974	        let guard1 = MacSessionGuard(provider: provider)
  1975	        XCTAssertNoThrow(try guard1.requireUnlocked(for: "click"))
  1976	        XCTAssertNoThrow(try guard1.requireUnlocked(for: "scroll"))
  1977	        // Both calls go to provider since MacSessionGuard itself does not cache —
  1978	        // caching is in SystemMacSessionStateProvider specifically
  1979	        XCTAssertEqual(provider.count, 2)
  1980	        // Document: SystemMacSessionStateProvider adds 200ms TTL on top
  1981	        // Manual verification: consecutive tool calls within 200ms share one IPC round-trip
  1982	        _ = callCount // suppress unused warning
  1983	    }
  1984	
  1985	    func testDispatcherBlocksAllGUIToolsWhenLocked() {
  1986	        let lockedGuard = MacSessionGuard(provider: FakeLockedSessionProvider())
  1987	        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: lockedGuard)
  1988	        let guiTools = ["list_apps", "get_app_state", "click", "perform_secondary_action",
  1989	                        "scroll", "drag", "type_text", "press_key", "set_value"]
  1990	        XCTAssertEqual(guiTools.count, 9)
  1991	        for tool in guiTools {
  1992	            let result = dispatcher.callToolAsResult(name: tool, arguments: ["app": "Finder"])
  1993	            XCTAssertTrue(result.isError, "Expected error for tool: \(tool)")
  1994	            let text = result.primaryText ?? ""
  1995	            XCTAssertTrue(
  1996	                text.contains("macOS is locked"),
  1997	                "Expected lock message for tool \(tool), got: \(text)"
  1998	            )
  1999	        }
  2000	    }
  2001	
  2002	    func testLockPolicyDefaultsToBlockWhenEnvironmentUnset() {
  2003	        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment([:]), .blockWhileLocked)
  2004	        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "0"]), .blockWhileLocked)
  2005	        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "false"]), .blockWhileLocked)
  2006	        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "nonsense"]), .blockWhileLocked)
  2007	    }
  2008	
  2009	    func testLockPolicyParsesAllowValuesFromEnvironment() {
  2010	        for value in ["1", "true", "TRUE", "  yes  ", "on", "allow"] {
  2011	            XCTAssertEqual(
  2012	                MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": value]),
  2013	                .allowWhileLocked,
  2014	                "Expected allow policy for env value: \(value)"
  2015	            )
  2016	        }
  2017	    }
  2018	
  2019	    func testGuardBlocksWhenLockedUnderDefaultPolicy() {
  2020	        // Explicit policy makes the default fail-closed contract independent of the test env.
  2021	        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .blockWhileLocked)
  2022	        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click"))
  2023	    }
  2024	
  2025	    func testGuardAllowsAllToolsWhenLockedUnderOptInPolicy() {
  2026	        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
  2027	        let tools = ["list_apps", "get_app_state", "click", "perform_secondary_action",
  2028	                     "scroll", "drag", "type_text", "press_key", "set_value"]
  2029	        for tool in tools {
  2030	            XCTAssertNoThrow(try guard_.requireUnlocked(for: tool), "Opt-in policy should permit \(tool) while locked")
  2031	        }
  2032	    }
  2033	
  2034	    func testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy() {
  2035	        // Unknown lock state (dict absent/unparseable) still fails closed by default, but the
  2036	        // opt-in accepts the same best-effort risk the operator asked for.
  2037	        let unknownLocked = FakeSnapshotProvider(
  2038	            snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
  2039	        )
  2040	        let blockGuard = MacSessionGuard(provider: unknownLocked, policy: .blockWhileLocked)
  2041	        XCTAssertThrowsError(try blockGuard.requireUnlocked(for: "click"))
  2042	        let allowGuard = MacSessionGuard(provider: unknownLocked, policy: .allowWhileLocked)
  2043	        XCTAssertNoThrow(try allowGuard.requireUnlocked(for: "click"))
  2044	    }
  2045	
  2046	    func testGuardStillAllowsEverythingWhenUnlockedRegardlessOfPolicy() {
  2047	        for policy in [MacSessionLockPolicy.blockWhileLocked, .allowWhileLocked] {
  2048	            let guard_ = MacSessionGuard(provider: FakeUnlockedSessionProvider(), policy: policy)
  2049	            XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
  2050	        }
  2051	    }
  2052	
  2053	    func testDispatcherAllowsAXToolsWhenLockedWithOptIn() {
  2054	        // With opt-in, the guard no longer short-circuits: list_apps passes the guard and runs
  2055	        // (it needs no live UI, so it succeeds), proving locked no longer blocks unconditionally.
  2056	        let optInGuard = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
  2057	        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: optInGuard)
  2058	        let result = dispatcher.callToolAsResult(name: "list_apps", arguments: [:])
  2059	        XCTAssertFalse(result.isError)
  2060	        XCTAssertFalse((result.primaryText ?? "").contains("macOS is locked"))
  2061	    }
  2062	
  2063	    // MARK: - App-agent socket peer authentication policy
  2064	
  2065	    func testPeerAuthRejectsDifferentUID() {
  2066	        let decision = AppAgentPeerAuthPolicy.decide(
  2067	            peerUID: 502,
  2068	            selfUID: 501,
  2069	            agentTeamIdentifier: "ABCDE12345",
  2070	            peerSatisfiesAgentRequirement: true,
  2071	            peerTeamIdentifier: "ABCDE12345"
  2072	        )
  2073	        guard case let .reject(reason) = decision else {
  2074	            return XCTFail("Expected reject for uid mismatch, got \(decision)")
  2075	        }
  2076	        XCTAssertTrue(reason.contains("uid"))
  2077	    }
  2078	
  2079	    func testPeerAuthAllowsSignedSameTeamSameUID() {
  2080	        let decision = AppAgentPeerAuthPolicy.decide(
  2081	            peerUID: 501,
  2082	            selfUID: 501,
  2083	            agentTeamIdentifier: "ABCDE12345",
  2084	            peerSatisfiesAgentRequirement: true,
  2085	            peerTeamIdentifier: "ABCDE12345"
  2086	        )
  2087	        XCTAssertEqual(decision, .allow)
  2088	    }
  2089	
  2090	    func testPeerAuthRejectsSignedAgentWhenPeerFailsRequirement() {
  2091	        // Signed agent + peer that does not satisfy the team requirement (unsigned, or different
  2092	        // developer) must be rejected — this is the confused-deputy defense.
  2093	        let decision = AppAgentPeerAuthPolicy.decide(
  2094	            peerUID: 501,
  2095	            selfUID: 501,
  2096	            agentTeamIdentifier: "ABCDE12345",
  2097	            peerSatisfiesAgentRequirement: false,
  2098	            peerTeamIdentifier: "ZZZZZ99999"
  2099	        )
  2100	        guard case let .reject(reason) = decision else {
  2101	            return XCTFail("Expected reject for failed requirement, got \(decision)")
  2102	        }
  2103	        XCTAssertTrue(reason.contains("ABCDE12345"))
  2104	        XCTAssertTrue(reason.contains("ZZZZZ99999"))
  2105	    }
  2106	
  2107	    func testPeerAuthFallsBackToSameUIDWhenAgentUnsigned() {
  2108	        // Unsigned/ad-hoc agent (nil or empty team) cannot pin a signature; same-uid peer is
  2109	        // allowed via the explicit fallback so local `swift build` dev binaries keep working.
  2110	        let unsignedTeams: [String?] = [nil, ""]
  2111	        for team in unsignedTeams {
  2112	            let decision = AppAgentPeerAuthPolicy.decide(
  2113	                peerUID: 501,
  2114	                selfUID: 501,
  2115	                agentTeamIdentifier: team,
  2116	                peerSatisfiesAgentRequirement: false,
  2117	                peerTeamIdentifier: nil
  2118	            )
  2119	            XCTAssertEqual(decision, .allowUnsignedFallback, "team=\(String(describing: team))")
  2120	        }
  2121	    }
  2122	
  2123	    func testPeerAuthUnsignedAgentStillRejectsDifferentUID() {
  2124	        // Even in the unsigned fallback, a different uid must never be allowed.
  2125	        let decision = AppAgentPeerAuthPolicy.decide(
  2126	            peerUID: 999,
  2127	            selfUID: 501,
  2128	            agentTeamIdentifier: nil,
  2129	            peerSatisfiesAgentRequirement: false,
  2130	            peerTeamIdentifier: nil
  2131	        )
  2132	        guard case .reject = decision else {
  2133	            return XCTFail("Expected reject for uid mismatch under unsigned agent, got \(decision)")
  2134	        }
  2135	    }
  2136	
  2137	    func testDispatcherAllowsUnlockedTools() {
  2138	        let unlockedGuard = MacSessionGuard(provider: FakeUnlockedSessionProvider())
  2139	        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: unlockedGuard)
  2140	        // list_apps is non-throwing and doesn't need special args — it passes guard and succeeds
  2141	        let result = dispatcher.callToolAsResult(name: "list_apps", arguments: [:])
  2142	        // list_apps always succeeds; the lock guard should not block it when unlocked
  2143	        XCTAssertFalse(result.isError)
  2144	    }
  2145	
  2146	    func testMCPServerStillHandlesInitializeWhenLocked() {
  2147	        // initialize/ping/tools/list all bypass the dispatcher, so lock state is irrelevant
  2148	        let server = StdioMCPServer(service: ComputerUseService())
  2149	        let initResponse = server.handle(
  2150	            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.0"},"capabilities":{}}}"#
  2151	        )
  2152	        XCTAssertNotNil(initResponse)
  2153	        XCTAssertTrue(initResponse!.contains("open-computer-use"))
  2154	
  2155	        let pingResponse = server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}"#)
  2156	        XCTAssertNotNil(pingResponse)
  2157	
  2158	        let listResponse = server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#)
  2159	        XCTAssertNotNil(listResponse)
  2160	        XCTAssertTrue(listResponse!.contains("list_apps"))
  2161	    }
  2162	
  2163	    private func makeSnapshot(treeLines: [String], focusedSummary: String?, selectedText: String? = nil) -> AppSnapshot {
  2164	        AppSnapshot(
  2165	            app: RunningAppDescriptor(

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "nl -ba packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift | sed -n '1,90p;250,310p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
     1	import Foundation
     2	
     3	func normalizedElementIndexArgument(_ value: Any?) -> String? {
     4	    if let string = value as? String {
     5	        return string.isEmpty ? nil : string
     6	    }
     7	
     8	    if let integer = value as? Int {
     9	        return String(integer)
    10	    }
    11	
    12	    if let number = value as? NSNumber {
    13	        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
    14	            return nil
    15	        }
    16	
    17	        return normalizedElementIndexNumber(number.doubleValue)
    18	    }
    19	
    20	    if let double = value as? Double {
    21	        return normalizedElementIndexNumber(double)
    22	    }
    23	
    24	    return nil
    25	}
    26	
    27	private func normalizedElementIndexNumber(_ value: Double) -> String? {
    28	    guard value.isFinite, value.rounded(.towardZero) == value else {
    29	        return nil
    30	    }
    31	
    32	    guard value >= Double(Int.min), value <= Double(Int.max) else {
    33	        return nil
    34	    }
    35	
    36	    return String(Int(value))
    37	}
    38	
    39	public final class ComputerUseToolDispatcher {
    40	    private let service: ComputerUseService
    41	    private let macSessionGuard: MacSessionGuard
    42	
    43	    public init(service: ComputerUseService = ComputerUseService(), guard macSessionGuard: MacSessionGuard = MacSessionGuard()) {
    44	        self.service = service
    45	        self.macSessionGuard = macSessionGuard
    46	    }
    47	
    48	    public func callTool(name: String, arguments: [String: Any]) throws -> ToolCallResult {
    49	        // Activity recording MUST NOT occur before this line — record only at the MCP layer (MCPServer/runtime) after the guard passes.
    50	        try macSessionGuard.requireUnlocked(for: name)
    51	        switch name {
    52	        case "list_apps":
    53	            return service.listApps()
    54	        case "get_app_state":
    55	            return try service.getAppState(
    56	                app: requireString("app", in: arguments),
    57	                textLimit: try optionalTextLimit("text_limit", in: arguments) ?? .defaults,
    58	                treeLimits: AccessibilityTreeLimits.defaults.replacing(
    59	                    maxNodeCount: try optionalPositiveInt("max_tree_nodes", in: arguments),
    60	                    maxDepth: try optionalPositiveInt("max_tree_depth", in: arguments)
    61	                )
    62	            )
    63	        case "click":
    64	            return try service.click(
    65	                app: requireString("app", in: arguments),
    66	                elementIndex: optionalElementIndex(in: arguments),
    67	                x: optionalDouble("x", in: arguments),
    68	                y: optionalDouble("y", in: arguments),
    69	                clickCount: Int(optionalDouble("click_count", in: arguments) ?? 1),
    70	                mouseButton: optionalString("mouse_button", in: arguments) ?? "left"
    71	            )
    72	        case "perform_secondary_action":
    73	            return try service.performSecondaryAction(
    74	                app: requireString("app", in: arguments),
    75	                elementIndex: requireElementIndex(in: arguments),
    76	                action: requireString("action", in: arguments)
    77	            )
    78	        case "scroll":
    79	            return try service.scroll(
    80	                app: requireString("app", in: arguments),
    81	                direction: requireString("direction", in: arguments),
    82	                elementIndex: requireElementIndex(in: arguments),
    83	                pages: optionalDouble("pages", in: arguments) ?? 1
    84	            )
    85	        case "drag":
    86	            return try service.drag(
    87	                app: requireString("app", in: arguments),
    88	                fromX: requireDouble("from_x", in: arguments),
    89	                fromY: requireDouble("from_y", in: arguments),
    90	                toX: requireDouble("to_x", in: arguments),
   250	    public let jsonObject: Any
   251	    public let hasToolError: Bool
   252	
   253	    public init(jsonObject: Any, hasToolError: Bool) {
   254	        self.jsonObject = jsonObject
   255	        self.hasToolError = hasToolError
   256	    }
   257	
   258	    public func jsonText() throws -> String {
   259	        let data = try JSONSerialization.data(
   260	            withJSONObject: jsonObject,
   261	            options: [.prettyPrinted, .withoutEscapingSlashes]
   262	        )
   263	        guard let text = String(data: data, encoding: .utf8) else {
   264	            throw ComputerUseError.message("Failed to encode call output as JSON.")
   265	        }
   266	        return text
   267	    }
   268	}
   269	
   270	public typealias OpenComputerUseSleepHandler = (TimeInterval) -> Void
   271	
   272	public func runOpenComputerUseCall(
   273	    _ invocation: OpenComputerUseCallInvocation,
   274	    service: ComputerUseService = ComputerUseService(),
   275	    guard macSessionGuard: MacSessionGuard = MacSessionGuard(),
   276	    sleepHandler: OpenComputerUseSleepHandler = { Thread.sleep(forTimeInterval: $0) }
   277	) throws -> OpenComputerUseCallOutput {
   278	    let dispatcher = ComputerUseToolDispatcher(service: service, guard: macSessionGuard)
   279	
   280	    switch invocation {
   281	    case let .single(toolName, argumentsJSON, argumentsFile):
   282	        let arguments = try readOpenComputerUseToolArguments(
   283	            json: argumentsJSON,
   284	            file: argumentsFile
   285	        )
   286	        let result = dispatcher.callToolAsResult(name: toolName, arguments: arguments)
   287	        return OpenComputerUseCallOutput(
   288	            jsonObject: result.asDictionary,
   289	            hasToolError: result.isError
   290	        )
   291	
   292	    case let .sequence(callsJSON, callsFile, interCallDelay):
   293	        let calls = try readOpenComputerUseCallSequence(json: callsJSON, file: callsFile)
   294	        var outputs: [[String: Any]] = []
   295	        var hasToolError = false
   296	
   297	        for (index, call) in calls.enumerated() {
   298	            let result = dispatcher.callToolAsResult(name: call.tool, arguments: call.arguments)
   299	            outputs.append([
   300	                "tool": call.tool,
   301	                "result": result.asDictionary,
   302	            ])
   303	
   304	            if result.isError {
   305	                hasToolError = true
   306	                break
   307	            }
   308	
   309	            if index < calls.count - 1, interCallDelay > 0 {
   310	                sleepHandler(interCallDelay)

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc 'rg -n -C 3 "CGSession|lock state|locked|isUnknown|fail-closed|fail closed|absent|unparseable|nil/empty|ScreenIsLocked|on-console|screensaver" README.md docs/ARCHITECTURE.md docs/RELIABILITY.md docs/SECURITY.md apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift'[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
docs/SECURITY.md-33-
docs/SECURITY.md-34-## Lock Guard 与 App-Screen 不变量
docs/SECURITY.md-35-
docs/SECURITY.md:36:- `MacSessionGuard` 在每个 tool call 入口检查 `CGSessionCopyCurrentDictionary` 的锁定状态；当字典缺失、为空或解析失败时一律视为已锁（fail-closed），返回 "Lock state unknown" 指示器。
docs/SECURITY.md-37-- 默认策略 `.blockWhileLocked`：锁定时不允许任何 `list_apps` / `get_app_state` / action tool 执行，安全保证与原先一致。
docs/SECURITY.md:38:- 显式 opt-in `OPEN_COMPUTER_USE_ALLOW_LOCKED=1`（`.allowWhileLocked`）：放行锁屏 best-effort 控制。未设置时保持 fail-closed。放行仅改变 guard 是否拦截，不绕过 Accessibility 权限（仍需系统授权）、不落盘截图、也不启用全局 HID event tap（`globalPointerFallbacksEnabled()` 默认仍为 false）。锁定时窗口截图受系统安全限制返回空图。
docs/SECURITY.md-39-- **App-agent 信任边界**：`.app` 模式下有一个持有 TCC 授权的常驻 agent，监听 `$TMPDIR/open-computer-use-agent.sock`（chmod 0600，仅限同一 uid，但**无对端认证**）。锁屏 opt-in 属于安全敏感设置，因此**只通过可信的启动环境**（`NSWorkspace.OpenConfiguration.environment`，由运维方运行的 proxy 从其真实 shell env 传入）在 agent 启动时固定，**不经过 per-call socket 通道**；agent 侧还会主动剥离 client 传入的该键（defense in depth），因此同 uid 的第三方进程**无法**对已运行的 agent 伪造该标志。策略在 agent 生命周期内固定，需从菜单栏退出 agent 后重启才能变更。
docs/SECURITY.md-40-- **App-agent socket 对端认证（peer authentication）**：`AppAgentSocketListener.acceptLoop` 在每个连接被处理前调用 `SocketPeerAuthenticator.authenticate(fd:)`：
docs/SECURITY.md-41-  - `getpeereid` 校验对端 euid == agent euid（同 uid），否则拒绝。
docs/SECURITY.md-42-  - 经 `LOCAL_PEERTOKEN` 取对端 audit token（含 pid + pidversion，能精确锁定连接进程实例，规避 PID 复用/连后 exec 的 TOCTOU）→ `SecCodeCopyGuestWithAttributes` 还原对端 `SecCode`，用需求 `anchor apple generic and identifier "<agent bundle id>" and certificate leaf[subject.OU] = "<agent TeamID>"` 校验：对端必须由与 agent **相同开发者（Team Identifier）签名**，且签名 identifier 与 agent 的 bundle identifier 一致（即本 app 自己的可执行文件；同 team 但 identifier 不同的二进制会被拒绝）。agent 非 bundle 运行时退化为仅 team pin。任一校验不满足则拒绝。
docs/SECURITY.md-43-  - **开发回退**：agent 自身未签名/ad-hoc（本地 `swift build`）时无法进行签名校验，退化为仅同 uid（`.allowUnsignedFallback`），并向 stderr 打印一次提示。纯策略逻辑在 `AppAgentPeerAuthPolicy`（可单测）。
docs/SECURITY.md-44-- **对端认证的真实边界（务必如实理解，勿夸大）**：签名校验只证明「连接进程运行的是这份已签名代码」，**不能**区分合法运维方与同 uid 攻击者。同 uid 代码可直接 `exec` 那份合法、同开发者签名的 CLI（位于 app bundle 固定路径，world-readable，见 `plugins/.../launch-open-computer-use.sh`）来中转命令，从而**仍能**复用 agent 的 TCC 授权——锁屏时亦然。因此对端认证只是**抬高门槛**（挡掉外部/未签名/异开发者的二进制直接连接），并**未真正关闭**同 uid confused-deputy。PR#2 记录的残余风险依旧成立。
docs/SECURITY.md:45:- **另需注意**：release 构建现在默认 fail-closed —— 当签名会回退到 ad-hoc/无签名时，`build-open-computer-use-app.sh` 直接报错拒绝构建；如确有意分发 ad-hoc release，须显式设置 `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1`（此时脚本会打印醒目警告，peer-auth 不生效）。
docs/SECURITY.md-46-- **结论**：对不可信/多租户主机，请使用**独立登录 session**，不要把 peer-auth 或锁屏 opt-in 当作隔离边界。真正更强的隔离需进一步收紧需求（Developer ID marker OID pinning）——见 issue #4。
docs/SECURITY.md-47-- `AppScreenSession` 维护严格的目标屏幕不变量：action call 执行前会比对 pid、target window ID、window bounds（8pt 容差）和截图像素尺寸；任一维度变更时返回 `appScreenStaleStateError`，要求 caller 先重新调用 `get_app_state`。
docs/SECURITY.md-48-- 状态菜单（`ControlStatusMenuController`）的诊断信息只暴露 toolName、app name / bundle id、pid 和连接数，不暴露 element labels、raw action args、截图数据或 AX 文本。
--
docs/RELIABILITY.md-29-## Lock Screen / Stale-Target / 状态菜单排查
docs/RELIABILITY.md-30-
docs/RELIABILITY.md-31-**锁定 session：**
docs/RELIABILITY.md:32:- 症状：所有 tool（除 `tools/list`）返回 "Session is locked" 或 "Lock state unknown"。
docs/RELIABILITY.md:33:- 排查：`CGSessionCopyCurrentDictionary` 在用户 session 锁定或不可用时返回 nil；fail-closed 行为是**默认**预期设计，不是 bug。
docs/RELIABILITY.md-34-- 解决（有人值守）：解锁当前 macOS 用户 session 后重试，或使用已登录桌面 session。
docs/RELIABILITY.md-35-- 解决（无人值守 agent 需锁屏继续工作）：设置 `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` 开启 best-effort 锁屏放行。开启后 action 仍能经 process-targeted 投递（AX / `postToPid`）驱动可访问性可控的 app；但**窗口截图返回空图**（`get_app_state` 只回 AX tree），coordinate-only 路径不可靠 —— 用 `element_index` 定位的 action。首次放行时 stderr 会打印一次降级提示。默认不开启。
docs/RELIABILITY.md-36-
--
docs/ARCHITECTURE.md-93-新增三个模块，统一由 `ComputerUseToolDispatcher` 在 tool call 入口处协调：
docs/ARCHITECTURE.md-94-
docs/ARCHITECTURE.md-95-**`MacSessionGuard`** (`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift`)
docs/ARCHITECTURE.md:96:- 每次 tool call 入口调用 `CGSessionCopyCurrentDictionary` 检查 `CGSSessionScreenIsLocked` 键。
docs/ARCHITECTURE.md:97:- 字典缺失、为空或解析失败 → `isUnknown = true`，视为已锁（fail-closed），返回错误并记录 "Lock state unknown" 指示器。
docs/ARCHITECTURE.md-98-- **锁屏策略 `MacSessionLockPolicy`**（`.fromEnvironment()` 读取 `OPEN_COMPUTER_USE_ALLOW_LOCKED`）：
docs/ARCHITECTURE.md-99-  - `.blockWhileLocked`（默认）：锁定时拒绝所有 action tool，行为与原先一致。
docs/ARCHITECTURE.md-100-  - `.allowWhileLocked`（`OPEN_COMPUTER_USE_ALLOW_LOCKED=1` 显式开启）：锁定时放行所有 tool，做 best-effort 控制。可行的原因是所有 action 都走 process-targeted 投递（AX `performAction`/`setAttributeValue` 或 `CGEvent.postToPid`，默认不经过全局 HID event tap），登录窗口占据屏幕时仍能送达目标进程。首次放行时向 stderr 打印一次降级提示。**锁定时的限制**：窗口截图返回空图（系统安全限制，`get_app_state` 只回传 AX tree 不含 image），依赖可见光标的 coordinate-only 路径不可靠 —— 应优先用 `element_index` 定位的 action。
--
docs/ARCHITECTURE.md-107-- `get_app_state` 成功后更新 identity；turn-ended 不清除（连续 turn 间可复用）。
docs/ARCHITECTURE.md-108-
docs/ARCHITECTURE.md-109-**`ControlActivityStore`** (`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ControlActivityStore.swift`)
docs/ARCHITECTURE.md:110:- 汇总所有连接的状态（idle / active / locked / permissionMissing / recentError）。
docs/ARCHITECTURE.md-111-- `ControlActivityEvent` 只携带 toolName、app name/bundle id、pid，不携带 args/文本/截图。
docs/ARCHITECTURE.md-112-- 供 `ControlStatusMenuController` 订阅，驱动状态菜单 UI。
docs/ARCHITECTURE.md-113-
--
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-57-        }
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-58-        Thread.detachNewThreadSelector(#selector(processStandardIO), toTarget: self, with: nil)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-59-
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:60:        // Proactive startup check — warn if CGSSessionScreenIsLocked key is absent (version skew indicator)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-61-        let startupSnapshot = MacSessionGuard().currentState()
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:62:        if startupSnapshot.isUnknown {
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:63:            fputs("[open-computer-use] WARNING: CGSSessionScreenIsLocked key absent from CGSessionCopyCurrentDictionary at startup (keys seen: \(startupSnapshot.rawKeysSeen.sorted().joined(separator: ","))). Lock detection will treat all states as locked. Verify macOS version compatibility.\n", stderr)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-64-        }
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-65-    }
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift-66-
--
README.md-39-
README.md-40-## Limitations
README.md-41-
README.md:42:**Lock Screen:** By default, Computer Use is blocked while macOS is locked (fail-closed). `CGSessionCopyCurrentDictionary` is unavailable to unprivileged processes when the session is locked; any lock-state evidence that is absent, nil, or unparseable is treated as locked. For fully attended, screenshot-driven automation, unlock the Mac or use a dedicated logged-in desktop session.
README.md-43-
README.md:44:For unattended agents (Claude Code, Codex) that must keep working while the screen is locked, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` to opt into **best-effort** control while locked. This works because every action tool delivers input process-targeted — accessibility actions (`AXUIElementPerformAction` / `AXUIElementSetAttributeValue`) or `CGEvent.postToPid`, never the global HID event tap — which keeps functioning while the login window owns the screen. Under this opt-in an agent can still read the accessibility tree via `get_app_state` and drive an accessibility-controllable app with element-targeted `click` / `type_text` / `scroll` / `set_value`. **Known limitations while locked:** window screenshots return blank (macOS blocks capture for security, so `get_app_state` yields the AX tree without an image) and coordinate-only paths that need a visible cursor are unreliable — prefer element-targeted (`element_index`) actions.
README.md-45-
README.md:46:**Trust boundary (read before enabling):** the opt-in is off by default. When you run from the `.app` bundle, set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` in the shell that first launches the agent — the policy is fixed for that agent's lifetime (quit it from the menu bar to change it) and is passed only through the trusted launch environment, not the per-call IPC channel, so another process cannot flip it against a running agent. The app-agent socket is peer-authenticated: on each connection the agent checks the caller's uid (`getpeereid`) and, whenever the agent binary carries a Team Identifier (any signed build, including Dev bundles auto-signed with an Apple Development certificate), requires the connecting process to be code-signed by the same developer (Team Identifier) — and, when the agent runs from a bundle, with the agent's own bundle identifier — via its audit token. This **raises the bar** — a foreign, unsigned, or other-developer binary can no longer connect and drive the agent. It does **not** make the agent safe on an untrusted machine: a process running as your user can still `exec` the legitimate, same-developer-signed CLI (it lives at a fixed path in the app bundle) and relay commands through it, so same-uid code you don't control can still reuse the agent's Accessibility grant — including while the screen is locked. Unsigned local `swift build` binaries fall back to same-uid trust only (a one-time stderr notice is printed). The release build script refuses to produce an ad-hoc-signed/unsigned release bundle unless `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` is set explicitly, so a distributed release cannot ship with peer authentication silently inactive. **For hostile or multi-tenant machines, use a dedicated logged-in session — do not rely on peer-auth or the locked opt-in as an isolation boundary.**
README.md-47-
README.md-48-## Quick Start
README.md-49-

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "sed -n '1907,2161p' packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift | rg -n '"'^'"\\s+func test' && rg -n \"MCPAppRuntime|Lock detection will treat all states as locked|version skew indicator\" packages/OpenComputerUseKit/Tests apps/OpenComputerUse"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
3:    func testMacSessionGuardBlocksWhenLocked() {
12:    func testMacSessionGuardAllowsWhenUnlocked() {
18:    func testMacSessionGuardFailsClosedOnNilDictionary() {
27:    func testMacSessionGuardFailsClosedOnEmptyDictionary() {
37:    func testMacSessionGuardFailsClosedOnParseFailed() {
47:    func testMacSessionGuardRawKeysDiagnostics() {
55:    func testSystemMacSessionStateProviderCachesWithinTTL() {
79:    func testDispatcherBlocksAllGUIToolsWhenLocked() {
96:    func testLockPolicyDefaultsToBlockWhenEnvironmentUnset() {
103:    func testLockPolicyParsesAllowValuesFromEnvironment() {
113:    func testGuardBlocksWhenLockedUnderDefaultPolicy() {
119:    func testGuardAllowsAllToolsWhenLockedUnderOptInPolicy() {
128:    func testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy() {
140:    func testGuardStillAllowsEverythingWhenUnlockedRegardlessOfPolicy() {
147:    func testDispatcherAllowsAXToolsWhenLockedWithOptIn() {
159:    func testPeerAuthRejectsDifferentUID() {
173:    func testPeerAuthAllowsSignedSameTeamSameUID() {
184:    func testPeerAuthRejectsSignedAgentWhenPeerFailsRequirement() {
201:    func testPeerAuthFallsBackToSameUIDWhenAgentUnsigned() {
217:    func testPeerAuthUnsignedAgentStillRejectsDifferentUID() {
231:    func testDispatcherAllowsUnlockedTools() {
240:    func testMCPServerStillHandlesInitializeWhenLocked() {
apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift:46:                    try MCPAppRuntime.run(server: server)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:5:final class MCPAppRuntime: NSObject, NSApplicationDelegate {
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:21:        let delegate = MCPAppRuntime(server: server)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:60:        // Proactive startup check — warn if CGSSessionScreenIsLocked key is absent (version skew indicator)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:63:            fputs("[open-computer-use] WARNING: CGSSessionScreenIsLocked key absent from CGSessionCopyCurrentDictionary at startup (keys seen: \(startupSnapshot.rawKeysSeen.sorted().joined(separator: ","))). Lock detection will treat all states as locked. Verify macOS version compatibility.\n", stderr)

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "rg -n \"class StdioMCPServer|struct StdioMCPServer|ComputerUseToolDispatcher\" packages/OpenComputerUseKit/Sources/OpenComputerUseKit apps/OpenComputerUse/Sources/OpenComputerUse | head -160 && rg -n \"callToolAsResult|dispatcher\\.callTool|Task\\s*\\{|DispatchQueue|detachNewThread|acceptLoop\" packages/OpenComputerUseKit/Sources/OpenComputerUseKit apps/OpenComputerUse/Sources/OpenComputerUse | head -240"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:39:public final class ComputerUseToolDispatcher {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:278:    let dispatcher = ComputerUseToolDispatcher(service: service, guard: macSessionGuard)
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift:20:public final class StdioMCPServer {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift:21:    private let dispatcher: ComputerUseToolDispatcher
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift:24:        self.dispatcher = ComputerUseToolDispatcher(service: service)
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:209:            Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:628:                Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:637:                Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:645:                Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:673:            Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:845:            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift:846:                Task { @MainActor [weak self] in
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:54:            Task { @MainActor in
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:58:        Thread.detachNewThreadSelector(#selector(processStandardIO), toTarget: self, with: nil)
apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift:101:        DispatchQueue.main.async {
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:210:            Task { @MainActor in
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:317:        Thread.detachNewThread {
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:318:            self.acceptLoop()
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:328:    private func acceptLoop() {
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:343:                Thread.detachNewThread {
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:348:                Thread.detachNewThread {
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:397:                Task { @MainActor in
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:438:                    Task { @MainActor in
apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:447:                    Task { @MainActor in
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift:19:        DispatchQueue.main.sync {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:114:    public func callToolAsResult(name: String, arguments: [String: Any]) -> ToolCallResult {
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:286:        let result = dispatcher.callToolAsResult(name: toolName, arguments: arguments)
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift:298:            let result = dispatcher.callToolAsResult(name: call.tool, arguments: call.arguments)
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift:73:                Task { @MainActor in
packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift:89:                let result = try dispatcher.callTool(name: name, arguments: arguments)

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Completed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[1mhook:[0m [2mPreToolUse[0m Failed
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "nl -ba apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift | sed -n '300,480p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
   300	            close(socketFD)
   301	            throw POSIXError(.init(rawValue: errno) ?? .EIO)
   302	        }
   303	
   304	        guard listen(socketFD, 16) == 0 else {
   305	            close(socketFD)
   306	            throw POSIXError(.init(rawValue: errno) ?? .EIO)
   307	        }
   308	
   309	        guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
   310	            close(socketFD)
   311	            unlink(path)
   312	            throw POSIXError(.init(rawValue: errno) ?? .EIO)
   313	        }
   314	    }
   315	
   316	    func start() {
   317	        Thread.detachNewThread {
   318	            self.acceptLoop()
   319	        }
   320	    }
   321	
   322	    func stop() {
   323	        running = false
   324	        close(socketFD)
   325	        unlink(path)
   326	    }
   327	
   328	    private func acceptLoop() {
   329	        while running {
   330	            let clientFD = accept(socketFD, nil, nil)
   331	            guard clientFD >= 0 else {
   332	                if running {
   333	                    Thread.sleep(forTimeInterval: 0.05)
   334	                }
   335	                continue
   336	            }
   337	
   338	            // Authenticate the connecting process before it can drive the TCC-authorized agent.
   339	            // Same-uid alone is insufficient (any user process could connect); require the peer to
   340	            // be code-signed by the same developer as this agent, with a same-uid dev fallback.
   341	            switch SocketPeerAuthenticator.authenticate(fileDescriptor: clientFD) {
   342	            case .allow:
   343	                Thread.detachNewThread {
   344	                    AppAgentConnection(fileDescriptor: clientFD).run()
   345	                }
   346	            case .allowUnsignedFallback:
   347	                UnsignedPeerFallbackNotice.shared.emitIfNeeded()
   348	                Thread.detachNewThread {
   349	                    AppAgentConnection(fileDescriptor: clientFD).run()
   350	                }
   351	            case let .reject(reason):
   352	                fputs("[open-computer-use] rejected app-agent socket peer: \(reason)\n", stderr)
   353	                close(clientFD)
   354	            }
   355	        }
   356	    }
   357	}
   358	
   359	private final class AppAgentConnection: @unchecked Sendable {
   360	    private let fileDescriptor: Int32
   361	    private let server = StdioMCPServer()
   362	
   363	    init(fileDescriptor: Int32) {
   364	        self.fileDescriptor = fileDescriptor
   365	    }
   366	
   367	    func run() {
   368	        guard let file = fdopen(fileDescriptor, "r+") else {
   369	            close(fileDescriptor)
   370	            return
   371	        }
   372	        defer { fclose(file) }
   373	
   374	        while let line = readAgentLine(file) {
   375	            let response = handle(requestLine: line)
   376	            writeAgentLine(response, to: file)
   377	        }
   378	    }
   379	
   380	    private func handle(requestLine: String) -> [String: Any] {
   381	        do {
   382	            guard let request = try JSONSerialization.jsonObject(with: Data(requestLine.utf8)) as? [String: Any],
   383	                  let kind = request["kind"] as? String
   384	            else {
   385	                return ["error": "Invalid app-agent request"]
   386	            }
   387	
   388	            switch kind {
   389	            case "agentInfo":
   390	                return [
   391	                    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
   392	                    "bundleURL": Bundle.main.bundleURL.standardizedFileURL.path,
   393	                    "executableURL": Bundle.main.executableURL?.standardizedFileURL.path ?? "",
   394	                    "processStartTime": appAgentProcessStartDate.timeIntervalSince1970,
   395	                ]
   396	            case "terminate":
   397	                Task { @MainActor in
   398	                    NSApp.terminate(nil)
   399	                }
   400	                return ["ok": true]
   401	            case "mcp":
   402	                let line = request["line"] as? String ?? ""
   403	                if let response = server.handle(line: line) {
   404	                    return ["response": response]
   405	                }
   406	                return ["response": NSNull()]
   407	            case "cli":
   408	                let arguments = request["arguments"] as? [String] ?? []
   409	                var environment = request["environment"] as? [String: String] ?? [:]
   410	                // Defense in depth: never honor a per-call client's attempt to set the lock-screen
   411	                // policy. It is fixed at agent launch; a forged value here is silently dropped.
   412	                environment.removeValue(forKey: MacSessionLockPolicy.environmentKey)
   413	                let response = AppAgentEnvironment.withOverrides(environment) {
   414	                    runCLI(arguments: arguments)
   415	                }
   416	                return [
   417	                    "stdout": response.stdout,
   418	                    "stderr": response.stderr,
   419	                    "exitCode": Int(response.exitCode),
   420	                ]
   421	            default:
   422	                return ["error": "Unknown app-agent request kind: \(kind)"]
   423	            }
   424	        } catch {
   425	            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
   426	            return ["error": message]
   427	        }
   428	    }
   429	
   430	    private func runCLI(arguments: [String]) -> CLIProxyResponse {
   431	        do {
   432	            let command = try parseOpenComputerUseCLI(arguments: arguments)
   433	
   434	            switch command {
   435	            case .launchOnboarding:
   436	                let permissions = PermissionDiagnostics.current()
   437	                if !permissions.allGranted {
   438	                    Task { @MainActor in
   439	                        PermissionOnboardingApp.present()
   440	                    }
   441	                }
   442	                return CLIProxyResponse(stdout: "", stderr: "", exitCode: EXIT_SUCCESS)
   443	
   444	            case .doctor:
   445	                let permissions = PermissionDiagnostics.current()
   446	                if !permissions.missingPermissions.isEmpty {
   447	                    Task { @MainActor in
   448	                        PermissionOnboardingApp.present()
   449	                    }
   450	                }
   451	                return CLIProxyResponse(stdout: permissions.summary + "\n", stderr: "", exitCode: EXIT_SUCCESS)
   452	
   453	            case .listApps:
   454	                let service = ComputerUseService()
   455	                return CLIProxyResponse(stdout: (service.listApps().primaryText ?? "") + "\n", stderr: "", exitCode: EXIT_SUCCESS)
   456	
   457	            case let .snapshot(app, textLimit, treeLimits):
   458	                let service = ComputerUseService()
   459	                let text = try service.getAppState(app: app, textLimit: textLimit, treeLimits: treeLimits).primaryText ?? ""
   460	                return CLIProxyResponse(stdout: text + "\n", stderr: "", exitCode: EXIT_SUCCESS)
   461	
   462	            case let .call(invocation):
   463	                let output = try runOpenComputerUseCall(invocation)
   464	                return CLIProxyResponse(
   465	                    stdout: try output.jsonText() + "\n",
   466	                    stderr: "",
   467	                    exitCode: output.hasToolError ? EXIT_FAILURE : EXIT_SUCCESS
   468	                )
   469	
   470	            default:
   471	                return CLIProxyResponse(stdout: "", stderr: "Unsupported proxied command.\n", exitCode: EXIT_FAILURE)
   472	            }
   473	        } catch {
   474	            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
   475	            return CLIProxyResponse(stdout: "", stderr: message + "\n", exitCode: EXIT_FAILURE)
   476	        }
   477	    }
   478	}
   479	
   480	private enum AppAgentEnvironment {

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[35m[3mexec[0m[0m
[1m/bin/zsh -lc "nl -ba packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift | sed -n '1,125p'"[0m in /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fix-mac-session-guard-lock-detection
[32m succeeded in 0ms:[0m
     1	import Foundation
     2	
     3	let computerUseServerInstructions = """
     4	Computer Use tools let you interact with macOS apps by performing UI actions.
     5	
     6	Some apps might have a separate dedicated plugin or skill. You may want to use that plugin or skill instead of Computer Use when it seems like a good fit for the task. While the separate plugin or skill may not expose every feature in the app, if the plugin can perform the task with its available features, prefer it. If the needed capability is not exposed there, use Computer Use may be appropriate for the missing interaction.
     7	
     8	Begin by calling `get_app_state` every turn you want to use Computer Use to get the latest state before acting. Codex will automatically stop the session after each assistant turn, so this step is required before interacting with apps in a new assistant turn.
     9	
    10	The available tools are list_apps, get_app_state, click, perform_secondary_action, scroll, drag, type_text, press_key, and set_value. If any of these are not available in your environment, use tool_search to surface one before calling any Computer Use action tools.
    11	
    12	Computer Use tools allow you to use the user's apps in the background, so while you're using an app, the user can continue to use other apps on their computer. Avoid doing anything that would disrupt the user's active session, such as overwriting the contents of their clipboard, unless they asked you to!
    13	
    14	After each action, use the action result or fetch the latest state to verify the UI changed as expected.
    15	Prefer element-targeted interactions over coordinate clicks when an index for the targeted element is available. Note that element indices are the sequential integers from the app state's accessibility tree.
    16	Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks.
    17	Ask the user before taking destructive or externally visible actions such as sending, deleting, or purchasing. If helpful, you can ask follow-up questions before taking action to make sure you’re understanding the user’s request correctly.
    18	"""
    19	
    20	public final class StdioMCPServer {
    21	    private let dispatcher: ComputerUseToolDispatcher
    22	
    23	    public init(service: ComputerUseService = ComputerUseService()) {
    24	        self.dispatcher = ComputerUseToolDispatcher(service: service)
    25	    }
    26	
    27	    public func run() throws {
    28	        while let line = readLine(strippingNewline: true) {
    29	            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    30	                continue
    31	            }
    32	
    33	            if let response = handle(line: line) {
    34	                FileHandle.standardOutput.write((response + "\n").data(using: .utf8)!)
    35	            }
    36	        }
    37	    }
    38	
    39	    public func handle(line: String) -> String? {
    40	        do {
    41	            guard let payload = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
    42	                return try encodeJSONRPCError(id: nil, code: -32700, message: "Invalid JSON-RPC payload")
    43	            }
    44	
    45	            let method = payload["method"] as? String
    46	            let id = payload["id"]
    47	            let params = payload["params"] as? [String: Any] ?? [:]
    48	
    49	            switch method {
    50	            case "initialize":
    51	                return try encodeJSONRPCResult(
    52	                    id: id,
    53	                    result: [
    54	                        "protocolVersion": "2025-03-26",
    55	                        "serverInfo": [
    56	                            "name": "open-computer-use",
    57	                            "version": openComputerUseVersion,
    58	                        ],
    59	                        "capabilities": [
    60	                            "tools": [
    61	                                "listChanged": false,
    62	                            ],
    63	                        ],
    64	                        "instructions": computerUseServerInstructions,
    65	                    ]
    66	                )
    67	            case "notifications/initialized":
    68	                return nil
    69	            case "notifications/turn-ended":
    70	                VisualCursorSupport.performOnMain {
    71	                    SoftwareCursorOverlay.reset()
    72	                }
    73	                Task { @MainActor in
    74	                    ControlActivityStore.shared.markTurnEnded(connectionID: nil)
    75	                }
    76	                return nil
    77	            case "ping":
    78	                return try encodeJSONRPCResult(id: id, result: [:])
    79	            case "tools/list":
    80	                return try encodeJSONRPCResult(
    81	                    id: id,
    82	                    result: [
    83	                        "tools": ToolDefinitions.all.map(\.asDictionary),
    84	                    ]
    85	                )
    86	            case "tools/call":
    87	                let name = params["name"] as? String ?? ""
    88	                let arguments = params["arguments"] as? [String: Any] ?? [:]
    89	                let result = try dispatcher.callTool(name: name, arguments: arguments)
    90	                return try encodeJSONRPCResult(
    91	                    id: id,
    92	                    result: result.asDictionary
    93	                )
    94	            default:
    95	                if method == nil {
    96	                    return nil
    97	                }
    98	
    99	                return try encodeJSONRPCError(id: id, code: -32601, message: "Method not found: \(method ?? "")")
   100	            }
   101	        } catch let error as ComputerUseError {
   102	            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
   103	            let id = payload?["id"]
   104	            let result = ToolCallResult.text(error.errorDescription ?? String(describing: error), isError: error.toolResultIsError)
   105	            return try? encodeJSONRPCResult(id: id, result: result.asDictionary)
   106	        } catch {
   107	            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
   108	            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
   109	            let id = payload?["id"]
   110	            return try? encodeJSONRPCResult(
   111	                id: id,
   112	                result: [
   113	                    "content": [
   114	                        [
   115	                            "type": "text",
   116	                            "text": message,
   117	                        ],
   118	                    ],
   119	                    "isError": true,
   120	                ]
   121	            )
   122	        }
   123	    }
   124	
   125	    private func encodeJSONRPCResult(id: Any?, result: [String: Any]) throws -> String {

[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
[1mhook:[0m [2mPostToolUse[0m Completed
