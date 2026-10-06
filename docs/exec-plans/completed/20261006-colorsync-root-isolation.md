# ColorSync root isolation and evidence-driven fix

- Goal: identify a modifiable cause of persistent display/color requests after hotplug; validate any fix rather than label reuse a root fix.
- Sequence: inventory runtime owners/active work and passive abnormal state; safely retire only verified idle and unused runtimes; sample available request/caller evidence; fresh minimal helper variants to separate descriptor/settings from explicit display configuration and teardown. Each test starts from measured healthy baseline; physical disconnect/reconnect is user-controlled.
- Bounds: no random display identities, ICC deletion, daemon restart, force quit, activity disruption or global input. Small batches with own display/helper removal assertions. No further 30-cycle pressure test until a promising fix exists.
- Evidence: exact CPU deltas/XPC rate, before/after topology/ICC hashes, source/build variants, runtime inventory, diagnostic limits. Keep raw identifiers/logs local; commit sanitized findings/code/history. Same-build LG/built-in controls are prior evidence, not an identified internal caller.
- Status: inspecting many background agents; active-session/display state alone does not prove absence of client work. Production code unchanged; no new displays created.

## Completion

- LG unplug/reconnect returned to ~1.7% CPU / .197 requests/s. User authorized autonomous small tests and explicitly allowed deferring unresolved internal root cause.
- Prior 90 ready results exclude explicit CG configuration (never applied). Current helper dealloc instrumentation completed; drain variant 3 cycles still increased CPU to 10.28% / 1.381 requests/s. Current one-cycle control increased to 13.19% / 1.781. Primaries candidate stopped after one on existing ICC hash change (146 files unchanged); final passive window 16.31% / 2.176. Own removal/exit confirmed for all five.
- Root services sampling requires unavailable privileges. Old other-worktree runtimes cannot prove idle via old agentInfo, so preserved; short user-level samples did not identify caller. Hardware direct-connection isolation unavailable while user away. No further pressure, no production candidate merged, unresolved compatibility explicitly deferred under user instruction.
- Added bounded external variant builder/lifecycle runner, sanitized results, reference/quality/history. Three variants compile and strictly verify signatures; 10 Python tests pass. Fixed serial/reuse/cleanup optimizations reviewed and distinguished from unresolved internal cause. No formal bundle changed, no restart of unrelated runtime.
