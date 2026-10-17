# Locked Use unlock latency

## Goal

Investigate delayed authorization plug-in loading during manual unlock, fix related host / installation and idle / IPC costs, and submit a PR.

## Constraints

Preserve native password fallback and peer / permit validation. Do not disable SIP, alter Apple signatures, or grant private entitlements. Keep diagnostics bounded and avoid automatic lock tests until a short recovery path is ready.

## Progress

- [x] Read the referenced diagnosis and reproduce the installed metadata / host boundary read-only.
- [x] Confirm delayed system assessment, subsequent successful loading, real marker export and privileged host session binding.
- [x] Fix relevant polling / admission costs with regression coverage.
- [x] Validate build and authorization behavior; document limits and submit PR.

## Result

Completed on 2026-10-15. Signed native build, isolated authorization-host checks and offline regressions passed. The final normal-MCP run automatically unlocked, captured and incremented Counter 0→1, held protection for five seconds, relocked, received both guard release acknowledgements, then observed manual unlock with Counter still at 1. The user confirmed full coverage on both physical displays, no desktop flash and normal manual unlock.

Submitted [PR #99](https://github.com/iFurySt/open-codex-computer-use/pull/99). Full fault-injection, Intel hardware and credential/session-state validation remain outside this patch's completed checks; general OS sluggishness is not claimed resolved by this test.
