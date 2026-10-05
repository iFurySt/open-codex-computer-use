# Reduce virtual display desktop disruption and contain app windows

## Scope

User reports vertically stacked physical screens (main above second), Dock migrating after each display creation, desktop refresh, and transient Calculator windows on the physical desktop. Identify display reconfiguration vs visible launch vs input activation separately; do not claim one explains all three.

## Work

- [x] Record actual physical/main/Dock geometry before and after lifecycle; collect launch-window/foreground timeline.
- [x] Avoid redundant origin transactions; preserve main ID and physical geometry, stable lease identities, keep virtual screens adjacent to the existing right edge without changing physical geometry.
- [ ] Hidden dedicated launch, move offscreen AX windows before unhide, verify visibility/identity/frame; contain unexpected owned windows.
- [x] Remove synthetic activation from virtual-session sky_click, retain ordinary calls and explicit method behavior.
- [ ] Unit/contract tests, real stacked-layout lifecycle + example/window/input observations, signed GUI checks when unlocked.
- [ ] Sync architecture/security/reliability/quality/history, locally commit without pushing.

## Boundaries

No changes to Dock/Spaces/Stage Manager preferences, physical layouts, cursor or global input. No killing user apps, forced discard or silent activation recovery. CGVirtualDisplay online/offline still triggers WindowServer reconfiguration; do not promise zero desktop redraw or Dock pinning without evidence. Test success must include actual layout/main/Dock observations, not only final virtual frame.

## Evidence and open acceptance

Fixed and reproduced the app-agent shutdown deadlock: terminateLater cannot reenter an occupied MainActor/main-dispatch executor; use RunLoop callbacks with worker cleanup. New GUI creation completes, and signed active-session protocol shutdown removes runtime/helper in under one second. Add creation progress and a reusable isolated shutdown smoke.

Swift 182 tests (1 opt-in skip), Node 24 contracts, existing smoke pass. Current stacked physical arrangement: old helper moved Dock from upper main to lower second despite unchanged physical frames/main ID; optimized 20-cycle lifecycle preserves frames/main and the initial lower-screen Dock. Stable serials skip additional layout transactions on repeated create. Upper-main Dock preservation remains unverified; no safe pinning workaround is asserted.

Hidden Calculator plus TextEdit initial document launch completes all six real cells. Calculator has zero physical-window samples and no owned app activation in repeated observations. TextEdit still has occasional one-frame samples on a physical screen, so strict example acceptance remains open despite a zero-sample successful run; do not label it fixed. Unknown later app windows, concurrent manual AppKit input and complete Spaces/lock recovery remain broader acceptance work. The automatic/explicit sidebar toggle duplication also remains open in the earlier GUI plan.
