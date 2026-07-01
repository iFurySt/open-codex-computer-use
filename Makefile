PROJECT ?=
SLUG ?=
AGENTS ?= claude,codex
SCENARIO ?= list-apps
RNR_SCENARIO ?= simple-action-stop
RNR_PACKET_DIR ?=
RNR_FIXTURE_ROOT ?=
RNR_OFFICIAL_PLUGIN_ROOT ?=
RNR_ALLOW_MISSING_OFFICIAL_PLUGIN ?= 0
RNR_BASELINE_SUMMARY_JSON ?= dist/record-and-replay-baseline-summary.json
RNR_OFFICIAL_GOLDEN_SUMMARY_JSON ?= dist/record-and-replay-official-golden-gate-summary.json

.PHONY: init build app test smoke event-stream-smoke event-stream-action-smoke event-stream-smoke-matrix event-stream-surface-smoke event-stream-no-active-smoke event-stream-probe event-stream-local-probe-smoke event-stream-official-probe event-stream-official-start-probe event-stream-probe-fixture-smoke event-stream-fixture-smoke event-stream-compare-smoke event-stream-golden-readiness-smoke event-stream-official-fixture-coverage-smoke event-stream-official-fixture-set-smoke event-stream-official-fixture-ingest-smoke event-stream-ocu-candidate-ingest-smoke event-stream-skill-scaffold-smoke record-and-replay-baseline-contract-smoke record-and-replay-baseline-summary-smoke record-and-replay-baseline-summary-audit-smoke record-and-replay-baseline-audit-targets-smoke record-and-replay-official-golden-capture-preflight record-and-replay-official-golden-capture-packet record-and-replay-official-golden-capture-packet-set record-and-replay-official-golden-capture-preflight-smoke record-and-replay-official-capture-finalizer-smoke record-and-replay-official-golden-fixture-gate record-and-replay-ocu-candidate-pairing-preflight record-and-replay-ocu-candidate-pairing-preflight-smoke record-and-replay-skill-repo-smoke npm-record-and-replay-skill-repo-smoke record-and-replay-baseline-smoke record-and-replay-baseline-audit record-and-replay-official-golden-gate record-and-replay-official-golden-gate-audit codex-record-and-replay-installer-smoke stress agent-smoke check-docs check-repo ci release-package npm-build npm-publish new-history new-plan

init:
	@if [ -z "$(PROJECT)" ]; then echo "用法: make init PROJECT=项目名"; exit 1; fi
	./scripts/init-project.sh "$(PROJECT)"

build:
	swift build

app:
	./scripts/build-open-computer-use-app.sh debug

test:
	swift test

smoke:
	./scripts/run-tool-smoke-tests.sh

event-stream-smoke:
	./scripts/run-event-stream-smoke-tests.sh

event-stream-action-smoke:
	OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 ./scripts/run-event-stream-smoke-tests.sh

event-stream-smoke-matrix:
	./scripts/run-event-stream-smoke-matrix.sh

event-stream-surface-smoke:
	./scripts/compare-event-stream-surface.py

event-stream-no-active-smoke:
	./scripts/compare-event-stream-no-active.py

event-stream-probe:
	@./scripts/probe-event-stream-recording.py --target local --start-stop

event-stream-local-probe-smoke:
	./scripts/test-event-stream-local-probe.py

event-stream-official-probe:
	@./scripts/probe-event-stream-recording.py --target official

event-stream-official-start-probe:
	@./scripts/probe-event-stream-recording.py --target official --start-stop --allow-start-timeout

event-stream-probe-fixture-smoke:
	./scripts/test-event-stream-probe-fixtures.py
	./scripts/test-event-stream-recording-probe.py

event-stream-fixture-smoke:
	./scripts/test-event-stream-fixture-import.py

event-stream-compare-smoke:
	./scripts/test-event-stream-recording-compare.py

event-stream-golden-readiness-smoke:
	./scripts/test-event-stream-golden-readiness.py

event-stream-official-fixture-coverage-smoke:
	./scripts/test-event-stream-official-fixture-coverage.py

event-stream-official-fixture-set-smoke:
	./scripts/test-event-stream-official-fixture-set.py

event-stream-official-fixture-ingest-smoke:
	./scripts/test-official-record-and-replay-fixture-ingest.py

event-stream-ocu-candidate-ingest-smoke:
	./scripts/test-ocu-record-and-replay-candidate-ingest.py

event-stream-skill-scaffold-smoke:
	./scripts/test-event-stream-skill-scaffold.py

record-and-replay-baseline-contract-smoke:
	./scripts/test-record-and-replay-baseline-contract.py

record-and-replay-baseline-summary-smoke:
	./scripts/test-record-and-replay-baseline-summary.py

record-and-replay-baseline-summary-audit-smoke:
	./scripts/test-record-and-replay-baseline-summary-audit.py

