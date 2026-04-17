#!/usr/bin/env bash

set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundled_app_binary="${plugin_root}/OpenComputerUse.app/Contents/MacOS/OpenComputerUse"
repo_root="$(cd "${plugin_root}/../.." && pwd)"
repo_app_binary="${repo_root}/dist/OpenComputerUse.app/Contents/MacOS/OpenComputerUse"

if [[ -x "${bundled_app_binary}" ]]; then
  cd "${plugin_root}"
  exec "${bundled_app_binary}" mcp
fi

if [[ -x "${repo_app_binary}" ]]; then
  cd "${repo_root}"
  exec "${repo_app_binary}" mcp
fi

echo "open-computer-use could not find a runnable app bundle." >&2
echo "Checked:" >&2
echo "  - ${bundled_app_binary}" >&2
echo "  - ${repo_app_binary}" >&2
echo "Run ./scripts/install-codex-plugin.sh to populate the Codex plugin cache." >&2
exit 1
