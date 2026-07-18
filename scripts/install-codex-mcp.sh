#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_helper="${script_dir}/install-config-helper.mjs"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
config_path="${codex_home}/config.toml"
server_name="open-computer-use"
launch_script="$(cd "${script_dir}/../plugins/open-computer-use/scripts" && pwd)/launch-open-computer-use.sh"
command_name="/bin/bash"
command_args="[\"${launch_script}\"]"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-codex-mcp.sh

Install the open-computer-use stdio MCP entry into ~/.codex/config.toml.
Uses the local launch script instead of the npm binary.
The script is idempotent: if the same MCP server entry already exists, it leaves the file unchanged.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "${codex_home}"

node "${config_helper}" codex-mcp "${config_path}" "${server_name}" "${command_name}" "${command_args}"
