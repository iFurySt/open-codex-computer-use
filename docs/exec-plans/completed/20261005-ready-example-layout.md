# Runnable Calculator/TextEdit example and paired notebook UI

## Goal

Seed each new session with an editable, executable real example: compute a value in Calculator, read its actual UI result, and write it into a session-owned TextEdit document. Keep strict background input and verify every real UI change. Arrange command/result side by side, pretty-print JSON, and place screenshots beside the UI tree. Match HeyYo's native Dictionary toolbar/sidebar placement.

## Milestones

- [x] Session-owned document launch and safe cleanup; real Calculator/TextEdit example kernel.
- [x] Default example cells with semantic AX selection and result binding.
- [x] Paired command/output, tree/screenshot layout and native toolbar placement.
- [x] Swift/Node tests, live example, signed build, docs/history and local commit.
- [x] Final signed GUI collapsed/expanded check after manual unlock and native sidebar structure correction.

## Constraints

No global input, activation recovery, pasteboard, AppleScript or simulated success. Do not attach user-owned documents implicitly; dedicated demo files remain recoverable if an app refuses cleanup. Keep ordinary tools compatible. Existing broader hardware acceptance stays open. Current checkpoint is ee87a1d; locally commit this increment after verification, without pushing.

## Evidence and remaining checks

Swift 180 tests (1 opt-in skip), Node 24 contracts, existing smoke pass. The production example runner verifies all six cells, actual Calculator 714, TextEdit AX content, SCK screenshots, unchanged frontmost PID, zero runner global events and removal of both owned apps/temp document/display. Background TextEdit Cmd-S did not save and its AX Save menu is disabled after set_value; omitted unrequested file persistence from the default example and documented this limitation.

Signed GUI has created the session and started Run all with two real applications and paired JSON/tree/image output. The Mac then locked and the session paused. The earlier explicit navigation item produced duplicate toggles and a sidebar below the toolbar. Corrected to HeyYo's native sidebar List + top/bottom safeAreaInset, fullSizeContentView and visible native page title, retaining only the system toggle. Final signed expanded/collapsed screenshots and AX confirm full-height sidebar, sidebar brand, one toggle and trailing actions. Broader hardware acceptance remains open in the desktop-containment plan; this layout/example delivery plan is complete.

Completion note: the later strict launch-containment runner detects occasional TextEdit startup samples on physical screens. This completion covers the runnable example and paired/native GUI layout, and does not assert strict zero-flash acceptance. See the active desktop-containment plan.
