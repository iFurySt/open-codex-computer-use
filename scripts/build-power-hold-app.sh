#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 1
fi
identity="${OPEN_COMPUTER_USE_CODESIGN_IDENTITY:-}"
suffix=""
app_name="Open Computer Use Power.app"
if [[ "$configuration" == debug ]]; then
  suffix=".dev"
  app_name="Open Computer Use Power (Dev).app"
fi
package="$repo_root/packages/OpenComputerUsePower"
swift build --package-path "$package" -c "$configuration" --product OCUPowerHost >&2
swift build --package-path "$package" -c "$configuration" --product OCUPowerHelper >&2
swift build --package-path "$package" -c "$configuration" --product OCUPowerGUIFixture >&2
binary_dir="$(swift build --package-path "$package" -c "$configuration" --show-bin-path)"
output="$repo_root/dist/power-hold/$configuration/$app_name"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Library/LaunchDaemons"
cp "$binary_dir/OCUPowerHost" "$output/Contents/MacOS/OCUPowerHost"
cp "$binary_dir/OCUPowerHelper" "$output/Contents/MacOS/OCUPowerHelper"
cp "$binary_dir/OCUPowerGUIFixture" "$output/Contents/MacOS/OCUPowerGUIFixture"
python3 - "$output" "$suffix" <<'PY'
import pathlib,plistlib,sys
root=pathlib.Path(sys.argv[1]); suffix=sys.argv[2]
service='com.opencomputeruse.power.helper'+suffix
info={'CFBundleIdentifier':'com.opencomputeruse.power.host'+suffix,
      'CFBundleExecutable':'OCUPowerHost','CFBundleName':'Open Computer Use Power',
      'CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0',
      'LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True}
(root/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
installed=pathlib.Path('/Applications')/root.name/'Contents/MacOS/OCUPowerHelper'
daemon={'Label':service,'ProgramArguments':[str(installed)],
        'AssociatedBundleIdentifiers':['com.opencomputeruse.power.host'+suffix],
        'MachServices':{service:True},'RunAtLoad':True,'KeepAlive':True,
        'ThrottleInterval':5,'ProcessType':'Background'}
(root/'Contents/Library/LaunchDaemons'/f'{service}.plist').write_bytes(plistlib.dumps(daemon))
PY
signer="${identity:--}"
codesign --force --options runtime --identifier "com.opencomputeruse.power.fixture$suffix" --sign "$signer" "$output/Contents/MacOS/OCUPowerGUIFixture"
codesign --force --options runtime --identifier "com.opencomputeruse.power.helper$suffix" --sign "$signer" "$output/Contents/MacOS/OCUPowerHelper"
codesign --force --options runtime --sign "$signer" "$output"
codesign --verify --strict "$output"
if [[ -z "$identity" ]]; then
  echo "Ad-hoc bundle: ordinary power holds only; Developer ID is required for lid helper installation." >&2
fi
printf '%s\n' "$output"
