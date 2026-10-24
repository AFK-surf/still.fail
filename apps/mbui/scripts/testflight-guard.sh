#!/bin/bash
# Release-only guards. No credentials, network, build or signing in `inputs`.
set -euo pipefail
fail() { echo "testflight: $*" >&2; exit 1; }
[[ ${RELEASE_VERSION:-} =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'marketing version must be explicit major.minor.patch'
[[ ${RELEASE_BUILD:-} =~ ^[1-9][0-9]{0,3}$ ]] || fail 'build must be an explicit positive integer (at most 4 digits)'
[[ ${RELEASE_SHA:-} =~ ^[0-9a-f]{40}$ ]] || fail 'expected SHA must be a full lowercase commit SHA'
[ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ] || fail 'manual dispatch only'
[ "${GITHUB_RUN_ATTEMPT:-}" = 1 ] || fail 'reruns forbidden; inspect Apple after an ambiguous upload, then dispatch a fresh build number'
[ "${GITHUB_REF:-}" = refs/heads/main ] || fail 'select main, not a tag or branch'
[ "${GITHUB_REPOSITORY:-}" = AFK-surf/still.fail ] || fail 'wrong repository'
[ "${GITHUB_SHA:-}" = "$RELEASE_SHA" ] || fail 'dispatch SHA does not match approved SHA'
case ${1:-inputs} in
  inputs) ;;
  checkout)
    [ "$(git rev-parse HEAD)" = "$RELEASE_SHA" ] || fail 'checkout differs from approved SHA'
    git fetch --no-tags origin main
    [ "$(git rev-parse FETCH_HEAD)" = "$RELEASE_SHA" ] || fail 'main moved; dispatch and approve the new SHA'
    ;;
  *) fail 'expected inputs or checkout' ;;
esac
