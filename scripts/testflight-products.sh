#!/bin/bash
# The manual release's selection, expanded before the shared tests and each app's upload.
# Only concrete identities reach testflight-product.sh, which checks their bundle IDs against Apple.
set -euo pipefail
case ${1-both} in
  both) echo '["stillfail","monoid"]' ;;
  stillfail) echo '["stillfail"]' ;;
  monoid) echo '["monoid"]' ;;
  *) echo 'testflight: select both, stillfail or monoid' >&2; exit 1 ;;
esac
