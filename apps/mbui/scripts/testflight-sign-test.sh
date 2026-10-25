#!/bin/bash
# Offline signing-contract regression: no real keys, codesign or security calls.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
. "$D/testflight-sign.sh"
case ${1:-test} in
  cleanup-*)
    T=$(mktemp -d); KEYCHAIN=$T/unused
    security() { :; }
    TESTFLIGHT_UPLOADED=no
    trap testflight_cleanup EXIT
    case "$1" in
      cleanup-success) TESTFLIGHT_UPLOADED=yes ;;
      cleanup-nounset) unset missing; printf '%s' "$missing" ;;
    esac
    exit 0
    ;;
esac
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
T="$ROOT/with spaces"; mkdir "$T"
APPDIR="$T/MBUI.app"; SHARE="$APPDIR/PlugIns/Share.appex"
KEYCHAIN="$T/signing.keychain-db"; IOS_SIGNING_SHA1=test-fingerprint
codesign() {
  local arg last= ent= expected=
  for arg in "$@"; do last=$arg; done
  [ "$1" = --force ] || return 0
  case "$last" in
    "$APPDIR/Frameworks/hermes.framework") expected= ;;
    "$SHARE") expected="$T/share.entitlements" ;;
    "$APPDIR") expected="$T/app.entitlements" ;;
    *) echo 'unexpected signing target' >&2; exit 1 ;;
  esac
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --entitlements ]; then shift; ent=$1; fi
    shift
  done
  [ "$ent" = "$expected" ] || { echo 'wrong signing entitlements' >&2; exit 1; }
  printf '%s\n' "$last" >> "$ROOT/signed"
}
testflight_sign_bundles
printf '%s\n' "$APPDIR/Frameworks/hermes.framework" "$SHARE" "$APPDIR" > "$ROOT/expected"
cmp "$ROOT/expected" "$ROOT/signed"
for mode in cleanup-early cleanup-nounset; do
  if "$BASH" "$0" "$mode" >/dev/null 2>&1; then
    echo "unexpected successful exit: $mode" >&2; exit 1
  fi
done
"$BASH" "$0" cleanup-success
echo 'TestFlight signing and cleanup contracts: passed (offline only)'
