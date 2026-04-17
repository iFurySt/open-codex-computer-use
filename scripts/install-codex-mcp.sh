#!/usr/bin/env bash

set -euo pipefail

codex_home="${CODEX_HOME:-${HOME}/.codex}"
config_path="${codex_home}/config.toml"
server_name="open-computer-use"
command_name="open-computer-use"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-codex-mcp.sh

Install the open-computer-use stdio MCP entry into ~/.codex/config.toml.
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

python3 - "${config_path}" "${server_name}" "${command_name}" <<'PY'
import json
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:
    print(f"python3 with tomllib is required: {exc}", file=sys.stderr)
    sys.exit(1)


def section_pattern(header: str) -> re.Pattern[str]:
    return re.compile(rf'(?ms)^\[{re.escape(header)}\]\n.*?(?=^\[|\Z)')


def remove_section(text: str, header: str) -> str:
    return section_pattern(header).sub("", text)


def upsert_section(text: str, header: str, body: str) -> str:
    section = f'[{header}]\n{body.rstrip()}\n'
    pattern = section_pattern(header)
    if pattern.search(text):
        return pattern.sub(section, text, count=1)

    if text and not text.endswith("\n"):
        text += "\n"
    if text and not text.endswith("\n\n"):
        text += "\n"
    return text + section


config_path = Path(sys.argv[1])
server_name = sys.argv[2]
command_name = sys.argv[3]
desired_args = ["mcp"]
legacy_server_name = "open-codex-computer-use"

text = config_path.read_text() if config_path.exists() else ""

try:
    parsed = tomllib.loads(text) if text.strip() else {}
except tomllib.TOMLDecodeError as exc:
    print(f"Existing Codex config is not valid TOML: {exc}", file=sys.stderr)
    sys.exit(1)

mcp_servers = parsed.get("mcp_servers")
if mcp_servers is not None and not isinstance(mcp_servers, dict):
    print('Existing Codex config has non-table "mcp_servers"; refusing to modify it.', file=sys.stderr)
    sys.exit(1)

target = (mcp_servers or {}).get(server_name)
legacy = (mcp_servers or {}).get(legacy_server_name)

target_matches = (
    isinstance(target, dict)
    and target.get("command") == command_name
    and target.get("args") == desired_args
)
legacy_matches = (
    isinstance(legacy, dict)
    and legacy.get("command") == command_name
    and legacy.get("args") == desired_args
)

if target_matches and not legacy_matches:
    print(f'Codex MCP server "{server_name}" is already installed in {config_path}.')
    sys.exit(0)

body = f'command = {json.dumps(command_name)}\nargs = {json.dumps(desired_args)}'
text = upsert_section(text, f'mcp_servers."{server_name}"', body)

if legacy_matches:
    text = remove_section(text, f'mcp_servers."{legacy_server_name}"')

text = re.sub(r"\n{3,}", "\n\n", text).rstrip() + "\n"
config_path.write_text(text)

if target_matches and legacy_matches:
    print(f'Codex MCP server "{server_name}" was already installed; removed legacy alias "{legacy_server_name}" from {config_path}.')
else:
    print(f'Installed Codex MCP server "{server_name}" into {config_path}.')
PY
