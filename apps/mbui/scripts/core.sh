#!/bin/bash
# The still.fail client core (client/core-ts of this repository) in Hermes on its Rust shell (client/shell), for the
# Apple apps (src/host/apple_core.mm) and Android's (src/host/android_core.c on still.fail's prebuilt engine): builds the
# pieces from the checkout and runs a headless smoke test. See core/README.md.
#   scripts/core.sh deps | shell [TARGET] | hermes | hermes-script FILE [OUT] | hermes-apple | engine [TARGET] | apple [TARGET]
#                   | smoke [build|run] | listen | login-test | vectors | sizes | clean | all
# EMBER: the still.fail checkout (default: this one, scripts/env.sh); out/core/ gets everything built.
# TARGET: a Rust target (default aarch64-apple-darwin; aarch64-apple-ios, aarch64-apple-ios-sim for iOS).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
ROOT=$PWD
EMBER=${EMBER:-$(cd "$TOOLS/.." && pwd)/ember-src}
OUT=$ROOT/out/core
# (Git Bash on Windows: paths as D:/…, which both its shell and Windows' programs take)
if [ "${OSTYPE:-}" = msys ] || [ "${OSTYPE:-}" = cygwin ]; then
  ROOT=$(cygpath -m "$ROOT")
  EMBER=$(cygpath -m "$EMBER")
fi
CORE_TS=$EMBER/client/core-ts
# The shell's intermediate build lives outside the checkout (and outside this repo): only the .a is kept in out/core.
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$(cd "$TOOLS/.." && pwd)/core-target}
export CARGO_TARGET_DIR
# rustup's cargo (it has the iOS/Android targets), before Homebrew's.
[ -x "$HOME/.cargo/bin/cargo" ] && export PATH=$HOME/.cargo/bin:$PATH
mkdir -p $OUT

# (Windows' Python is `python`)
PY=$(command -v python3 || command -v python)
now() { "$PY" -c 'import time;print(time.time())'; }
since() { "$PY" -c "print(round($(now)-$1,2))"; }

deps() {
  [ -d "$CORE_TS" ] || { echo "no ember checkout at $EMBER (EMBER=...)"; exit 1; }
  (cd $CORE_TS && pnpm install --frozen-lockfile --prefer-offline 2>&1 | tail -5)
}

# deps, when this checkout has not had them (a fresh worktree: esbuild and Babel missing from core-ts's node_modules)
have_deps() {
  [ -x $CORE_TS/node_modules/.bin/esbuild ] && [ -d $CORE_TS/node_modules/@babel/core ] || deps
}

# libstillfail_shell.a for TARGET: the crate is a cdylib + lib; `cargo rustc --crate-type staticlib` makes the
# archive without touching ember's Cargo.toml. What it needs from the system goes to out/core/shell-<target>.libs.
shell() {
  local target=${1:-aarch64-apple-darwin}
  local t0=$(now)
  (cd $EMBER/client/shell && cargo rustc --release --lib --crate-type staticlib --target $target \
      -- --print native-static-libs 2> >(tee $OUT/shell-$target.log >&2))
  # (rustc prints it only when it builds: a fresh build keeps the last one)
  local libs=$(grep -o 'native-static-libs: .*' $OUT/shell-$target.log | tail -1 | sed 's/native-static-libs: //')
  [ -n "$libs" ] && echo "$libs" > $OUT/shell-$target.libs
  mkdir -p $OUT/$target
  cp $CARGO_TARGET_DIR/$target/release/libstillfail_shell.a $OUT/$target/
  strip -S -x -o $OUT/$target/libstillfail_shell.stripped.a $OUT/$target/libstillfail_shell.a 2>/dev/null || true
  echo "shell $target in $(since $t0) s: $(stat -f %z $OUT/$target/libstillfail_shell.a) bytes; links: $(libs $target)"
}

