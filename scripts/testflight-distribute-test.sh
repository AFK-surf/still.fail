#!/bin/bash
# Offline: a curl of its own answers as App Store Connect does and says what it was asked. No Apple calls, no secrets.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/curl" <<'C'
#!/bin/bash
url=${*: -1}
method=GET
for a in "$@"; do case $a in POST|PATCH) method=$a ;; esac; done
echo "$method ${url#https://api.appstoreconnect.apple.com/v1/}" >> "$FAKE/calls"
case $url in
  */apps/*/betaAppLocalizations*)
    if [[ $url = */apps/6818750243/* && $RELEASE_PRODUCT = monoid ]]; then cat "$FAKE/source-localizations"; else cat "$FAKE/localizations"; fi ;;
  */apps/*/betaAppReviewDetail*)
    if [[ $url = */apps/6818750243/* ]]; then cat "$FAKE/source-contact"; else cat "$FAKE/contact"; fi ;;
  */betaAppReviewDetails/*) cat > "$FAKE/contact-write"; echo '{}' ;;
  */betaAppLocalizations|*/betaAppLocalizations/*)
    cat > "$FAKE/description"
    [ -z "${DESCRIPTION_REFUSE:-}" ] || { echo '{"errors":[{"detail":"description refused"}]}'; exit 22; }
    echo '{}' ;;
  */apps/*) echo "{\"data\":{\"type\":\"apps\",\"id\":\"${ANSWER_APP:-$IOS_ASC_APP_ID}\",\"attributes\":{\"bundleId\":\"${ANSWER_BUNDLE:-$IOS_BUNDLE_ID}\"}}}" ;;
  */builds\?*)
    n=$(cat "$FAKE/polls" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE/polls"
    state=$(sed -n "$((n + 1))p" "$FAKE/states")
    case $state in
      '') state=$(tail -1 "$FAKE/states") ;;
    esac
    case $state in
      DOWN) exit 22 ;;
      NONE) echo '{"data":[]}' ;;
      *) echo "{\"data\":[{\"id\":\"b1\",\"attributes\":{\"processingState\":\"$state\"}}]}" ;;
    esac ;;
  *betaGroups\?*Internal*) cat "$FAKE/internal" ;;
  *betaGroups\?*external*) cat "$FAKE/external" ;;
  */betaGroups)
    cat > "$FAKE/created"
    [ -z "${CREATE_REFUSE:-}" ] || { echo '{"errors":[{"detail":"creation refused"}]}'; exit 22; }
    jq --argjson internal "${CREATE_INTERNAL:-false}" '.data.id = "ge-new" | .data.attributes.isInternalGroup = $internal' "$FAKE/created" ;;
  *) [ ! -e "$FAKE/refuse" ] || { echo '{"errors":[{"detail":"refused"}]}'; exit 22; }; cat > /dev/null ;;
esac
C
cat > "$W/bin/gh" <<'C'
#!/bin/bash
echo "gh $*" >> "$FAKE/dispatched"
C
chmod +x "$W/bin/curl" "$W/bin/gh"
export PATH=$W/bin:$PATH RUNNER_TEMP=$W GITHUB_STEP_SUMMARY=$W/summary ASC_POLL_SECONDS=0 ASC_POLL_TRIES=6 GITHUB_REPOSITORY=AFK-surf/monoid
export RELEASE_BUILD=5 RELEASE_VERSION=0.1.0 ASC_KEY_ID=ABCDE12345 ASC_ISSUER_ID=issuer
export RELEASE_PRODUCT=stillfail
export ASC_PRIVATE_KEY_B64=$(openssl ecparam -name prime256v1 -genkey -noout | openssl base64 -A)
good_internal='{"data":[{"id":"gi","attributes":{"isInternalGroup":true}}]}'
good_external='{"data":[{"id":"ge","attributes":{"isInternalGroup":false}}]}'
good_localizations='{"data":[{"id":"en","attributes":{"locale":"en-US","description":"Existing description"}}]}'
run() {
  export FAKE=$W/fake
  rm -rf "$FAKE"; mkdir "$FAKE"
  printf '%s\n' $1 > "$FAKE/states"
  echo "${INTERNAL_ANSWER:-$good_internal}" > "$FAKE/internal"
  echo "${EXTERNAL_ANSWER:-$good_external}" > "$FAKE/external"
  echo "${LOCALIZATIONS:-$good_localizations}" > "$FAKE/localizations"
  echo '{"data":[{"attributes":{"feedbackEmail":"feedback@example.com"}}]}' > "$FAKE/source-localizations"
  echo "${CONTACT:-{\"data\":{\"id\":\"review\",\"attributes\":{\"contactFirstName\":\"Keep\"}}}}" > "$FAKE/contact"
  echo "${SOURCE_CONTACT:-{\"data\":{\"attributes\":{\"contactFirstName\":\"Source\",\"contactLastName\":\"Person\",\"contactPhone\":\"+15555550123\",\"contactEmail\":\"review@example.com\",\"demoAccountName\":\"never-copy\"}}}}" > "$FAKE/source-contact"
  [ -z "${REFUSE:-}" ] || touch "$FAKE/refuse"
  touch "$FAKE/calls"
  RELEASE_ROUND=${ROUND:-1} RELEASE_EXTERNAL=${2:-false} bash -c '. "$1/../apps/mbui/scripts/testflight-product.sh"; export IOS_ASC_APP_ID IOS_BUNDLE_ID; bash "$1/testflight-distribute.sh"' _ "$D" > "$W/out" 2>&1
}
posts() { grep '^POST' "$FAKE/calls" || true; }
expect_posts() { [ "$(posts)" = "$1" ] || { echo "expected posts: $1"$'\n'"got: $(posts)" >&2; cat "$W/out" >&2; exit 1; }; }
refuses() { if run "$@"; then echo "unexpected success: $*" >&2; exit 1; fi; }

