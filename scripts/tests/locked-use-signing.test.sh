#!/usr/bin/env bash
# Simulate an isolated CI keychain. No real keychain changes are made.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/locked-use-build-common.sh"
state='original'
security() {
  if [[ "$*" == 'list-keychains -d user' ]]; then
    echo '    "/mock/login.keychain-db"'
    echo '    "/mock/system.keychain"'
  elif [[ "$*" == 'list-keychains -d user -s /mock/ci.keychain-db /mock/login.keychain-db /mock/system.keychain' ]]; then
    state='ci-enabled'
  elif [[ "$*" == 'list-keychains -d user -s /mock/login.keychain-db /mock/system.keychain' ]]; then
    state='original'
  else
    echo 'Unexpected keychain mutation' >&2; return 1
  fi
}
OPEN_COMPUTER_USE_CODESIGN_KEYCHAIN='/mock/ci.keychain-db'
signing_succeeds() { [[ "$state" == 'ci-enabled' ]]; }
signing_fails() { [[ "$state" == 'ci-enabled' ]] && return 42; }
locked_use_with_keychain signing_succeeds
[[ "$state" == original ]]
status=0
locked_use_with_keychain signing_fails || status=$?
[[ "$status" == 42 && "$state" == original ]]
echo 'CI keychain selection and restoration checked on success and failure.'
