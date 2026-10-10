# Persistent screenshot configuration

## User request
Provide a user config file, environment overrides and `ocu config` commands so ordinary users can persist screenshot settings without shell environment setup, while reviewing PRs #72 and #43.

## Changes
- Added npm launcher config list/get/set/reset/path/help; atomic 0600 JSON writes, unknown-field preservation and validation. Default path uses XDG_CONFIG_HOME or the user's `.config/ocu/config.json`; an absolute explicit file override is supported.
- Native macOS snapshots reload configuration per capture. Valid ENV > file > defaults; malformed files warn and use ENV/defaults. App-agent requests forward caller path and isolate image environment settings.
- Added PNG/JPG/lossless WebP encoding with a matching MIME and format-neutral screenshot data; PNG remains the default and the old PNG accessor remains compatible and the internal PNG helper keeps dimension capping. All encodings keep actual returned-image coordinate mapping. Fixed dimension-cap scaling below the previous absolute minScale.
- Preserved #65 hardware capture first and SCK fallback; timeout applies to SCK only. Windows/Linux unchanged. This implementation combines the configurable-bound direction in #43 with the JPEG direction in #72 with the final size-only policy requested by the user.
- Added explicit `maxLongEdgePixels`, `scaleDownAfterMaxSize`, `discardBelowPixelCount` settings. Minimum size means width × height, as requested: 63 pixels are omitted and 64 retained by default; zero disables this filter. Filtering also applies after resizing. Oversize images scale down by default, or are omitted when scaling is disabled. Nullable size bounds disable that limit. Legacy config names remain readable.
- Omitted screenshots carry a reason while preserving AX output; coordinate clicks/drags reject missing screenshot coordinates.
- Pinned libwebp-Xcode 1.6.0, linked libwebp statically and included its BSD license in npm/App packaging. JPG quality does not affect lossless WebP.
- Final user decision: removed maxBytes and byteBudgetMinScale together with the retry loop, old internal PNG byte limits and ENV overrides. Encoding runs once after the long-edge cap; stale file/ENV budget values have no effect, and CLI rejects removed settings. Regression tests verify exact retained dimensions for all formats.
- Added paired English/Chinese configuration guides linked from their respective READMEs. Following the user’s writing preference, simplified both guides to the file location and default JSON, basic CLI usage, then one complete settings/defaults/commands table. Removed detailed runtime, ENV, compatibility and integration sections; retained ENV precedence and the key pixel-area semantics. Corrected the architecture screenshot paragraph to remove the superseded byte-budget behavior.
- Updated READMEs, architecture/security, usage and feature notes; added configuration documentation.

## Verification
- Swift: 192 tests, 7 opt-in live tests skipped, zero failures.
- Node: 30 tests passed, including actual staging/launcher testing with inert native packaging fixtures; no release artifact validation claimed.
- Native tests cover file reload, malformed-file fallback, precedence, all three encodings, bounds and coordinate mapping. Node covers persistence, invalid writes, file privacy and packaging.
- Documentation check and git diff whitespace check passed.
- Full smoke failed at the fixture type_text append assertion. An independent unmodified origin/main snapshot reproduced the same failure. Cursor-idle phase was not reached; real desktop readability/capture is unverified.
- System Node could not load its simdjson library; used the bundled Codex Node runtime without changing system installation.

## Attribution and delivery
- Integrates the screenshot-format/API cleanup and byte-cap removal from [#72](https://github.com/iFurySt/open-codex-computer-use/pull/72) by @hyprcat (ATG), and the configurable capture/size controls, scaling fix and request environment isolation from [#43](https://github.com/iFurySt/open-codex-computer-use/pull/43) by @aikins01 (Aikins Laryea). The final implementation adapts both contributions to persistent configuration and the agreed size-only policy.
- Consolidated the local development commits with Co-authored-by trailers using the original contributors’ commit identities. The replacement PR credits both authors and closes #72/#43 when merged; their original branches remain untouched.
- Synced with current main before delivery, retaining the v1.0.0 release notes alongside the new feature entry. Post-sync Swift and Node tests passed.
- PR delivery is authorized; no merge, release, signed App replacement or live desktop automation. The pre-existing smoke failure remains a separate follow-up.
