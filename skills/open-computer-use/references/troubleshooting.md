# Open Computer Use Troubleshooting

Read this reference when setup, permission checks, app discovery, snapshots, or actions fail.

## First Checks

Start with:

```sh
open-computer-use -h
open-computer-use doctor
open-computer-use call list_apps
```

On macOS, `doctor` reports Accessibility and Screen Recording status. If either is missing, ask the user to approve the onboarding UI.

## App Not Found

If `get_app_state` cannot find an app:

1. Run `open-computer-use call list_apps`.
2. Use the app name or bundle identifier from that result.
3. Confirm the app is running and has a visible, non-minimized window.
4. On macOS, rerun `open-computer-use doctor`.

Do not silently switch to a different app when the requested target is not available.

## Empty Or Missing Snapshot

Common causes:

- The app has no visible window.
- The window is minimized, hidden, or on an unavailable desktop.
- macOS Screen Recording permission is missing.
- Windows or Linux commands are running outside the logged-in desktop session.
- Linux screenshot support is blocked by the compositor or desktop portal state.

Ask the user to bring the target app/window into a visible state when automation cannot do so safely.

## Element Action Fails

If an element-targeted action fails:

1. Re-run `get_app_state`.
2. Confirm the `element_index` still exists and refers to the intended UI element.
3. Prefer `set_value` for settable text/value controls.
4. Prefer `perform_secondary_action` only for actions exposed in the state result.
5. Use coordinate `click`, `scroll`, or `drag` only after the semantic route is unavailable.

## Desktop Session Issues

Windows UI Automation and Linux AT-SPI require a live user desktop. SSH sessions, CI jobs, launch daemons, or services often do not have access to the GUI session even when the CLI binary starts successfully.

If desktop access is missing, ask the user to run the command from the logged-in desktop session or start the target app visibly in that session.

## Permission And Safety Issues

- Do not bypass macOS TCC prompts.
- Do not enable global pointer fallbacks unless the user asks for low-level diagnostic behavior.
- Do not interact with password managers or sensitive apps unless the user explicitly requests it.
- Pause before submitting, sending, deleting, purchasing, or approving anything externally visible.
