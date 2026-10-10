#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: scripts/build-locked-use-plugin.sh [--identity <Developer ID Application identity>]'
  echo 'Build and test a deny-only ABI probe in .build/locked-use. Does not install or modify authorization rules.'
  exit 0
fi
identity="-"
if [[ $# -eq 2 && "$1" == "--identity" && -n "$2" ]]; then
  identity="$2"
elif [[ $# -ne 0 ]]; then
  echo 'Unexpected arguments; see --help.' >&2; exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then echo 'The Authorization plugin probe requires macOS.' >&2; exit 1; fi
output="${repo_root}/.build/locked-use"
bundle="${output}/OCULockProbe.bundle"
mkdir -p "${bundle}/Contents/MacOS"
xcrun clang -std=c11 -Wall -Wextra -Werror -fvisibility=hidden -mmacosx-version-min=14.0 \
  -bundle -framework Security -framework CoreFoundation \
  "${repo_root}/experiments/LockedUse/AuthorizationPlugin/Plugin.c" \
  -o "${bundle}/Contents/MacOS/OCULockProbe"
cat > "${bundle}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.opencomputeruse.locked-use.authorization-probe</string>
<key>CFBundleExecutable</key><string>OCULockProbe</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>OCUProbeOnly</key><true/>
</dict></plist>
PLIST
sign_args=(--force --sign "${identity}")
if [[ "${identity}" != "-" ]]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" "${bundle}"
codesign --verify --strict "${bundle}"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Security "${repo_root}/experiments/LockedUse/AuthorizationPlugin/PluginTests.c" \
  -o "${output}/plugin-abi-tests"
"${output}/plugin-abi-tests" "${bundle}/Contents/MacOS/OCULockProbe"
xcrun swiftc -framework Security "${repo_root}/experiments/LockedUse/Sources/AuthorizationProbe.swift" \
  -o "${output}/authorization-probe"
echo 'Built deny-only probe. Signing verification is not SecurityAgent Library Validation or notarization.'
