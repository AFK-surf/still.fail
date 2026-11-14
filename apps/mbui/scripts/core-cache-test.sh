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
# (the bundle: its entry, the core, the rules it imports where the checkout has them, and what a case has it import
# besides, FAKE_IMPORTS; its inputs said from where it ran, as esbuild says them, or as a case has them said wrongly:
# from another place, FAKE_META_FROM, or without the entry, FAKE_META_NO_ENTRY)
cat > "$fixture/bin/esbuild" <<'ESBUILD'
#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
arg = lambda name: next(a[len(name):] for a in args if a.startswith(name))
checkout = pathlib.Path(arg('--alias:@stillfail='))
sources = [pathlib.Path(next(a for a in args if not a.startswith('--'))), pathlib.Path(arg('--alias:@core=')) / 'store.ts']
sources += [checkout / p for p in ['rules/js/rules.js'] + os.environ.get('FAKE_IMPORTS', '').split() if (checkout / p).exists()]
out = pathlib.Path(arg('--outfile='))
meta = pathlib.Path(arg('--metafile='))
out.write_text(''.join(source.read_text() for source in sources))
listed = sources[1:] if os.environ.get('FAKE_META_NO_ENTRY') else sources
meta.write_text(json.dumps({'inputs': {os.path.relpath(source, os.environ.get('FAKE_META_FROM', '.')): {} for source in listed}}))
with open(os.environ['FAKE_BUILD_LOG'], 'a') as log:
    log.write('built\n')
