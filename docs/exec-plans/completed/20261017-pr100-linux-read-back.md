# PR #100: Linux action read-back on current main

## Objective

Resolve #100 against latest main, review and repair any issues, run Linux regression and isolated real-widget tests, then push to the original contributor branch and report merge readiness. Do not merge.

## Constraints

- Reuse the existing worktree and running container engine. Do not start a desktop VM.
- Test only disposable fixture widgets on an isolated virtual display; do not touch personal applications.
- Preserve default native read-back, explicit observation, error propagation and previously observed indexes when read-back is disabled.
- Preserve the contributor's commits. Synchronize remote refs before a fast-forward push.

## Progress

- [x] Merge current main; resolve the release-note conflict while retaining both entries.
- [x] Review Go/Python branches and add regressions for any uncovered defects.
- [x] Run Go, Python and Node tests on Linux; validate real GTK/AT-SPI actions with and without read-back.
- [x] Update existing history and relevant documentation; push follow-ups and verify PR status.

## Validation

Use a temporary Linux container with a private D-Bus session, Xvfb display and GTK fixture. Verify successful actions return only an acknowledgment when disabled and actual widget state changes on the next explicit observation; default actions still return a snapshot, failures still surface, and repeated operations use the preserved index cache. Record any platform or scenario limits without claiming broader desktop performance.

## Evidence and outcome

- Production changes merged cleanly; the sole conflict was the release-note table, resolved by retaining both contributions.
- Full Linux Go test binary passed in Debian 12 ARM64; Python 14/14 and Node 24 36/36 passed. Linux-targeted vet, ARM64/AMD64 builds and repository checks passed.
- The native MCP/GTK test independently verified real widget state after short acknowledgments, repeated indexes, Unicode input, Return, secondary actions and errors. Default snapshots and explicit observations passed.
- Unmodified main failed the regression for all seven action branches. No further production-code defect was found.
- The reusable smoke starts Xvfb before the private D-Bus session so the accessibility registry inherits the display for key synthesis. Coverage is X11/GTK/AT-SPI; Wayland, other toolkits and whole-task performance remain outside this validation.
