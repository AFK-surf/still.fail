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
echo 'TestFlight input guards: passed (offline only)'
