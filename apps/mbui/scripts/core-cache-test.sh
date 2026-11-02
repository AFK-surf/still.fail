#!/bin/bash
# A warm build directory may be reused with a different still.fail checkout (as the Android release runners do).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/out"
fixture=$(mktemp -d "$root/out/core-cache-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
work="$fixture/work"
mkdir -p "$work/scripts" "$work/core" "$fixture/bin"
cp "$root/scripts/core.sh" "$work/scripts/core.sh"
touch "$work/scripts/env.sh" "$work/core/hermes.ts"

# Keep this a test of the build's input selection: fake the compiler and Babel, so no toolchain is needed.
cat > "$fixture/bin/node" <<'NODE'
#!/bin/sh
exit 0
NODE
cat > "$fixture/bin/hermesc" <<'HERMES'
#!/bin/bash
while [ "$1" != -out ]; do shift; done
cp "$3" "$2"
HERMES
cat > "$fixture/bin/esbuild" <<'ESBUILD'
#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
arg = lambda name: next(a[len(name):] for a in args if a.startswith(name))
source = pathlib.Path(arg('--alias:@core=')) / 'store.ts'
out = pathlib.Path(arg('--outfile='))
meta = pathlib.Path(arg('--metafile='))
out.write_text(source.read_text())
meta.write_text(json.dumps({'inputs': {str(source): {}}}))
with open(os.environ['FAKE_BUILD_LOG'], 'a') as log:
    log.write('built\n')
ESBUILD
chmod +x "$fixture/bin/"*
for checkout in a b; do
  mkdir -p "$fixture/$checkout/client/core-ts/src" "$fixture/$checkout/client/core-ts/node_modules/.bin" \
    "$fixture/$checkout/client/core-ts/node_modules/@babel/core"
  cp "$fixture/bin/esbuild" "$fixture/$checkout/client/core-ts/node_modules/.bin/esbuild"
done
printf 'old core\n' > "$fixture/a/client/core-ts/src/store.ts"
printf 'new core\n' > "$fixture/b/client/core-ts/src/store.ts"
export PATH="$fixture/bin:$PATH" HERMESC="$fixture/bin/hermesc" HBC_CACHE= CARGO_TARGET_DIR="$fixture/target"
export ENTRY="$work/core/hermes.ts"
export FAKE_BUILD_LOG="$fixture/builds.log"
build() { EMBER="$fixture/$1" bash "$work/scripts/core.sh" hermes; }

if [ "${1:-all}" != keyed ]; then
  build a
  build a
  test "$(wc -l < "$FAKE_BUILD_LOG" | tr -d ' ')" = 1
  build b
  if ! cmp -s "$work/out/core/core.hbc" "$fixture/b/client/core-ts/src/store.ts"; then
    echo 'the second checkout must build its own core, even if the first checkout is unchanged' >&2
    exit 1
  fi
  printf 'newer core\n' > "$fixture/b/client/core-ts/src/store.ts"
  build b
  cmp "$work/out/core/core.hbc" "$fixture/b/client/core-ts/src/store.ts"
  echo 'core cache follows the checkout and its changed inputs'
fi

if [ "${1:-all}" != checkout ]; then
  # A clean Git tree has a content key. Even if a checkout preserves the old file's time and size, a new tree must
  # not fall back to the old mtime stamp when the new key is absent from the cache.
  repo="$fixture/b"
  mkdir -p "$repo/media" "$repo/web/public/avatars"
  printf 'media\n' > "$repo/media/entry"
  printf 'avatars\n' > "$repo/web/public/avatars/entry"
  printf 'old core\n' > "$repo/client/core-ts/src/store.ts"
  git -C "$repo" init -q
  git -C "$repo" add client/core-ts/src/store.ts media web/public/avatars
  git -C "$repo" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm old
  export HBC_CACHE="$fixture/cache"
  build b
  cp -p "$repo/client/core-ts/src/store.ts" "$fixture/time"
  printf 'new core\n' > "$repo/client/core-ts/src/store.ts"
  touch -r "$fixture/time" "$repo/client/core-ts/src/store.ts"
  git -C "$repo" add client/core-ts/src/store.ts
  git -C "$repo" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm new
  build b
  if ! cmp -s "$work/out/core/core.hbc" "$repo/client/core-ts/src/store.ts"; then
    echo 'a changed Git tree must not reuse a timestamp stamp for an older core' >&2
    exit 1
  fi
  echo 'core cache follows the content of a clean Git tree'
fi
