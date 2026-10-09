#!/bin/sh
# Puts releases made into a directory (scripts/release.sh or .github/release-desktop.py with RELEASE_DIR) in the
# cloud's releases bucket, under the same names: the files first, side by side, then the feeds that say they are out
# (station*.json, android/…/latest.json, desktop/*.yml), so nothing points at a file not there yet.
# CI builds the releases beside the check: an app's files, named by their version, are put by its own job at once
# (nothing points at them yet: --files); the station's, named the same each time, and every feed, once the check
# passed (.github/workflows/pipeline.yml, put). --files takes each file it put out of the directory, leaving the feeds
# for the put after.
#   release-put.sh [--files | --feeds] <dir>…
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

# The account the bucket is in, for Cloudflare's API: asked once (empty when the token cannot say).
account_id=${CLOUDFLARE_ACCOUNT_ID:-}
if [ -z "$account_id" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  account_id=$(curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts" 2>/dev/null \
    | grep -o '"id":"[0-9a-f]\{32\}"' | head -1 | cut -d'"' -f4) || account_id=""
fi
# The object put straight through Cloudflare's API, as wrangler does it, without its start-up and at the speed the line
# has (a 148 MB zip took wrangler ~45 s from mini1, whose upload is ~5.5 MB/s): wrangler when that cannot be done.
api_put() {
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "$account_id" ] || return 1
  curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: $3" -T "$2" \
    "https://api.cloudflare.com/client/v4/accounts/$account_id/r2/buckets/stillfail-releases/objects/$1" > /dev/null
}
# put <name in the bucket> <file> <content type>, tried again twice when Cloudflare's API fails on the way.
put() {
  for try in 1 2 3; do
    how=api
    { api_put "$@" || { how=wrangler; (cd "$root/cloud" && pnpm exec wrangler r2 object put "stillfail-releases/$1" --file "$2" --content-type "$3" --remote >/dev/null); }; } && {
      echo "uploaded $1 ($(du -h "$2" | cut -f1), $how)"; return 0; }
    [ $try = 3 ] || { echo "putting $1 failed (try $try), trying again" >&2; sleep 15; }
  done
  return 1
}
type_of() {
  case $1 in
    *.json) echo application/json ;;
    *.yml) echo "text/yaml; charset=utf-8" ;;
    *.tar.gz) echo application/gzip ;;
    *.sha256) echo "text/plain; charset=utf-8" ;;
    *.zip) echo application/zip ;;
    *.apk) echo application/vnd.android.package-archive ;;
    *) echo application/octet-stream ;;
  esac
}
feed() { case $1 in station*.json | */latest.json | desktop/*.yml) return 0 ;; *) return 1 ;; esac; }
# What a pass puts: a Node first (a station's release that names it is fetched by its fixed name, not through a feed),
# then the other files, then the feeds.
pass_of() { case $1 in node/*) echo node ;; *) if feed "$1"; then echo feeds; else echo files; fi ;; esac; }

passes="node files feeds"
taken=""
case "${1:-}" in --files) passes="node files"; taken=yes; shift ;; --feeds) passes=feeds; shift ;; esac
for dir in "$@"; do
  [ -d "$dir" ] || { echo "no releases in $dir" >&2; exit 1; }
  names=$(cd "$dir" && find . -type f | sed 's|^\./||' | sort)
  for pass in $passes; do
    pids=""
    for name in $names; do
      [ "$(pass_of "$name")" = "$pass" ] || continue
      { put "$name" "$dir/$name" "$(type_of "$name")" && if [ -n "$taken" ]; then rm "$dir/$name"; fi; } &
      pids="$pids $!"
    done
    for pid in $pids; do wait "$pid" || { echo "not all of $dir was put" >&2; exit 1; }; done
  done
done
