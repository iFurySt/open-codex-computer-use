# PR #95: verify live cursor following on current main

## Objective

Review #95 against current main, reproduce remaining cursor-follow defects, fix them on the contributor branch and report merge readiness. Preserve the original contribution. Do not merge the PR as part of this task.

## Scope

- Follow the live window frame during travel, settle, click feedback and idle.
- Keep Accessibility IPC out of the overlay render loop; bound tracking state and outstanding reads.
- Preserve input delivery and window focus policies. This is visual cursor positioning, not a new input-routing mode.
- Keep existing motion dynamics for stationary windows and clear tracking at cursor/session cleanup.

## Progress

- [x] Fetch PR head and merge current main without conflicts.
- [x] Reproduce stale idle/click targets with production-overlay regression tests.
- [x] Fix live placement, tracking lifecycle and bounded frame acquisition.
- [x] Run Swift/Node checks, smoke and isolated live-window validation where available.
- [x] Update history/docs and deliver follow-up commits on the existing PR branch.

## Validation

Exercise the actual overlay loop with controlled frame changes, including repeated moves, a move back to the original frame, unanchored targets and reset. Verify slow frame reads do not block rendering or accumulate work. Use only isolated test windows for live checks; do not move personal app windows or synthesize user typing. Distinguish injected tests from real Accessibility frame observations in the final evidence.

## Evidence and decisions

- The original overlay failed three of four new regression tests (16 assertions). Fixes now cover idle/pulse targets, the actual visible travel endpoint, stale anchors and orphan idle timers.
- Frame reads run on a serial worker at up to 30 Hz with one outstanding request. Retain only the current source and last valid frame; discard results for replaced sources.
- Swift: 351 tests, 8 skipped, 0 failures. Node: 36 passed. Fixture action smoke and cursor idle smoke passed after updating its old tool-list assertion for main's query tool.
- The production overlay followed an isolated real AX window during travel, pulse and idle. Only one physical display was available. The full service-click test explicitly skips on this machine because the XCTest host does not satisfy the installed Locked Use identity check; retain that protection.
- No input-routing changes or version bump. Preserve the contributor's original commit and update the existing PR.