# Waits through not visible yet, processing and a failed request; internal alone by default.
run 'NONE PROCESSING DOWN VALID'
expect_posts 'POST betaGroups/gi/relationships/builds'
[ "$(cat "$FAKE/polls")" = 4 ]
# The switch: the external group too, then the review.
run VALID true
expect_posts 'POST betaGroups/gi/relationships/builds
POST betaGroups/ge/relationships/builds
POST betaAppReviewSubmissions'
# Still processing as a round's wait ends: the next round, with what it was given, nothing added.
run PROCESSING true
expect_posts ''
grep -q 'external=true -f round=2' "$FAKE/dispatched"
# Apple refused the build, or never finished, or the requests keep failing: nothing added.
refuses INVALID; expect_posts ''
refuses FAILED; expect_posts ''
ROUND=10 refuses PROCESSING; expect_posts ''
refuses DOWN; expect_posts ''
# A group of the wrong kind or duplicate name is never used; missing internal groups are not created.
INTERNAL_ANSWER=$good_external refuses VALID; expect_posts ''
INTERNAL_ANSWER='{"data":[]}' refuses VALID; expect_posts ''
EXTERNAL_ANSWER=$good_internal refuses VALID true; expect_posts 'POST betaGroups/gi/relationships/builds'
EXTERNAL_ANSWER='{"data":[{"id":"a"},{"id":"b"}]}' refuses VALID true; expect_posts 'POST betaGroups/gi/relationships/builds'
# Apple refusing the addition fails the job.
REFUSE=1 refuses VALID
grep -q refused "$W/out"
# monoid's build lookup and subsequent wait rounds stay on monoid; another app's record refuses before any write.
export RELEASE_PRODUCT=monoid
# Explicit first-time setup fills missing contact fields and feedback email only; the existing name is preserved.
RELEASE_PREPARE_MONOID=true run VALID true
grep -qF 'PATCH betaAppReviewDetails/review' "$FAKE/calls"
jq -e '.data.attributes == {contactLastName:"Person",contactPhone:"+15555550123",contactEmail:"review@example.com"}' "$FAKE/contact-write" >/dev/null
jq -e '.data.attributes == {feedbackEmail:"feedback@example.com"}' "$FAKE/description" >/dev/null
RELEASE_PREPARE_MONOID=true SOURCE_CONTACT='{"data":{"attributes":{}}}' refuses VALID true
expect_posts ''
grep -q 'review contact needs configuring' "$W/out"
# First external release: create a description for the verified app, or fill only descriptions that are missing.
LOCALIZATIONS='{"data":[]}' run VALID true
expect_posts 'POST betaAppLocalizations
POST betaGroups/gi/relationships/builds
POST betaGroups/ge/relationships/builds
POST betaAppReviewSubmissions'
jq -e '.data.attributes.locale == "en-US" and (.data.attributes.description | startswith("monoid ")) and .data.relationships.app.data.id == "6832495462"' "$FAKE/description" >/dev/null
LOCALIZATIONS='{"data":[{"id":"en","attributes":{"locale":"en-US","description":"Existing description"}},{"id":"zh","attributes":{"locale":"zh-Hans"}}]}' run VALID true
grep -qF 'PATCH betaAppLocalizations/zh' "$FAKE/calls"
! grep -qF 'PATCH betaAppLocalizations/en' "$FAKE/calls"
jq -e '.data.id == "zh" and (.data.attributes | keys) == ["description"] and (.data.attributes.description | startswith("monoid "))' "$FAKE/description" >/dev/null
LOCALIZATIONS='{"data":[]}' DESCRIPTION_REFUSE=1 refuses VALID true
expect_posts 'POST betaAppLocalizations'
LOCALIZATIONS='{"data":[]}' run VALID false
expect_posts 'POST betaGroups/gi/relationships/builds'
! grep -q betaAppLocalizations "$FAKE/calls"
# The first external release creates its app's group, then adds the build and submits review.
EXTERNAL_ANSWER='{"data":[]}' run VALID true
expect_posts 'POST betaGroups/gi/relationships/builds
POST betaGroups
POST betaGroups/ge-new/relationships/builds
POST betaAppReviewSubmissions'
jq -e '.data.attributes == {name:"external default",isInternalGroup:false} and .data.relationships.app.data == {type:"apps",id:"6832495462"}' "$FAKE/created" >/dev/null
creation_refuses() {
  EXTERNAL_ANSWER='{"data":[]}' refuses VALID true
  expect_posts 'POST betaGroups/gi/relationships/builds
POST betaGroups'
}
CREATE_REFUSE=1 creation_refuses
CREATE_INTERNAL=true creation_refuses
run VALID true
grep -qF 'GET builds?filter[app]=6832495462&filter[version]=5' "$FAKE/calls"
expect_posts 'POST betaGroups/gi/relationships/builds
POST betaGroups/ge/relationships/builds
POST betaAppReviewSubmissions'
run PROCESSING true
grep -q 'product=monoid' "$FAKE/dispatched"
ANSWER_BUNDLE=fail.still.iphone refuses VALID; expect_posts ''
ANSWER_APP=6818750243 refuses VALID; expect_posts ''
echo 'testflight-distribute: ok'
