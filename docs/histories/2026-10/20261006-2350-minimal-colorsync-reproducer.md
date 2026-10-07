## [2026-10-06 23:50] | Task: Reproduce ColorSync trigger in standalone minimal demo

### Execution Context
* Agent ID: `/root`
* Base Model: GPT-6 (exact backend identifier unavailable)
* Runtime: Codex local, macOS arm64

### User Query
> 继续探索根源，优先用独立最少代码复现，定位最核心的代码。

### Changes Overview
- Added 71-line standalone Foundation/CoreGraphics private-display demo with staged descriptor/init/apply/exit protocol, fixed identity and no OCU linkage.
- Added one-process controller, CPU/profile/topology guards and stage-protocol tests. Same signed binary compares init-only vs one applied mode; latter reproduces post-exit request increment. Own removal and exit verified.
- Documented elevated baseline, existing ICC update and unresolved internal caller; no production fix claimed. Thirteen Python tests, clang compile, strict signing and no-create protocol smoke pass.

### Design Intent
Separate private display creation/activation from runtime, capture, layout and input so future diagnosis has a minimal reproducible trigger.

### Files Modified
- `experiments/DisplayPerformance/MinimalDisplay.m`
- `experiments/DisplayPerformance/minimal.py`
- `experiments/DisplayPerformance/test_minimal.py`
- `experiments/DisplayPerformance/results-minimal-20261006.json`
- `docs/references/20261006-minimal-colorsync-reproducer.md`
- `docs/exec-plans/completed/20261006-minimal-colorsync-reproducer.md`

### 2026-10-07 follow-up
User asked to actually rerun the minimal demo and verify ColorSync CPU increases. Same binary verified by SHA-256; one applied cycle, safe guard cleanup, two post-exit passive windows. Before apply ~15.83% CPU / 2.579 requests/s, after removal ~18.44–18.78% / 2.958–3.006. All 146 ICC hashes stable; exit/removal confirmed, no formal App changes. Saved sanitized metrics and appended reference; internal root remains unresolved.
