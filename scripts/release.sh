#!/bin/sh
# Builds the still.fail station's releases (the layout of scripts/station-bundle.sh) and puts them in the cloud's releases
# bucket, where install.sh (cloud/src/install.ts) gets them: this Mac's (darwin-arm64), and Linux's (linux-x64,
# linux-arm64, built from here: scripts/linux-station.sh).
# The apps too, for their updaters: `desktop` (apps/desktop/build.sh: the zip, its blockmap and stillfail-mac.yml, in desktop/) and
# `android` (apps/android/build.py --release: stillfail-<n>.apk and latest.json, in android/). Their version is the
# commits in the history, so a release is made from a new commit; the latest is put last, once its files are there.
#   release.sh [--beta] [PLATFORM…]   (default: the station's three; desktop and android only when named)
#   release.sh promote [station]
# --beta: to the test channel instead (cloud/src/install.ts): the station's tarballs in beta/ and station-beta.json; the
# beta apps, apps of their own beside the released ones (fail.still.desktop.beta: apps/desktop/build.sh --beta, its
# stillfail-beta-<version> zip and blockmap and its feed desktop/stillfail-beta-mac.yml, electron-updater's channel
# stillfail-beta; fail.still.android.beta: apps/android/build.py --release --beta, android/stillfail-beta-<n>.apk and
# android/beta/latest.json).
# promote: the test channel's station release becomes the stable one: its tarballs and station.json copied to the
# stable names, nothing built. (The beta apps are other apps: a released app is released by release.sh desktop/android.
# The web app is promoted by cloud/deploy.py promote-web.)
# RELEASE_DIR=dir: into that directory instead of the bucket (the dev cloud serves them from dist/releases: cloud/test/dev.ts).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# copy <name in the bucket> <new name> <content type>: within the bucket (or RELEASE_DIR).
copy() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$RELEASE_DIR/$1" "$RELEASE_DIR/$2" && echo "copied $1 to $2 in $RELEASE_DIR"
  else
    (cd "$root/cloud" && pnpm exec wrangler r2 object get "stillfail-releases/$1" --file "$out/copy" --remote >/dev/null)
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "stillfail-releases/$2" --file "$out/copy" --content-type "$3" --remote >/dev/null)
    rm -f "$out/copy"
    echo "copied $1 to $2"
  fi
}

if [ "${1:-}" = promote ]; then
  shift
  for what in ${*:-station}; do
    case $what in
      # The tarballs first, the feed that says they are out last.
      station)
        for platform in darwin-arm64 linux-x64 linux-arm64; do copy "beta/stillfail-station-$platform.tar.gz" "stillfail-station-$platform.tar.gz" application/gzip; done
        copy station-beta.json station.json application/json
        ;;
      *) echo "promote what? only the station (the beta apps are apps of their own: release.sh desktop or android releases the stable ones), not $what" >&2; exit 2 ;;
    esac
  done
  exit 0
fi

beta=""
if [ "${1:-}" = --beta ]; then beta=yes; shift; fi
[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || { echo "releases are made on a Mac with Apple silicon" >&2; exit 1; }
platforms=${*:-darwin-arm64 linux-x64 linux-arm64}

# put <file> <name in the bucket> <content type>
put() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$1" "$RELEASE_DIR/$2" && echo "put $2 in $RELEASE_DIR"
  else
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "stillfail-releases/$2" --file "$1" --content-type "$3" --remote >/dev/null)
    echo "uploaded $2 ($(du -h "$1" | cut -f1))"
  fi
}

build=$(git -C "$root" rev-list --count HEAD)
[ -z "$(git -C "$root" status --porcelain)" ] || echo "note: the working tree has changes; the apps are numbered by the commit ($build) all the same" >&2

for platform in $platforms; do
  case $platform in
    desktop)
      # The app (fail.still.desktop) on its feed, stillfail-mac.yml; with --beta the beta app (fail.still.desktop.beta)
      # on stillfail-beta-mac.yml.
      sh "$root/apps/desktop/build.sh" ${beta:+--beta}
      zip="stillfail${beta:+-beta}-0.1.$build-arm64-mac.zip"
      feed="stillfail${beta:+-beta}-mac.yml"
      put "$root/apps/desktop/out/$zip" "desktop/$zip" application/zip
      put "$root/apps/desktop/out/$zip.blockmap" "desktop/$zip.blockmap" application/octet-stream
      put "$root/apps/desktop/out/$feed" "desktop/$feed" "text/yaml; charset=utf-8"
      ;;
    android)
      # fail.still.android on android/latest.json; with --beta fail.still.android.beta on android/beta/latest.json.
      ORG_GRADLE_PROJECT_stillfailBuild=$build python3 "$root/apps/android/build.py" --release ${beta:+--beta} --tasks :app:assembleRelease
      apk="$root/apps/android/app/build/outputs/apk/release/app-release.apk"
      name="stillfail${beta:+-beta}-$build.apk"
      put "$apk" "android/$name" application/vnd.android.package-archive
      printf '{"versionCode":%s,"versionName":"0.1.%s","file":"android/%s","sha256":"%s","size":%s}\n' \
        "$build" "$build" "$name" "$(shasum -a 256 "$apk" | cut -d' ' -f1)" "$(wc -c < "$apk" | tr -d ' ')" > "$out/latest.json"
      put "$out/latest.json" "android/${beta:+beta/}latest.json" application/json
      ;;
    *)
      sh "$root/scripts/station-bundle.sh" "$out/$platform" "$platform"
      # Under the new name only: the old name (ember-station-*.tar.gz) keeps the last release from before the rename,
      # for the cloud's installer from before it, which would not know this layout (cloud/src/install.ts).
      file="stillfail-station-$platform.tar.gz"
      tar -czf "$out/$file" -C "$out/$platform" stillfail
      put "$out/$file" "${beta:+beta/}$file" application/gzip
      station=yes
      ;;
  esac
done
# What stations read to say a newer release is out (mesh/app/src/updates.rs), once its files are there.
if [ -n "${station:-}" ]; then
  printf '{"version":"0.1.%s","build":%s,"commit":"%s"}\n' "$build" "$build" "$(git -C "$root" rev-parse HEAD)" > "$out/station.json"
  put "$out/station.json" "station${beta:+-beta}.json" application/json
fi
