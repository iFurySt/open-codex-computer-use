## [2026-10-11 02:36] | Task: Add an optional web research example

### User request

Add free Parallel Search MCP access through a useful, optional Open Computer Use example.

### Changes

- Added a separately installed example using the official MCP JavaScript SDK,
  anonymous Streamable HTTP discovery, `web_search` and `web_fetch`.
- Run the example through the existing `ocu js --file` entry point. It prints
  research output without performing desktop actions or changing native tools.
- Added request-header, shared-session, output, error and cleanup checks.
- Updated README links, the third-party data boundary and feature release notes.

### Design intent

Research setup instructions before a desktop task while keeping all network
dependencies opt-in. Calls use an explicit project User-Agent, propagate errors,
time out, and close their connection. No credentials or desktop data are read.

### Affected files

- `examples/parallel-search/`
- `README.md` and `README.zh-CN.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
