#!/usr/bin/env bash
# Build only. Installing/starting the privileged service is a separate step.
set -euo pipefail
if [[ $# != 2 || "$1" != --identity || -z "$2" || "$2" == - ]]; then
  echo 'Usage: scripts/build-locked-use-components.sh --identity "Developer ID Application: ..."' >&2
  exit 64
fi
identity="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
swift build --product OpenComputerUseLockedUseBroker
swift build --product OpenComputerUseLockedUseInstaller
binary_dir="$(swift build --show-bin-path)"
output="$repo_root/.build/locked-use/components"
mkdir -p "$output"
cp "$binary_dir/OpenComputerUseLockedUseBroker" "$output/OpenComputerUseLockedUseBroker"
cp "$binary_dir/OpenComputerUseLockedUseInstaller" "$output/OpenComputerUseLockedUseInstaller"
codesign --force --options runtime --timestamp --identifier dev.opencomputeruse.locked-use.installer \
  --sign "$identity" "$output/OpenComputerUseLockedUseInstaller"
codesign --force --options runtime --timestamp --identifier dev.opencomputeruse.locked-use.broker \
  --sign "$identity" "$output/OpenComputerUseLockedUseBroker"
team="$(codesign -dv --verbose=4 "$output/OpenComputerUseLockedUseBroker" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then echo 'Developer ID team unavailable.' >&2; exit 1; fi
scripts/build-locked-use-guardian.sh --identity "$identity"
ditto '.build/locked-use/Open Computer Use Guardian (Dev).app' "$output/Open Computer Use Guardian (Dev).app"
bundle="$output/OpenComputerUseLockedUseAuthorizationPlugin.bundle"
mkdir -p "$bundle/Contents/MacOS"
xcrun clang -fobjc-arc -std=gnu11 -Wall -Wextra -Werror -fvisibility=hidden -mmacosx-version-min=14.0 \
  "-DOCU_SIGNING_TEAM=\"$team\"" -I packages/LockedUseNative/include -bundle -framework Security -framework Foundation -lbsm \
  experiments/LockedUse/AuthorizationPlugin/RemotePlugin.m packages/LockedUseNative/PeerIdentity.c \
  -o "$bundle/Contents/MacOS/OpenComputerUseLockedUseAuthorizationPlugin"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.opencomputeruse.locked-use.authorization</string>
<key>CFBundleExecutable</key><string>OpenComputerUseLockedUseAuthorizationPlugin</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
codesign --verify --strict "$bundle"
codesign --verify --strict "$output/OpenComputerUseLockedUseBroker"
xcrun clang -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -framework Security \
  experiments/LockedUse/AuthorizationPlugin/RemotePluginTests.c -o "$output/remote-plugin-abi-tests"
"$output/remote-plugin-abi-tests" "$bundle/Contents/MacOS/OpenComputerUseLockedUseAuthorizationPlugin"
echo 'Signed Broker, Guardian and remote plugin built. No system files or authorization rules changed.'

fixture="$output/Locked Use Native Fixture (Dev).app"
mkdir -p "$fixture/Contents/MacOS"
cp "$binary_dir/OpenComputerUseGuardian" "$fixture/Contents/MacOS/OpenComputerUseGuardian"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.opencomputeruse.locked-use.fixture.dev</string>
<key>CFBundleExecutable</key><string>OpenComputerUseGuardian</string>
<key>CFBundleName</key><string>Locked Use Native Fixture</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$identity" "$fixture"
