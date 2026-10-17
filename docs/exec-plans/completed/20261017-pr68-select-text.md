# PR #68: select_text through the current JS entry

## Objective

Merge current main into #68, preserve the contributor's implementation, complete app-bound JavaScript selection, review native safety/targeting and Unicode behavior, add meaningful tests and push follow-up commits to the same PR. Do not merge.

## Scope and constraints

- macOS native select_text plus app.selectText; preserve clear unsupported behavior on Linux/Windows.
- Use current queried-index resolution, Locked Use action checks, read-back mode and read-only snapshot recovery.
- Missing/ambiguous text, unsupported attributes and unverified results must be visible to callers without keyboard/pointer fallback.
- Test only disposable fixture/own AppKit widgets, not personal documents. Keep existing identity protection intact.

## Progress

- [x] Merge latest main and resolve tool-list, service, test and skill conflicts.
- [x] Review resolver/native implementation, repair safety/verification and compatibility defects.
- [x] Add validated JS API, forwarding tests and documentation.
- [x] Run full Swift/Node, native/MCP/JS fixture smoke and real AX selection checks where possible.
- [x] Update existing history, synchronize remotes, push and report merge readiness.

## Validation

Cover UTF-16 ranges, literal repeated/overlapping text and prefix/suffix disambiguation, both caret modes, unsupported/refused/unreadable selection, queried indices, no-read-back mode, session revalidation and JS error propagation. Distinguish synthetic fixture transport tests from real AX widget checks and document host restrictions.

## Evidence and outcome

- Integrated current main through `531c9d4`, including repository identity, trusted-publishing documentation and the upstream 1.1.2 release update. Preserve the original PR commit.
- Added app.selectText for Persistent and Worker sessions. Native actions resolve query indexes, validate leases, require a settable range, detect changed UTF-16 text and require an exact applied range, even without full read-back. Results use read-only recovery.
- Literal Unicode search fixes canonically equivalent spelling producing an incorrect range; exact overlapping counts use constant match-storage space.
- Swift 374 tests, 8 skipped, 0 failures. Selection-specific 22/22 includes a real own NSTextView AX test. Node 42/42 passed; native tool/cursor smoke and Worker JS/native fixture selection smoke passed.
- Follow-up real-service validation passed using the repository's normally packaged and signed release app, without changing system approvals or bypassing identity/session checks. The earlier Broken pipe came from using a development signing identifier absent from the installed client approvals.
- Worker JS → native MCP → real AX query index → selectText passed against disposable AppKit text views in both editable and read-only modes. Independently exported widget state confirmed UTF-16 ranges 3/2, 6/0 and 8/0, unchanged text, ambiguity/missing-text errors and no-read-back acknowledgments. The window could not become key/main, avoiding keyboard interference. This closes the previously unverified real-service chain; platform/opt-in suite skips remain separately documented.
- UUID-scoped fixture state and notifications isolate the new smoke. All temporary probe executables and windows were cleaned up. No version bump; Linux/Windows keep explicit unsupported behavior.
