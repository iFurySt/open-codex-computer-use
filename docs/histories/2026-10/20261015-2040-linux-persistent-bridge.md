# Add an opt-in session-owned Linux Python bridge

Agent: Codex; runtime: Linux.

User request: submit scoped improvements for the remaining Linux performance paths.

Draft: lifecycle implementation and automated subprocess tests are ready for review; live AT-SPI desktop soak/latency validation is still required.

Set `OPEN_COMPUTER_USE_LINUX_PERSISTENT_BRIDGE=1` when starting the native MCP server to reuse a Python/GI process and one temporary script for serial JSON-line requests. Default MCP mode and CLI calls remain one-shot. The bridge is private to the MCP session, is closed at turn-end/EOF, and is configured with Linux parent-death SIGKILL. Orderly shutdown removes the temporary directory; a hard-killed parent can leave that directory.

Transport errors, malformed JSON, crashes and the 30-second deadline kill/reap the worker. Failed operations are never replayed; a subsequent request may start a fresh worker. Application-level tool errors are returned unchanged without restarting a healthy bridge. Request handling stays serial; asynchronous MCP cancellation notifications are not added.

Validation: Go suite and race detector; subprocess fixtures cover reuse, timeout, crash, malformed response, application errors, restart, turn-end, EOF and cleanup. Python streaming-loop tests cover multiple requests, errors and EOF. No live desktop or end-to-end speedup claim.

This draft builds on #100 so the no-read-back action path also uses the session runner; the first commit belongs to that PR. Its diff will shrink after #100 merges.

Changed areas: Linux native/bridge code and tests, architecture, release and feature documentation.

Follow-up review: drain pending GLib events before each valid streaming request,
bounded to 20 ms / 1,000 iterations. Add a bounded-drain regression; live AT-SPI
cache freshness remains an explicit draft acceptance item.
