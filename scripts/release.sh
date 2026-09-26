#!/bin/sh
# Builds ember station's release for this machine's platform, from what is built here (the station page in dist/admin
# by `pnpm build`, ember-mesh by cargo in mesh/), and puts it in ember cloud's releases bucket, where install.sh
# (cloud/src/install.ts) gets it. The release is the clone's layout, with its own Node:
#   ember/{bin/ember, src/, package.json, node_modules/ (production), dist/admin/, mesh/target/release/ember-mesh, node/bin/node}
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  *) echo "no release for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
[ -f "$root/dist/admin/index.html" ] || { echo "dist/admin is missing: run pnpm build first" >&2; exit 1; }
[ -x "$root/mesh/target/release/ember-mesh" ] || { echo "ember-mesh is missing: cargo build --release in mesh/" >&2; exit 1; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
app="$out/ember"
mkdir -p "$app/node/bin" "$app/mesh/target/release" "$app/dist"
cp "$(command -v node)" "$app/node/bin/node"
cp -R "$root/src" "$root/bin" "$root/package.json" "$app/"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$root/mesh/target/release/ember-mesh" "$app/mesh/target/release/"
(cd "$app" && npm install --omit=dev --no-package-lock --no-audit --no-fund --loglevel=error >/dev/null)
git -C "$root" rev-parse HEAD > "$app/VERSION"
file="ember-station-$platform.tar.gz"
tar -czf "$out/$file" -C "$out" ember
echo "$file: $(du -h "$out/$file" | cut -f1)"
cd "$root/cloud" && pnpm exec wrangler r2 object put "ember-releases/$file" --file "$out/$file" --content-type application/gzip --remote >/dev/null
echo "uploaded $file"
