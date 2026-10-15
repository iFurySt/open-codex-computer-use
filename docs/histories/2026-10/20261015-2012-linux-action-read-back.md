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
