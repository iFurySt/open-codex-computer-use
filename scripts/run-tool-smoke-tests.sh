#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${repo_root}"

swift build
OPEN_COMPUTER_USE_VISUAL_CURSOR=0 ".build/debug/OpenComputerUseSmokeSuite"
".build/debug/OpenComputerUseSmokeSuite" --cursor-idle-only
