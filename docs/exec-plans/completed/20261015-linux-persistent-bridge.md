# Opt-in Linux MCP Python bridge

## Goal and scope
Reuse Python/GI initialization within one native MCP session when explicitly enabled. Keep the existing one-shot CLI and default MCP execution unchanged. No global daemon or cross-session sharing.

## Decisions and risks
- Serialize JSON-line requests. Never replay a failed/timed-out operation: the GUI may already have changed.
- Use a 30-second request deadline. Kill/reap the worker before transport recovery; a later request may start a fresh worker.
- Close at MCP EOF and turn-end, clear turn-local index cache, and set Linux parent-death SIGKILL for native-process termination.
- Remove the temporary bridge script on orderly shutdown. A hard-killed parent may leave its temporary directory, though its child is killed.
- The optional path needs real AT-SPI desktop soak testing before becoming a default. Existing MCP request processing remains serial; this does not add asynchronous MCP cancellation notifications.
- When combined with the action read-back fix, route its acknowledgment branch through the same service runner.

## Verification
- [x] Real subprocess fixtures: worker reuse, application errors, malformed JSON, crash, deadline, next-request recovery, close and EOF/turn-boundary behavior.
- [x] Go tests with the race detector.
- [x] Python JSON-line loop: multiple requests, malformed input, application error, EOF.
- [x] Keep persistent mode opt-in; document rollback by removing its environment variable.
- [ ] Live desktop soak/latency validation; tracked as a draft-PR acceptance item, not claimed complete.

## Delivery state
Implementation and automated validation are complete. Submit as a draft for lifecycle review and live desktop validation; no production-readiness or latency claim.
