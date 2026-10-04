#!/bin/sh
# Puts releases made into a directory (scripts/release.sh with RELEASE_DIR) in the cloud's releases bucket, under the
# same names: the files first, then the feeds that say they are out (station*.json, android/…/latest.json,
# desktop/*-mac.yml), so nothing points at a file not there yet. CI builds the Android app beside the check and puts it
# once the check passed (.github/workflows/pipeline.yml: android, android-put).
#   release-put.sh <dir>…
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

# put <name in the bucket> <file> <content type>, tried again twice when Cloudflare's API fails on the way.
put() {
  for try in 1 2 3; do
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "stillfail-releases/$1" --file "$2" --content-type "$3" --remote >/dev/null) && {
      echo "uploaded $1 ($(du -h "$2" | cut -f1))"; return 0; }
    [ $try = 3 ] || { echo "putting $1 failed (try $try), trying again" >&2; sleep 15; }
  done
  return 1
}
type_of() {
  case $1 in
    *.json) echo application/json ;;
    *.yml) echo "text/yaml; charset=utf-8" ;;
    *.tar.gz) echo application/gzip ;;
    *.zip) echo application/zip ;;
    *.apk) echo application/vnd.android.package-archive ;;
    *) echo application/octet-stream ;;
  esac
}
feed() { case $1 in station*.json | */latest.json | desktop/*-mac.yml) return 0 ;; *) return 1 ;; esac; }

for dir in "$@"; do
  [ -d "$dir" ] || { echo "no releases in $dir" >&2; exit 1; }
  names=$(cd "$dir" && find . -type f | sed 's|^\./||' | sort)
  [ -n "$names" ] || { echo "no releases in $dir" >&2; exit 1; }
  for pass in files feeds; do
    for name in $names; do
      if feed "$name"; then [ $pass = feeds ] || continue; else [ $pass = files ] || continue; fi
      put "$name" "$dir/$name" "$(type_of "$name")"
    done
  done
done