# The core for Hermes (every native host: src/host/apple_core.mm, src/host/android_core.c): out/core/core.hbc. Made as ember's
# client/core-ts/scripts/hermes-bundle.ts makes it (esbuild to ES2020; Babel's class transform, as Hermes 0.81 has no
# classes; then React Native 0.81.4's hermesc, the engine's Hermes, to bytecode), but from an entry of ours (ENTRY,
# default core/hermes.ts: still.fail's alone; core/media-hermes.ts with the media module), `@core/` and `@ember/`
# aliased (`@core/` is client/core-ts/src, `@ember/` this checkout). hermesc: $HERMESC, else the one ember's apps/android/build.py keeps in its cache, else
# fetched (npm pack react-native@0.81.4) into out/core/hermesc.
HERMES_RN=0.81.4
hermesc() {
  if [ -n "${HERMESC:-}" ]; then echo "$HERMESC"; return; fi
  local bin=sdks/hermesc/$([ "$(uname)" = Darwin ] && echo osx-bin || echo linux64-bin)/hermesc
  for c in "$HOME/Library/Caches/stillfail-build/hermesc-$HERMES_RN/package" "$OUT/hermesc/package"; do
    if [ -x "$c/$bin" ]; then echo "$c/$bin"; return; fi
  done
  mkdir -p $OUT/hermesc
  (cd $OUT/hermesc && npm pack react-native@$HERMES_RN --silent > /dev/null \
    && tar -xzf react-native-$HERMES_RN.tgz package/sdks/hermesc && rm react-native-$HERMES_RN.tgz)
  echo "$OUT/hermesc/package/$bin"
}

# core.hbc's stamp: the bundle's inputs (esbuild's metafile), the entry and hermesc, by mtime and size
hbc_stamp() {
  "$PY" - "$OUT/core-hermes.meta.json" "${ENTRY:-$ROOT/core/hermes.ts}" "$1" <<'PY'
import json, os, sys
meta, entry, hermesc = sys.argv[1:4]
try:
    inputs = sorted(json.load(open(meta))['inputs'])
except (OSError, ValueError, KeyError):
    sys.exit(1)
def st(p):
    try:
        s = os.stat(p)
        return [s.st_mtime_ns, s.st_size]
    except OSError:
        return None
print(json.dumps({'entry': entry, 'hermesc': [hermesc, st(hermesc)], 'inputs': {p: st(p) for p in inputs}}))
PY
}

hermes() {
  have_deps
  local t0=$(now)
  local hc="$(hermesc)"
  # the same inputs as the last build's: that build's core.hbc
  if [ -f $OUT/core.hbc ] && [ -f $OUT/core.hbc.stamp ] && [ "$(hbc_stamp "$hc" 2>/dev/null)" = "$(cat $OUT/core.hbc.stamp)" ]; then
    echo "hermes: core.hbc as it was (its inputs unchanged)"
    return 0
  fi
  # never an old core.hbc after a failed step (it would hide a module gone missing)
  rm -f $OUT/core-hermes.js $OUT/core.hbc $OUT/core.hbc.stamp
  # what an app's modules import from npm (media/core's effect) found in the core's own node_modules
  NODE_PATH=$CORE_TS/node_modules $CORE_TS/node_modules/.bin/esbuild ${ENTRY:-$ROOT/core/hermes.ts} --bundle \
    --format=iife --platform=neutral --main-fields=module,main --target=es2020 --minify --legal-comments=none \
    --alias:@core=$CORE_TS/src --alias:@ember=$EMBER --resolve-extensions=.ts,.js,.mjs \
    --outfile=$OUT/core-hermes.js --metafile=$OUT/core-hermes.meta.json --log-level=warning \
    || { echo "hermes: bundle failed"; return 1; }
  # Classes as functions (and `extends Error` as Babel's wrapped native super), with ember's Babel.
  (cd $CORE_TS && node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { transformSync } from '@babel/core';
const f = process.argv[1];
const out = transformSync(readFileSync(f, 'utf8'), { babelrc: false, configFile: false, compact: true, plugins: ['@babel/plugin-transform-classes'] });
if (!out || !out.code) throw new Error('babel made nothing');
writeFileSync(f, out.code);" $OUT/core-hermes.js) || { echo "hermes: class transform failed"; return 1; }
  "$hc" -emit-binary -O -block-scoping -out $OUT/core.hbc $OUT/core-hermes.js \
    || { echo "hermes: hermesc failed"; rm -f $OUT/core.hbc; return 1; }
  hbc_stamp "$hc" > $OUT/core.hbc.stamp || rm -f $OUT/core.hbc.stamp
  echo "hermes in $(since $t0) s: $(wc -c < $OUT/core-hermes.js | tr -d ' ') bytes of script, $(wc -c < $OUT/core.hbc | tr -d ' ') of bytecode"
}

# A plain script (no bundle, no Babel) as bytecode, OUT (default out/core/core.hbc, the core's place: Android's
# listen-test; the stamp goes with it, so the next `hermes` makes the core again).
hermes_script() {
  local out=${2:-$OUT/core.hbc}
  rm -f "$out"
  [ "$out" = $OUT/core.hbc ] && rm -f $OUT/core.hbc.stamp
  "$(hermesc)" -emit-binary -O -out "$out" "$1" || { echo "hermes-script: hermesc failed"; return 1; }
  echo "hermes-script: $1 as $(wc -c < "$out" | tr -d ' ') bytes of bytecode"
}

# React Native 0.81.4's Hermes for Apple's systems, the one Android's hermes-android is (the same release's Maven
# tarball, `react-native-artifacts:hermes-ios-release`; MIT): macOS's hermes.framework (Library/Frameworks/macosx), iOS's
# hermes.xcframework (Library/Frameworks/universal: the device's and the simulator's slices), the headers of Hermes and
# its JSI (include). Fetched once into a cache every worktree shares (as ember's apps/android/build.py keeps hermesc:
# ~/Library/Caches/stillfail-build/hermes-apple-<version>), its sha256 checked; never committed. out/core/hermes links
# to its destroot.
HERMES_APPLE_URL=https://repo1.maven.org/maven2/com/facebook/react/react-native-artifacts/$HERMES_RN/react-native-artifacts-$HERMES_RN-hermes-ios-release.tar.gz
HERMES_APPLE_SHA256=0a9ada4198ed5bbd4a8099197cd100397d65cc86cd44c8eba6c162099081e554
hermes_apple() {
  local cache=${STILLFAIL_BUILD_CACHE:-$HOME/Library/Caches/stillfail-build}/hermes-apple-$HERMES_RN
  if [ ! -f $cache/destroot/include/hermes/hermes.h ]; then
    mkdir -p "$(dirname $cache)"
    local tmp=$(mktemp -d "$cache.XXXXXX")
    curl -fsSL --retry 3 -o $tmp/hermes.tgz $HERMES_APPLE_URL || { rm -rf $tmp; echo "hermes-apple: download failed"; return 1; }
    local sum=$(shasum -a 256 $tmp/hermes.tgz | cut -d' ' -f1)
    [ "$sum" = $HERMES_APPLE_SHA256 ] || { rm -rf $tmp; echo "hermes-apple: sha256 $sum, not $HERMES_APPLE_SHA256"; return 1; }
    tar -xzf $tmp/hermes.tgz -C $tmp && rm $tmp/hermes.tgz
    # (another build may have put it there meanwhile: theirs kept)
    if [ -d $cache ]; then rm -rf $tmp; else mv $tmp $cache; fi
    echo "hermes-apple: Hermes $HERMES_RN for macOS and iOS in $cache"
  fi
  [ "$(readlink $OUT/hermes 2>/dev/null)" = $cache/destroot ] || ln -sfn $cache/destroot $OUT/hermes
}

# Where Hermes's framework for TARGET is (the directory holding hermes.framework).
hermes_fw() {
  case ${1:-aarch64-apple-darwin} in
    aarch64-apple-darwin) echo $OUT/hermes/Library/Frameworks/macosx ;;
    aarch64-apple-ios-sim) echo $OUT/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64_x86_64-simulator ;;
    aarch64-apple-ios) echo $OUT/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64 ;;
    *) echo "core.sh: no Hermes for $1" >&2; return 1 ;;
  esac
}

