# Background input benchmarks (macOS)

Measured numbers for the background paths in this repo: `sky_click`, `key_method=sky_key`,
`get_app_state` snapshots, the occlusion keep-alive, and `window_placement=agent_display`.
Every number below comes from a test that is in the repo and can be re-run with the commands at
the end. Nothing here is estimated.

## Environment

| Item | Value |
| --- | --- |
| Machine | Apple M5, 16 GB；另在 Apple Silicon macOS 26.6.2 复验跨版本默认值 |
| macOS | 27.0 (26A5425a), single built-in display 3024x1964 Retina；26.6.2 (25G83) compatibility run |
| Chrome | Google Chrome 152.0.7977.82, isolated `--user-data-dir`, `--app=` window 600x420 |
| Date | 2026-09-08 / 2026-09-09 |
| Foreground during tests | `OpenComputerUseFixture` window fully covering the target, its text field first responder |
| Machine idle | Yes for every table below. Runs with a user at the keyboard were discarded (their keys landed in the test windows). |

## 1. Background click and key latency

`BackgroundInputBenchmarkLiveTests`, target = isolated Chrome fully covered by the fixture.
"Returns" is the time until the dispatcher returns; "observed" is until the page reflected the
action (polled every 3 ms via the window title, so it includes Chromium's own processing plus
up to a few ms of polling).

### Final defaults, unpinned window, 50 cycles

| Action | Success | Returns p50 | Returns p95 | Returns max | Observed p50 | Observed p95 | Observed max |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `sky_click` (single, exact-once) | 50/50 | 81.8 ms | 87.1 ms | 111.2 ms | 260.2 ms | 271.4 ms | 289.5 ms |
| `sky_key` `type_text` | 50/50 | 30.1 ms | 35.4 ms | 36.4 ms | 236.7 ms | 243.7 ms | 247.3 ms |

Frontmost app unchanged in every cycle. "Exact-once" means the page's click counter advanced by
exactly one per cycle; a double-fire would fail the run.

### Before tuning (inherited fixed gaps), unpinned, 25 to 50 cycles

| Action | Success | Returns p50 | Observed p50 |
| --- | --- | --- | --- |
| `sky_click` | 50/50 | 322.7 ms | 390.1 ms |
| `sky_key` `type_text` (300 ms key settle + 100 ms release) | 50/50 | 525.8 ms | 567.1 ms |

Observed latency barely moved (Chromium-internal work dominates it); the returned-call latency
is what the tuning removed.

## 2. Which gaps can be zero: the sweep that set the defaults

Same benchmark, 30 cycles per row, unpinned. Knobs: `FOCUS` = gap after each synthetic
focus/defocus record (`OPEN_COMPUTER_USE_FOCUS_RECORD_SETTLE_MS`); `SCALE` = multiplier on the
`sky_click` recipe gaps and renderer settle (`OPEN_COMPUTER_USE_SKY_CLICK_DELAY_SCALE`); type_text
chunk gap and press_key tail were 0 in every row except the last.

| FOCUS | SCALE | sky_click | sky_key | sky_click returns p50 | sky_key returns p50 |
| --- | --- | --- | --- | --- | --- |
| 0 ms | 0 | 0/30 | 5/30 | 5.6 ms | 8.3 ms |
| 20 ms | 0 | 0/30 | 7/30 | 53.9 ms | 55.8 ms |
| 20 ms | 0.05 | 30/30 | 30/30 | 67.1 ms | 54.5 ms |
| 0 ms | 0.1 | 30/30 | 30/30 | 33.3 ms | 6.5 ms |
| 10 ms | 0.1 | 30/30 | 30/30 | 57.6 ms | 29.8 ms |
| 20 ms | 0.1 | 30/30 | 30/30 | 79.8 ms | 53.7 ms |
| 0 ms | 0.25 | 30/30 | 30/30 | 69.6 ms | 5.7 ms |
| 0 ms | 1 | 30/30 | 30/30 | 234.1 ms | 5.7 ms |
| 40 ms | 1 (old defaults, with 20 ms chunk + 100 ms press tail) | 30/30 | 30/30 | 323.0 ms | 119.1 ms |

Readings:

- macOS 27 accepted zero-delay events in this sweep, but this does not establish a portable
  default. On macOS 26.6.2 the same pinned benchmark produced 18/20 and then 49/50 successful
  `sky_key` cycles with zero settle/release; setting both to 10 ms produced 50/50. Ordinary
  `auto` input was not covered by this background-only benchmark, so its established 20 ms
  type chunk gap and 100 ms press-key tail remain unchanged.
- The gap after a focus record is cross-channel: focus records travel `SLPSPostEventRecordTo`,
  mouse and key events travel `CGEventPostToPid`. 0 ms passed in every row that had non-zero
  click gaps, but the default is 10 ms (was 40) to keep margin.
