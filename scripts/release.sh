#!/bin/sh
# Builds the still.fail station's releases (the layout of scripts/station-bundle.sh) and puts them in the cloud's releases
# bucket, where install.sh (cloud/src/install.ts) gets them: this Mac's (darwin-arm64), and Linux's (linux-x64,
# linux-arm64, built from here: scripts/linux-station.sh).
# The apps too, for their updaters: `desktop` (apps/desktop/build.sh: the zip and stillfail-mac.yml, in desktop/) and
# `android` (apps/android/build.py --release: stillfail-<n>.apk and latest.json, in android/). Their version is the
# commits in the history, so a release is made from a new commit; the latest is put last, once its files are there.
#   release.sh [PLATFORM…]   (default: the station's three; desktop and android only when named)
# RELEASE_DIR=dir: into that directory instead of the bucket (the dev cloud serves them from dist/releases: cloud/test/dev.ts).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || { echo "releases are made on a Mac with Apple silicon" >&2; exit 1; }
platforms=${*:-darwin-arm64 linux-x64 linux-arm64}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# put <file> <name in the bucket> <content type>
put() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$1" "$RELEASE_DIR/$2" && echo "put $2 in $RELEASE_DIR"
  else
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "ember-releases/$2" --file "$1" --content-type "$3" --remote >/dev/null)
    echo "uploaded $2 ($(du -h "$1" | cut -f1))"
  fi
}

build=$(git -C "$root" rev-list --count HEAD)
[ -z "$(git -C "$root" status --porcelain)" ] || echo "note: the working tree has changes; the apps are numbered by the commit ($build) all the same" >&2

for platform in $platforms; do
  case $platform in
    desktop)
      # The app (fail.still.desktop) on its feed, stillfail-mac.yml.
      sh "$root/apps/desktop/build.sh"
      zip="stillfail-0.1.$build-arm64-mac.zip"
      put "$root/apps/desktop/out/$zip" "desktop/$zip" application/zip
      put "$root/apps/desktop/out/stillfail-mac.yml" desktop/stillfail-mac.yml "text/yaml; charset=utf-8"
      ;;
    android)
      ORG_GRADLE_PROJECT_stillfailBuild=$build python3 "$root/apps/android/build.py" --release --tasks :app:assembleRelease
      apk="$root/apps/android/app/build/outputs/apk/release/app-release.apk"
      put "$apk" "android/stillfail-$build.apk" application/vnd.android.package-archive
      printf '{"versionCode":%s,"versionName":"0.1.%s","file":"android/stillfail-%s.apk","sha256":"%s","size":%s}\n' \
        "$build" "$build" "$build" "$(shasum -a 256 "$apk" | cut -d' ' -f1)" "$(wc -c < "$apk" | tr -d ' ')" > "$out/latest.json"
      put "$out/latest.json" android/latest.json application/json
      ;;
    *)
      sh "$root/scripts/station-bundle.sh" "$out/$platform" "$platform"
      # Under the new name only: the old name (ember-station-*.tar.gz) keeps the last release from before the rename,
      # for the cloud's installer from before it, which would not know this layout (cloud/src/install.ts).
      file="stillfail-station-$platform.tar.gz"
      tar -czf "$out/$file" -C "$out/$platform" stillfail
      put "$out/$file" "$file" application/gzip
      station=yes
      ;;
  esac
done
# What stations read to say a newer release is out (mesh/app/src/updates.rs), once its files are there.
if [ -n "${station:-}" ]; then
  printf '{"version":"0.1.%s","build":%s,"commit":"%s"}\n' "$build" "$build" "$(git -C "$root" rev-parse HEAD)" > "$out/station.json"
  put "$out/station.json" station.json application/json
fi
