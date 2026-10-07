# Thirty standalone minimal-display cycles

- User explicitly requested the same 30-cycle pressure pattern to distinguish reduced post-exit load from accumulating post-exit load, despite no perceived stutter from one cycle.
- Use identical signed 71-line demo and fixed warm slot 28, same external topology; no OCU library/application/capture/input workload. Two passive 30-second baselines, ten groups of three, 4 seconds online and 2 seconds after removal per cycle, 30-second removed checkpoints, three final passive windows.
- Preserve ICC hashes/count and physical topology, verify each own process exit and CG removal. Abort on ownership collision, changed topology/profile or cleanup failure, never terminate unrelated runtime/system services. Existing elevated baseline is explicitly an incremental limitation, not a fresh healthy run.
- Save sanitized build/source fingerprints, metrics, cleanup and history; update progress approximately each batch; local commit. Formal App unchanged, no restart required.
- Status: implementing bounded standalone stress controller; user authorized total 30 explicitly.

## Executed

- Same signed minimal binary completed 30 cycles, all online/exit/removal verified, no ICC hash/count or physical-topology drift, no cleanup errors. Baseline/control ~19%; removed checkpoints rose through ~26/33/41/48/56/62/71/86/100/99%. Three final passive windows ~100.13/99.10/99.03% with ~15–16 requests/s.
- User explicitly reported stutter after completion. No further creation; requested manual LG disconnect for recovery confirmation. Recovery outcome pending.
- Added bounded explicit 1..30 controller, 17 offline tests pass, README and sanitized results/reference/quality updated. Root caller and hardware/other-runtime isolation unresolved.

## Completion boundary

The requested 30-cycle experiment, post-exit observations, code/tests and documentation are complete. Manual LG recovery is a requested follow-up awaiting user action, not reported as completed; no further display creation is scheduled.
