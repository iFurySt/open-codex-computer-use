# Locked Use unlock latency

## Goal

Fix the authorization plug-in load failure seen during manual unlock, check related idle / IPC costs, and submit a reviewed PR.

## Constraints

Preserve native password fallback and peer / permit validation. Do not disable SIP, alter Apple signatures, or grant private entitlements. Keep diagnostics bounded and avoid automatic lock tests until a short recovery path is ready.

## Progress

- [x] Read the referenced diagnosis and reproduce the installed metadata / host boundary read-only.
- [x] Confirm delayed system assessment, subsequent successful loading, real marker export and privileged host session binding.
- [x] Fix relevant polling / admission costs with regression coverage.
- [ ] Validate build and authorization behavior; document limits and submit PR.
