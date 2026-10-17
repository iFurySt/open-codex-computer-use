#!/usr/bin/env bash
# Isolated deny-only right; NEVER writes system.login.screensaver.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
right='dev.opencomputeruse.locked-use.preflight'
plugin_name='OCULockProbe'
plugin_id='dev.opencomputeruse.locked-use.authorization-probe'
plugins='/Library/Security/SecurityAgentPlugins'
destination="${plugins}/${plugin_name}.bundle"
usage() {
  echo 'Usage: scripts/manage-locked-use-probe.sh install|uninstall'
  echo 'Requires administrator execution. Registers ONLY an independent deny-only diagnostic right.'
  echo 'Build with --identity before install; reads no credentials and never modifies system.login.screensaver.'
}
if [[ "${1:-}" == '--help' ]]; then usage; exit 0; fi
if [[ $# -ne 1 || ( "$1" != 'install' && "$1" != 'uninstall' ) ]]; then usage >&2; exit 2; fi
if [[ "$(uname -s)" != Darwin ]]; then echo 'macOS required.' >&2; exit 1; fi
if [[ "$(id -u)" != 0 ]]; then echo 'Run this reviewed script with sudo; administrator privileges are required.' >&2; exit 1; fi
# A root-owned scratch directory, not a predictable /tmp file.
scratch="$(mktemp -d /private/var/tmp/ocu-auth-probe.XXXXXX)"
staging=''
cleanup() {
  if [[ -n "${staging}" ]]; then rm -rf "${staging}"; fi
  rm -rf "${scratch}"
}
trap cleanup EXIT

if [[ "$1" == 'uninstall' ]]; then
  staged_copy="${plugins}/StagedPlugins/${plugin_name}.bundle"
  for candidate in "${destination}" "${staged_copy}"; do
    if [[ -e "${candidate}" ]]; then
      installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist")"
      if [[ "${installed_id}" != "${plugin_id}" ]]; then echo 'Bundle identity changed; refusing removal.' >&2; exit 1; fi
    fi
  done
  if /usr/bin/security authorizationdb read "${right}" > "${scratch}/current.plist" 2> "${scratch}/read-error"; then
    /usr/bin/python3 - "${scratch}/current.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    rule = plistlib.load(stream)
if rule.get('class') != 'evaluate-mechanisms' or rule.get('mechanisms') != ['OCULockProbe:preflight']:
    sys.exit('The probe right has changed; refusing to remove another configuration.')
PY
    /usr/bin/security authorizationdb remove "${right}"
  elif [[ "$(cat "${scratch}/read-error")" != *'-60005'* ]]; then
    cat "${scratch}/read-error" >&2; exit 1
  fi
  for candidate in "${destination}" "${staged_copy}"; do
    if [[ -e "${candidate}" ]]; then rm -rf "${candidate}"; fi
  done
  echo 'Removed diagnostic right and probe bundle. Screensaver rules were not modified.'
  exit 0
fi

source_bundle="${repo_root}/.build/locked-use/${plugin_name}.bundle"
if [[ ! -d "${source_bundle}" ]]; then echo 'Build the signed probe first; see docs/locked-use.md.' >&2; exit 1; fi
if [[ -e "${destination}" ]]; then echo 'Probe destination already exists; uninstall the reviewed previous probe first.' >&2; exit 1; fi
if /usr/bin/security authorizationdb read "${right}" > "${scratch}/existing.plist" 2> "${scratch}/read-error"; then
  echo 'Probe right already exists; refusing to overwrite it.' >&2; exit 1
elif [[ "$(cat "${scratch}/read-error")" != *'-60005'* ]]; then
  cat "${scratch}/read-error" >&2; exit 1
fi
mkdir -p "${plugins}"
staging="$(mktemp -d "${plugins}/.ocu-auth-probe.XXXXXX")"
/usr/bin/ditto "${source_bundle}" "${staging}/${plugin_name}.bundle"
staged_bundle="${staging}/${plugin_name}.bundle"
/usr/bin/codesign --verify --strict -R "=identifier \"${plugin_id}\" and anchor apple generic" "${staged_bundle}"
signature="$(/usr/bin/codesign -dv --verbose=4 "${staged_bundle}" 2>&1)"
if [[ "${signature}" != *'Authority=Developer ID Application:'* ]]; then
  echo 'A Developer ID Application signature is required; ad-hoc and development probes cannot be installed by this script.' >&2; exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :OCUProbeOnly' "${staged_bundle}/Contents/Info.plist")" != true ]]; then
  echo 'Not a diagnostic probe bundle.' >&2; exit 1
fi
chown -R root:wheel "${staged_bundle}"
chmod -R go-w "${staged_bundle}"
mv "${staged_bundle}" "${destination}"
cat > "${scratch}/right.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>class</key><string>evaluate-mechanisms</string>
<key>mechanisms</key><array><string>OCULockProbe:preflight</string></array>
<key>shared</key><false/>
<key>timeout</key><integer>0</integer>
<key>tries</key><integer>1</integer>
<key>comment</key><string>OCU isolated deny-only ABI probe; never grants session unlock.</string>
</dict></plist>
PLIST
if ! /usr/bin/security authorizationdb write "${right}" < "${scratch}/right.plist"; then
  rm -rf "${destination}"
  echo 'Right registration failed; removed staged probe bundle.' >&2
  exit 1
fi
echo 'Installed ONLY the diagnostic right. Run .build/locked-use/authorization-probe as your ordinary GUI user.'
echo 'A denied return is expected; confirm the plugin marker in unified logs before claiming loading succeeded.'
