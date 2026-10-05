# Session workspace and editable action notebook

## Goal

Replace the application sidebar with independently selectable virtual-display sessions. Create a display before attaching applications, support multiple apps on one display, and provide editable OCU tool cells with individual/run-all execution and visible outputs.

## Milestones

- [x] Multi-session registry, per-session capture, multi-app ownership and restoration.
- [x] Session sidebar, creation, app attachment sheet and managed-window selector.
- [x] Editable tool notebook, session binding, serial execution, outputs and stop/pause.
- [x] Tests, signed build and real GUI verification; synchronize docs/history.

## Constraints

Keep existing CLI/MCP/JS calls compatible. Inputs remain scoped to a verified app/window in a session; no global events, activation recovery or shell execution. Quit cleans all sessions, retaining the runtime when any cleanup fails. Notebook outputs are held in memory and not automatically persisted. Hardware acceptance left open in the original virtual-display plan remains open.

## Verification

Swift/Node contracts and existing smoke; live runner with two sessions and two real targets on one display, cross-session binding refusal, per-app snapshots, pause and independent teardown. Signed native GUI creation, attachment, editable cell execution and output inspection.

## Results

Completed implementation and core validation on macOS 26.5.1 / arm64. Swift 178 tests (1 optional live test skipped), Node 24 contracts, existing fixture/cursor smoke, single-session core runner and multi-session real AppKit runner pass. The latter verifies two 1×/2× displays, two apps on one display, three real notebook AX changes, unique process ownership, pause/capture isolation and independent/full cleanup.

Signed GUI validation covered creating an empty session, adding Calculator, Run all outputs, adding/editing/playing a click cell with sign change and restoration, creating/switching a second session and retaining notebooks, explicit resume after macOS desktop notifications, and Quit cleanup of both displays and the dedicated app. Strict signing checks pass. The final auto-scroll addition compiled, but a subsequent Mac lock prevented its final live UI recheck. Notebook outputs remain in memory and the kernel supports OCU tool JSON, not arbitrary JS/shell or .ipynb import/export.

Original hardware acceptance remains open in [the virtual-display plan](../active/20261005-virtual-display.md). No push, publishing or notarization submission. The baseline checkpoint commit is 128117b; the follow-up is committed locally at the user’s next checkpoint request.
