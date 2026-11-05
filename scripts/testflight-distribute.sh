#!/bin/bash
# After the release's upload (mbui-testflight-distribute.yml): waits for Apple to process the build (it has no event to
# wait for), then adds it to the internal group, whose testers have it at once. With RELEASE_EXTERNAL=true also adds it to
# the external group and submits it to Beta App Review; its testers have it once Apple approves, which is not waited for.
# A job has five minutes: a run waits four, then dispatches the next round, ten rounds in all.
# The groups by name, each checked to be the kind it should be, so a build never reaches external testers by a wrong id.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
fail() { echo "testflight: $*" >&2; exit 1; }
[[ ${RELEASE_BUILD:-} =~ ^[1-9][0-9]*$ ]] || fail 'no build number'
[[ ${RELEASE_VERSION:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'no version'
[[ ${RELEASE_ROUND:-} =~ ^[1-9][0-9]*$ ]] || fail 'no round'
[[ ${RELEASE_EXTERNAL:-} =~ ^(true|false)$ ]] || fail 'external is true or false'
[[ ${ASC_KEY_ID:-} =~ ^[A-Z0-9]{10}$ ]] || fail 'invalid ASC key ID'
INTERNAL_GROUP='Internal Testers'
EXTERNAL_GROUP='external default'
APP=6818750243
T=$(mktemp -d "${RUNNER_TEMP:-/tmp}/mbui-testflight-distribute.XXXXXX")
trap 'rm -rf "$T"' EXIT
umask 077
export API_PRIVATE_KEYS_DIR=$T/private_keys
mkdir "$API_PRIVATE_KEYS_DIR"
printf %s "$ASC_PRIVATE_KEY_B64" | base64 --decode > "$API_PRIVATE_KEYS_DIR/AuthKey_$ASC_KEY_ID.p8"
. "$D/../apps/mbui/scripts/testflight-asc.sh"
summary() { echo "$*"; echo "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; }

# A token lasts 10 minutes: one for each try. Five failed requests in a row end it, none kept quiet.
tries=${ASC_POLL_TRIES:-8}
missed=0
build=
while :; do
  asc_token
  if asc_get "builds?filter[app]=$APP&filter[version]=$RELEASE_BUILD&filter[preReleaseVersion.version]=$RELEASE_VERSION&limit=2" > "$T/build.json"; then
    missed=0
    jq -e '.data | type == "array" and length <= 1' "$T/build.json" >/dev/null || fail 'invalid ASC build response'
    state=$(jq -r '.data[0].attributes.processingState // "NOT_VISIBLE"' "$T/build.json")
    echo "build $RELEASE_BUILD: $state"
    case $state in
      VALID) build=$(jq -r '.data[0].id' "$T/build.json"); break ;;
      NOT_VISIBLE | PROCESSING) ;;
      *) fail "Apple did not take build $RELEASE_BUILD: $state" ;;
    esac
  else
    missed=$((missed + 1))
    [ "$missed" -lt 5 ] || fail 'five ASC requests failed in a row'
  fi
  tries=$((tries - 1))
  if [ "$tries" = 0 ]; then
    [ "$RELEASE_ROUND" -lt 10 ] || fail "build $RELEASE_BUILD still not processed; add it by hand once it is"
    gh workflow run mbui-testflight-distribute.yml --repo "$GITHUB_REPOSITORY" --ref main \
      -f version="$RELEASE_VERSION" -f build="$RELEASE_BUILD" -f external="$RELEASE_EXTERNAL" -f round=$((RELEASE_ROUND + 1))
    summary "Build $RELEASE_BUILD still processing: round $((RELEASE_ROUND + 1)) dispatched."
    exit 0
  fi
  sleep "${ASC_POLL_SECONDS:-30}"
done

group_id() {
  asc_get "betaGroups?filter[app]=$APP&filter[name]=$(jq -rn --arg n "$1" '$n | @uri')&limit=2" > "$T/group.json"
  jq -e --argjson internal "$2" '(.data | length) == 1 and .data[0].attributes.isInternalGroup == $internal' "$T/group.json" >/dev/null ||
    fail "no single $([ "$2" = true ] && echo internal || echo external) group named \"$1\""
  jq -r '.data[0].id' "$T/group.json"
}
add_to_group() {
  jq -cn --arg id "$build" '{data:[{type:"builds",id:$id}]}' | asc_post "betaGroups/$1/relationships/builds"
}

asc_token
group=$(group_id "$INTERNAL_GROUP" true)
add_to_group "$group"
summary "Build $RELEASE_BUILD added to \"$INTERNAL_GROUP\"."
if [ "$RELEASE_EXTERNAL" = true ]; then
  group=$(group_id "$EXTERNAL_GROUP" false)
  add_to_group "$group"
  jq -cn --arg id "$build" '{data:{type:"betaAppReviewSubmissions",relationships:{build:{data:{type:"builds",id:$id}}}}}' |
    asc_post betaAppReviewSubmissions
  summary "Build $RELEASE_BUILD added to \"$EXTERNAL_GROUP\" and submitted to Beta App Review; its testers have it once Apple approves."
fi
