#!/bin/sh
# Puts releases made into a directory (scripts/release.sh or .github/release-desktop.sh with RELEASE_DIR) in the
# cloud's releases bucket, under the same names: the files first, side by side, then the feeds that say they are out
# (station*.json, …/latest.json, desktop/*.yml, modules/<id>/*.json), so nothing points at a
# file not there yet.
# CI builds the releases beside the check: an app's files, named by their version, are put by its own job at once
# (nothing points at them yet: --files); the station's, named the same each time, and every feed, once the check
# passed (.github/workflows/pipeline.yml, put). --files takes each file it put out of the directory, leaving the feeds
# for the put after.
# --stage (the station's job, on the CI Mac): its files put in the bucket at once all the same, under staged/<when>-<commit>/,
# not carried to the put in a run artifact (that went up through the proxy the CI Mac's DNS sends GitHub to, 40 MB a release,
# 2026-10-23): each left in the directory as <name>.staged, saying where it is. A put finding one takes the file back
# from there first, and deletes it there once all is put (scripts/release-prune.ts deletes what stays after two days).
# --unstage <dir>: what was staged taken back into <dir> beside its marker (the job making the release's deltas needs the
# station's archives: scripts/release-deltas.ts); a put after takes the marker as taken, and deletes the staged copy.
#   release-put.sh [--files | --feeds | --stage | --unstage] <dir>…
#   release-put.sh --hand <dir> | --unhand <dir> <name>… | --drop <name>…
#   release-put.sh --clean-uploaded <name> <local copy>
set -eu
root=${STILLFAIL_RELEASE_TOOLS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

# STILLFAIL_DIRECT_DNS (the CI Mac's CI jobs: .github/actions/setup-mac): Cloudflare's API reached directly, by the address
# that DNS server gives, not through the machine's own (the proxy on the home network, whose line went down for hours twice on
# 2026-10-21 and failed two releases' puts; directly the upload is ~4.5 MB/s against ~5.5). Unanswered: as before.
direct=""
# (every curl to Cloudflare's API given up when its connection is not made in 15 s or stalls under 1 KB/s for 20 s,
# the put tried again or wrangler's after: a TLS handshake to the direct address that never finished held the curl
# for its own default of 300 s, the release's Android and Mac puts 5 minutes each, 2026-10-31)
limits="--connect-timeout 15 --speed-limit 1024 --speed-time 20"
if [ -n "${STILLFAIL_DIRECT_DNS:-}" ]; then
  ip=$(dig +short +time=3 +tries=2 @"$STILLFAIL_DIRECT_DNS" api.cloudflare.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1) || ip=""
  if [ -n "$ip" ]; then direct="--resolve api.cloudflare.com:443:$ip"; echo "Cloudflare's API directly, at $ip"
  else echo "Cloudflare's API: $STILLFAIL_DIRECT_DNS gave no address; through the machine's own DNS" >&2; fi
fi
# The account the bucket is in, for Cloudflare's API: asked once (empty when the token cannot say).
account_id=${CLOUDFLARE_ACCOUNT_ID:-}
if [ -z "$account_id" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  # shellcheck disable=SC2086 # direct is words
  account_id=$(curl $direct $limits -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts" 2>/dev/null \
    | grep -o '"id":"[0-9a-f]\{32\}"' | head -1 | cut -d'"' -f4) || account_id=""
fi
# The object put straight through Cloudflare's API, as wrangler does it, without its start-up and at the speed the line
# has (a 148 MB zip took wrangler ~45 s from the CI Mac, whose upload is ~5.5 MB/s): wrangler when that cannot be done.
# R2's answer names the object's MD5 as it was written (its etag, one request's upload): the same as the file's, it is
# in the bucket as made, said where STILLFAIL_PUT_RECEIPTS names a directory (apps/mbui/scripts/beta.sh: then not
# fetched back whole to be compared, 20-105 s of GitHub's runners now and then, main ae77ba19, 2a233edf, 2026-11-02).
api_put() {
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "$account_id" ] || return 1
  answer=$(mktemp)
  # shellcheck disable=SC2086 # direct is words
  curl $direct $limits -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: $3" -T "$2" \
    "https://api.cloudflare.com/client/v4/accounts/$account_id/r2/buckets/stillfail-releases/objects/$1" > "$answer" || { rm -f "$answer"; return 1; }
  etag=$(grep -o '"etag":"[0-9a-f]\{32\}"' "$answer" | head -1 | cut -d'"' -f4) || etag=""
  rm -f "$answer"
  if [ -n "${STILLFAIL_PUT_RECEIPTS:-}" ] && [ -n "$etag" ] && [ "$etag" = "$(md5_of "$2")" ]; then
    mkdir -p "$STILLFAIL_PUT_RECEIPTS" && printf '%s\n' "$etag" > "$STILLFAIL_PUT_RECEIPTS/$(printf %s "$1" | tr / _)"
  fi
  return 0
}
md5_of() { if command -v md5sum > /dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }
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
# get <name in the bucket> <file>, and drop <name in the bucket>: as put, through Cloudflare's API or wrangler.
api_get() {
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "$account_id" ] || return 1
  # shellcheck disable=SC2086 # direct is words
  curl $direct $limits -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -o "$2" \
    "https://api.cloudflare.com/client/v4/accounts/$account_id/r2/buckets/stillfail-releases/objects/$1"
}
get() {
  for try in 1 2 3; do
    { api_get "$@" || (cd "$root/cloud" && pnpm exec wrangler r2 object get "stillfail-releases/$1" --file "$2" --remote >/dev/null); } && return 0
    [ $try = 3 ] || { echo "getting $1 failed (try $try), trying again" >&2; sleep 15; }
  done
  return 1
}
# A build's warm directory holds a second copy of the signed Mac archive. Remove it only after reading the object back
# from R2 and comparing every byte. If the read or comparison fails, keep the local copy for a retry.
clean_uploaded() {
  [ -f "$2" ] || return 0
  back=$(mktemp)
  if get "$1" "$back" && cmp -s "$back" "$2"; then
    rm -f "$back"
    rm -f "$2" || { echo "could not remove $2" >&2; return 1; }
    echo "removed uploaded local copy of $1"
  else
    rm -f "$back"
    echo "could not verify $1 in R2; kept $2" >&2
    return 1
  fi
}
# --files receives a staging copy. The optional source identifies the warm build copy of this one object; compare
# them before cleaning it, so a later build with a different file at that path cannot be removed accidentally.
clean_cache_copy() {
  [ "$1" = "${STILLFAIL_RELEASE_CACHE_KEY:-}" ] || return 0
  source=${STILLFAIL_RELEASE_CACHE_SOURCE:-}
  [ -n "$source" ] && [ -f "$source" ] || return 0
  if ! cmp -s "$2" "$source"; then
    echo "local copy of $1 differs from the upload; kept $source" >&2
    return 0
  fi
  clean_uploaded "$1" "$source"
}
drop() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "$account_id" ]; then
    # shellcheck disable=SC2086 # direct is words
    curl $direct $limits -fsS -X DELETE -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$account_id/r2/buckets/stillfail-releases/objects/$1" > /dev/null && return 0
  fi
  (cd "$root/cloud" && pnpm exec wrangler r2 object delete "stillfail-releases/$1" --remote >/dev/null)
}
type_of() {
  case $1 in
    *.json) echo application/json ;;
    *.yml) echo "text/yaml; charset=utf-8" ;;
    *.tar.gz) echo application/gzip ;;
    *.sha256) echo "text/plain; charset=utf-8" ;;
    *.zip) echo application/zip ;;
    *.apk) echo application/vnd.android.package-archive ;;
    *.zst) echo application/zstd ;;
    *.xz) echo application/x-xz ;;
    *) echo application/octet-stream ;;
  esac
}
feed() { case $1 in station*.json | */latest.json | desktop/*.yml | modules/*.json) return 0 ;; *) return 1 ;; esac; }
# What a pass puts: a Node first (a station's release that names it is fetched by its fixed name, not through a feed),
# then the other files, then the feeds.
pass_of() { case $1 in node/*) echo node ;; *) if feed "$1"; then echo feeds; else echo files; fi ;; esac; }

passes="node files feeds"
taken=""
case "${1:-}" in
  --files) passes="node files"; taken=yes; shift ;;
  --feeds) passes=feeds; shift ;;
  --unstage)
    shift
    for dir in "$@"; do
      for marker in $(cd "$dir" && find . -type f -name '*.staged' | sed 's|^\./||' | sort); do
        file="$dir/${marker%.staged}"
        [ -f "$file" ] && continue
        get "$(cat "$dir/$marker")" "$file.part" || { rm -f "$file.part"; echo "could not get ${marker%.staged} back" >&2; exit 1; }
        mv "$file.part" "$file"; echo "got ${marker%.staged} back"
      done
    done
    exit 0 ;;
  --clean-uploaded)
    [ "$#" -eq 3 ] || { echo "usage: release-put.sh --clean-uploaded <name> <local copy>" >&2; exit 1; }
    clean_uploaded "$2" "$3"
    exit 0 ;;
  --stage)
    shift
    stage="staged/$(date -u +%s)-${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD)}"
    for dir in "$@"; do
      [ -d "$dir" ] || { echo "no releases in $dir" >&2; exit 1; }
      pids=""
      for name in $(cd "$dir" && find . -type f ! -name '*.staged' | sed 's|^\./||' | sort); do
        if feed "$name"; then continue; fi
        { put "$stage/$name" "$dir/$name" "$(type_of "$name")" && printf '%s\n' "$stage/$name" > "$dir/$name.staged" && rm "$dir/$name"; } &
        pids="$pids $!"
      done
      for pid in $pids; do wait "$pid" || { echo "not all of $dir was staged" >&2; exit 1; }; done
    done
    exit 0 ;;
  # --hand <dir>: what is left in a job's directory (its feeds, the .staged markers), as one tar, put under staged/
  # as --stage puts files, its name said on stdout: what a job on the CI Mac hands the put, not in a run artifact (whose
  # upload, through the proxy the CI Mac's DNS sends GitHub to, broke off: ECONNRESET, main's android 09a022da and 5c89fdd1,
  # 2026-10-29). --unhand <dir> <name>…: each taken back into <dir>, left there for a rerun of the put until --drop
  # <name>… deletes it once all is put (deleted as soon as it was taken back, a put cancelled on the way left its rerun
  # nothing to take back: 404, main 912c3551, 2026-11-03).
  --hand)
    dir=$2; [ -d "$dir" ] || { echo "no releases in $dir" >&2; exit 1; }
    key="staged/$(date -u +%s)-${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD)}/hand-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n').tar"
    # (COPYFILE_DISABLE: macOS's tar without its ._ files of each file's extended attributes)
    tar_=$(mktemp); (cd "$dir" && COPYFILE_DISABLE=1 tar -cf "$tar_" .)
    put "$key" "$tar_" application/x-tar >&2; rm -f "$tar_"
    echo "$key"; exit 0 ;;
  --unhand)
    dir=$2; shift 2; mkdir -p "$dir"
    for key in "$@"; do
      tar_=$(mktemp); get "$key" "$tar_" || { echo "could not get $key back" >&2; exit 1; }
      tar -xf "$tar_" -C "$dir"; rm -f "$tar_"; echo "got $key back"
    done
    exit 0 ;;
  --drop)
    shift
    for key in "$@"; do drop "$key" || echo "deleting $key failed: scripts/release-prune.ts deletes it in two days" >&2; done
    exit 0 ;;
esac
# The files staged before (--stage), taken back first (by a put of the files: --feeds leaves them).
staged=""
for dir in "$@"; do
  [ -d "$dir" ] || { echo "no releases in $dir" >&2; exit 1; }
  case $passes in *files*) ;; *) continue ;; esac
  for marker in $(cd "$dir" && find . -type f -name '*.staged' | sed 's|^\./||' | sort); do
    key=$(cat "$dir/$marker")
    # (taken back already by --unstage)
    [ -f "$dir/${marker%.staged}" ] || get "$key" "$dir/${marker%.staged}" || { echo "could not get $key back" >&2; exit 1; }
    rm "$dir/$marker"; staged="$staged $key"
    echo "got ${marker%.staged} back from $key"
  done
done
for dir in "$@"; do
  names=$(cd "$dir" && find . -type f | sed 's|^\./||' | sort)
  for pass in $passes; do
    pids=""
    for name in $names; do
      [ "$(pass_of "$name")" = "$pass" ] || continue
      # (an Android release's symbols, scripts/release.sh's: never a reason to fail or hold back the put, a warning;
      # taken out all the same, so no later put tries them again)
      case $name in symbols/*)
        { put "$name" "$dir/$name" "$(type_of "$name")" || echo "release-put.sh: warning: $name not put (the release goes on without it)" >&2
          if [ -n "$taken" ]; then rm -f "$dir/$name"; fi; } &
        pids="$pids $!"; continue ;;
      esac
      { put "$name" "$dir/$name" "$(type_of "$name")" && clean_cache_copy "$name" "$dir/$name" && if [ -n "$taken" ]; then rm "$dir/$name"; fi; } &
      pids="$pids $!"
    done
    for pid in $pids; do wait "$pid" || { echo "not all of $dir was put" >&2; exit 1; }; done
  done
done
for key in $staged; do drop "$key" || echo "deleting $key failed: scripts/release-prune.ts deletes it in two days" >&2; done
