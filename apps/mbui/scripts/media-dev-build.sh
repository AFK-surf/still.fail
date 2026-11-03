#!/bin/bash
# Build or reuse exactly the app renderer a media-job requested. Run on the build station, never on a small VM.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
repo=$(cd "$D/../../.." && pwd)
usage='media-dev-build.sh RUNTIME_KEY INBOX_DIR [BASE_COMMIT [mbui-film|mbui-film-wasm]]'
[ "$#" -ge 2 ] && [ "$#" -le 4 ] || { echo "$usage" >&2; exit 2; }
expected=$1
inbox=$2
base=${3:-}
part=${4:-mbui-film}
case "$part" in mbui-film|mbui-film-wasm) ;; *) echo 'media-dev-build: invalid renderer part' >&2; exit 2 ;; esac
case "$expected" in *[!0-9a-f]*|'') echo 'media-dev-build: invalid runtime key' >&2; exit 2 ;; esac
[ "${#expected}" -eq 24 ] || { echo 'media-dev-build: invalid runtime key' >&2; exit 2; }
if [ -n "$base" ]; then
  case "$base" in *[!0-9a-f]*) echo 'media-dev-build: invalid base commit' >&2; exit 2 ;; esac
  [ "${#base}" -eq 40 ] || { echo 'media-dev-build: invalid base commit' >&2; exit 2; }
fi
case "$inbox" in /*) ;; *) inbox="$PWD/$inbox" ;; esac
mkdir -p "$inbox" "$repo/apps/mbui/out"
work=$(mktemp -d "$repo/apps/mbui/out/media-dev-build.XXXXXXXX")
snapshot=0
cleanup() {
  rm -rf "$work"
  if [ "$snapshot" = 1 ]; then rm -rf "$repo/.git"; fi
}
trap cleanup EXIT
cd "$repo"

# A station_task mirror has the source contents but no Git metadata, which native.ts needs to hash its inputs.
if [ ! -e .git ]; then
  git init -q
  snapshot=1
  git add -A
  git -c user.name='Media snapshot' -c user.email='media-snapshot@localhost' -c core.hooksPath=/dev/null \
    -c commit.gpgsign=false commit -qm 'Snapshot for media rendering'
fi
key() { node scripts/native.ts key "$part" darwin-arm64; }
actual=$(key)
[ "$actual" = "$expected" ] || { echo "media-dev-build: source key $actual does not match requested $expected" >&2; exit 1; }

# Reuse a complete shared artifact when available. A new build goes in this mirror's own cache: if the sources
# change during a build, it cannot poison other worktrees' shared cache.
private=0
if renderer=$(STILLFAIL_NATIVE=offline node scripts/native.ts path "$part" darwin-arm64 2>/dev/null); then
  echo "media-dev-build: reused shared $expected" >&2
else
  private=1
  renderer=$(STILLFAIL_NATIVE_CACHE="$repo/apps/mbui/out/media-native-cache" STILLFAIL_NATIVE=build \
    node scripts/native.ts path "$part" darwin-arm64)
fi
if [ "$(key)" != "$expected" ]; then
  if [ "$private" = 1 ]; then rm -rf "$renderer"; fi
  echo 'media-dev-build: sources changed during the build' >&2; exit 1
fi
jq -e --arg key "$expected" --arg part "$part" '.part == $part and .target == "darwin-arm64" and .key == $key' \
  "$renderer/manifest.json" >/dev/null

# The temporary Git snapshot's commit is not the original worktree's revision. Record the supplied base, or omit it.
mkdir "$work/renderer"
cp "$renderer/sffilm" "$renderer/media.sh" "$work/renderer/"
if [ "$part" = mbui-film-wasm ]; then
  cp "$renderer/scene.wasm" "$renderer/native.node" "$renderer/run.mjs" "$renderer/compact.mjs" "$work/renderer/"
fi
if [ -n "$base" ] || [ "$snapshot" = 1 ]; then
  jq --arg base "$base" '.commit = $base' "$renderer/manifest.json" > "$work/renderer/manifest.json"
else
  cp "$renderer/manifest.json" "$work/renderer/manifest.json"
fi
name="$part-darwin-arm64-$expected.tar.gz"
tar -czf "$work/$name" -C "$work/renderer" .
mv -f "$work/$name" "$inbox/$name"
# Publish only the verified artifact to this station's shared cache as well, so other chats can reuse it.
STILLFAIL_NATIVE= STILLFAIL_NATIVE_INBOX="$inbox" node scripts/native.ts file-key "$part" darwin-arm64 "$expected" >/dev/null
echo "media-dev-build: $inbox/$name"