- The `sky_click` recipe gaps cannot be 0. At scale 0 every click failed and the following key
  cycle mostly failed too; scale 0.05 passed everything. Default is 0.2 (2x the passing minimum),
  which is 20 ms after the primer and 20 ms renderer settle instead of 100 ms each.

Current defaults: `FOCUS=10`, `SCALE=0.2`, `TYPE_CHUNK=20`, `PRESS_KEY=100`, `SKY_KEY_SETTLE=10`,
`SKY_KEY_RELEASE=10`. All six are environment variables; see `docs/RELIABILITY.md`.

## 3. Pinned versus unpinned window

Same benchmark, 15 cycles per row, `sky_key` only. "Pinned" = the occlusion keep-alive had
disabled the window's occlusion notifications while it was visible (what `get_app_state` does),
so Chromium still considered the covered page visible.

| Window | Key settle | Success | Returns p50 | Observed p50 |
| --- | --- | --- | --- | --- |
| pinned | 0 ms | 15/15 | 220.9 ms* | 271.2 ms |
| unpinned | 0 ms | 15/15 | 221.9 ms* | 267.0 ms |
| unpinned | 20 ms | 15/15 | 246.9 ms* | 288.7 ms |
| unpinned | 100 ms | 15/15 | 325.9 ms* | 367.3 ms |
| unpinned | 300 ms | 15/15 | 526.5 ms* | 569.7 ms |

Compatibility follow-up on macOS 26.6.2, pinned isolated Chrome, 50 cycles: zero settle/release
gave 49/50 keys, while 10 ms settle/release gave 50/50 keys (clicks were 50/50 in both runs).

\* these rows still carried the old 40 ms focus gaps, 20 ms chunk gap and 100 ms release. The
point of the table is that the key settle does not affect success in either state.

## 4. Snapshot (`get_app_state`) phases

`OPEN_COMPUTER_USE_DEBUG_TIMING=1`, real apps on this machine, read-only policy.

| Phase | Measured |
| --- | --- |
| Window capture via `SLSHWCaptureWindowList` (now primary) | 14.8 to 32.6 ms across 9 apps, retina resolution |
| Window capture via ScreenCaptureKit (fallback) | 86.9 to 154.6 ms; fails with -3811 for windows on inactive fullscreen Spaces |
| AX tree walk | 26.4 to 81.4 ms (Chrome, 300 to 600 nodes) |
| Whole snapshot incl. PNG encoding | 47 ms (5-node app) to 1044 ms (Blender, 5 nodes but slow AX) |

## 5. Agent display (`window_placement=agent_display`)

`AgentDisplayLiveTests` and the parked survey, poll-based waits (no fixed sleeps).

| Step | Measured |
| --- | --- |
| Create the virtual display (`applySettings:` returns) | 333 to 353 ms |
| Display ready (bounds valid and its Space listed by WindowServer) | 407 to 572 ms from creation |
| Park a window (AX position set, frame inside the display, Space updated) | 144 to 230 ms with the display already up; 518 to 911 ms when the display is created for it |
| Restore a window to its original origin | 260 ms (live test); 496 to 1149 ms in the survey, dominated by waiting for the frame to report the old origin |
| Display removed after last restore | yes; online display count returned to 1 every time |

Chromium page on the parked window: `visibilityState` becomes `visible`, the full web tree is
present, capture and click/type work. Frontmost app and pointer unchanged in every run.

## 6. Reliability counts

| Test | Result |
| --- | --- |
| `BackgroundInputBenchmarkLiveTests`, 50 cycles, final defaults | 50/50 clicks, 50/50 keys, exact-once, frontmost unchanged |
| `SkyKeyboardLiveTests` (typing, backspace, `shift+a`, `cmd+a` via menu, release) | pass |
| `SkyClickLiveTests` (exactly one DOM click, no foreground side effects) | pass |
| `OcclusionKeepAliveLiveTests` (covered page stays visible, tree and screenshot intact) | pass |
| `CrossSpaceLiveTests` (window on a real second Desktop; snapshot, click, type; active Space unchanged) | pass |
| `AgentDisplayLiveTests` (hidden window parked, driven, restored, display removed) | pass |
| Physical (HID) keystrokes while a target holds synthetic key state | delivered to the real frontmost app, not to the target |
| `swift test` | 176 tests, 0 failures, 7 live tests skipped by default |

## 7. Multi-app survey (`AppMatrixLiveTests`)

27 running GUI apps, read-only snapshot each, plus click and type into an empty text field
where one exists. Input only targets fields whose current value is empty and whose center lies
inside the window, and the marker is removed afterwards.

