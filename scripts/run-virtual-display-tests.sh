#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
swift build --product VirtualDisplayHost
swift build --product VirtualDisplayTestApp
swift build --product VirtualDisplayRunner
binary_dir="$(swift build --show-bin-path)"
exec "${binary_dir}/VirtualDisplayRunner" "$@"