# The core's engine for TARGET: src/host/apple_core.mm (Objective-C++: the core's thread and loop, Hermes and its JSI,
# the shell's C ABI, secure.* and listen.*) as out/core/<target>/libmbui_core.a, which the apps with the core link
# beside the shell's .a and Hermes's framework (src/stillfail/moon.pkg; the iOS build's hook). Made again only when its
# sources (or this script) are newer.
engine() {
  local target=${1:-aarch64-apple-darwin} cc
  hermes_apple || return 1
  case $target in
    aarch64-apple-darwin) cc="xcrun --sdk macosx clang++ -arch arm64" ;;
    aarch64-apple-ios-sim) cc="xcrun --sdk iphonesimulator clang++ -arch arm64 -mios-simulator-version-min=17.0" ;;
    aarch64-apple-ios) cc="xcrun --sdk iphoneos clang++ -arch arm64 -miphoneos-version-min=17.0" ;;
    *) echo "engine: no target $target"; return 1 ;;
  esac
  local lib=$OUT/$target/libmbui_core.a
  if [ -f $lib ] && [ $lib -nt src/host/apple_core.mm ] && [ $lib -nt src/host/core_api.h ] && [ $lib -nt "$D/core.sh" ]; then
    return 0
  fi
  mkdir -p $OUT/$target
  $cc -std=c++20 -fobjc-arc -fexceptions -frtti -O2 -Wall -Isrc/host -I$OUT/hermes/include \
    -c src/host/apple_core.mm -o $OUT/$target/apple_core.o || { echo "engine: $target did not compile"; return 1; }
  rm -f $lib && ar rcs $lib $OUT/$target/apple_core.o
  echo "engine $target: $lib ($(wc -c < $lib | tr -d ' ') bytes)"
}

