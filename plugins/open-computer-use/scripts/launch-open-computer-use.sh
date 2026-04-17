#!/usr/bin/env bash

set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${plugin_root}/../.." && pwd)"
candidate_binaries=(
  "${plugin_root}/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
  "${plugin_root}/OpenComputerUse.app/Contents/MacOS/OpenComputerUse"
  "${repo_root}/dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
  "${repo_root}/dist/OpenComputerUse.app/Contents/MacOS/OpenComputerUse"
)

for app_binary in "${candidate_binaries[@]}"; do
  if [[ -x "${app_binary}" ]]; then
    if [[ "${app_binary}" == "${plugin_root}"/* ]]; then
      cd "${plugin_root}"
    else
      cd "${repo_root}"
    fi
    exec "${app_binary}" mcp
  fi
done

echo "open-computer-use could not find a runnable app bundle." >&2
echo "Checked:" >&2
for app_binary in "${candidate_binaries[@]}"; do
  echo "  - ${app_binary}" >&2
done
echo "Run ./scripts/install-codex-plugin.sh to populate the Codex plugin cache." >&2
exit 1