### On the desktop (windows left where they were)

| App | Engine | Snapshot | Nodes | Web tree | Screenshot | Input |
| --- | --- | --- | --- | --- | --- | --- |
| Zed | native | 156 ms | 14 | | 306 KB | no empty field |
| TextEdit | native | 105 ms | 53 | | 63 KB | no empty field |
| System Settings | native | 213 ms | 98 | | 321 KB | typed and cleared |
| KiCad | native (wx) | 159 ms | 33 | | 424 KB | no empty field |
| Alma | native | 47 ms | 5 | | 5 KB | no empty field |
| Blender | GL | 1044 ms | 5 | | 555 KB (fullscreen Space; SCK failed, HW capture worked) | no empty field |
| VS Code | Electron | 434 ms | 310 | yes | 244 KB (fullscreen Space; SCK failed, HW capture worked) | no empty field |
| Slack | Electron | 375 ms | 261 | yes | 388 KB | typed and cleared |
| Google Chrome | Chromium | 772 ms | 610 | yes | 199 KB | no empty field |
| Safari | WebKit | 409 ms | 394 | yes | 269 KB | candidate was a popover child outside the window; rejected by design |
| Notes, Mail, Excel, Activity Monitor, Terminal, Helium, Figma, Canva, Linear, Devin | various | `cgWindowNotFound` | | | | apps running with no window; read-only policy does not activate them |

### Parked on the agent display, then restored

| App | Park | Snapshot on display | Nodes | Web tree | Screenshot | Input while parked | Restore | Back at origin |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Zed | 911 ms | 98 ms | 14 | | 335 KB | no empty field | 638 ms | yes |
| TextEdit | 652 ms | 61 ms | 53 | | 25 KB | no empty field | 550 ms | yes |
| Safari | 635 ms | 359 ms | 394 | yes | 280 KB | no empty field | 887 ms | yes |
| Alma | 518 ms | 24 ms | 5 | | 4 KB | no empty field | 496 ms | yes |
| Slack | 522 ms | 365 ms | 261 | yes | 250 KB | typed and cleared, 132 ms | 983 ms | yes |
| Google Chrome | 606 ms | 647 ms | 610 | yes | 215 KB | no empty field | 1149 ms | yes |
| System Settings | 557 ms | 154 ms | 101 | | 152 KB | typed and cleared, 108 ms | 624 ms | yes |
| KiCad | 689 ms | 74 ms | 27 | | 88 KB | no empty field | 619 ms | yes |
| VS Code, Blender | skipped | | | | | fullscreen windows cannot be repositioned | | |

Frontmost app and pointer unchanged for the whole run; the display was removed at the end.

## 8. What the numbers do not cover

- One machine, one macOS build (a beta). Private SPI behaviour must be re-measured per release.
- "Observed" latency includes Chromium's internal processing and the title polling; it is a
  ceiling, not a measurement of the runtime.
- Background typing was verified in one native app, one Electron app and Chromium. WebKit and
  native document editors were only read, not typed into, because the survey refuses to type
  into non-empty fields.

## Reproduce

```sh
# unit suite
swift test

# 50-cycle latency benchmark (defaults), window not pinned
OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH=1 OPEN_COMPUTER_USE_BENCH_CYCLES=50 OPEN_COMPUTER_USE_BENCH_UNPINNED=1 \
  swift test --filter BackgroundInputBenchmarkLiveTests

# sweep example: zero focus gap, tenth click gaps
OPEN_COMPUTER_USE_RUN_BACKGROUND_BENCH=1 OPEN_COMPUTER_USE_BENCH_CYCLES=30 OPEN_COMPUTER_USE_BENCH_UNPINNED=1 \
  OPEN_COMPUTER_USE_FOCUS_RECORD_SETTLE_MS=0 OPEN_COMPUTER_USE_SKY_CLICK_DELAY_SCALE=0.1 \
  swift test --filter BackgroundInputBenchmarkLiveTests

# live regressions
OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests
OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests
OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests
OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests      # needs a second Desktop
OPEN_COMPUTER_USE_RUN_AGENT_DISPLAY_LIVE_TEST=1 swift test --filter AgentDisplayLiveTests

# app survey (types into real apps; run only when nobody is using the Mac)
OPEN_COMPUTER_USE_RUN_APP_MATRIX=1 swift test --filter AppMatrixLiveTests
OPEN_COMPUTER_USE_RUN_APP_MATRIX=1 OPEN_COMPUTER_USE_APP_MATRIX_PARK=1 swift test --filter AppMatrixLiveTests

# per-phase timings on any command
OPEN_COMPUTER_USE_DEBUG_TIMING=1 open-computer-use call get_app_state --args '{"app":"Google Chrome"}'
```
