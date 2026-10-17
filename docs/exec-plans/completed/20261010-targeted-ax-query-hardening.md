# Harden PR #73 targeted AX query

## Scope
Update the contributor’s existing PR on current main, retaining author history. Integrate persistent screenshot config, hardware/SCK capture, background-window and agent-display behavior. Keep query macOS-only and add its JS entry points.

## Decisions
- Query resolves running applications only. Exact means exact, with no automatic substring retry.
- Query indexes are session-local, bound to the process/window, bounded and never reused. Reject wrong-app, stale-window, stale-element and expired indexes before input; refresh geometry without cached-coordinate fallback.
- Return matches with truncation/stopping metadata. Bound traversal nodes, child fetches/queue, strings and AX call/query time. Use a single bounded traversal for consistent role/text/visibility matching instead of the opaque native predicate path.
- Add app.query and a lightweight getApp option that does not fetch initial state. Preserve existing getApp behavior by default; document the persistent-session requirement for query then action.

## Progress
- [x] Merge current main without discarding screenshot/background changes.
- [x] Harden registry, arguments, window/element validation and traversal.
- [x] Add JS API and focused regression tests.
- [x] Update docs/history and complete checks. Follow-up commits are ready for the original #73 branch.

## Validation
Swift unit tests with injected registry/search inputs; Node mock-native and persistent-session tests; actual invalid window_id subprocess regression; docs/whitespace checks. No app installation, foreground interaction or unrelated PR changes. Live AX latency remains a separate opt-in check; cooperative deadline is not a hard interrupt of an in-flight system AX call.

## Results
- `swift test`: 207 tests, 7 skipped, zero failures.
- `node --test scripts/node-repl/*.test.mjs`: 33 tests passed, including persistent query/action, malformed options and response metadata.
- `make check-docs` and `git diff --check`: passed.
- Direct native CLI regression with negative window_id: structured tool error and exit 1, no process trap; app-agent proxy disabled for the check.
- Fresh origin/main and contributor source fetched; current main is integrated and the original contributor head is an ancestor. No force push is needed.
- Real desktop latency and stale-window behavior have not been exercised interactively. Registry/walk/argument logic is covered with injected tests; the cooperative traversal deadline cannot interrupt an in-flight AX system call.
