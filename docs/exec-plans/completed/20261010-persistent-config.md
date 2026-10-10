# Persistent OCU configuration

## Goal and scope
Provide `ocu config` and a user JSON settings file, with environment overrides, for macOS screenshot encoding and bounds. Keep PNG defaults and the #65 hardware capture path. Windows/Linux screenshot policy is unchanged. Work from remote main independently of local experimental branches.

## Decisions and risks
- Use `$XDG_CONFIG_HOME/ocu/config.json`, otherwise `~/.config/ocu/config.json`; absolute `OPEN_COMPUTER_USE_CONFIG_FILE` overrides the file.
- Precedence: valid environment override, valid persisted value, built-in default. Reload each capture. Invalid runtime settings warn and fall back; CLI rejects invalid writes and malformed files.
- Screenshot settings are separate from safety gates. Atomic private writes; no implicit configuration writes during reads.
- Preserve screenshot coordinate mapping and bound PNG, JPG and lossless WebP. Keep existing public PNG helpers for compatibility.

- Final decision: remove byte budgets, their scale floor and ENV overrides; encode once after the long-edge cap. Stale budget settings are ignored and no longer listed or configurable.
- Follow-up: explicit resize/discard fields; minimum image area is width × height (default 64 pixels), checked before/after resizing. Preserve AX and explain omission, reject screenshot coordinates when omitted. Nullable maximum long edge; lossless WebP uses pinned static libwebp with bundled license.

## Validation and progress
- [x] Implement CLI, native loader and proxy isolation.
- [x] Test persistence, precedence, malformed files, encoding, bounds and packaging.
- [x] Synchronize docs/history and prepare a PR consolidating #72/#43 with both contributors credited.

## Results
Swift 192 tests (7 skipped) and Node 30 tests passed, including isolated npm staging. Docs/whitespace passed. Full smoke failed at fixture type_text; clean origin/main independently reproduced it. No signed App/release or real-desktop capture validation. Implementation is prepared on current main for the replacement PR, with Co-authored-by credit and existing PR heads untouched.
