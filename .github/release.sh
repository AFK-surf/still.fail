#!/bin/sh
# scripts/release.sh --beta in CI (.github/workflows/pipeline.yml): the test channel's station release (its three
# platforms) or test app (android), uploaded to the releases bucket. What it needs comes from the environment's secrets
# and is removed after: POSTHOG_JSON (the key the station reports errors with), ANDROID_DEBUG_KEYSTORE_B64 (the key
# every Android release is signed with: studio's ~/.android/debug.keystore; another would stop installed apps updating),
# CLOUDFLARE_API_TOKEN (the bucket; without it, the machine's own `wrangler login`).
#   sh .github/release.sh station|android
set -eu
cd "$(dirname "$0")/.."
pnpm install --frozen-lockfile --prefer-offline > /dev/null
(cd cloud && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/stillfail-release.XXXXXX")
trap 'rm -rf "$dir"' EXIT
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || unset CLOUDFLARE_API_TOKEN
if [ -n "${POSTHOG_JSON:-}" ]; then (umask 077 && printf '%s' "$POSTHOG_JSON" > "$dir/posthog.json"); export STILLFAIL_POSTHOG="$dir/posthog.json"; fi

case "${1:?usage: release.sh station|android}" in
  station)
    # station-bundle.sh takes darwin-arm64's stillfail-station from mesh/target; built in the runner's own target,
    # kept between runs (the checkout's is cleaned each time), and put there.
    (cd mesh && cargo build --release -p stillfail-station)
    mkdir -p mesh/target/release
    cp "$CARGO_TARGET_DIR/release/stillfail-station" mesh/target/release/
    export LINUX_TARGET_DIR="$CARGO_TARGET_DIR/linux"
    sh scripts/release.sh --beta
    ;;
  android)
    [ -n "${ANDROID_DEBUG_KEYSTORE_B64:-}" ] || { echo "ANDROID_DEBUG_KEYSTORE_B64 is not set: not releasing an app installed ones could not update to"; exit 1; }
    # The Android Gradle plugin signs with $ANDROID_USER_HOME/debug.keystore (signingConfigs.debug): this one, not the runner's.
    mkdir -p "$dir/android"
    printf '%s' "$ANDROID_DEBUG_KEYSTORE_B64" | base64 -d > "$dir/android/debug.keystore"
    export ANDROID_USER_HOME="$dir/android"
    sh scripts/release.sh --beta android
    apk=apps/android/app/build/outputs/apk/release/app-release.apk
    # The certificate it was signed with: the same SHA-256 every time (studio's key).
    "${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/36.0.0/apksigner" verify --print-certs "$apk" | grep -i "SHA-256" || true
    ;;
  *) echo "no such release: $1"; exit 2 ;;
esac
