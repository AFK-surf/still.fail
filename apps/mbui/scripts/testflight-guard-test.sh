#!/bin/bash
# Offline guard tests only: no build, Apple calls, secrets, signing or keychain access.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
export RELEASE_VERSION=0.1.0 RELEASE_BUILD=5 RELEASE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export GITHUB_RUN_ATTEMPT=1
export GITHUB_SHA=$RELEASE_SHA GITHUB_REF=refs/heads/main GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REPOSITORY=AFK-surf/still.fail
pass() { bash "$D/testflight-guard.sh" inputs; }
reject() { if env "$@" bash "$D/testflight-guard.sh" inputs >/dev/null 2>&1; then echo "unexpected acceptance: $*" >&2; exit 1; fi; }
pass
for version in '' 0.1 v0.1.0 01.1.0 0.1.0-beta '0.1.0;echo bad'; do reject RELEASE_VERSION="$version"; done
for build in '' 0 -1 01 1.0 abc 10000 1000000000 '5;echo bad'; do reject RELEASE_BUILD="$build"; done
for ref in refs/heads/topic refs/tags/main refs/tags/v0.1.0; do reject GITHUB_REF="$ref"; done
reject GITHUB_EVENT_NAME=push
reject GITHUB_RUN_ATTEMPT=2
reject GITHUB_RUN_ATTEMPT=0
reject GITHUB_RUN_ATTEMPT=''
reject GITHUB_EVENT_NAME=pull_request
reject GITHUB_REPOSITORY=someone/fork
reject RELEASE_SHA=aaaaaaa
reject RELEASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
reject GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
reject RELEASE_SHA='$(echo unsafe)'
# A real shallow checkout and local file remote: no GitHub or Apple requests.
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
git init -q -b codex/testflight-fixture "$ROOT/origin"
git -C "$ROOT/origin" config user.name 'TestFlight guard test'
git -C "$ROOT/origin" config user.email 'testflight-guard@example.invalid'
git -C "$ROOT/origin" config commit.gpgsign false
git -C "$ROOT/origin" commit -q --allow-empty -m first
first=$(git -C "$ROOT/origin" rev-parse HEAD)
git -C "$ROOT/origin" update-ref refs/heads/main "$first"
git clone -q --depth 1 --branch main "file://$ROOT/origin" "$ROOT/checkout"
export RELEASE_SHA=$first GITHUB_SHA=$first
checkout_pass() { (cd "$ROOT/checkout" && bash "$D/testflight-guard.sh" checkout) > /dev/null 2>&1; }
checkout_reject() {
  if checkout_pass; then echo 'unexpected checkout acceptance' >&2; exit 1; fi
}
checkout_pass
git -C "$ROOT/origin" commit -q --allow-empty -m forward
forward=$(git -C "$ROOT/origin" rev-parse HEAD)
git -C "$ROOT/origin" update-ref refs/heads/main "$forward"
# main moves, but the tested checkout stays pinned to the dispatch commit.
checkout_pass
[ "$(git -C "$ROOT/checkout" rev-parse HEAD)" = "$first" ]
git -C "$ROOT/checkout" checkout -q --detach "$forward"
checkout_reject # a different checkout must not be signed
export RELEASE_SHA=$forward GITHUB_SHA=$forward
checkout_pass
git -C "$ROOT/origin" update-ref refs/heads/main "$first"
checkout_reject # main rolled back and removed the approved commit
git -C "$ROOT/origin" checkout -q --orphan codex/unrelated
git -C "$ROOT/origin" commit -q --allow-empty -m unrelated
git -C "$ROOT/origin" update-ref refs/heads/main HEAD
checkout_reject # unrelated replacement history cannot authorize a release
echo 'TestFlight input and pinned-main guards: passed (offline only)'
