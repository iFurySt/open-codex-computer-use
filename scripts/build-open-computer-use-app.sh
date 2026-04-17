#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"

cd "${repo_root}"

binary_dir="$(swift build -c "${configuration}" --show-bin-path)"
swift build -c "${configuration}" --product OpenComputerUse

app_root="${repo_root}/dist/OpenComputerUse.app"
contents_dir="${app_root}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

rm -rf "${app_root}"
mkdir -p "${macos_dir}" "${resources_dir}"

cp "${binary_dir}/OpenComputerUse" "${macos_dir}/OpenComputerUse"
chmod +x "${macos_dir}/OpenComputerUse"

cat > "${contents_dir}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>OpenComputerUse</string>
  <key>CFBundleIdentifier</key>
  <string>dev.opencodex.OpenComputerUse</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Open Computer Use</string>
  <key>CFBundleDisplayName</key>
  <string>Open Computer Use</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "${contents_dir}/Info.plist" >/dev/null

echo "Built ${app_root}"
