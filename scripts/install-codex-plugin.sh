#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
config_path="${codex_home}/config.toml"
marketplace_name="open-computer-use-local"
plugin_name="open-computer-use"
plugin_source_root="${repo_root}/plugins/${plugin_name}"
plugin_manifest="${plugin_source_root}/.codex-plugin/plugin.json"
configuration="debug"
rebuild="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)
      rebuild="true"
      shift
      ;;
    --configuration)
      configuration="${2:-}"
      if [[ -z "${configuration}" ]]; then
        echo "--configuration requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--rebuild] [--configuration debug|release]" >&2
      exit 1
      ;;
  esac
done

app_binary="${repo_root}/dist/OpenComputerUse.app/Contents/MacOS/OpenComputerUse"

if [[ "${rebuild}" == "true" || ! -x "${app_binary}" ]]; then
  "${repo_root}/scripts/build-open-computer-use-app.sh" "${configuration}"
fi

if [[ ! -f "${repo_root}/.agents/plugins/marketplace.json" ]]; then
  echo "Missing ${repo_root}/.agents/plugins/marketplace.json" >&2
  exit 1
fi

if [[ ! -f "${plugin_manifest}" ]]; then
  echo "Missing ${plugin_manifest}" >&2
  exit 1
fi

if [[ ! -x "${app_binary}" ]]; then
  echo "Missing runnable app binary at ${app_binary}" >&2
  exit 1
fi

plugin_version="$(
  python3 - "${plugin_manifest}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    manifest = json.load(fh)

print(manifest["version"])
PY
)"

if [[ -z "${plugin_version}" ]]; then
  echo "Failed to read plugin version from ${plugin_manifest}" >&2
  exit 1
fi

plugin_cache_root="${codex_home}/plugins/cache/${marketplace_name}/${plugin_name}"
plugin_install_root="${plugin_cache_root}/${plugin_version}"

mkdir -p "${codex_home}" "${plugin_cache_root}"
rm -rf "${plugin_install_root}"
mkdir -p "${plugin_install_root}"

rsync -a "${plugin_source_root}/" "${plugin_install_root}/"
rsync -a "${repo_root}/dist/OpenComputerUse.app" "${plugin_install_root}/"

python3 - "${config_path}" "${repo_root}" "${marketplace_name}" "${plugin_name}" <<'PY'
import json
import re
import sys
from pathlib import Path


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
repo_root = Path(sys.argv[2]).resolve()
marketplace_name = sys.argv[3]
plugin_name = sys.argv[4]

text = config_path.read_text() if config_path.exists() else ""

for header in (
    'mcp_servers."open-codex-computer-use"',
    'mcp_servers."open-computer-use"',
):
    text = remove_section(text, header)

text = upsert_section(
    text,
    f"marketplaces.{marketplace_name}",
    f'source_type = "local"\nsource = {json.dumps(str(repo_root))}',
)
text = upsert_section(
    text,
    f'plugins."{plugin_name}@{marketplace_name}"',
    "enabled = true",
)

text = re.sub(r"\n{3,}", "\n\n", text).rstrip() + "\n"
config_path.write_text(text)
PY

echo "Installed ${plugin_name}@${marketplace_name}"
echo "Marketplace source: ${repo_root}"
echo "Plugin cache: ${plugin_install_root}"
echo "Updated Codex config: ${config_path}"
echo "Restart Codex to load the plugin marketplace."
