#!/bin/sh
# scripts/release.sh --beta in CI (.github/workflows/pipeline.yml): the test channel's station release (its four
# platforms) or test app (android), uploaded to the releases bucket. What it needs comes from the environment's secrets
# and is removed after: POSTHOG_JSON (the key the station and the Android app report errors with), ANDROID_DEBUG_KEYSTORE_B64 (the key
# every Android release is signed with: studio's ~/.android/debug.keystore; another would stop installed apps updating),
# CLOUDFLARE_API_TOKEN (the bucket; without it, the machine's own `wrangler login`).
#   sh .github/release.sh [--stable] station|android|modules
set -eu
beta=--beta
if [ "${1:-}" = --stable ]; then beta=""; shift; fi
cd "$(dirname "$0")/.."
pnpm install --frozen-lockfile --prefer-offline > /dev/null
(cd cloud && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/stillfail-release.XXXXXX")
trap 'rm -rf "$dir"' EXIT
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || unset CLOUDFLARE_API_TOKEN
if [ -n "${POSTHOG_JSON:-}" ]; then (umask 077 && printf '%s' "$POSTHOG_JSON" > "$dir/posthog.json"); export STILLFAIL_POSTHOG="$dir/posthog.json"; fi

case "${1:?usage: release.sh station|android|modules}" in
  station)
    # The station in TypeScript, bundled for each platform (scripts/station-bundle.sh) with its native parts prebuilt:
    # the natives job before this one built and published those of this commit (all four platforms).
    (cd station && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
    # The native parts signed with the desktop app's identity (.github/sign-station.sh): macOS keeps the launcher's
    # Local Network grant across releases. Without the signing keychain (.github/mac_signing.py), a warning and ad hoc parts.
    if [ -n "${MACOS_DEVELOPER_ID_KEYCHAIN_B64_1:-}" ] && [ -n "${KEYCHAIN_PASSWORD_AFK:-}" ]; then export STILLFAIL_SIGN_STATION=1
    else echo "::warning::no signing keychain: the station's native parts are ad hoc, and macOS asks for the local network again after an update"; fi
    sh scripts/release.sh ${beta:+$beta}
    ;;
  android)
    [ -n "${ANDROID_DEBUG_KEYSTORE_B64:-}" ] || { echo "ANDROID_DEBUG_KEYSTORE_B64 is not set: not releasing an app installed ones could not update to"; exit 1; }
    # The Android Gradle plugin signs with $ANDROID_USER_HOME/debug.keystore (signingConfigs.debug): this one, not the runner's.
    mkdir -p "$dir/android"
    printf '%s' "$ANDROID_DEBUG_KEYSTORE_B64" | base64 -d > "$dir/android/debug.keystore"
    export ANDROID_USER_HOME="$dir/android"
    # (scripts/release.sh verifies the APK, mbui's stable or beta, and that it is signed with studio's key
    # before putting it, and prints the certificate)
    sh scripts/release.sh ${beta:+$beta} android
    ;;
  modules)
    # The modules' packages (scripts/module-bundle.ts): plain files, signed; nothing of the machine's in them. Each
    # entry bundled by the station's esbuild (its packages installed for it).
    (cd station && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
    sh scripts/release.sh ${beta:+$beta} modules
    ;;
  *) echo "no such release: $1"; exit 2 ;;
esac
