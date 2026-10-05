# macOS virtual display and standalone OCU workspace

## Goal

Ship an OCU GUI for app selection and live virtual-monitor preview, backed by the same session registry as CLI/MCP/JS. Keep background input strict: never activate an app or use global pointer input in a virtual session.

Status: implementation delivered and automated/native core checks passed. Keep this plan active for the controlled hardware acceptance items below; those items are not complete.

## Milestones

- [x] Private Objective-C bridge and disposable display-holder process.
- [x] Shared session lifecycle, exact window binding, placement/restoration and capture.
- [x] Session-aware tools and JS bindings, with nonintrusive input enforcement.
- [x] Standalone GUI and shared demo preview; bundle/sign the helper.
- [x] Real AppKit runner, repeated lifecycle tests and third-party compatibility evidence.
- [x] Regression tests, documentation and history.

## Decisions

- 2026-10-05: One active display/session and one target application, with multiple managed windows. Default 1920×1080 logical points at 1×, optional 2×.
- 2026-10-05: A disposable helper owns only the private display API. Capture/AX remain in the signed OCU process. EOF terminates the helper; removal must be observed.
- 2026-10-05: GUI uses the existing OCU bundle identity, signing configuration and runtime. Reuse HeyYo's native window/navigation patterns without importing its business dependencies.
- 2026-10-05: Real GUI acceptance uses AX and ScreenCaptureKit, never FixtureBridge. Unsupported background operations fail closed.

## Verification

Run Swift tests, Node contracts, existing smoke, native bundle/signature checks, and a live runner covering exact window binding, UI changes, frontmost/pointer preservation, 1×/2× and 20 create/destroy cycles. Record unavailable permissions and untested OS/Space/third-party behavior explicitly. Do not infer compatibility from event delivery alone.

## Risks

Private ABI changes, display removal delays, application self-activation, shared desktop focus, modal/system windows and capture reconfiguration. Pause on invalid geometry/identity/desktop state; do not force-quit borrowed or unsaved applications. Crash recovery is best effort with identity verification.

## Implementation evidence

- Swift 175 tests pass (1 opt-in live test skipped); Node 23 contracts pass; existing fixture/tool/cursor smoke passes.
- macOS 26.5.1 / arm64: real AppKit AX click, Unicode value, scroll, sheet, 1×/2× identifiable capture marker, 20 lifecycle cycles, stale-frame teardown, pause/read-only inspection/resume, client and turn cache isolation, and owned-helper SIGKILL cleanup verified.
- Release app and helper signed with the existing Developer ID configuration; strict signature verification passes. Dev permission-missing UI verified. Release reused existing permissions.
- Native GUI Calculator session: launch, exact placement, live preview, same namespace CLI join, AX sign change and restoration, pause/input rejection/resume, close-with-session-alive/reopen, End cleanup and Quit with an active session verified.
- Default TextEdit launch had no exact ordinary window; temporary-profile Chrome activated itself. Both failed closed and cleaned up. app_post/sky_click did not change the AppKit counter. Drag is rejected rather than declared supported.
- Foreground AppKit probe encountered a foreground switch, so active/key/first-responder preservation remains unverified. No global event delivery was observed in the background runner.
- Docs check passes; repo hygiene fails on pre-existing missing template/config/workflow files.

## Acceptance still requiring controlled hardware runs

Persistent human typing with AppKit focus/resign evidence, Spaces/Stage Manager, sleep/lock/unlock, runtime permission revocation, parent crash recovery, unsaved-content refusal, cross-architecture and other macOS versions. These are documented limits, not inferred support. Native preview is viewing only. No release publishing or notarization submission performed.

Final hardening: kernel process-start identity supports unbundled AppKit targets; snapshot/action scope excludes the system menu bar and other windows; the controlled target uses a nonactivating native sheet after NSAlert activation was observed. Latest real 2× core runner passes these guards.

Final artifact check: rebuilt release and dev variants with the existing signing configuration and verified each bundle/helper strictly. The final release artifact starts via LaunchServices even from a no-argument CLI launch. Calculator AX sign changes were verified again through the shared CLI session; active-session Quit removed the app, helper, display and owned recovery marker. Swift 175 tests (1 skipped), Node 23 tests, docs and diff checks remain passing. Virtual events isolate requested modifiers from physical keyboard modifiers. Parent-crash/profile recovery has identity guards but still needs end-to-end acceptance.