record-and-replay-baseline-audit-targets-smoke:
	./scripts/test-record-and-replay-baseline-audit-make-targets.py

record-and-replay-official-golden-capture-preflight:
	@./scripts/prepare-record-and-replay-official-golden-capture.py

record-and-replay-official-golden-capture-packet:
	@packet_dir="$(RNR_PACKET_DIR)"; \
	if [ -z "$${packet_dir}" ]; then packet_dir="$${TMPDIR:-/tmp}/ocu-rnr-official-$(RNR_SCENARIO)"; fi; \
	set --; \
	if [ -n "$(RNR_FIXTURE_ROOT)" ]; then set -- "$$@" --fixture-root "$(RNR_FIXTURE_ROOT)"; fi; \
	if [ -n "$(RNR_OFFICIAL_PLUGIN_ROOT)" ]; then set -- "$$@" --official-plugin-root "$(RNR_OFFICIAL_PLUGIN_ROOT)"; fi; \
	if [ "$(RNR_ALLOW_MISSING_OFFICIAL_PLUGIN)" = "1" ]; then set -- "$$@" --allow-missing-official-plugin; fi; \
	./scripts/prepare-record-and-replay-official-golden-capture.py \
		"$$@" \
		--scenario "$(RNR_SCENARIO)" \
		--capture-packet-dir "$${packet_dir}"

record-and-replay-official-golden-capture-packet-set:
	@packet_dir="$(RNR_PACKET_DIR)"; \
	if [ -z "$${packet_dir}" ]; then packet_dir="$${TMPDIR:-/tmp}/ocu-rnr-official-golden-packets"; fi; \
	set --; \
	if [ -n "$(RNR_FIXTURE_ROOT)" ]; then set -- "$$@" --fixture-root "$(RNR_FIXTURE_ROOT)"; fi; \
	if [ -n "$(RNR_OFFICIAL_PLUGIN_ROOT)" ]; then set -- "$$@" --official-plugin-root "$(RNR_OFFICIAL_PLUGIN_ROOT)"; fi; \
	if [ "$(RNR_ALLOW_MISSING_OFFICIAL_PLUGIN)" = "1" ]; then set -- "$$@" --allow-missing-official-plugin; fi; \
	./scripts/prepare-record-and-replay-official-golden-capture.py \
		"$$@" \
		--capture-packet-dir "$${packet_dir}" \
		--capture-packet-recommended-scenarios

record-and-replay-official-golden-capture-preflight-smoke:
	./scripts/test-record-and-replay-official-golden-capture-preflight.py

record-and-replay-official-capture-finalizer-smoke:
	./scripts/test-record-and-replay-official-capture-finalizer.py

record-and-replay-official-golden-fixture-gate:
	@./scripts/check-event-stream-official-fixture-coverage.py --require-readiness

record-and-replay-ocu-candidate-pairing-preflight:
	@./scripts/prepare-record-and-replay-ocu-candidate-pairing.py

record-and-replay-ocu-candidate-pairing-preflight-smoke:
	./scripts/test-record-and-replay-ocu-candidate-pairing-preflight.py

record-and-replay-skill-repo-smoke:
	./scripts/test-record-and-replay-skill-repo-scaffold.py

npm-record-and-replay-skill-repo-smoke:
	node ./scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs

record-and-replay-baseline-smoke:
	./scripts/run-record-and-replay-baseline-smoke.sh

record-and-replay-baseline-audit:
	@mkdir -p "$$(dirname "$(RNR_BASELINE_SUMMARY_JSON)")"
	./scripts/run-record-and-replay-baseline-smoke.sh --summary-json "$(RNR_BASELINE_SUMMARY_JSON)"

record-and-replay-official-golden-gate:
	./scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden

record-and-replay-official-golden-gate-audit:
	@mkdir -p "$$(dirname "$(RNR_OFFICIAL_GOLDEN_SUMMARY_JSON)")"
	./scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden --summary-json "$(RNR_OFFICIAL_GOLDEN_SUMMARY_JSON)"

codex-record-and-replay-installer-smoke:
	node ./scripts/test-codex-record-and-replay-installer.mjs

stress:
	./scripts/run-tool-stress-tests.sh

agent-smoke:
	node ./scripts/run-agent-smoke-tests.mjs --agents=$(AGENTS) --scenario=$(SCENARIO)

check-docs:
	./scripts/check-docs.sh

check-repo:
	./scripts/check-docs.sh
	./scripts/check-repo-hygiene.sh

ci:
	./scripts/ci.sh

release-package:
	./scripts/release-package.sh

npm-build:
	node ./scripts/npm/build-packages.mjs

npm-publish:
	node ./scripts/npm/publish-packages.mjs

new-history:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-history SLUG=变更名"; exit 1; fi
	./scripts/new-history.sh "$(SLUG)"

new-plan:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-plan SLUG=计划名"; exit 1; fi
	./scripts/new-exec-plan.sh "$(SLUG)"
