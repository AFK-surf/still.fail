#!/bin/bash
# Manual release on an ephemeral GitHub-hosted macOS runner only. Never invoke locally.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
fail() { echo "testflight: $*" >&2; exit 1; }
bash "$D/testflight-guard.sh" checkout
[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] && [ "${RUNNER_OS:-}" = macOS ] || fail 'requires disposable GitHub macOS runner'
for name in IOS_DISTRIBUTION_P12_B64 IOS_DISTRIBUTION_P12_PASSWORD IOS_APP_PROFILE_B64 IOS_SHARE_PROFILE_B64 IOS_SIGNING_SHA1 ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_B64; do
  [ -n "${!name:-}" ] || fail "configure environment secret $name"
done
[ "${IOS_TEAM_ID:-}" = D9AAN3VJK8 ] || fail 'confirm IOS_TEAM_ID=D9AAN3VJK8'
[ "${IOS_APP_GROUP:-}" = group.fail.still.iphone ] || fail 'confirm existing IOS_APP_GROUP=group.fail.still.iphone'
[ "${IOS_RELEASE_REVIEWED:-}" = true ] || fail 'environment IOS_RELEASE_REVIEWED must confirm migration, capabilities and encryption review'
[[ $IOS_SIGNING_SHA1 =~ ^[0-9A-Fa-f]{40}$ ]] || fail 'IOS_SIGNING_SHA1 must identify the Apple Distribution certificate'
[[ $ASC_KEY_ID =~ ^[A-Z0-9]{10}$ ]] || fail 'invalid ASC key ID'
umask 077
T=$(mktemp -d "$RUNNER_TEMP/mbui-testflight.XXXXXX")
KEYCHAIN=$T/signing.keychain-db
cleanup() { security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true; rm -rf "$T"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export API_PRIVATE_KEYS_DIR=$T/private_keys
mkdir "$API_PRIVATE_KEYS_DIR"
printf %s "$ASC_PRIVATE_KEY_B64" | base64 --decode > "$API_PRIVATE_KEYS_DIR/AuthKey_$ASC_KEY_ID.p8"
. "$D/testflight-asc.sh"
asc_preflight
printf %s "$IOS_DISTRIBUTION_P12_B64" | base64 --decode > "$T/certificate.p12"
printf %s "$IOS_APP_PROFILE_B64" | base64 --decode > "$T/app.mobileprovision"
printf %s "$IOS_SHARE_PROFILE_B64" | base64 --decode > "$T/share.mobileprovision"
# Verify both profiles before building/importing any key. Exact IDs, not wildcard profiles.
profile() {
  local kind=$1 bid=$2 p=$T/$1.plist expires i cert found=no
  security cms -D -i "$T/$kind.mobileprovision" > "$p"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$p")" = "$IOS_TEAM_ID" ] || fail "$kind profile team"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$p")" = "$IOS_TEAM_ID.$bid" ] || fail "$kind profile application identifier"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$p")" = "$IOS_TEAM_ID" ] || fail "$kind entitlement team"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$p")" = false ] || fail "$kind is not distribution"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:beta-reports-active' "$p")" = true ] || fail "$kind is not App Store distribution"
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$p" >/dev/null 2>&1 || fail "$kind is a device profile"
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$p" >/dev/null 2>&1 || fail "$kind is an enterprise profile"
  # PlistBuddy handles entitlement keys containing dots without key-path ambiguity.
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$p" > "$T/profile-entitlements.plist"
  plutil -convert json -o "$T/entitlements.json" "$T/profile-entitlements.plist"
  jq -e --arg group "$IOS_APP_GROUP" '."com.apple.security.application-groups" | index($group) != null' "$T/entitlements.json" >/dev/null || fail "$kind profile lacks existing app group"
  expires=$(plutil -extract ExpirationDate raw "$p")
  [ "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s)" -gt "$(date +%s)" ] || fail "$kind profile expired"
  i=0
  while cert=$(plutil -extract "DeveloperCertificates.$i" raw "$p" 2>/dev/null); do
    printf %s "$cert" | base64 --decode > "$T/cert.der"
    [ "$(openssl x509 -inform DER -in "$T/cert.der" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr 'a-f' 'A-F')" != "$(printf %s "$IOS_SIGNING_SHA1" | tr 'a-f' 'A-F')" ] || found=yes
    i=$((i+1))
  done
  [ "$found" = yes ] || fail "$kind profile does not authorize signing certificate"
  # Only entitlements used by this native app; never copy arbitrary profile permissions.
  jq -n --arg app "$IOS_TEAM_ID.$bid" --arg team "$IOS_TEAM_ID" --arg group "$IOS_APP_GROUP" \
    '{"application-identifier":$app,"com.apple.developer.team-identifier":$team,"com.apple.security.application-groups":[$group],"get-task-allow":false,"beta-reports-active":true}' > "$T/$kind.entitlements"
  plutil -convert xml1 "$T/$kind.entitlements"
}
profile app fail.still.iphone
profile share fail.still.iphone.share
export APP=stillfail MBUI_IOS_SDK=iphoneos MBUI_IOS_ID=fail.still.iphone
export MBUI_IOS_BUILD=$RELEASE_BUILD MBUI_IOS_VERSION=$RELEASE_VERSION EMBER=$PWD
bash "$D/ios.sh" build
APPDIR=$PWD/apps/mbui/out/ios-device/MBUI.app
SHARE=$APPDIR/PlugIns/Share.appex
for kind in app share; do
  bundle=$APPDIR; bid=fail.still.iphone
  if [ "$kind" = share ]; then bundle=$SHARE; bid=$bid.share; fi
  for pair in "CFBundleIdentifier=$bid" "CFBundleVersion=$RELEASE_BUILD" "CFBundleShortVersionString=$RELEASE_VERSION" "MBUIAppGroup=$IOS_APP_GROUP"; do
    [ "$(/usr/libexec/PlistBuddy -c "Print :${pair%%=*}" "$bundle/Info.plist")" = "${pair#*=}" ] || fail "built $kind ${pair%%=*} mismatch"
  done
  cp "$T/$kind.mobileprovision" "$bundle/embedded.mobileprovision"
