#!/usr/bin/env bash

set -euo pipefail

claude_config_path="${CLAUDE_CONFIG_PATH:-${HOME}/.claude.json}"
project_root="$(pwd -P)"
server_name="open-computer-use"
command_name="open-computer-use"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-claude-mcp.sh

Install the open-computer-use stdio MCP entry into ~/.claude.json for the current project.
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

python3 - "${claude_config_path}" "${project_root}" "${server_name}" "${command_name}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
project_root = sys.argv[2]
server_name = sys.argv[3]
command_name = sys.argv[4]
desired_entry = {
    "type": "stdio",
    "command": command_name,
    "args": ["mcp"],
}
legacy_server_name = "open-codex-computer-use"

if config_path.exists():
    try:
        raw = config_path.read_text()
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as exc:
        print(f"Existing Claude config is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(1)
else:
    data = {}

if not isinstance(data, dict):
    print("Existing Claude config root is not a JSON object; refusing to modify it.", file=sys.stderr)
    sys.exit(1)

projects = data.setdefault("projects", {})
if not isinstance(projects, dict):
    print('Existing Claude config has non-object "projects"; refusing to modify it.', file=sys.stderr)
    sys.exit(1)

project_entry = projects.setdefault(project_root, {})
if not isinstance(project_entry, dict):
    print(f'Existing Claude project entry for {project_root} is not an object; refusing to modify it.', file=sys.stderr)
    sys.exit(1)

mcp_servers = project_entry.setdefault("mcpServers", {})
if not isinstance(mcp_servers, dict):
    print(f'Existing Claude project MCP config for {project_root} is not an object; refusing to modify it.', file=sys.stderr)
    sys.exit(1)

target = mcp_servers.get(server_name)
legacy = mcp_servers.get(legacy_server_name)

target_matches = target == desired_entry
legacy_matches = legacy == desired_entry

if target_matches and not legacy_matches:
    print(f'Claude MCP server "{server_name}" is already installed for {project_root} in {config_path}.')
    sys.exit(0)

mcp_servers[server_name] = desired_entry

if legacy_matches:
    del mcp_servers[legacy_server_name]

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

if target_matches and legacy_matches:
    print(f'Claude MCP server "{server_name}" was already installed for {project_root}; removed legacy alias "{legacy_server_name}" from {config_path}.')
else:
    print(f'Installed Claude MCP server "{server_name}" for {project_root} into {config_path}.')
PY