ESBUILD
# (git, but for the command a case has fail, FAKE_GIT_FAILS)
printf '#!/bin/sh\nfor a; do [ "$a" != "${FAKE_GIT_FAILS:-}" ] || { echo "fatal: $a made to fail" >&2; exit 128; }; done\nexec "%s" "$@"\n' \
  "$(command -v git)" > "$fixture/bin/git"
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
build() { SF_SRC="$fixture/$1" bash "$work/scripts/core.sh" hermes; }

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
  # (the checkout as the repository is: a tsconfig.json and a package.json at its root, over all it has)
  repo="$fixture/b"
  mkdir -p "$repo/rules/js" "$repo/web/public/avatars" "$repo/docs" "$repo/station/src"
  printf 'old rules\n' > "$repo/rules/js/rules.js"
  printf 'avatars\n' > "$repo/web/public/avatars/index.json"
  printf 'old core\n' > "$repo/client/core-ts/src/store.ts"
  printf 'a note\n' > "$repo/docs/note"
  printf '{"compilerOptions":{"strict":true}}\n' > "$repo/tsconfig.json"
  printf '{"type":"module"}\n' > "$repo/package.json"
  git -C "$repo" init -q
  commit() {
    git -C "$repo" add client/core-ts/src rules web docs station tsconfig.json package.json
    git -C "$repo" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm "$1"
  }
  # what `hermes` said (shown where it fails), and the key it kept the core by (none: not kept)
  said=
  built() { said=$(build b 2>&1) || { printf '%s\n' "$said" >&2; exit 1; }; }
  key() { printf '%s\n' "$said" | sed -n 's/.*kept as \([0-9a-f]*\).*/\1/p' | head -1; }
  made_of() { cat "$@" | cmp -s - "$work/out/core/core.hbc"; }
  builds() { wc -l < "$FAKE_BUILD_LOG" | tr -d ' '; }
  commit old
  export HBC_CACHE="$fixture/cache"
  built
  if [ -z "$(key)" ]; then
    echo 'the core of a clean Git tree must be kept by a content key' >&2
    exit 1
  fi
  cp -p "$repo/client/core-ts/src/store.ts" "$fixture/time"
  printf 'new core\n' > "$repo/client/core-ts/src/store.ts"
  touch -r "$fixture/time" "$repo/client/core-ts/src/store.ts"
  commit new
  built
  if ! made_of "$repo/client/core-ts/src/store.ts" "$repo/rules/js/rules.js"; then
    echo 'a changed Git tree must not reuse a timestamp stamp for an older core' >&2
    exit 1
  fi
  echo 'core cache follows the content of a clean Git tree'

  # The key is of everything the bundle takes: a file of it outside the core's own tree (the rules, the words) changed
  # alone is another key, not the core of before under the same one.
  before=$(key)
  printf 'new rules\n' > "$repo/rules/js/rules.js"
  commit 'new rules'
  built
  if ! made_of "$repo/client/core-ts/src/store.ts" "$repo/rules/js/rules.js" || [ "$(key)" = "$before" ]; then
    echo "a change to rules/js/rules.js alone must make the core again, under a new key: $said" >&2
    exit 1
  fi
  # ... and what the bundle does not take changed alone is the same key: the core kept, not made.
  before=$(key) made=$(builds)
  printf 'another note\n' > "$repo/docs/note"
  commit 'a note'
  built
  if [ "$(key)" != "$before" ] || [ "$(builds)" != "$made" ]; then
    echo "the same inputs must have the same key, the core taken from the cache: $said" >&2
    exit 1
  fi
  # ... and what esbuild makes the bundle by and its metafile does not list, changed alone, is another key too.
  before=$(key) made=$(builds)
  printf '{"compilerOptions":{"strict":false}}\n' > "$repo/tsconfig.json"
  commit 'not strict'
  built
  if [ "$(key)" = "$before" ] || [ "$(builds)" = "$made" ]; then
    echo "a change to tsconfig.json alone must make the core again, under a new key: $said" >&2
    exit 1
  fi
  # ... and so is such a file come later to a directory between a path of the key and the root, where there was none:
  # esbuild makes the files under it by it from then on (the nearest), and the core kept before it is not taken.
  for config in client/tsconfig.json web/package.json; do
    before=$(key) made=$(builds)
    printf '{}\n' > "$repo/$config"
    git -C "$repo" add "$config"
    commit "$config"
    built
    if [ -z "$(key)" ] || [ "$(key)" = "$before" ] || [ "$(builds)" = "$made" ]; then
      echo "$config added over files of the bundle must make the core again, under a new key: $said" >&2
      exit 1
    fi
  done
  # ... one added and not committed is no key.
  printf '{}\n' > "$repo/rules/package.json"
  git -C "$repo" add rules/package.json
  built
  if [ -n "$(key)" ] || ! printf '%s\n' "$said" | grep -q 'core.hbc has no key.*: rules/package.json is changed'; then
    echo "a package.json added over files of the bundle and not committed is no key, and said: $said" >&2
    exit 1
  fi
  git -C "$repo" rm -qf client/tsconfig.json web/package.json rules/package.json
  commit 'no config but the root has'
  echo 'core cache key follows every input of the bundle, and nothing else'

  # A bundle that takes a file the key does not cover is refused where it is made, the file and the line to change
  # said: nothing is kept under a key that leaves an input out.
  printf 'other\n' > "$repo/station/src/other.ts"
  printf 'core with other\n' > "$repo/client/core-ts/src/store.ts"
  commit 'the core imports station/src/other.ts'
  if said=$(FAKE_IMPORTS=station/src/other.ts build b) || ! printf '%s\n' "$said" | grep -q 'station/src/other.ts.*HBC_TREES' \
    || [ -f "$work/out/core/core.hbc" ]; then
    echo "a bundle taking a tracked file outside the key's trees must be refused, naming it and HBC_TREES: $said" >&2
    exit 1
  fi
  # ... and so is, with a key, one that takes a file git does not track (the key is of what is committed); with no
  # key it is made, and not kept.
  mkdir -p "$repo/client/i18n"
  printf 'made by a build\n' > "$repo/client/i18n/made.json"
  kept=$(ls "$HBC_CACHE" | wc -l | tr -d ' ')
  if said=$(FAKE_IMPORTS=client/i18n/made.json build b) || ! printf '%s\n' "$said" | grep -q 'client/i18n/made.json.*does not track'; then
    echo "with a key, a bundle taking a file git does not track must be refused, naming it: $said" >&2
    exit 1
  fi
  HBC_CACHE= FAKE_IMPORTS=client/i18n/made.json built
  if ! made_of "$repo/client/core-ts/src/store.ts" "$repo/rules/js/rules.js" "$repo/client/i18n/made.json" \
    || [ -n "$(key)" ] || [ "$(ls "$HBC_CACHE" | wc -l | tr -d ' ')" != "$kept" ]; then
    echo "with no key, a bundle taking a file git does not track is made and not kept: $said" >&2
    exit 1
  fi
  # ... and so is one made by a tsconfig.json the key does not cover. The nearest over a file of the key's is in the
  # key wherever it is, so that is one over a file itself refused, said to come with that file, and what one extends,
  # said to be added.
  printf '{}\n' > "$repo/docs/tsconfig.json"
  printf 'other\n' > "$repo/docs/other.ts"
  printf 'core with docs\n' > "$repo/client/core-ts/src/store.ts"
  commit 'the core imports docs/other.ts, a tsconfig.json over it'
  if said=$(FAKE_IMPORTS=docs/other.ts build b) || ! printf '%s\n' "$said" | grep -q 'takes docs/other.ts.*add it (or its directory) to HBC_TREES' \
    || ! printf '%s\n' "$said" | grep -q 'made by docs/tsconfig.json.*it does once docs/other.ts (or its directory) is in HBC_TREES' \
    || [ -f "$work/out/core/core.hbc" ]; then
    echo "a bundle made by a tracked tsconfig.json over a file outside the key's trees must be refused, naming both and HBC_TREES: $said" >&2
    exit 1
  fi
  git -C "$repo" rm -q docs/tsconfig.json docs/other.ts
  printf '{}\n' > "$repo/docs/base.json"
  printf '{\n  // as the root says\n  "extends": "./docs/base",\n}\n' > "$repo/tsconfig.json"
  commit 'the tsconfig.json extends another'
  if said=$(build b) || ! printf '%s\n' "$said" | grep -q 'made by docs/base.json (tsconfig.json extends it,.*add it to HBC_TREES' || [ -f "$work/out/core/core.hbc" ]; then
    echo "a bundle made by what its tsconfig.json extends, outside the key's trees, must be refused, naming it: $said" >&2
    exit 1
  fi
  printf '{}\n' > "$repo/tsconfig.json"
  commit 'the tsconfig.json alone'
  echo 'core cache keeps no bundle with an input outside its key'

  # The check never passes having held nothing: inputs that are no files from where it reads them (a metafile said
  # from another place) and a metafile without the entry are refused, with a key and without one.
  for cache in "$HBC_CACHE" ''; do
    if said=$(HBC_CACHE=$cache FAKE_META_FROM="$fixture" build b 2>&1) || ! printf '%s\n' "$said" | grep -q 'no file from .*cannot be held' \
      || [ -f "$work/out/core/core.hbc" ]; then
      echo "a bundle whose inputs are no files must be refused (HBC_CACHE=$cache): $said" >&2
      exit 1
    fi
    if said=$(HBC_CACHE=$cache FAKE_META_NO_ENTRY=1 build b 2>&1) || ! printf '%s\n' "$said" | grep -q 'none of them its entry.*cannot be held' \
      || [ -f "$work/out/core/core.hbc" ]; then
      echo "a bundle whose inputs lack its entry must be refused (HBC_CACHE=$cache): $said" >&2
      exit 1
    fi
  done
  echo 'core cache passes no bundle it held to nothing'

  # No key where HBC_CACHE asks for one says why: a change not committed (the first path), a git command that failed
  # (a status that fails is no clean tree). Without HBC_CACHE nothing is said.
  built
  if [ -z "$(key)" ] || printf '%s\n' "$said" | grep -q 'has no key'; then
    echo "the core of a clean Git tree must be kept by a content key, nothing said of none: $said" >&2
    exit 1
  fi
  printf 'rules of one own\n' > "$repo/rules/js/rules.js"
  built
  if [ -n "$(key)" ] || ! printf '%s\n' "$said" | grep -q 'core.hbc has no key.*: rules/js/rules.js is changed' \
    || ! made_of "$repo/client/core-ts/src/store.ts" "$repo/rules/js/rules.js"; then
    echo "a change not committed is no key, the core made, and the path said: $said" >&2
    exit 1
  fi
  HBC_CACHE= built
  if printf '%s\n' "$said" | grep -q 'has no key'; then
    echo "without HBC_CACHE nothing is said of a key: $said" >&2
    exit 1
  fi
  git -C "$repo" checkout -q -- rules/js/rules.js
  for fails in ls-tree status; do
    FAKE_GIT_FAILS=$fails built
    if [ -n "$(key)" ] || ! printf '%s\n' "$said" | grep -q "core.hbc has no key.*git $fails.* failed.*fatal: $fails made to fail"; then
      echo "git $fails failing is no key, and said: $said" >&2
      exit 1
    fi
  done
  echo 'core cache says why it has no key'
fi
