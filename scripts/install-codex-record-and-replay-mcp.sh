#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_helper="${script_dir}/install-config-helper.mjs"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
config_path="${codex_home}/config.toml"
server_name="record_and_replay"
command_name="open-computer-use"
command_args='["event-stream","mcp"]'

usage() {
  cat <<'EOF'
Usage: ./scripts/install-codex-record-and-replay-mcp.sh

Install the Open Computer Use Record & Replay stdio MCP entry into ~/.codex/config.toml.
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
