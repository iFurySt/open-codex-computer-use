## [2026-10-15 20:12] | Task: Honor action read-back configuration on Linux

### Execution Context
- Agent: Codex
- Runtime: Linux development environment

### User Request
Submit a focused upstream fix for Linux ignoring the existing action read-back switch.

### Changes
- Match macOS parsing of `OPEN_COMPUTER_USE_ACTION_READ_BACK`; preserve read-back by default.
- Pass an internal `skip_read_back` request to the Python bridge for actions only.
- Skip the post-action wait and snapshot when disabled, return `ok`, and retain the last explicitly observed index cache.
- Keep explicit observations and input error propagation unchanged.
- Add bridge and service regression tests, architecture documentation, and a release note.

### Design Intent
The persistent REPL already disables action read-back and discards action results. Linux previously ignored this setting and repeatedly generated AX trees, focus/selection summaries, and screenshots. This change implements the existing contract without changing tool schemas or adding a separate screenshot-only mode. Callers must explicitly observe updated state before reusing indexes after UI changes; action acknowledgment is not proof of UI settlement or task success.

### Files Modified
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseLinux/runtime_test.py`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`

### Validation Scope
Automated tests cover the switch contract, all seven Python action branches, default read-back, explicit observations, preserved cache aliases, and bridge error responses. No live desktop benchmark is claimed.


### 2026-10-17: current-main review and Linux widget validation

- Merged main at `9bc2bd7` (including #95). Only the feature-release-notes table conflicted; retained both the Linux entry and main's release/cursor entries. The production implementation needed no further changes after review.
- Added `scripts/run-linux-read-back-smoke.sh` and `scripts/tests/linux-read-back-smoke.py`: a private D-Bus/Xvfb session, a disposable real GTK fixture and native MCP client. Updated the architecture, Linux plan and `docs/linux-action-read-back.md` with the scoped runner and its prerequisites.
- Used the already-running container engine with a temporary Debian 12 ARM64 container; no desktop VM was started. Copied only repository test inputs and compiled test artifacts into it.
- The full Linux Go test binary (Go 1.26.1 cross-compiled on the host) passed in Linux. Python bridge tests: 14 passed. Node 24 REPL/CLI/config tests: 36 passed. Linux-targeted `go vet`, formatting, ARM64/AMD64 builds, shell/Python syntax, documentation and whitespace checks passed.
- Real GTK/AT-SPI through native MCP passed set_value, repeated cached-index clicks, secondary action, Unicode insertion and Return delivery. Disabled read-back returned only `ok`; invalid widget actions still failed; explicit observation returned the new entry/counter state; the default action returned an updated snapshot. Fixture state was independently checked rather than inferred from the acknowledgment.
- Negative proof against unmodified main's Python bridge: the same regression suite failed for all seven action branches; the PR implementation passed all 14 tests.
- Xvfb must start before the private D-Bus session so the activated AT-SPI registry inherits its display and can synthesize keys. This is handled by the runner.
- Validation covers X11/GTK/AT-SPI. It does not establish Wayland/other-toolkit behavior or a whole-task speedup; no physical-desktop benchmark was run.