# What an Apple app with the core needs for TARGET, each made when missing or stale: Hermes, the engine, the shell's .a
# (built once: rebuild it with `shell`), the core's bytecode (ENTRY, by default the media app's entry, as Android's).
apple() {
  local target=${1:-aarch64-apple-darwin}
  engine $target || return 1
  [ -f $OUT/$target/libstillfail_shell.a ] || shell $target || return 1
  ENTRY=${ENTRY:-$ROOT/core/media-hermes.ts} hermes
}

# The shell's link line for TARGET, each library once (-framework X, -lY; clang adds -lSystem and -lobjc itself).
libs() {
  python3 -c '
import sys
t = open(sys.argv[1]).read().split(); out = []; i = 0
while i < len(t):
    x = t[i:i + 2] if t[i] == "-framework" else t[i:i + 1]; i += len(x)
    if " ".join(x) not in out and x[0] not in ("-lSystem", "-lobjc"): out.append(" ".join(x))
print(" ".join(out))' $OUT/shell-$1.libs
}

# A command-line program of core/FILE.m with the engine (libmbui_core.a: Hermes on the shell), for macOS: out/core/NAME.
core_program() {
  local target=aarch64-apple-darwin fw=$(hermes_fw aarch64-apple-darwin)
  apple $target || return 1
  clang -fobjc-arc -O2 -Wall -Isrc/host core/$1.m mbui/src/host/apple_listen.m $OUT/$target/libmbui_core.a \
    $OUT/$target/libstillfail_shell.a $(libs $target) -F$fw -framework hermes -Wl,-rpath,$fw -lc++ \
    -framework Foundation -Wl,-dead_strip -o $OUT/$1
}

# core/smoke.m + the engine, for macOS.
smoke_build() {
  core_program smoke || return 1
  strip -o $OUT/smoke.stripped $OUT/smoke
  echo "smoke: $(stat -f %z $OUT/smoke) bytes, stripped $(stat -f %z $OUT/smoke.stripped)"
}

