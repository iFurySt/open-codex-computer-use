#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
config_helper="${script_dir}/install-config-helper.mjs"
skill_source="${repo_root}/skills/open-computer-use"

dsh_home="${DSH_HOME:-${HOME}/.dsh}"
profile_name="web"
command_override=""
with_hook=1
with_skill=1
force_skill=0

usage() {
  cat <<'EOF'
Usage: ./scripts/install-dsh-mcp.sh [options]

Install the open-computer-use stdio MCP server into a DeepSeek Harness (DSH)
profile, and register the turn-boundary hook that keeps the software cursor from
sticking on screen.

This is a compatibility integration through DSH's generic MCP client. It does
not register a first-class DSH computer-use provider.

The managed block in the profile patch is delimited by markers and replaced in
place, so re-running updates it and leaves the rest of the file untouched.

Options:
  --profile <name>   DSH profile to patch (default: web)
  --dsh-home <dir>   Harness home (default: $DSH_HOME or ~/.dsh)
  --command <path>   Executable DSH spawns for the MCP server (default: auto-detect)
  --no-hook          Do not write the turn-boundary hook config or its patch row
  --no-skill         Do not copy the skill into <dsh-home>/skills
  --force-skill      Replace an existing skill directory that differs from this
                     checkout (the previous copy is kept as a timestamped backup)
  -h, --help         Show this help.

Environment:
  DSH_HOME                     Harness home; same meaning as --dsh-home
  OPEN_COMPUTER_USE_COMMAND    Same meaning as --command

Why the hook is part of this installer:
  Open Computer Use hides its software cursor only at a turn boundary, signalled
  by the MCP notifications/turn-ended notification. dsh-mcp-client never sends
  that notification, so without the hook the cursor stays on screen after the
  first action of any session or subagent. The hook maps DSH's Stop point onto
  the Open Computer Use CLI. Use --no-hook only if you do not want the cursor.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--profile requires a value" >&2
        exit 1
      fi
      profile_name="$2"
      shift 2
      ;;
    --dsh-home)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--dsh-home requires a value" >&2
        exit 1
      fi
      dsh_home="$2"
      shift 2
      ;;
    --command)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--command requires a value" >&2
        exit 1
      fi
      command_override="$2"
      shift 2
      ;;
    --no-hook)
      with_hook=0
      shift
      ;;
    --no-skill)
      with_skill=0
      shift
      ;;
    --force-skill)
      force_skill=1
      shift
      ;;
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

if ! command -v node >/dev/null 2>&1; then
  echo "node is required to update the DSH profile patch" >&2
  exit 1
fi

