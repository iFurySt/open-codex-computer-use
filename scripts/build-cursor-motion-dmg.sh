#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="release"
arch_mode="native"
version=""
output_dir=""

usage() {
  cat <<'EOF'
Usage: ./scripts/build-cursor-motion-dmg.sh [--configuration debug|release] [--arch native|arm64|x86_64|universal] [--version X.Y.Z] [--output-dir PATH]

Examples:
  ./scripts/build-cursor-motion-dmg.sh
  ./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version 0.1.0
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      if [[ -z "${configuration}" ]]; then
        echo "--configuration requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --arch)
      arch_mode="${2:-}"
      if [[ -z "${arch_mode}" ]]; then
        echo "--arch requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --version)
      version="${2:-}"
      if [[ -z "${version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      if [[ -z "${output_dir}" ]]; then
        echo "--output-dir requires a value" >&2
        exit 1
      fi
      shift 2
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

if [[ "${configuration}" != "debug" && "${configuration}" != "release" ]]; then
  echo "Unsupported configuration: ${configuration}" >&2
  exit 1
fi

if [[ "${arch_mode}" != "native" && "${arch_mode}" != "arm64" && "${arch_mode}" != "x86_64" && "${arch_mode}" != "universal" ]]; then
  echo "Unsupported arch mode: ${arch_mode}" >&2
  exit 1
fi

if [[ -z "${version}" ]]; then
  if tag="$(git -C "${repo_root}" describe --tags --exact-match 2>/dev/null)"; then
    version="${tag#v}"
  else
    version="0.0.0-dev"
  fi
fi

if [[ -z "${output_dir}" ]]; then
  output_dir="${repo_root}/dist/release/cursor-motion"
fi

build_binary() {
  local triple="${1:-}"
  local scratch_path="${2:-}"
  local -a args=(-c "${configuration}")

  if [[ -n "${triple}" ]]; then
    args+=(--triple "${triple}")
  fi

  if [[ -n "${scratch_path}" ]]; then
    args+=(--scratch-path "${scratch_path}")
  fi

  local binary_dir
  binary_dir="$(swift build "${args[@]}" --show-bin-path)"
  swift build "${args[@]}" --product CursorMotion >&2
  printf '%s/CursorMotion\n' "${binary_dir}"
}

app_name="Cursor Motion.app"
bundle_identifier="com.ifuryst.cursormotion"
bundle_version="${CURSOR_MOTION_BUNDLE_VERSION:-${GITHUB_RUN_NUMBER:-$(git -C "${repo_root}" rev-list --count HEAD 2>/dev/null || echo 1)}}"
cursor_reference_source="${repo_root}/docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window-252.png"
app_root="${output_dir}/${app_name}"
contents_dir="${app_root}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
dmg_root="${output_dir}/dmg-root"
dmg_path="${output_dir}/CursorMotion-${version}.dmg"

rm -rf "${output_dir}"
mkdir -p "${macos_dir}" "${resources_dir}" "${dmg_root}"

cd "${repo_root}"

case "${arch_mode}" in
  native)
    cp "$(build_binary "" "")" "${macos_dir}/CursorMotion"
    ;;
  arm64)
    cp "$(build_binary "arm64-apple-macosx14.0" ".build/cursor-motion-arm64-${configuration}")" "${macos_dir}/CursorMotion"
    ;;
  x86_64)
    cp "$(build_binary "x86_64-apple-macosx14.0" ".build/cursor-motion-x86_64-${configuration}")" "${macos_dir}/CursorMotion"
    ;;
  universal)
    arm_binary="$(build_binary "arm64-apple-macosx14.0" ".build/cursor-motion-arm64-${configuration}")"
    x86_binary="$(build_binary "x86_64-apple-macosx14.0" ".build/cursor-motion-x86_64-${configuration}")"
    lipo -create -output "${macos_dir}/CursorMotion" "${arm_binary}" "${x86_binary}"
    ;;
esac

chmod +x "${macos_dir}/CursorMotion"

if [[ ! -f "${cursor_reference_source}" ]]; then
  echo "Missing cursor reference asset: ${cursor_reference_source}" >&2
  exit 1
fi

cp "${cursor_reference_source}" "${resources_dir}/official-software-cursor-window-252.png"

cat > "${contents_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CursorMotion</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Cursor Motion</string>
  <key>CFBundleDisplayName</key>
  <string>Cursor Motion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${bundle_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "${contents_dir}/Info.plist" >/dev/null
codesign --force --deep --sign - "${app_root}" >/dev/null 2>&1 || true

cp -R "${app_root}" "${dmg_root}/"
ln -s /Applications "${dmg_root}/Applications"

hdiutil create \
  -volname "Cursor Motion" \
  -srcfolder "${dmg_root}" \
  -ov \
  -format UDZO \
  "${dmg_path}" \
  >/dev/null

echo "${dmg_path}"
