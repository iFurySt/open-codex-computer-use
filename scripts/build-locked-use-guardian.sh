#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
identity="-"
configuration="debug"
arch_mode="native"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) identity="${2:?Missing signing identity}"; shift 2 ;;
    --configuration) configuration="${2:?Missing configuration}"; shift 2 ;;
    --arch) arch_mode="${2:?Missing architecture}"; shift 2 ;;
    *) echo 'Usage: scripts/build-locked-use-guardian.sh [--identity ID] [--configuration debug|release] [--arch native|arm64|x86_64|universal]' >&2; exit 64 ;;
  esac
done
[[ "$configuration" == debug || "$configuration" == release ]] || exit 64
cd "$repo_root"
source "$repo_root/scripts/locked-use-build-common.sh"
locked_use_architectures
name="OCU Guardian (Dev)"
output="$repo_root/.build/locked-use"
if [[ "$configuration" == release ]]; then
  name="OCU Guardian"
  output="$output/release"
fi
if [[ "$arch_mode" != native ]]; then output="$output-$arch_mode"; fi
app_path="$output/$name.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$repo_root/assets/app-icons/open-computer-use-1024.png" "$app_path/Contents/Resources/OCUShieldLogo.png"
locked_use_build_product OCUGuardian "$app_path/Contents/MacOS/OCUGuardian"
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.opencomputeruse.locked-use.guardian.dev</string>
<key>CFBundleExecutable</key><string>OCUGuardian</string>
<key>CFBundleName</key><string>${name}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>${locked_use_version}</string>
<key>LSUIElement</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>Detect local takeover and relock during Locked Use.</string>
</dict></plist>
PLIST
if [[ "$identity" == "-" ]]; then
  locked_use_sign --force --sign - "$app_path"
else
  locked_use_sign --force --options runtime,library --timestamp --sign "$identity" "$app_path"
fi
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