# Twice on one data directory: a first start (no files yet), then one over what the first left.
# /usr/bin/time -l: the process's peak resident size and footprint. MB_CORE_TRACE=1 shows the shell's operations.
smoke_run() {
  local dir=$(mktemp -d /tmp/mbui-core-smoke.XXXXXX) code=0
  : > $OUT/smoke.log
  for run in first again; do
    echo "== $run run ==" | tee -a $OUT/smoke.log
    MB_CORE_BUNDLE=$OUT/core.hbc /usr/bin/time -l $OUT/smoke "$dir" ${CLOUD:-https://app.still.fail} > $OUT/smoke-$run.log 2>&1 || code=1
    cat $OUT/smoke-$run.log >> $OUT/smoke.log
    grep -v '^ *0  \|messages\|signals\|swaps\|block\|context switches\|page' $OUT/smoke-$run.log
    echo "data dir after it: $(cd "$dir" && find . -type f | sort | tr '\n' ' ')" | tee -a $OUT/smoke.log
  done
  rm -rf "$dir"
  return $code
}

# listen.* (apple_core.mm on apple_listen.m) with core/listen-test.js (as bytecode) in the core's place: core/listen_test.m.
listen_test() {
  core_program listen_test || return 1
  hermes_script $ROOT/core/listen-test.js $OUT/listen-test.hbc || return 1
  local dir=$(mktemp -d /tmp/mbui-core-listen.XXXXXX) code=0
  MB_CORE_BUNDLE=$OUT/listen-test.hbc $OUT/listen_test "$dir" || code=1
  rm -rf "$dir"
  return $code
}

# The core demo's login command (scripts/mac.sh login, MBUI_AUTH_LOGIN: still.fail's sign-in on the host's
# browser_login) as a station's remote login would run it, up to the person's browser step, against still.fail cloud: a fresh data directory, BROWSER a stand-in that keeps the
# page's address. Nobody signs in: the browser that comes back is curl, with a state that is not the sign-in's.
login_test() {
  MBUI_CORE=1 "$D/mac.sh" build > /dev/null
  local exe=$ROOT/_build/native/release/build/stillfail/coredemo/coredemo.exe
  local dir=$(mktemp -d /tmp/mbui-login.XXXXXX) code=0
  printf '#!/bin/sh\necho "$1" > "%s/url"\n' "$dir" > $dir/browser
  chmod +x $dir/browser
  MB_CORE_BUNDLE=$OUT/core.hbc MBUI_CORE_DATA=$dir/data BROWSER=$dir/browser MBUI_AUTH_LOGIN=1 $exe > $dir/out.log 2>&1 &
  local pid=$!
  # Not waited for forever: a minute is ample for what follows.
  (sleep 60; kill $pid 2> /dev/null) &
  local watchdog=$!
  for _ in $(seq 60); do [ -s $dir/url ] && break; sleep 0.5; done
  local url=$(cat $dir/url 2>/dev/null)
  ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; code=1; fi; }
  ok "the page went to BROWSER" '[ -n "$url" ]'
  local port=$(python3 -c '
import sys, urllib.parse as u
p = u.urlparse(sys.argv[1]); q = u.parse_qs(p.query); back = u.urlparse(q.get("redirect_uri", [""])[0])
ok = p.scheme == "https" and p.path == "/v1/auth/google/start" and "state" in q and back.scheme == "http" and back.hostname == "127.0.0.1" and back.path == "/oauth/callback"
print(back.port if ok else 0)' "$url")
  ok "it is still.fail cloud's login page, coming back to 127.0.0.1:$port/oauth/callback" '[ "$port" -gt 0 ]'
  if [ -f "$EMBER/station/src/logins/parse.ts" ]; then
    local seen=$(node --experimental-strip-types --no-warnings --input-type=module -e "
const { loopbackOf } = await import('$EMBER/station/src/logins/parse.ts');
const b = loopbackOf(process.argv[1]);
console.log(b && b.state ? b.host + ':' + b.port + b.path : 'none');" "$url" 2>&1)
    ok "a station's login takes it as a loopback login with a state ($seen)" '[ "$seen" = "127.0.0.1:$port/oauth/callback" ]'
  fi
  ok "the app itself listens there (lsof, as the station checks before relaying)" 'lsof -a -p $pid -iTCP:$port -sTCP:LISTEN -n -P | grep -q "127.0.0.1:$port"'
  ok "another path is not taken" '[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$port/favicon.ico)" = 404 ]'
  ok "nor the callback under another host name" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: elsewhere.example:$port" "http://127.0.0.1:$port/oauth/callback?code=x&state=y")" = 404 ]'
  ok "the app still waits" 'kill -0 $pid 2>/dev/null'
  local page=$(curl -s "http://127.0.0.1:$port/oauth/callback?code=x&state=not-this-one")
  ok "the browser coming back gets the host's page" 'echo "$page" | grep -q "已回到 app"'
  local exit_code=0
  wait $pid || exit_code=$?
  kill $watchdog 2> /dev/null || true
  wait $watchdog 2> /dev/null || true
  ok "the app exits 1 (the state was not the sign-in's: $(grep -a 'Sign-in failed' $dir/out.log | head -1))" '[ $exit_code = 1 ] && grep -q "Sign-in failed" $dir/out.log'
  ok "it no longer listens" '! lsof -iTCP:$port -sTCP:LISTEN -n -P > /dev/null'
  [ $code = 0 ] || cat $dir/out.log
  rm -rf "$dir"
  return $code
}

# src/core/vectors_test.mbt: core-ts's diff and apply over values shaped like the topics (core/delta-vectors.ts).
vectors() {
  EMBER=$EMBER node core/delta-vectors.ts > src/core/vectors_test.mbt
  echo "vectors: $(grep -c '^test ' src/core/vectors_test.mbt) tests in src/core/vectors_test.mbt"
}

sizes() {
  ls -la $OUT/core.hbc $OUT/*/libstillfail_shell*.a $OUT/*/libmbui_core.a $OUT/smoke $OUT/smoke.stripped 2>/dev/null
}

case "${1:-all}" in
  deps) deps ;;
  shell) shell "$2" ;;
  hermes) hermes ;;
  hermes-script) hermes_script "$2" "${3:-}" ;;
  hermes-apple) hermes_apple ;;
  engine) engine "${2:-aarch64-apple-darwin}" ;;
  apple) apple "${2:-aarch64-apple-darwin}" ;;
  listen) listen_test ;;
  login-test) login_test ;;
  smoke)
    case "${2:-all}" in
      build) smoke_build ;;
      run) smoke_run ;;
      *) smoke_build && smoke_run ;;
    esac ;;
  vectors) vectors ;;
  sizes) sizes ;;
  clean) rm -rf "$CARGO_TARGET_DIR"; echo "removed $CARGO_TARGET_DIR (out/core kept)" ;;
  all) deps; shell; smoke_build; smoke_run; sizes ;;
  *) echo "usage: scripts/core.sh deps | shell [TARGET] | hermes | hermes-script FILE [OUT] | hermes-apple | engine [TARGET] | apple [TARGET] | smoke [build|run] | listen | login-test | vectors | sizes | clean | all"; exit 2 ;;
esac
