## [2026-10-06 23:30] | Task: Bound ColorSync root isolation and preserve unresolved evidence

### Execution Context
* Agent ID: `/root`
* Base Model: GPT-6 (exact backend identifier unavailable)
* Runtime: Codex local, macOS arm64

### User Query
> 定位外屏条件下反复创建/销毁后的 ColorSync 累积；可自主测试，无法解决时整理最早问题、serial 等优化并保留未解决边界。

### Changes Overview
- Added external-source lifecycle variants and bounded 1–3 cycle runner with high-baseline, ICC content and topology guards; own-resource cleanup and diagnostic parsing.
- Recorded five verified cycles: dealloc completed, one-second drain did not prevent accumulation, explicit primaries aborted on one existing ICC hash update. No production fix claimed or merged.
- Reviewed fixed identity pool, retain/reuse and actual-removal safeguards; documented unresolved system caller, hardware path and old-runtime isolation boundaries.
- Updated experiment guidance, reference, quality and completed execution plan; all ten Python tests and three signed experimental builds passed. Formal App unchanged; no unrelated runtime restarted.

### Design Intent
Avoid presenting mitigation as root fix or increasing desktop pressure without a promising candidate. Preserve reproducible, sanitized evidence and stop guards.

### Files Modified
- `experiments/DisplayPerformance/build_isolation.py`
- `experiments/DisplayPerformance/lifecycle.py`
- `experiments/DisplayPerformance/test_isolation.py`
- `experiments/DisplayPerformance/results-isolation-20261006.json`
- `docs/references/20261006-colorsync-root-isolation.md`
- `docs/exec-plans/completed/20261006-colorsync-root-isolation.md`
