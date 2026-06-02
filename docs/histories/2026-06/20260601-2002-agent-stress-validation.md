## [2026-06-01 20:02] | Task: Agent stress validation

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex desktop`

### User Query
> Add validation that proves the open computer-use MCP can be installed, stress tested, and used from Claude, Hermes, and Codex CLI.

### Changes Overview
**Scope:** repository validation scripts and docs

**Key Actions:**
- **Added deterministic stress runner**: `scripts/run-tool-stress-tests.sh` repeats the fixture-backed smoke suite and runs the visual cursor idle smoke.
- **Added optional agent smoke runner**: `scripts/run-agent-smoke-tests.mjs` can ask Claude Code, Codex CLI, and Hermes to call the `open-computer-use` MCP `list_apps` tool. The default agent set is Claude/Codex; Hermes stays explicit so provider/model routing can be supplied when needed.
- **Added fixture agent scenario**: `--scenario=fixture` launches `OpenComputerUseFixture`, asks the selected agent to call `get_app_state`, `set_value`, and `click`, then independently verifies the fixture text field and counter state.
- **Added full fixture agent scenario**: `--scenario=fixture-full` asks agents to use `get_app_state`, `set_value`, `click`, `type_text`, `press_key`, `perform_secondary_action`, `scroll`, and `drag`, then verifies exact final fixture state.
- **Kept Hermes model and turn routing configurable**: the smoke runner accepts `--hermes-provider`, `--hermes-model`, and `--hermes-max-turns` so local installations with stale default model aliases or longer tool-call plans can still validate MCP wiring.
- **Added make targets and docs**: `make stress`, `make agent-smoke`, configurable `AGENTS`/`SCENARIO`, and README examples document the validation path.

### Design Intent (Why)
The project already had a single smoke pass, but agent integrations and repeated fixture loops were manual. These scripts make the validation path reproducible without requiring live agents to perform hundreds of GUI mutations.

### Files Modified
- `scripts/run-tool-stress-tests.sh`
- `scripts/run-agent-smoke-tests.mjs`
- `Makefile`
- `README.md`

### Validation
- `OPEN_COMPUTER_USE_STRESS_LOOPS=2 OPEN_COMPUTER_USE_STRESS_CONFIGURATION=release ./scripts/run-tool-stress-tests.sh`
- `node ./scripts/run-agent-smoke-tests.mjs --agents=claude --command=open-computer-use --json`
- `node ./scripts/run-agent-smoke-tests.mjs --agents=codex --command=open-computer-use --json`
- `node ./scripts/run-agent-smoke-tests.mjs --agents=hermes --command=open-computer-use --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --json`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=codex --command=open-computer-use --json`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=claude --command=open-computer-use --json --claude-budget-usd=3.00`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture --agents=hermes --command=open-computer-use --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --json`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=codex --command=open-computer-use --json --timeout-ms=180000`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=claude --command=open-computer-use --json --timeout-ms=180000 --claude-budget-usd=3.00`
- `node ./scripts/run-agent-smoke-tests.mjs --scenario=fixture-full --agents=hermes --command=open-computer-use --hermes-provider=anthropic --hermes-model=claude-opus-4-20250514 --json --timeout-ms=180000`
- `swift test`
- `make check-docs`
- `OPEN_COMPUTER_USE_STRESS_LOOPS=20 OPEN_COMPUTER_USE_STRESS_CONFIGURATION=release ./scripts/run-tool-stress-tests.sh`

The latest 20-loop stress run completed 200 fixture operations plus cursor idle smoke in 76 seconds. Claude, Codex, and Hermes validated the read-only `list_apps` scenario. Claude, Codex, and Hermes also validated the fixture and full fixture scenarios with independent final-state checks. Hermes required explicit provider/model routing because this local Hermes default model alias returned HTTP 404 before tool use; the full fixture scenario also needed a 12-turn Hermes budget to complete all requested tool calls.
