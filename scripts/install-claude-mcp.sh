#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_helper="${script_dir}/install-config-helper.mjs"
claude_config_path="${CLAUDE_CONFIG_PATH:-${HOME}/.claude.json}"
project_root="$(pwd -P)"
server_name="open-computer-use"
launch_script="$(cd "${script_dir}/../plugins/open-computer-use/scripts" && pwd)/launch-open-computer-use.sh"
command_name="/bin/bash"
command_args="[\"${launch_script}\"]"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-claude-mcp.sh

Install the open-computer-use stdio MCP entry into ~/.claude.json (global and current project).
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

node "${config_helper}" claude-mcp-global "${claude_config_path}" "${server_name}" "${command_name}" "${command_args}"
node "${config_helper}" claude-mcp "${claude_config_path}" "${project_root}" "${server_name}" "${command_name}" "${command_args}"
