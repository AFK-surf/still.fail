#!/bin/bash
# Sourced signing lifecycle, compatible with macOS's Bash 3.2.
testflight_cleanup() {
  local status=$?
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$T"
  # Bash 3.2 can report status 0 for nounset errors when an EXIT trap succeeds.
  # Only the explicit post-upload state permits a successful exit.
  [ "$status" -ne 0 ] || [ "${TESTFLIGHT_UPLOADED:-no}" = yes ] || status=1
  trap - EXIT
  exit "$status"
}

testflight_sign_bundles() {
  local bundle
  for bundle in "$APPDIR/Frameworks/hermes.framework" "$SHARE" "$APPDIR"; do
    set -- --force --sign "$IOS_SIGNING_SHA1" --keychain "$KEYCHAIN" --generate-entitlement-der
    case "$bundle" in
      "$SHARE") set -- "$@" --entitlements "$T/share.entitlements" ;;
      "$APPDIR") set -- "$@" --entitlements "$T/app.entitlements" ;;
    esac
    codesign "$@" "$bundle"
    codesign --verify --strict "$bundle"
  done
  codesign --verify --deep --strict "$APPDIR"
}
