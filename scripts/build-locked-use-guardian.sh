#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
identity="-"
if [[ $# == 2 && "$1" == "--identity" && -n "$2" ]]; then
  identity="$2"
elif [[ $# != 0 ]]; then
  echo 'Usage: scripts/build-locked-use-guardian.sh [--identity "Developer ID Application: ..."]' >&2
  exit 64
fi

cd "$repo_root"
swift build --product OpenComputerUseGuardian
binary_dir="$(swift build --show-bin-path)"
app_path="$repo_root/.build/locked-use/Open Computer Use Guardian (Dev).app"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/OpenComputerUseGuardian" "$app_path/Contents/MacOS/OpenComputerUseGuardian"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.opencomputeruse.locked-use.guardian.dev</string>
<key>CFBundleExecutable</key><string>OpenComputerUseGuardian</string>
<key>CFBundleName</key><string>Open Computer Use Guardian (Dev)</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>LSUIElement</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>Detect local takeover and relock during the Locked Use rehearsal.</string>
</dict></plist>
PLIST
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app_path"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app_path"
fi
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
