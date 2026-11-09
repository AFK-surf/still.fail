#!/bin/bash
# Offline: identity selection and ASC preflight with simulated Apple responses, never a key or network request.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "testflight-product-test: $*" >&2; exit 1; }
. "$D/testflight-asc.sh"
asc_token() { :; }
asc_get() {
  echo "$1" >> "$T/calls"
  case $1 in
    apps/*) jq -cn --arg app "${ANSWER_APP:-$IOS_ASC_APP_ID}" --arg bid "${ANSWER_BUNDLE:-$IOS_BUNDLE_ID}" '{data:{type:"apps",id:$app,attributes:{bundleId:$bid}}}' ;;
    builds*) printf '%s\n' "${BUILDS:-{\"data\":[]}}" ;;
    *) fail "unexpected request $1" ;;
  esac
}
export RELEASE_BUILD=5
check() {
  . "$D/testflight-product.sh"
  [ "$IOS_APP_NAME/$IOS_BUNDLE_ID/$IOS_EXPECTED_APP_GROUP/$IOS_ASC_APP_ID" = "$1" ] || fail 'wrong product identity'
  : > "$T/calls"
  asc_preflight
  grep -qF "builds?filter[app]=$IOS_ASC_APP_ID&filter[version]=5" "$T/calls" || fail 'duplicate check selected another app'
}
unset RELEASE_PRODUCT
check 'still.fail/fail.still.iphone/group.fail.still.iphone/6818750243'
export RELEASE_PRODUCT=monoid
check 'monoid/build.monoid.iphone/group.build.monoid.iphone/6832495462'
reject() { if ( "$@" ) > "$T/out" 2>&1; then fail 'accepted mismatched identity'; fi; }
ANSWER_BUNDLE=fail.still.iphone reject asc_preflight
ANSWER_APP=6818750243 reject asc_preflight
BUILDS='{"data":[{"id":"already-used"}]}' reject asc_preflight
BUILDS='{"data":[],"links":{"next":"another-page"}}' reject asc_preflight
IOS_ASC_APP_ID='' reject asc_preflight
IOS_ASC_APP_ID='6818750243/relationships' reject asc_preflight
RELEASE_PRODUCT=unknown reject . "$D/testflight-product.sh"
echo 'TestFlight product identity and ASC preflight: passed (offline only)'
