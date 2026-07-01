#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/check-docs.sh"
"${repo_root}/scripts/check-repo-hygiene.sh"
"${repo_root}/scripts/check-action-pinning.sh"

while IFS= read -r file; do
  bash -n "$file"
done < <(find "${repo_root}/scripts" -type f -name '*.sh' | sort)

while IFS= read -r file; do
  node --check "$file"
done < <(find "${repo_root}/scripts" -type f -name '*.mjs' | sort)

while IFS= read -r file; do
  python3 -m py_compile "$file"
done < <(find "${repo_root}/scripts" -type f -name '*.py' | sort)

(
  cd "${repo_root}"
  npm run package:skill
  ./scripts/compare-event-stream-surface.py
  ./scripts/compare-event-stream-no-active.py
  ./scripts/test-event-stream-probe-fixtures.py
  ./scripts/test-event-stream-recording-probe.py
  ./scripts/test-event-stream-local-probe.py
  ./scripts/test-event-stream-golden-readiness.py
  ./scripts/test-event-stream-official-fixture-coverage.py
  ./scripts/check-event-stream-official-fixture-coverage.py --allow-missing
  ./scripts/test-record-and-replay-baseline-contract.py
  ./scripts/test-record-and-replay-baseline-summary.py
  ./scripts/test-record-and-replay-baseline-summary-audit.py
  RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-ci-outer-summary.json RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=/tmp/ocu-rnr-ci-outer-golden-summary.json ./scripts/test-record-and-replay-baseline-audit-make-targets.py
  ./scripts/test-record-and-replay-baseline-runner-summary-json.py
  ./scripts/test-record-and-replay-official-golden-capture-preflight.py
  ./scripts/test-record-and-replay-official-capture-finalizer.py
  ./scripts/test-record-and-replay-ocu-candidate-pairing-preflight.py
  ./scripts/test-event-stream-official-fixture-set.py
  ./scripts/test-official-record-and-replay-fixture-ingest.py
  ./scripts/test-ocu-record-and-replay-candidate-ingest.py
  ./scripts/test-event-stream-skill-scaffold.py
  ./scripts/test-record-and-replay-skill-repo-scaffold.py
  node ./scripts/test-codex-record-and-replay-installer.mjs
  swift test
  ./scripts/run-event-stream-smoke-matrix.sh
)

if command -v go >/dev/null 2>&1; then
  (
    cd "${repo_root}/apps/OpenComputerUseWindows"
    go test ./...
  )
  (
    cd "${repo_root}/apps/OpenComputerUseLinux"
    go test ./...
  )
fi

echo "基础 CI 检查通过"
