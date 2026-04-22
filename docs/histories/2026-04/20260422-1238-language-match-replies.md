## [2026-04-22 12:38] | Task: Match reply language to user query

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> Add a repo rule so replies use the same language as the user query.

### Changes Overview
**Scope:** Repo instructions, collaboration guide

**Key Actions:**
- **[Agent routing rule]**: Added a concise rule to `AGENTS.md` requiring replies to default to the same language as the user query.
- **[Repo-level sync]**: Mirrored the same expectation in `docs/REPO_COLLAB_GUIDE.md` so the behavior is recorded in the formal docs set.
- **[History record]**: Logged the change under `docs/histories/`.

### Design Intent (Why)
Language switching without an explicit user request is a collaboration bug. The repo should state that reply language follows the user's query language so the expectation is stable across turns and agents.

### Files Modified
- `AGENTS.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/histories/2026-04/20260422-1238-language-match-replies.md`
