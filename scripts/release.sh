#!/bin/sh
# Builds ember station's release for this machine's platform (the layout of scripts/station-bundle.sh) and puts it in
# ember cloud's releases bucket, where install.sh (cloud/src/install.ts) gets it.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  *) echo "no release for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sh "$root/scripts/station-bundle.sh" "$out"
file="ember-station-$platform.tar.gz"
tar -czf "$out/$file" -C "$out" ember
echo "$file: $(du -h "$out/$file" | cut -f1)"
cd "$root/cloud" && pnpm exec wrangler r2 object put "ember-releases/$file" --file "$out/$file" --content-type application/gzip --remote >/dev/null
echo "uploaded $file"
