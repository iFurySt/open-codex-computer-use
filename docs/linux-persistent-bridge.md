# Add an opt-in session-owned Linux Python bridge

Draft: lifecycle implementation and automated subprocess tests are ready for review; live AT-SPI desktop soak/latency validation is still required.

Set `OPEN_COMPUTER_USE_LINUX_PERSISTENT_BRIDGE=1` when starting the native MCP server to reuse a Python/GI process and one temporary script for serial JSON-line requests. Default MCP mode and CLI calls remain one-shot. The bridge is private to the MCP session, is closed at turn-end/EOF, and is configured with Linux parent-death SIGKILL. Orderly shutdown removes the temporary directory; a hard-killed parent can leave that directory.

Transport errors, malformed JSON, crashes and the 30-second deadline kill/reap the worker. Failed operations are never replayed; a subsequent request may start a fresh worker. Application-level tool errors are returned unchanged without restarting a healthy bridge. Request handling stays serial; asynchronous MCP cancellation notifications are not added.

Validation: Go suite and race detector; subprocess fixtures cover reuse, timeout, crash, malformed response, application errors, restart, turn-end, EOF and cleanup. Python streaming-loop tests cover multiple requests, errors and EOF. No live desktop or end-to-end speedup claim.

Before each valid streaming request, the bridge drains pending GLib events for
at most 20 ms / 1,000 iterations so AT-SPI event processing is not omitted in
the long-lived path. Desktop cache freshness under sustained events remains a
live-soak acceptance item.

This draft builds on #100 so the no-read-back action path also uses the session runner; the first commit belongs to that PR. Its diff will shrink after #100 merges.
