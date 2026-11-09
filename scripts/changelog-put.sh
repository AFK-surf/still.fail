#!/bin/sh
# The changelog people read in the apps (scripts/changelog.ts), from main's history, put in the releases bucket:
# changelog.json (the test channel's, a commit an entry) and changelog-stable.json (the stable channel's, a release an
# entry: docs/releases), which still.fail cloud serves and marks bug reports fixed by. CI runs it once what it says is
# out (.github/workflows/pipeline.yml: put, or changelog when nothing was released). Needs the whole history.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
node "$root/scripts/changelog.ts" > "$out/changelog.json"
node "$root/scripts/changelog.ts" --stable > "$out/changelog-stable.json"
# Put as the releases are (scripts/release-put.sh: Cloudflare's API, wrangler only without it): wrangler's own start, its
# packages installed first, was most of the minute this step took for two small files (main 8904c9f5, 41541039595).
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || (cd "$root/cloud" && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
sh "$root/scripts/release-put.sh" "$out"
for name in changelog changelog-stable; do
  echo "$name: $(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).length)' "$out/$name.json") entries"
done
