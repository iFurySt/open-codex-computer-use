# macOS cleaned AX snapshot deltas

## Goal

Keep full AX acquisition, compare the cleaned semantic tree, and publish compact changes with enough context to act. macOS only; no observer or incremental acquisition work.

## Decisions

- Auto output by default; full recovery and none output are explicit modes.
- Stable integer references are separate from traversal budgets and never recycled within a client.
- AX object equality is primary identity; unique identifier plus matched parent/role is a conservative fallback. No fuzzy name/geometry rebinding.
- Operation caches and published snapshot history are separate. JS only advances its model baseline after emitting AX.
- Preserve existing cleaning, screenshot behavior, virtual-session read-back and input gates. Notebook outputs remain full.
- Missing baseline, changed observation scope, truncation or delta >= 80% of full text recovers with full output.

## Milestones

- [x] Structured renderer and identity reconciliation.
- [x] Delta output/history and native/JS/CLI/notebook integration.
- [x] Reconstruction, stale references, isolation and token replay tests.
- [x] Available automated verification, documentation and history; local commit is the final delivery step.

## Validation

Run swift test, node --test scripts/node-repl/*.test.mjs, headless tool smoke, and signed app build. Replay deterministic semantic transitions and report text tokens separately from screenshots. Real-app and model success measurements must be reported with their actual limits, never inferred from fixture savings.

## References

Playwright v1.59.0 AI snapshot tests and anchortree identity/diff design; external clones remain outside this repository and are not build dependencies. Record exact revisions after cloning.

## Outcome (2026-10-06)

- Swift: 217 tests, 2 pre-existing environment skips, no failures. JS: 31 passed. Native 11-step headless smoke and cursor idle smoke passed. Signed development App built.
- o200k_base / tiktoken 0.12.0 deterministic projection replay (21 observations including baseline): 90.34% fewer tokens for form updates, 72.45% for list changes, 92.36% for unchanged state. Screenshots excluded; this is not a model success benchmark.
- Real AppKit runner acquired AX/SCK and passed its unchanged-diff assertion; the action was then paused by the existing system-dialog/login-screen gate. No safety gate was bypassed. Real action/commercial-app/model comparisons are tracked as follow-up debt rather than claimed as complete.
- Order patches replace the affected sibling list; they do not compute a minimal sequence of moves. This is simple and reconstructable, and the measured list trace still exceeds the 50% token-reduction target.
- Playwright reference: 01b2b1533e0bfa1c582117e3ec109fcb57657747 (v1.59.0). anchortree reference: 2f085c506e9fa92e24940ba7c280545a35bee529. External clones were inspected, not vendored.
- No release version or tag change, and no push.
