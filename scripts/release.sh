#!/bin/sh
# Builds the still.fail station's releases (the station in TypeScript, laid out by scripts/station-bundle.sh) and puts
# them in the cloud's releases bucket, where install.sh (cloud/src/install.ts) gets them: darwin-arm64, linux-x64 and
# linux-arm64, each with its Node and its native parts (prebuilt for that platform: scripts/native.ts).
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
# A station's release names the Node it runs on (its NODE_VERSION), which is not in it: that Node goes beside the releases, once
# per version (node/node-v<version>-<platform>.tar.gz and its .sha256: scripts/node-dist.sh), when they lack it.
# RELEASE_DIR=dir: into that directory instead of the bucket (the dev cloud serves them from dist/releases: cloud/test/dev.ts).
# RELEASES=<url>: where the releases are read from, to see whether a Node is there already (still.fail cloud's; "" with
# RELEASE_DIR: only that directory is looked in).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# r2 <get|put> <key> <wrangler's other arguments>: the bucket's object, tried again twice when Cloudflare's API fails on
# the way (a 502, "fetch failed": three releases stopped on one on 2026-10-02); putting or getting it again is harmless.
r2() {
  verb=$1 key=$2; shift 2
  for try in 1 2 3; do
    (cd "$root/cloud" && pnpm exec wrangler r2 object "$verb" "stillfail-releases/$key" "$@" --remote >/dev/null) && return 0
    [ $try = 3 ] || { echo "r2 $verb $key failed (try $try), trying again" >&2; sleep 15; }
  done
  return 1
}

# copy <name in the bucket> <new name> <content type>: within the bucket (or RELEASE_DIR).
copy() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$RELEASE_DIR/$1" "$RELEASE_DIR/$2" && echo "copied $1 to $2 in $RELEASE_DIR"
  else
    r2 get "$1" --file "$out/copy"
    r2 put "$2" --file "$out/copy" --content-type "$3"
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
platforms=${*:-darwin-arm64 linux-x64 linux-arm64}
for platform in $platforms; do
  if [ "$platform" != android ] && [ "$(uname -s)-$(uname -m)" != Darwin-arm64 ]; then
    echo "$platform releases require a Mac with Apple silicon" >&2; exit 1
  fi
done

# put <file> <name in the bucket> <content type>
put() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$1" "$RELEASE_DIR/$2" && echo "put $2 in $RELEASE_DIR"
  else
    r2 put "$2" --file "$1" --content-type "$3"
    echo "uploaded $2 ($(du -h "$1" | cut -f1))"
  fi
}

build=$(git -C "$root" rev-list --count HEAD)
releases=${RELEASES-https://app.still.fail/releases}
# Whether the releases have <name> already: in RELEASE_DIR, or where they are read from.
released() {
  # Its first byte asked for: the releases answer GET (ranges too), not HEAD.
  { [ -n "${RELEASE_DIR:-}" ] && [ -f "$RELEASE_DIR/$1" ]; } || { [ -n "$releases" ] && curl -fs -r 0-0 -o /dev/null "$releases/$1"; }
}
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
      # Packed and put beside the next platform's bundling (each ~20 s, one after another before 2026-10-04).
      file="stillfail-station-$platform.tar.gz"
      (tar -czf "$out/$file" -C "$out/$platform" stillfail && put "$out/$file" "${beta:+beta/}$file" application/gzip) &
      putting="${putting:-} $!"
      # Its Node, unless the releases have that version already.
      node_file="node/node-v$(cat "$root/.node-version")-$platform.tar.gz"
      if ! released "$node_file"; then
        dist=$(sh "$root/scripts/node-dist.sh" "$out/node-$platform" "$platform")
        put "$dist" "$node_file" application/gzip
        put "$dist.sha256" "$node_file.sha256" "text/plain; charset=utf-8"
      fi
      station=yes
      ;;
  esac
done
for pid in ${putting:-}; do wait "$pid" || { echo "a station release was not put" >&2; exit 1; }; done
# What stations read to say a newer release is out (station/src/updates/updates.ts), once its files are there.
if [ -n "${station:-}" ]; then
  printf '{"version":"0.1.%s","build":%s,"commit":"%s"}\n' "$build" "$build" "$(git -C "$root" rev-parse HEAD)" > "$out/station.json"
  put "$out/station.json" "station${beta:+-beta}.json" application/json
fi