# Keep a stable absolute path in the profile. DSH can resolve PATH commands, but
# GUI and background launches do not necessarily inherit the installer's PATH.
resolve_command() {
  local -a candidates=()
  local explicit_command=""
  local explicit_source=""

  if [[ -n "${command_override}" ]]; then
    explicit_command="${command_override}"
    explicit_source="--command"
  elif [[ -n "${OPEN_COMPUTER_USE_COMMAND:-}" ]]; then
    explicit_command="${OPEN_COMPUTER_USE_COMMAND}"
    explicit_source="OPEN_COMPUTER_USE_COMMAND"
  fi

  if [[ -n "${explicit_command}" ]]; then
    if [[ "${explicit_command}" != /* ]]; then
      echo "${explicit_source} must be an absolute executable path: ${explicit_command}" >&2
      return 2
    fi
    if [[ ! -f "${explicit_command}" || ! -x "${explicit_command}" ]]; then
      echo "${explicit_source} is not an executable file: ${explicit_command}" >&2
      return 2
    fi
    printf '%s\n' "${explicit_command}"
    return 0
  fi

  candidates+=(
    "${HOME}/Applications/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
    "${HOME}/Applications/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
    "/Applications/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
    "/Applications/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
  )

  local npm_root=""
  if command -v npm >/dev/null 2>&1; then
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -n "${npm_root}" ]]; then
      candidates+=(
        "${npm_root}/open-computer-use/dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
        "${npm_root}/open-computer-use/dist/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
      )
    fi
  fi

  local shim=""
  shim="$(command -v open-computer-use 2>/dev/null || true)"
  if [[ -n "${shim}" ]]; then
    candidates+=("${shim}")
  fi

  local candidate=""
  for candidate in "${candidates[@]}"; do
    if [[ "${candidate}" == /* && -f "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

command_path=""
set +e
command_path="$(resolve_command)"
resolve_status=$?
set -e
if [[ "${resolve_status}" -ne 0 ]]; then
  if [[ "${resolve_status}" -eq 2 ]]; then
    exit 1
  fi
  cat >&2 <<'EOF'
Could not find an Open Computer Use executable to register.

Pass one explicitly, or make one available first:
  --command "/path/to/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
  npm install -g open-computer-use
  make app   # from a source checkout, then install the built bundle

A DSH profile spawns the executable directly, so the path must exist and be
executable; a bare command name resolved through PATH is not enough unless it is
an absolute path.
EOF
  exit 1
fi

# Fail before changing profile files if the executable is not an OCU MCP server.
node "${config_helper}" probe-stdio-mcp "${command_path}" mcp

profile_dir="${dsh_home}/profiles/${profile_name}"
patch_path="${profile_dir}/cordis.patch.yml"
hooks_path="${dsh_home}/ocu-hooks.json"

mkdir -p "${profile_dir}"

node "${config_helper}" dsh-mcp "${patch_path}" "${hooks_path}" "${command_path}" "${with_hook}"

if [[ "${with_hook}" -eq 0 ]]; then
  echo "Turn-boundary hook skipped (--no-hook); the software cursor can stay on screen between turns." >&2
fi

skill_target="${dsh_home}/skills/open-computer-use"
skill_summary="not installed (--no-skill)"

if [[ "${with_skill}" -eq 1 ]]; then
  if [[ ! -d "${skill_source}" ]]; then
    echo "Skill source not found at ${skill_source}; skipping the skill copy." >&2
    skill_summary="not installed (source missing)"
  elif [[ ! -e "${skill_target}" ]]; then
    node "${config_helper}" copy-into-dir "${dsh_home}/skills" "${skill_source}"
    skill_summary="installed at ${skill_target}"
  elif diff -rq "${skill_source}" "${skill_target}" >/dev/null 2>&1; then
    echo "Skill already current at ${skill_target}"
    skill_summary="already current at ${skill_target}"
  elif [[ "${force_skill}" -eq 1 ]]; then
    skill_backup="${skill_target}.bak-$(date +%Y%m%d-%H%M%S)"
    mv "${skill_target}" "${skill_backup}"
    echo "Existing skill moved to ${skill_backup}" >&2
    node "${config_helper}" copy-into-dir "${dsh_home}/skills" "${skill_source}"
    skill_summary="replaced at ${skill_target} (backup: ${skill_backup})"
  else
    cat >&2 <<EOF
Skill at ${skill_target} differs from this checkout; leaving it untouched so a
local copy is never overwritten silently. Re-run with --force-skill to replace it
(a timestamped backup is kept).
EOF
    skill_summary="left existing copy untouched at ${skill_target}"
  fi
fi

cursor_summary="not installed (--no-hook)"
if [[ "${with_hook}" -eq 1 ]]; then
  cursor_summary="hidden automatically at each turn boundary via ${hooks_path}"
fi

cat <<EOF

Installed into DSH profile "${profile_name}".

  tools      mcp__ocu__* (discovered from the installed Open Computer Use server)
  cursor     ${cursor_summary}
  skill      ${skill_summary}

This installs Open Computer Use through DSH's generic MCP compatibility path; it
does not reserve DSH's first-class computer-use provider slot. DSH reloads the
web profile when the patch changes. Other profiles may require a restart. On
macOS, grant Accessibility and Screen Recording to the app bundle once; verify
with:

  "${command_path}" doctor
EOF
