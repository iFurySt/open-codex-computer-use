## [2026-09-06 10:41] | Task: Reconcile image capture controls with main

### User Query
> Resolve the image capture environment controls change against the latest main branch without creating a merge commit.

### Changes Overview
- Materialized the merge-tree integration of the feature branch and latest main.
- Resolved the macOS app-agent conflict by retaining main's response binding while clearing unset image capture keys for both MCP and CLI requests.
- Preserved serialized environment overrides and restoration of prior process values.

### Design Intent
Each proxied request must observe the host's current image capture settings, including defaults when a host variable is unset, without leaking temporary process environment changes across concurrent requests.

### Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `docs/histories/2026-09/20260906-1041-reconcile-image-capture-controls.md`
