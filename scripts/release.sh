#!/bin/sh
# Builds ember station's releases (the layout of scripts/station-bundle.sh) and puts them in ember cloud's releases
# bucket, where install.sh (cloud/src/install.ts) gets them: this Mac's (darwin-arm64), and Linux's (linux-x64,
# linux-arm64, built from here: scripts/linux-station.sh).
#   release.sh [PLATFORM…]   (default: all three)
# RELEASE_DIR=dir: into that directory instead of the bucket (the dev cloud serves them from dist/releases: cloud/test/dev.ts).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || { echo "releases are made on a Mac with Apple silicon" >&2; exit 1; }
platforms=${*:-darwin-arm64 linux-x64 linux-arm64}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for platform in $platforms; do
  sh "$root/scripts/station-bundle.sh" "$out/$platform" "$platform"
  file="ember-station-$platform.tar.gz"
  tar -czf "$out/$file" -C "$out/$platform" ember
  echo "$file: $(du -h "$out/$file" | cut -f1)"
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR" && cp "$out/$file" "$RELEASE_DIR/" && echo "put $file in $RELEASE_DIR"
  else
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "ember-releases/$file" --file "$out/$file" --content-type application/gzip --remote >/dev/null)
    echo "uploaded $file"
  fi
done
