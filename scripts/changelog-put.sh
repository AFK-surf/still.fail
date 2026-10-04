#!/bin/sh
# The changelog people read in the apps (docs/changelog.md), from main's history, put in the releases bucket:
# changelog.json (the test channel's, a commit an entry) and changelog-stable.json (the stable channel's, a release an
# entry: docs/releases), which still.fail cloud serves and marks bug reports fixed by. CI runs it once what it says is
# out (.github/workflows/pipeline.yml: put, or changelog when nothing was released). Needs the whole history.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
node "$root/scripts/changelog.ts" > "$out/changelog.json"
node "$root/scripts/changelog.ts" --stable > "$out/changelog-stable.json"
(cd "$root/cloud" && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
for name in changelog changelog-stable; do
  # Cloudflare's API fails now and then on the way: put again, twice at most.
  for try in 1 2 3; do
    (cd "$root/cloud" && pnpm exec wrangler r2 object put "stillfail-releases/$name.json" --file "$out/$name.json" --content-type application/json --remote > /dev/null) && break
    [ $try = 3 ] && exit 1
    sleep 15
  done
  echo "$name: $(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).length)' "$out/$name.json") entries"
done
