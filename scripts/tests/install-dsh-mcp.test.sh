#!/usr/bin/env bash
#
# Behavioural test for scripts/install-dsh-mcp.sh: it must register a runnable
# MCP command, add the turn-boundary hook, leave the user's own patch rows alone,
# stay idempotent, and honour --no-hook / --no-skill.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="${repo_root}/scripts/install-dsh-mcp.sh"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

fake_command="${work_dir}/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
mkdir -p "$(dirname "${fake_command}")"
printf '#!/bin/sh\nexit 0\n' > "${fake_command}"
chmod +x "${fake_command}"

dsh_home="${work_dir}/dsh"
profile_dir="${dsh_home}/profiles/web"
mkdir -p "${profile_dir}"
printf -- "- id: web-runtime\n  config:\n    trustedHosts:\n      - 1.2.3.4\n" > "${profile_dir}/cordis.patch.yml"

"${installer}" --dsh-home "${dsh_home}" --command "${fake_command}" >/dev/null

patch="${profile_dir}/cordis.patch.yml"
hooks="${dsh_home}/ocu-hooks.json"

grep -q "id: mcp-open-computer-use" "${patch}" || fail "patch is missing the MCP row"
grep -q "id: ocu-turn-ended-hook" "${patch}" || fail "patch is missing the turn-boundary hook row"
grep -q "id: web-runtime" "${patch}" || fail "the installer dropped the user's existing rows"
grep -q "trustedHosts" "${patch}" || fail "the installer dropped the user's existing config"
pass "patch keeps the user's rows and adds both managed rows"

grep -q "${fake_command}" "${patch}" || fail "patch does not reference the installed command"
grep -q "${fake_command}" "${hooks}" || fail "hook config does not reference the installed command"
node -e 'const fs = require("node:fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const command = data.hooks.Stop[0].hooks[0].command;
if (!command.includes("turn-ended")) process.exit(1);
if (!command.trimStart().startsWith(String.fromCharCode(34))) process.exit(1);' "${hooks}" || fail "hook config is not the expected quoted Stop command"
pass "hook config runs turn-ended with a quoted command path"

[[ -f "${dsh_home}/skills/open-computer-use/SKILL.md" ]] || fail "skill was not copied into the DSH skill root"
pass "skill is installed into the DSH skill root"

before="$(cksum < "${patch}")"
"${installer}" --dsh-home "${dsh_home}" --command "${fake_command}" >/dev/null
[[ "$(cksum < "${patch}")" == "${before}" ]] || fail "re-running changed the patch"
[[ "$(grep -c 'managed by install-dsh-mcp.sh' "${patch}")" == "1" ]] || fail "re-running duplicated the managed block"
pass "re-running is idempotent"

no_hook_home="${work_dir}/dsh-no-hook"
"${installer}" --dsh-home "${no_hook_home}" --command "${fake_command}" --no-hook --no-skill >/dev/null
if grep -q "id: ocu-turn-ended-hook" "${no_hook_home}/profiles/web/cordis.patch.yml"; then
  fail "--no-hook still wrote the hook row"
fi
if [[ -f "${no_hook_home}/ocu-hooks.json" ]]; then
  fail "--no-hook still wrote the hook config"
fi
if [[ -d "${no_hook_home}/skills" ]]; then
  fail "--no-skill still copied the skill"
fi
pass "--no-hook and --no-skill are honoured"

conflict_home="${work_dir}/dsh-conflict"
conflict_profile="${conflict_home}/profiles/web"
mkdir -p "${conflict_profile}"
printf -- "- insert:\n    - id: mcp-open-computer-use\n      name: '@deepseek-ai/dsh-mcp-client'\n" > "${conflict_profile}/cordis.patch.yml"
if "${installer}" --dsh-home "${conflict_home}" --command "${fake_command}" >/dev/null 2>&1; then
  fail "installer accepted a hand-written row it would duplicate"
fi
if [[ -f "${conflict_home}/ocu-hooks.json" ]]; then
  fail "installer wrote hook config before refusing the conflicting patch"
fi
pass "a hand-written duplicate row is refused instead of duplicated"

echo "install-dsh-mcp tests passed"