done
password=$(openssl rand -hex 32)
security create-keychain -p "$password" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$password" "$KEYCHAIN"
security import "$T/certificate.p12" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" "$KEYCHAIN" >/dev/null
security find-identity -v -p codesigning "$KEYCHAIN" | grep -i "$IOS_SIGNING_SHA1.*Apple Distribution:" >/dev/null || fail 'not an available Apple Distribution identity'
# Known native bundle layout: fail on unexpected nested code rather than silently omit signing it.
[ "$(find "$APPDIR" -type d -name '*.appex' | wc -l | tr -d ' ')" = 1 ] || fail 'unexpected extensions'
[ "$(find "$APPDIR" -type d -name '*.framework' | wc -l | tr -d ' ')" = 1 ] || fail 'unexpected frameworks'
[ -d "$APPDIR/Frameworks/hermes.framework" ] || fail 'missing Hermes'
for bundle in "$APPDIR/Frameworks/hermes.framework" "$SHARE" "$APPDIR"; do
  ent=()
  [ "$bundle" != "$SHARE" ] || ent=(--entitlements "$T/share.entitlements")
  [ "$bundle" != "$APPDIR" ] || ent=(--entitlements "$T/app.entitlements")
  codesign --force --sign "$IOS_SIGNING_SHA1" --keychain "$KEYCHAIN" --generate-entitlement-der "${ent[@]}" "$bundle"
  codesign --verify --strict "$bundle"
done
codesign --verify --deep --strict "$APPDIR"
mkdir "$T/Payload"
cp -R "$APPDIR" "$T/Payload/"
(cd "$T" && zip -qry app.ipa Payload)
# Check again after build/sign, and after environment approval; no automatic retry of upload.
bash "$D/testflight-guard.sh" checkout
asc_preflight
# altool changed its option spelling in newer Xcode. Select from this runner's
# advertised help, never trial-upload/retry against Apple.
xcrun altool --help > "$T/altool-help.txt" 2>&1
if grep -q -- '--api-key ' "$T/altool-help.txt"; then
  xcrun altool --validate-app "$T/app.ipa" --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app -f "$T/app.ipa" --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
elif grep -q -- '--apiKey' "$T/altool-help.txt"; then
  xcrun altool --validate-app --file "$T/app.ipa" --type ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app --file "$T/app.ipa" --type ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  fail 'unsupported altool authentication syntax'
fi
echo "Upload accepted for 6818750243: $RELEASE_VERSION ($RELEASE_BUILD), $RELEASE_SHA. Processing/tester availability is NOT confirmed." >> "$GITHUB_STEP_SUMMARY"
