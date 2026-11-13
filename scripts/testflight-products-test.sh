#!/bin/bash
# Offline: the default releases both apps; each selected app resolves to its own signing and ASC identity.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
fail() { echo "testflight-products-test: $*" >&2; exit 1; }
products() { bash "$D/testflight-products.sh" "$@"; }
[ "$(products)" = '["stillfail","monoid"]' ] || fail 'default must release both apps'
for selection in both stillfail monoid; do
  picked=$(products "$selection")
  [ "$(printf '%s' "$picked" | jq 'unique | length')" = "$([ "$selection" = both ] && echo 2 || echo 1)" ] || fail 'wrong number of apps'
  for product in $(printf '%s' "$picked" | jq -rj '.[] + " "'); do
    [ "$selection" = both ] || [ "$product" = "$selection" ] || fail 'selected another app'
    identity=$(RELEASE_PRODUCT=$product bash -c '. "$1"; echo "$IOS_BUNDLE_ID/$IOS_EXPECTED_APP_GROUP/$IOS_ASC_APP_ID"' _ "$D/../apps/mbui/scripts/testflight-product.sh")
    case $product in
      stillfail) [ "$identity" = 'fail.still.iphone/group.fail.still.iphone/6818750243' ] || fail 'still.fail identity' ;;
      monoid) [ "$identity" = 'build.monoid.iphone/group.build.monoid.iphone/6832495462' ] || fail 'monoid identity' ;;
      *) fail 'a non-concrete identity reached the upload' ;;
    esac
  done
done
for invalid in '' unknown 'both,monoid'; do
  if products "$invalid" >/dev/null 2>&1; then fail 'accepted an invalid selection'; fi
done
echo 'TestFlight app selection: passed (offline only)'
