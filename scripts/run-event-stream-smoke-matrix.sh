#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

run_step() {
  local name="$1"
  shift
  echo "==> ${name}" >&2
  "$@"
}

run_step "event-stream default MCP lifecycle" ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream no-active status/stop" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_NO_ACTIVE=1 ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream maximum-duration timeout" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TIMEOUT=1 ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream wait timeout" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_WAIT_TIMEOUT=1 ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream approval denied" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL=deny ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream approval cancelled" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL=cancel ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream MCP elicitation approval" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_MCP_ELICITATION=1 ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream app-agent wait/notify" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APP_AGENT_WAIT=1 ./scripts/run-event-stream-smoke-tests.sh
run_step "event-stream fixture import" ./scripts/test-event-stream-fixture-import.py
run_step "event-stream recording compare" ./scripts/test-event-stream-recording-compare.py

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_SCREENSHOTS:-0}" == "1" ]]; then
  run_step "event-stream screenshot context" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_SCREENSHOTS=1 ./scripts/run-event-stream-smoke-tests.sh
fi

if [[ "${OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_OFFICIAL:-0}" == "1" ]]; then
  run_step "event-stream official surface compare" env OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL=1 ./scripts/run-event-stream-smoke-tests.sh
fi

echo '{"ok":true,"matrix":"event-stream"}'
