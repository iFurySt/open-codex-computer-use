## [2026-09-22 17:39] | Task: Add `ocu js` and `ocu repl`

### 🤖 Execution Context
* **Agent ID**: `TRAE CLI`
* **Base Model**: `GPT-5.4`
* **Runtime**: `local macOS repository workspace`

### 📥 User Query
> Add both direct `ocu js` and persistent `ocu repl` commands, clarify whether OCU stays resident, and expose code-first capability status without hiding commands when Node or another component is unavailable.

### 🛠 Changes Overview
**Scope:** npm launcher, JavaScript REPL CLI, capability diagnostics, tests, and user/developer documentation.

**Key Actions:**
- **Direct code execution**: Added positional, stdin, and file-backed `ocu js` execution with configurable timeout and optional JSON result output.
- **Terminal REPL**: Added `ocu repl` with persistent top-level bindings, `.help`, `.editor` / `.end`, `.reset`, `.exit`, piped line mode, and deterministic Worker/native child cleanup.
- **Capability contract**: Added human-readable and JSON `ocu capabilities` output for Node, adapter, kernel, native MCP, `js`, and `repl`; help keeps the commands visible and marks current availability.
- **Compatibility**: Kept `ocu mcp` as the existing native 9-tool stdio server and left the Codex plugin's separate `js` / `js_reset` MCP surface unchanged.
- **Launcher structure**: Reduced generated npm bin files to a small bootstrap and moved command behavior into a reusable, directly tested module.
- **Runtime boundary**: Documented that the npm launcher requires Node.js 18+, reuses its current Node executable, and is separate from the macOS app agent that may stay resident for permission identity reuse.

### 🧠 Design Intent (Why)
Stable command discovery is more useful to users and agents than silently removing commands based on environment state. The CLI therefore always documents `js` and `repl`, while a separate structured preflight reports exactly which runtime component is missing. One-shot and persistent modes reuse the same proven Worker/native MCP bridge, without widening or changing the native MCP protocol.

### 📁 Files Modified
- `scripts/node-repl/open-computer-use-cli.mjs`
- `scripts/node-repl/open-computer-use-cli.test.mjs`
- `scripts/npm/build-packages.mjs`
- `scripts/ci.sh`
- `Makefile`
- `README.md`
- `docs/references/js-repl.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`

### ✅ Validation
- `node --test scripts/node-repl/*.test.mjs` — 18/18 passed.
- npm staging launcher — help, JSON capabilities, positional/stdin `js`, piped persistent `repl`, `.reset`, and real `cua.listApps()` passed against the bundled macOS runtime.
- Raw `ocu mcp` JSON-RPC `tools/list` — still exactly 9 native tools.
- `swift test` — 167 tests, 0 failures, 1 opt-in live test skipped; 9-tool/cursor smoke passed.
- Linux/Windows Go tests, Linux Python tests, shell/Node syntax, docs, action pinning, DSH installer tests, and diff checks passed.
- Release build produced macOS universal, Linux arm64/amd64, and Windows arm64/amd64 artifacts. Isolated tgz installs passed on local macOS Node 22.22.1 and Linux x64 devbox Node 22.16.0, including capability detection, multiline REPL, native bridge, exact 9-tool compatibility, and SIGTERM child cleanup.
- A PATH restricted to `/usr/bin:/bin` on the local machine reproduces the documented npm bootstrap boundary: the shebang exits 127 with `env: node: No such file or directory` before CLI code can run.
- Full `scripts/ci.sh` remains blocked only by the existing repository-hygiene gate: the `main` checkout lacks `.editorconfig`, `.markdownlint.json`, and several expected `.github` templates/workflows. All later CI substeps were run separately and passed.
