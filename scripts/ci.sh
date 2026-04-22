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

if command -v go >/dev/null 2>&1; then
  (
    cd "${repo_root}/apps/OpenComputerUseWindows"
    go test ./...
  )
fi

echo "基础 CI 检查通过"
