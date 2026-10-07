## [2026-10-07 08:31] | Task: Verify thirty minimal display cycles and post-exit ColorSync accumulation

### Execution Context
* Agent ID: `/root`
* Base Model: GPT-6 (exact backend identifier unavailable)
* Runtime: Codex local, macOS arm64

### User Query
> 单次没有卡顿、退出又降下来，要求用最小 demo 与以前一样运行 30 次。完成后明确反馈“有变卡的”。

### Changes Overview
- Added explicit bounded 1–30 cycle standalone controller using same signed demo, fixed warm identity, actual online/exit/removal checks and ICC content/topology guards.
- Recorded ten removed-screen checkpoints and three final passive windows: ~19% to ~99–100% combined ColorSync CPU, all 146 ICC hashes stable, thirty exits/removals confirmed. User reports stutter; manual recovery confirmation requested, no system daemon/profile/preference changes.
- Added regression tests for bounds/checkpoint sequencing/resource guards/cleanup; 17 Python tests and strict signature verification pass. Synced README, reference, quality, plan and sanitized results. Formal App unchanged.

### Design Intent
Distinguish online peak reduction from accumulated post-exit baseline; keep subjective stutter separate from CPU until actual feedback, and preserve internal-root limitations.

### Files Modified
- `experiments/DisplayPerformance/minimal_cycles.py`
- `experiments/DisplayPerformance/test_minimal_cycles.py`
- `experiments/DisplayPerformance/results-minimal-thirty-20261007.json`
- `docs/references/20261007-minimal-display-thirty-cycles.md`
