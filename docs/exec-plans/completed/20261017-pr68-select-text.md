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

- Integrated current main through `0daece0`, including repository identity and trusted-publishing documentation updates. Preserve the original PR commit.
- Added app.selectText for Persistent and Worker sessions. Native actions resolve query indexes, validate leases, require a settable range, detect changed UTF-16 text and require an exact applied range, even without full read-back. Results use read-only recovery.
- Literal Unicode search fixes canonically equivalent spelling producing an incorrect range; exact overlapping counts use constant match-storage space.
- Swift 374 tests, 8 skipped, 0 failures. Selection-specific 22/22 includes a real own NSTextView AX test. Node 42/42 passed; native tool/cursor smoke and Worker JS/native fixture selection smoke passed.
- An additional signed-native real-service probe returned Broken pipe from this machine's Locked Use observer connection. It is not counted as passed; no identity/session checks were bypassed. Real AX primitive coverage and native fixture transport coverage are distinct from full real-app service validation.
- UUID-scoped fixture state and notifications isolate the new smoke. All temporary probe executables and windows were cleaned up. No version bump; Linux/Windows keep explicit unsupported behavior.
