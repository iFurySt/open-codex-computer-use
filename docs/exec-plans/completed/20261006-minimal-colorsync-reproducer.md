# Minimal private-display ColorSync reproducer

- Goal: reproduce independently of OCU runtime/bridge/GUI, separate descriptor allocation, display init, mode application and process exit, and identify the smallest observed triggering sequence.
- Constraints: fixed warmed identity slot, bounded individual cycles, baseline CPU guard, own helper removal assertions, no system daemon/profile/preference manipulation or unrelated runtime termination. Existing external topology and old runtimes remain limitations.
- Plan: standalone single Objective-C source plus clang build; staged stdin protocol for passive measurement between private API calls; independent controller and sanitized report. Compare process exit without settings against one configured cycle only if needed; stop on excessive load/profile growth/topology change. Tests for protocol/bounds/cleanup. Documentation/history/local commit; no formal App rebuild unless verified production fix exists.
- Status: implementing standalone staged demo. Prior root-isolation run finished with no virtual screen and ~16% ColorSync CPU; fresh passive baseline required, incremental testing must be labeled accurately.

## Completion

- Built/signed one 71-line standalone Objective-C binary, no OCU/AppKit application/capture/input/layout dependencies or dealloc hook. Same binary staged conditions: init-only never online and ~2.14–2.20 requests/s; one apply makes screen online, CPU guard terminates own demo, after removal ~2.57 requests/s / 17.71% CPU.
- Both own processes exit 0 and removal verified, no ICC growth (146); apply restores one existing profile's content after prior primaries experiment. Existing abnormal baseline and preserved runtimes prevent clean-room internal-root claims.
- Added bounded controller/protocol tests, sanitized metrics, reference/quality/history. 13 Python tests pass, strict signature verification and no-create protocol/argument smoke passed. No production fix or formal bundle change; no further pressure tests. Minimal trigger achieved; internal defect remains explicitly unresolved.
