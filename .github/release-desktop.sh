#!/bin/sh
# Build and sign mbui's Mac app with the existing Developer ID and notary profile. The app's core installs its
# own dependencies when it needs to build bytecode; the website's root packages are not part of this release.
#   sh .github/release-desktop.sh [--product monoid] [--stable] [--out DIR]
# --product monoid: monoid's Mac app (scripts/release.sh --product), for monoid's bucket.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
beta=--beta suffix=-beta channel=beta/ out= product=stillfail
while [ "$#" -gt 0 ]; do
  case "$1" in
    --product) shift; product=${1:?--product needs a name} ;;
    --stable) beta= suffix= channel= ;;
    --out) shift; out=${1:?--out needs a directory} ;;
    *) echo "release-desktop: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$out" ]; then
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || { echo "CLOUDFLARE_API_TOKEN is required" >&2; exit 1; }
  (cd cloud && pnpm install --frozen-lockfile --prefer-offline)
fi
dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/stillfail-release.XXXXXX")
trap 'rm -rf "$dir"' EXIT
if [ -n "${POSTHOG_JSON:-}" ]; then
  (umask 077 && printf '%s' "$POSTHOG_JSON" > "$dir/posthog.json")
  export STILLFAIL_POSTHOG="$dir/posthog.json"
fi
unset UNSIGNED
export RELEASE_DIR="$dir/releases"
# The signing helper removes its secrets from the child's environment. release.sh checks the signed archive's
# identifier, team and build before making either the mbui or the older Electron updater's feed.
# shellcheck disable=SC2046 # --product and its value, two words, another product's alone
python3 .github/mac_signing.py run -- sh scripts/release.sh $([ "$product" = stillfail ] || echo --product "$product") ${beta:+$beta} desktop
version=$(git rev-list --count HEAD)
set -- "desktop/$product$suffix-0.1.$version-arm64-mac.zip" "mac/${channel}latest.json"
# (electron-updater's feed: still.fail's alone, which had an Electron app)
[ "$product" != stillfail ] || set -- "$@" "desktop/stillfail$suffix-mac.yml"
for name do
  [ -f "$RELEASE_DIR/$name" ] || { echo "Expected desktop artifact missing: $name" >&2; exit 1; }
done
for name do
  if [ -n "$out" ]; then
    mkdir -p "$out/$(dirname "$name")"
    cp -p "$RELEASE_DIR/$name" "$out/$name"
  fi
done
if [ -z "$out" ]; then
  # Put here, the deltas from the builds before made first (scripts/release-deltas.ts: never a reason not to put it;
  # with --out, the job putting it makes them: .github/workflows/pipeline.yml deltas).
  releases=https://app.still.fail/releases
  [ "$product" = stillfail ] || releases=https://app.$product.build/releases
  node scripts/release-deltas.ts "$RELEASE_DIR" --releases "$releases" --deadline "${STILLFAIL_DELTAS_SECONDS:-90}" || echo "release-desktop: no deltas" >&2
  sh "$root/scripts/release-put.sh" "$RELEASE_DIR"
fi
